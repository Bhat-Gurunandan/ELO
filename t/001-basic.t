#!perl

use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Test::More;
use Data::Dumper;

my @msg_queue;
my %processes;

sub send_to ($pid, $msg) {
    push @msg_queue => [ $pid, $msg ];
}

sub loop ( $MAX_TICKS ) {

    my $tick = 0;
    while ($tick < $MAX_TICKS) {
        $tick++;

        # deliver all the messages in the queue
        while (@msg_queue) {
            my $next = shift @msg_queue;
            my ($pid, $m) = $next->@*;
            unless (exists $processes{$pid}) {
                warn "Got message for unknown pid($pid)";
                next;
            }
            push $processes{$pid}->[0]->@* => $m;
        }

        my @active = values %processes;
        while (@active) {
            my $active = shift @active;
            my ($mbox, $env, $f) = $active->@*;

            if ( $mbox->@* ) {
                $f->($env, shift $mbox->@* );
                # if we still have messages
                if ( $mbox->@* ) {
                    # handle them in the next loop ...
                    push @active => $active;
                }
            }
        }

        say "---------------------------- tick($tick)";
    }

}

%processes = (
    out => [
        [],
        {},
        sub ($env, $msg) {
            say( "OUT => $msg" );
        },
    ],
    alarm => [
        [],
        {},
        sub ($env, $msg) {
            my ($timer, $event) = @$msg;
            if ( $timer == 0 ) {
                send_to( out => "!alarm! DONE");
                send_to( @$event );
            }
            else {
                send_to( out => "!alarm! counting down $timer" );
                send_to( alarm => [ $timer - 1, $event ] );
            }
        },
    ],
    env => [
        [],
        {},
        sub ($env, $msg) {
            if ( scalar @$msg == 2 ) {
                my ($key, $value) = @$msg;
                send_to( out => "storing $key => $value");
                $env->{$key} = $value;
            }

            send_to( out => "ENV{ ".(join ', ' => map { join ' => ' => $_, $env->{$_} } keys %$env)." }");
        },
    ],
    main => [
        [],
        {},
        sub ($env, $msg) {
            send_to( out => "->main starting ..." );
            send_to( env => [ foo => 10 ] );
            send_to( env => [ bar => 20 ] );
            send_to( alarm => [ 2, [ env => [ baz => 30 ] ]] );
            send_to( alarm => [ 15, [ env => [ gorch => 50 ] ]] );
        },
    ],
);

# initialise ...
send_to( main => 1 );
# loop ...
loop( 20 );

done_testing;
