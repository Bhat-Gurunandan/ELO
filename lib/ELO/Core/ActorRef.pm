package ELO::Core::ActorRef;
use v5.36;

use Carp 'confess';

use ELO::Constants qw[ $SIGEXIT ];

use parent 'ELO::Core::Abstract::Process';
use slots (
    actor_class => sub {},
    actor_args  => sub { +[] },
    # ...
    _actor    => sub {},      # the instance of the actor_class, with the actor_args
    _children => sub { +[] }, # any child processes created
);

sub BUILD ($self, $params) {
    $self->trap( $SIGEXIT );

    eval {
        $self->{_actor} = $self->{actor_class}->new( +{ $self->{actor_args}->%* } );
        1;
    } or do {
        my $e = $@;
        confess 'Could not instantiate actor('.$self->{actor_class}.') because: '.$e;
    };

    # we want to call the on-start event, but we want
    # it to be sure to take place in next available
    # tick of the loop. This is expecially important
    # in the root Actor, which will get created very
    # early in the lifetime of the system
    $self->loop->next_tick(sub {
        $self->{_actor}->on_start( $self )
    });
}

# ...

sub spawn_actor ($self, $actor_class, $actor_args={}, $env=undef) {
    my $child = $self->next::method( $actor_class, $actor_args, $env );
    push $self->{_children}->@* => $child;
    $self->link( $child );
    return $child;
}

# ...

sub apply ($self, $event) {
    $self->{_actor}->apply( $self, $event );
}

1;

__END__

=pod

=cut
