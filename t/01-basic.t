use Test::More tests => 4;
use Test::Mojo;

use FindBin;
require "$FindBin::Bin/../mojoreq.pl";

my $t = Test::Mojo->new;
$t->get_ok('/')
  ->status_is(302)
  ->header_like(Location => qr/\/list\/open/)
  ->content_is('');

