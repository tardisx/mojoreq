use Test::More tests => 2;
use Test::Mojo;

use FindBin;
require "$FindBin::Bin/../mojoreq.pl";

my $t = Test::Mojo->new;
$t->get_ok('/')->status_is(302);
