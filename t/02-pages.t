use Test::More tests => 183;
use Test::Mojo;
use strict;

$ENV{MOJO_CONFIG} = 'mojoreq.json-sample';

use FindBin;
require "$FindBin::Bin/../mojoreq.pl";

my $t = Test::Mojo->new;
# create 60 tickets
foreach my $item (1..60) {
  my %req_details = ( subject     => "mojoreq_test_subject_page_${item}_$$",
                      description => "mojoreq_test_description_page_${item}_$$",
                      product     => 'product1',
                      category    => 'bug' );
  
  $t->post_form_ok('/req/add', { %req_details })
     ->status_is(302)
     ->header_like(Location => qr/\/req\/\d+/);
}


# now the list of open bugs should span more than one page
$t->get_ok('/list/open')
  ->content_like(qr/Next/)
  ->content_unlike(qr/Prev/);  # no previous on first page


