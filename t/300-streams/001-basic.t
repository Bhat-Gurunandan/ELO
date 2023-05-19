#!perl

use v5.36;

use Test::More;

use constant DEBUG => 1;

=pod

This is an example of "cold" streams in that
they are not async  at all.

=cut

use ELO::Stream;

# ...

package MySubscription {
    use v5.36;

    use parent 'UNIVERSAL::Object::Immutable';
    use roles 'ELO::Stream::Core::Subscription';
    use slots;

    sub BUILD ($self, $) {
        $self->publisher->roles::DOES('ELO::Stream::Iterator')
            || die 'The `publisher` must do the `ELO::Stream::Iterator` role ('.$self->publisher.')';

        $self->subscriber->roles::DOES('ELO::Stream::Refreshable')
            || die 'The `subscriber` must do the `ELO::Stream::Refreshable` role ('.$self->subscriber.')';
    }

    sub request ($self, $num_elements) {
        warn "MySubscription::request($num_elements) called\n" if main::DEBUG();
        my $complete = 0;
        for (1 .. $num_elements) {
            if ( $self->publisher->has_next ) {
                $self->subscriber->on_next(
                    $self->publisher->next
                );
            }
            else {
                $self->subscriber->on_complete;
                $complete++;
                last;
            }
        }

        return if $complete;

        warn "/// MySubscription::request($num_elements) should we refresh ????\n" if main::DEBUG();
        if ( $self->subscriber->should_refresh ) {
            $self->subscriber->refresh( $self );
        }
    }
}

package MySubscriber {
    use v5.36;

    use parent 'UNIVERSAL::Object';
    use roles 'ELO::Stream::Core::Subscriber',
              'ELO::Stream::Core::Subscriber::AutoRefresh';

    use slots (
        total_seen => sub { 0 },
        seen       => sub { 0 },
    );

    sub on_subscribe ($self, $subscription) {
        warn "<<<<<<<<<<<<< MySubscriber::on_subscribe called with ($subscription)\n" if main::DEBUG();
        $self->refresh( $subscription );
        $self->{total_seen} = 0;
        $self->{seen}       = 0;
    }

    sub should_refresh ($self) {
        warn "MySubscriber::should_refresh called seen(".$self->{seen}.")\n" if main::DEBUG();
        $self->{seen} == $self->request_size
    }

    sub on_refresh ($self, $subscription) {
        warn ">>>>>>>>>>>>> MySubscriber::on_refresh called with ($subscription)\n" if main::DEBUG();
        $self->{seen} = 0;
    }

    sub on_next ($self, $v) {
        warn "MySubscriber::on_next called with ($v)\n" if main::DEBUG();
        $self->{total_seen}++;
        $self->{seen}++;
    }

    sub on_complete ($self) {
        warn "++++++++++++++++ MySubscriber::on_complete called\n" if main::DEBUG();
    }
}

package MyPublisher {
    use v5.36;

    use parent 'UNIVERSAL::Object';
    use roles  'ELO::Stream::Core::Publisher',
               'ELO::Stream::Iterator';

    use slots (
        counter   => sub { 0 },
        max_value => sub { 300 },
    );

    sub create_subscription_for ($self, $subscriber) {
        MySubscription->new(
            publisher  => $self,
            subscriber => $subscriber
        )
    }

    sub has_next ($self) {
        warn "MyPublisher::has_next called\n" if main::DEBUG();
        $self->{counter} <= $self->{max_value}
    }

    sub next ($self) {
        warn "MyPublisher::next called\n" if main::DEBUG();
        return $self->{counter}++;
    }
}

my $s = MySubscriber->new( request_size => 10 );
my $p = MyPublisher
            ->new( max_value => 50 )
            ->subscribe( $s );

ok(1);

done_testing;

1;

__END__
