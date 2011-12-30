use Test::More tests => 26;
use Test::Mojo;
use strict;

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

my %req_details = ( subject     => "mojoreq_test_subject_$$",
                    description => "mojoreq_test_description_$$",
                    product     => 'product1',
                    category    => 'bug' );

$t->post_form_ok('/req/add', { %req_details })
  ->status_is(302)
  ->header_like(Location => qr/\/req\/\d+/);

my $url = $t->tx->res->headers->header('location');
my ($new_request_num) = ($url =~ /(\d+)$/);

# now the list of open bugs should contain this bug
$t->get_ok('/list/open')
  ->content_like(qr/$new_request_num/)
  ->content_like(qr/$$/);   # and the subject

# close it and check again
$t->post_form_ok("/req/$new_request_num",
                 { %req_details,
                   id       => $new_request_num, 
                   complete => 1 })
  ->status_is(302);

$t->get_ok('/list/open')
  ->content_unlike(qr/$$/)   # should no longer see that subject
  ->content_like(qr/request $new_request_num updated/i); # but we should see the update message (flash)

# and we should find it in the closed list
$t->get_ok('/list/closed')
  ->content_like(qr/$new_request_num/)
  ->content_like(qr/$$/);   # and the subject
