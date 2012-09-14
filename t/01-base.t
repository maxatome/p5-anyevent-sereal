use strict;
use warnings;

use Test::More tests => 11;

use AnyEvent;
BEGIN { require AnyEvent::Impl::Perl unless $ENV{PERL_ANYEVENT_MODEL} }
use AnyEvent::Util;
use AnyEvent::Sereal;

sub set_and_run_loop (&)
{
    my $code = shift;

    my $cv = AnyEvent->condvar;

    my($rd, $wr) = portable_socketpair;

    my $read_error;

    my $rd_ae = AnyEvent::Handle::->new (
	fh       => $rd,
	on_eof   => sub { $cv->broadcast },
	on_error => sub { $read_error = 0 + $!; $cv->broadcast },
	on_read  => sub { BAIL_OUT('No push_read waiting!!!') });

    my $wr_ae = AnyEvent::Handle::->new(
	fh     => $wr,
	on_eof => sub { BAIL_OUT('EOF on write!') });

    undef $wr;
    undef $rd;

    $code->($wr_ae, $rd_ae);

    $cv->wait;

    return $read_error;
}

my $error;

$error = set_and_run_loop
{
    my($wr_ae, $rd_ae) = @_;

    $wr_ae->push_write(sereal => [4,3,2]);
    $wr_ae->push_write(sereal => 12);
    $wr_ae->push_write(sereal => 0);
    $wr_ae->push_write(sereal => undef);
    $wr_ae->push_write(sereal => 'a' x 1000, { snappy => 1 });
    $wr_ae->push_write(sereal => bless { a => 1 }, 'FooBar');
    undef $_[0]; # undef $wr_ae in the caller context

    $rd_ae->push_read(sereal => sub { is("@{$_[1]}", "4 3 2") });
    $rd_ae->push_read(sereal => sub { is($_[1], 12) });
    $rd_ae->push_read(sereal => sub { is($_[1], 0) });
    $rd_ae->push_read(sereal => sub { is($_[1], undef) });
    $rd_ae->push_read(sereal => sub { is($_[1], 'a' x 1000) });

    $rd_ae->push_read(sereal => sub
		      {
			  my(undef, $obj) = @_;

			  isa_ok($obj, 'FooBar');
			  is_deeply($obj, { a => 1 });
		      });
};
is($error, undef);

# Errors...

# Too BIG
$error = set_and_run_loop
{
    my($wr_ae, $rd_ae) = @_;

    $wr_ae->push_write(sereal => [ ('a' x 1000) x 1000 ]);
    undef $_[0];		# undef $wr_ae in the caller context

    local $AnyEvent::Sereal::SERIALIZED_MAX_SIZE = 7;
    $rd_ae->push_read(sereal => sub { die 'push_read callback called!' });
};
is($error, 0 + Errno::E2BIG);

# Bad encoding
$error = set_and_run_loop
{
    my($wr_ae, $rd_ae) = @_;

    $wr_ae->push_write("\1<<<<<");
    undef $_[0];		# undef $wr_ae in the caller context

    $rd_ae->push_read(sereal => sub { die 'push_read callback called!' });
};
is($error, 0 + Errno::EBADMSG);

# Refuse snappy
$error = set_and_run_loop
{
    my($wr_ae, $rd_ae) = @_;

    $wr_ae->push_write(sereal => 'a' x 400_000, { snappy => 1 });
    undef $_[0]; # undef $wr_ae in the caller context

    $rd_ae->push_read(sereal => { refuse_snappy => 1 },
		      sub { die 'push_read callback called!' });
};
is($error, 0 + Errno::EBADMSG);
