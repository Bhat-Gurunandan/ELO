#!perl

use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Test::More;
use List::Util 'first';
use Data::Dumper;

use EventLoop;
use EventLoop::Actors;
use EventLoop::IO;

actor bounce => sub ($env, $msg) {
    match $msg, +{
        up => sub ($body) {
            my ($cnt) = @$body;
            out::print("bounce(UP) => $cnt");
            send_to( PID, down => [$cnt+1] )
        },
        down => sub ($body) {
            my ($cnt) = @$body;
            out::print("bounce(DOWN) => $cnt");
            send_to( PID, up => [$cnt+1] );
        }
    };
};

actor main => sub ($env, $msg) {
    out::print("-> main starting ...");

    my $bounce = spawn( 'bounce' );
    send_to( $bounce, up => [1] );

    timeout( 10,
        sequence(
            out::print("JELLO!"),
            [ SYS, kill => [$bounce]]
        ));
};

# loop ...
ok loop( 20, 'main' );

done_testing;

