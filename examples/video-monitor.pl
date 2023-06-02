#!perl

use v5.36;
use experimental 'try', 'builtin', 'for_list';

use Data::Dumper;
use Data::Dump;

# TODO:
# Create Color types which will support
# each of the following:
#
# Monochrome( 1 | 0 )
#   1 bit (monochrome) display using the following chars
#       ▄ ▀ █ <space>
#   or even better, use these chars and do 4x4
#       ▖  QUADRANT LOWER LEFT
#       ▗  QUADRANT LOWER RIGHT
#       ▘  QUADRANT UPPER LEFT
#       ▙  QUADRANT UPPER LEFT AND LOWER LEFT AND LOWER RIGHT
#       ▚  QUADRANT UPPER LEFT AND LOWER RIGHT
#       ▛  QUADRANT UPPER LEFT AND UPPER RIGHT AND LOWER LEFT
#       ▜  QUADRANT UPPER LEFT AND UPPER RIGHT AND LOWER RIGHT
#       ▝  QUADRANT UPPER RIGHT
#       ▞  QUADRANT UPPER RIGHT AND LOWER LEFT
#       ▟  QUADRANT UPPER RIGH
#
# Greyscale( 0 .. 255 )
#   8 bit greyscale display
#       using 1/2 boxes & fg+bg colors
#
# RGBD( 0 .. 255, 0 .. 255, 0 .. 255 )
#   24 bit color display
#       using 1/2 boxes & fg+bg colors
#
# For other stuff, here is some ref:
# https://www.w3.org/TR/xml-entity-names/025.html - Boxes
# https://www.w3.org/TR/xml-entity-names/022.html - some lines and stuff
# https://www.w3.org/TR/xml-entity-names/023.html - ^^
# https://www.w3.org/TR/xml-entity-names/024.html - numbers
# https://www.w3.org/TR/xml-entity-names/027.html - lines, boxes, arrows
# https://www.w3.org/TR/xml-entity-names/029.html - arrows
# line characters??
# ╱ ╳ ╲
#


package VideoDisplay {
    use v5.36;
    use experimental 'try', 'builtin', 'for_list';
    use builtin qw[ ceil ];

    use Data::Dumper;

    use Time::HiRes qw[ sleep time ];
    use Carp        qw[ confess ];

    # ...
    use POSIX;
    use Term::Cap;

    use constant HIDE_CURSOR  => 'vi';
    use constant SHOW_CURSOR  => 've';
    use constant CLEAR_SCREEN => 'cl';
    use constant CLEAR_LINE   => 'cm';
    use constant TO_NEXT_LINE => 'do';

    use constant PIXEL => '▀';

    my sub _init_termcap {
        my $termios = POSIX::Termios->new; $termios->getattr;
        my $tc = Term::Cap->Tgetent({ TERM => undef, OSPEED => $termios->getospeed });
        $tc->Trequire( HIDE_CURSOR, SHOW_CURSOR, CLEAR_SCREEN, CLEAR_LINE, TO_NEXT_LINE );
        $tc;
    }

    sub new ($class, $width, $height, $refresh_rate) {
        my $self = {
            refresh => ($refresh_rate // die 'A `refresh_rate` is required'),
            width   => ($width        // die 'A `width` is required'),
            height  => ($height       // die 'A `height` is required'),
            tc      => _init_termcap,
            fh      => \*STDOUT,
        };
        bless $self => $class;
    }

    sub turn_on ($self) {
        my $fh  = $self->{fh};
        my $tc  = $self->{tc};

        $tc->Tputs(HIDE_CURSOR,  1, *$fh );
        $tc->Tputs(CLEAR_SCREEN, 1, *$fh );

        $self;
    }

    sub turn_off ($self) {
        my $fh  = $self->{fh};
        my $tc  = $self->{tc};

        $tc->Tputs(SHOW_CURSOR,  1, *$fh );
        $tc->Tputs(CLEAR_SCREEN, 1, *$fh );

        $self;
    }

    sub run_shader ($self, $shader) {
        my $fh  = $self->{fh};
        my $tc  = $self->{tc};

        # FIXME: respect previously set singal
        # but not really urgent now
        local $SIG{INT} = sub { $self->turn_off; exit(0) };

        my $ticks    = 0;
        my @row_idxs = (0 .. ($self->{height}-1));
        my @col_idxs = (0 .. ($self->{width} -1));
        my @buffer   = ( map { ' ' x $self->{width} } @row_idxs );

        #  fps | time in milliseconds
        # -----+---------------------
        #  120 | 0.00833
        #  100 | 0.01000
        #   60 | 0.01667
        #   50 | 0.02000
        #   30 | 0.03333
        #   25 | 0.04000
        #   10 | 0.10000

        my $refresh = $self->{refresh};

        my $bias  = 0.0999999999;
           $bias -= ($refresh - 60) * 0.001 if $refresh > 60;

        my $timing  = (1 / $refresh);
           $timing -= ($timing * $bias);;

        do {
            my ($start, $rows_rendered, $raw_dur, $dur, $raw_fps, $fps);

            $start         = time;
            $rows_rendered = 0;

            my @frame;
            foreach my ($x1, $x2) ( @row_idxs ) {
                push @frame => join '' => map {
                    colored( PIXEL,
                        sprintf 'r%dg%db%d on_r%dg%db%d' => map {
                            # scale them to 255
                            $_ > 255 ? 255 : $_ <= 0 ? 0 : int($_)
                        } (
                            $shader->( $x1, $_, $ticks ),
                            $shader->( $x2, $_, $ticks )
                        )
                    )
                } @col_idxs;
            }

            $tc->Tgoto(CLEAR_LINE, 0, 0, *$fh);
            foreach my $i ( 0 .. $#frame ) {
                if ( $frame[$i] ne $buffer[$i] ) {
                    print $frame[$i];
                    $rows_rendered++;
                }
                $tc->Tputs(TO_NEXT_LINE, 1, *$fh);
            }

            @buffer = @frame;

            $raw_dur = time - $start;
            $raw_fps = 1 / $raw_dur;

            sleep( $timing - $raw_dur ) if $raw_dur < $timing;

            $dur = time - $start;
            $fps = 1 / $dur;

            printf('tick: %05d | lines-drawn: %03d | fps: %3d | raw-fps: ~%.02f | time(ms): %.05f | raw-time(ms): %.05f',
                   $ticks, $rows_rendered, ceil($fps), $raw_fps, $dur, $raw_dur);

        } while ++$ticks;
    }
}

my $FPS = $ARGV[0] // 60;
my $W   = $ARGV[1] // 120;
my $H   = $ARGV[2] // 60;

my $d = VideoDisplay->new( $W, $H, $FPS )
            ->turn_on
            ->run_shader(sub ($x, $y, $t) {
                my $div = $t / 255;
                my $mod = $t % 255;

                (($div % 2) == 0) ? $mod : (255 - $mod),
                $x,
                $y,
            });


1;

__END__





