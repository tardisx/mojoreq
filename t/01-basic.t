use Test::More tests => 15;
use Test::Mojo;

use FindBin;
require "$FindBin::Bin/../mojoreq.pl";

my $t = Test::Mojo->new;
# check we are redirected from the / URL
$t->get_ok('/')
  ->status_is(302)
  ->header_like(Location => qr/\/list\/open/)
  ->content_is('');

# check the list page has links to add and new
$t->get_ok('/list/open')
  ->content_like(qr/Add Request/)
  ->content_like(qr/Open Requests/);

# check the form contains our form fields
$t->get_ok('/req/add')
  ->status_is(200)
  ->content_like(qr/select name="product"/)
  ->content_like(qr/select name="category"/)
  ->content_like(qr/textarea.*description/);

$t->post_form_ok('/req/add', {subject     => $$, 
                              description => $$,
                              product => 'product1',
                              category => 'bug',
                             })
  ->status_is(302)
  ->header_like(Location => qr/\/req\/(\d+)/);

