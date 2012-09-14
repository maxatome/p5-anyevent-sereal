use strict;
use warnings;
package AnyEvent::Sereal;

use AnyEvent ();
use AnyEvent::Handle;

our $SERIALIZED_MAX_SIZE = 1_000_000; # bytes

{
    package # hide from pause
        AnyEvent::Handle;

    use Sereal::Encoder 'encode_sereal';

    # push_write(sereal => $data, [$options])
    register_write_type(
        sereal => sub
        {
            shift;              # $self not needed

            pack "w/a*", encode_sereal(shift, @_);
        });

    use Sereal::Decoder 'decode_sereal';

    # push_read(sereal => [$sereal_options], $cb->($hdl, $data))
    register_read_type(
        sereal => sub
        {
            my($self, $cb, $options) = @_;

            return sub
            {
                # when we can use 5.10 we can use ".", but for 5.8 we
                # use the re-pack method
                defined(my $len = eval { no warnings 'uninitialized';
                                         unpack "w", $_[0]{rbuf} })
                    or return;

                if ($len > $AnyEvent::Sereal::SERIALIZED_MAX_SIZE)
                {
                    $self->_error(Errno::E2BIG);
                    return;
                }

                my $format = length pack "w", $len;

                if ($format + $len <= length $_[0]{rbuf})
                {
                    my $data = substr($_[0]{rbuf}, $format, $len);
                    substr($_[0]{rbuf}, 0, $format + $len, '');

                    my $dec;
                    eval { $dec = decode_sereal($data, $options); 1 }
                        or return $_[0]->_error(Errno::EBADMSG);

                    $cb->($_[0], $dec);
                }
                else
                {
                    # remove prefix
                    substr($_[0]{rbuf}, 0, $format, '');

                    # read remaining chunk
                    $_[0]->unshift_read(
                        chunk => $len, sub
                        {
                            my $dec;
                            eval { $dec = decode_sereal($_[1], $options); 1 }
                                or return $_[0]->_error(Errno::EBADMSG);

                            $cb->($_[0], $dec);
                        });
                }

                return 1;
            };
        });
}

1;
__END__

=encoding iso-8859-1

=head1 NAME

AnyEvent::Sereal - Sereal stream serializer/deserializer for AnyEvent

=head1 SYNOPSIS

    use AnyEvent::Sereal;
    use AnyEvent::Handle;

    my $hdl = AnyEvent::Handle->new(
        # settings...
    );
    $hdl->push_write(sereal => [ 1, 2, 3 ]);
    $hdl->push_read(sereal => sub {
        my($hdl, $data) = @_;
          # $data is [ 1, 2, 3 ]
    });

    # Can pass L<Sereal::Encoder> options to C<push_write>
    $hdl->push_write(sereal => 'a' x 1_000, { snappy => 1 });

    # And pass L<Sereal::Decoder> options to C<push_read>
    $hdl->push_read(sereal => { refuse_snappy => 1 }, sub { ... });

=head1 DESCRIPTION

L<AnyEvent::Sereal> is Sereal serializer/deserializer for L<AnyEvent>.

The maximum size of serialized (and possibly compressed) data is
specified by the variable
C<$AnyEvent::Sereal::SERIALIZED_MAX_SIZE>. It defaults to 1_000_000
bytes. In case received data seems to contain more than this number of
bytes, an error C<Errno::E2BIG> is given to the error handler.


=head1 SEE ALSO

L<AnyEvent::Handle> and storable filter.

L<Sereal::Encoder> and L<Sereal::Decoder>.

=head1 AUTHOR

Maxime SoulE<eacute>, E<lt>btik-cpan@scoubidou.comE<gt>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Ijenko.

http://www.ijenko.com

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
