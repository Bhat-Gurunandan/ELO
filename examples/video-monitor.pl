#!perl

use v5.36;
use experimental 'try', 'builtin', 'for_list';

use Data::Dumper;

package VideoDisplay {
    use v5.36;
    use experimental 'for_list';

    use Time::HiRes qw[ sleep time ];

    $|++;

    use constant HIDE_CURSOR  => "\e[?25l";
    use constant SHOW_CURSOR  => "\e[?25h";
    use constant HOME_CURSOR  => "\e[0;0H";
    use constant CLEAR_SCREEN => "\e[0;0H;\e[0J";
    use constant RESET        => "\e[0m";

    use constant PIXEL        => '▀';
    use constant PIXEL_FORMAT => "\e[38;2;%d;%d;%d;48;2;%d;%d;%d;m".PIXEL;

    sub new ($class, $width, $height, $refresh) {
        my $self = {
            refresh   => ($refresh // die 'A `refresh` is required'),
            width     => ($width   // die 'A `width` is required'),
            height    => ($height  // die 'A `height` is required'),
            # ...
            _row_idxs => [ 0 .. ($height-1) ],
            _col_idxs => [ 0 ..  ($width-1) ],
            _timing   => 0,
        };

        # calculate a reasonable refresh rate
        if ($refresh) {
            my $bias  = 0.0999999999;
               $bias -= ($refresh - 60) * 0.001 if $refresh > 60;

            my $timing  = (1 / $refresh);
               $timing -= ($timing * $bias);

            $self->{_timing} = $timing;
        }

        bless $self => $class;
    }

    sub turn_on ($self) {
        print HIDE_CURSOR;
        print CLEAR_SCREEN;
        $self;
    }

    sub turn_off ($self) {
        print SHOW_CURSOR;
        print CLEAR_SCREEN;
        print RESET;
        $self;
    }

    sub run_shader ($self, $shader) {
        # FIXME: respect previously set singal
        # but not really urgent now
        local $SIG{INT} = sub { $self->turn_off; exit(0) };

        my @row_idxs = $self->{_row_idxs}->@*;
        my @col_idxs = $self->{_col_idxs}->@*;

        #use Data::Dumper;
        #die Dumper [
        #    (join ', ' => @row_idxs),
        #    (join ', ' => @col_idxs),
        #    '---',
        #    (join ', ' => $self->{_row_idxs}->@*),
        #    (join ', ' => $self->{_col_idxs}->@*),
        #];

        my $ticks   = 0;
        my $refresh = $self->{refresh};
        my $timing  = $self->{_timing};

        my ($start,
            $dur, $dur_acc, $dur_actual_acc,
            $fps, $avg_fps, $actual_fps) =
            (0,0,0,0,0,0,0);

        my $shader_harness = sub {
            foreach my ($x1, $x2) ( @row_idxs ) {
                foreach my $y ( @col_idxs ) {
                    printf( PIXEL_FORMAT,
                        $shader->( $x1, $y, $ticks ),
                        $shader->( $x2, $y, $ticks ),
                    );
                }
                say '';
            }
        };

        my $harness = $shader_harness;

        do {
            $start = time;

            print HOME_CURSOR;
            $harness->();
            print RESET;

            $dur      = time - $start;
            $fps      = 1 / $dur;
            $dur_acc += $dur;

            sleep( $timing - $dur ) if $refresh && $dur < $timing;

            $dur_actual_acc += time - $start;

            (
                ($actual_fps = (1 / ($dur_acc        / $ticks))),
                ($avg_fps    = (1 / ($dur_actual_acc / $ticks)))

            ) if $ticks && ($ticks % 10) == 0;

            printf('frame: %05d | fps: %.02f | ~fps: %.02f | time(ms): %.03f | runtime(ms): %.03f | elapsed(ms): %.03f',
                   $ticks, $avg_fps, $actual_fps, $dur, $dur_acc, $dur_actual_acc);

        } while ++$ticks; # <= 300; # ... for running NYTProf

        $self->turn_off;
    }
}


my $FPS = $ARGV[0] // 60;
my $W   = $ARGV[1] // 120;
my $H   = $ARGV[2] // 60;

die "Height must be a even number, ... or reall weird stuff happens" if ($H % 2) != 0;

my $d = VideoDisplay->new( $W, $H, $FPS )
            ->turn_on
            ->run_shader(sub ($x, $y, $t) {

                return (55,55,55) if $x == 0 || $x == ($H-1);
                return (55,55,55) if $y == 0 || $y == ($W-1);

                return (0, 0, 0) if $x < 4 || $x > ($H-5);
                return (0, 0, 0) if $y < 4 || $y > ($W-5);

                #return $t, $x, $y;

                my $r = ((($t / 255) % 2) == 0) ? ($t % 255) : (255 - ($t % 255));
                my $g = $x;
                my $b = $y;

                # make some plaid ...
                my $bump = 10;
                foreach ( 6, 4, 8 ) {
                    ($r+=$bump, $g+=$bump, $b+=$bump) if ($y % $_) == 0;
                    ($r+=$bump, $g+=$bump, $b+=$bump) if ($x % $_) == 0;
                    $bump += ($bump < 0) ? 10 : -5;
                }

                # make sure we don't overflow ...
                $r = 255 if $r > 255;
                $g = 255 if $g > 255;
                $b = 255 if $b > 255;

                $r = 0 if $r < 0;
                $g = 0 if $g < 0;
                $b = 0 if $b < 0;

                return $r, $g, $b;
            });

1;

__END__

#  fps | time in milliseconds
# -----+---------------------
#  120 | 0.00833
#  100 | 0.01000
#   60 | 0.01667
#   50 | 0.02000
#   30 | 0.03333
#   25 | 0.04000
#   10 | 0.10000

CURSOR MOVEMENTS:
    https://en.wikipedia.org/wiki/ANSI_escape_code#CSI_(Control_Sequence_Introducer)_sequences


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
#   it would be possible to "tint" this display
#       given a base RGB value, we just dark/lighten it
#
# RGB( 0 .. 255, 0 .. 255, 0 .. 255 )
#   24 bit color display
#       using 1/2 boxes & fg+bg colors
#       basicaly what I have below
#   in theory we could also support lower bit-depths
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



