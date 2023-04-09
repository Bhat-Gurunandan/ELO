#!perl

use v5.24;
use warnings;
use experimental qw[ signatures lexical_subs postderef ];

use Data::Dumper;

use ELO::Loop;
use ELO::Timers qw[
    timer
    cancel_timer
    interval
    cancel_interval
];

use ELO::Util::Logger;

my $log = ELO::Util::Logger->new;

sub Responder ($this, $msg) {
    $log->debug( $this, "ENTERED" );

    $log->info( $this, $msg );
}

sub init ($this, $msg) {
    $log->debug( $this, "ENTERED" );
    my $r = $this->spawn( Responder => \&Responder );

    my $t0 = timer( $this, 0, [ $r, ['Hello ... timeout(0)'] ] );
    my $t1 = timer( $this, 1, [ $r, ['Hello ... timeout(1)'] ] );
    my $t2 = timer( $this, 2, [ $r, ['Hello ... timeout(2)'] ] );

    my $t5 = timer( $this, 5, [ $r, ['Hello ... timeout(5)'] ] );
    my $t3 = timer( $this, 3, sub { cancel_timer( $t5 ) } );

    my $i0 = interval( $this, 3, [ $r, ['Hello ... interval(3)'] ] );
    my $i2 = timer( $this, 10, sub { cancel_interval( $i0 ) } );

}

ELO::Loop->run( \&init );

1;
