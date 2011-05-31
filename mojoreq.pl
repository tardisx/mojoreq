#!/usr/bin/env perl

use Mojolicious::Lite;
use DBI;
use Data::Dumper;

my @request_fields = qw/id subject description complete product category modified/;
my @products = qw/product1 product2/;
my @categorys = qw/bug feature/;

my $db = DBI->connect('dbi:SQLite:dbname=mojoreq.db') || die DBI->errstr;

get '/' => sub {
  my $self = shift;
  $self->redirect_to('/list/open');
};

get '/list/:state' => sub {
  my $self = shift;

  my $state = $self->param('state');
  my $args = { complete => $state eq 'open' ? 0 : 1 };

  my $list = load_requests($args);
  
  $self->stash->{requests} = $list;
  $self->render('list');
};

get '/req/:req' => [req => qr/\d+/]  => sub {
  my $self = shift;
  my $req_id = $self->param('req');

  $self->stash->{products}  = \@products;
  $self->stash->{categorys} = \@categorys;

  load_param_from_request_id($self, $req_id);

  $self->render('req');
};

get '/req/add' => sub {
  my $self = shift;

  $self->stash->{products} = \@products;
  $self->stash->{categorys} = \@categorys;

  $self->render('req_add');
};

post '/req/:req' => [req => qr/\d+/]  => sub {
  my $self = shift;

  $self->stash->{products} = \@products;
  $self->stash->{categorys} = \@categorys;

  eval { 
    save_request_from_param($self);
  };
  if ($@) {
    $self->stash->{error} = $@;
    $self->render('req');
  }
  else {
    $self->flash(message => "Request " .$self->param('id') . " updated."); 
    $self->redirect_to('/req/'.$self->param('id'));
  }
};

post '/req/add' => sub {
  my $self = shift;
  my $request;

  $self->stash->{products} = \@products;
  $self->stash->{categorys} = \@categorys;

  eval { 
    save_request_from_param($self);
  };
  if ($@) {
    $self->stash->{error} = $@;
    $self->render('req_add');
  }
  else {
    $self->flash(message => "Request " .$self->param('id') . " created."); 
    $self->redirect_to('/req/'.$self->param('id'));
  }
};

app->start;

=pod

CREATE TABLE request (
  id       INTEGER PRIMARY KEY,
  subject  TEXT NOT NULL,
  product  TEXT NOT NULL,
  category TEXT NOT NULL,
  description TEXT NOT NULL,
  modified INTEGER NOT NULL,
  complete BOOLEAN DEFAULT 0
);

=cut

sub save_request_from_param {
  my $self = shift;

  my $req_save;
  
  foreach (@request_fields) {
    $req_save->{$_} = $self->param($_);
  }

  # validate
  die "bad subject\n" if (! $req_save->{subject});
  die "bad description\n" if (! $req_save->{description});

  # some special cases / default values
  $req_save->{modified} = time();

  # fix booleans
  $req_save->{complete} = 0 if (! $req_save->{complete});

  if ($req_save->{id}) {
    # load old record
    update_db($req_save);
  }
  else {
    my $id = insert_db($req_save);
    $self->param('id', $id);  # set the id
  }

  return;
}

sub load_param_from_request_id {
  my $self    = shift;
  my $id      = shift;

  my $request = load_db($id);

  # fix booleans
  $request->{complete} = undef if (! $request->{complete});

  foreach (@request_fields) {
    $self->param($_, $request->{$_});
  }

  return;
}

sub load_db {
  my $id = shift;
  my $sth = $db->prepare("SELECT * FROM request WHERE id = ?") || die $db->errstr;
  $sth->execute($id) || die $db->errstr;
  my $row = $sth->fetchrow_hashref();
  if (! $row) {
    die "no row fetching $id";
  }
  $sth->finish();
  return $row;
}

sub update_db {
  my $hash = shift;
  my @fields = grep !/id/, @request_fields;

  my $sql = "UPDATE request SET ";
  foreach (@fields) {
    $sql.= "$_ = ?, ";
  }
  $sql =~ s/, $/ WHERE id = ?/;

  my $sth = $db->prepare($sql) || die $db->errstr;
  $sth->execute((map {$hash->{$_}} @fields), $hash->{id}) || die $db->errstr;
  return $hash->{id};
}

sub insert_db {
  my $hash = shift;
  my @fields = grep !/id/, @request_fields;

  my $sql = "INSERT INTO request (";
  $sql.= join (',', @fields);
  $sql.= ') VALUES (';
  $sql.= join (',', map {'?'} @fields);
  $sql.= ')';

  my $sth = $db->prepare($sql) || die $db->errstr;
  $sth->execute(map {$hash->{$_}} @fields) || die $db->errstr;

  my $id = $db->last_insert_id(undef, undef, undef, undef);
  die "no id?" unless $id;
  return $id;
}

sub load_requests {
  my $args = shift || {};
  $args->{complete} = 0 if (! $args->{complete});
  
  my $sth = $db->prepare("SELECT * FROM request WHERE complete = ?");
  $sth->execute($args->{complete});

  my @list;
  
  while (my $row = $sth->fetchrow_hashref()) {
    push @list, $row;
  }
  
  return \@list;
}

__DATA__

@@ index.html.ep
% layout 'default';
% title 'Welcome';
Welcome to Mojolicious!

@@ req.html.ep
% layout 'default';
% title 'Request ' . param('id') . ' - ' . param('subject');
<%= include 'req_form' %>

@@ req_add.html.ep
% layout 'default';
% title 'Add Request';
<%= include 'req_form' %>

@@ req_form.html.ep
% my $form_dest = param('id') ? param('id') : 'add';
<%= form_for $form_dest => (method => 'post') => begin %>

% if (param('id')) {
  <%= hidden_field 'id' => param('id') %>
% }


<table>
  <tr>
    <th>Subject:</th>
    <td><%= text_field 'subject', size => 65 %></td>
  </tr>

  <tr>
    <th>Product:</th>
    <td><%= select_field product => stash('products') %>
  </tr>

  <tr>
    <th>Category:</th>
    <td><%= select_field category => stash('categorys') %>
  </tr>

  <tr>
    <th>Description:</th>
    <td><%= text_area 'description', rows => 8, cols => 45 %></td>
  </tr>

  <tr>
    <th>Complete?:</th>
    <td><%= check_box 'complete' => 1 %></td>
  </tr>

</table>

<%= submit_button %>

<% end %>

@@ list.html.ep
% layout 'default';
% title 'List';
% use Time::Duration qw/ago concise/;
<table>
  <tr>
    <th>id</th>
    <th>product</th>
    <th>category</th>
    <th>subject</th>
    <th>last modified</th>
  </tr>
% foreach (@$requests) {
  <tr>
    <th><%= link_to reqreq => {req => $_->{id} } => begin %> <%= $_->{id} %> <% end %></th>
    <td><%= $_->{product} %></td>
    <td><%= $_->{category} %></td>
    <td><%= $_->{subject} %></td>
    <td><%= concise(ago(time()- $_->{modified})) %></td>
  </tr>
% }
</table>
 
% if (! @$requests) {
<p>No records</p>
% }

@@ layouts/default.html.ep
<!doctype html><html>
  <head><title><%= title %></title>
  <style type="text/css" media="screen, print, projection">
	body,
	html {
		margin:0;
		padding:0;
		color:#000;
		background:#a7a09a;
                font-family: Verdana, Arial, Helvetica, Sans-Serif;
                font-size: 8pt;

	}
	#wrap {
		width:850px;
		margin:0 auto;
		background:#99c;
	}
	#header {
    	padding:5px 10px;
		background:#ddd;
	}
	h1 {
	    margin:0;
        }
	#nav {
		padding:5px 10px;
		background:#c99;
	}
	#nav ul {
		margin:0;
		padding:0;
		list-style:none;
	}
	#nav li {
		display:inline;
		margin:0;
		padding:0;
	}
	#main {
		float:left;
		width:580px;
		padding:10px;
		background:#9c9;
	}
	h2 {
		margin:0 0 1em;
	}
	#sidebar {
		float:right;
		width:230px;
		padding:10px;
		background:#99c;
	}
	#footer {
		clear:both;
		padding:5px 10px;
		background:#cc9;
	}
	#footer p {
		margin:0;
        }
        a:link    {color: blue}
        a:visited {color: blue}
        a:active  {color: blue}
        a:hover   {color: red;}
        p.message {
                color: #32e;
                font-size: 14px;
        }
        p.error {
                color: #f00;
                font-size: 14px;
        }
	* html #footer {
		height:1px;
	}
	</style>
  </head>
  <body>
  <div id="wrap">
    <div id="header">
      <h1><%= title %></h1>
    </div>
    <div id="nav">
      <ul>
        <li>[<a href="/req/add">Add a new request</a>]</li>
        <li>[<a href="/list/open">List open requests</a>]</li>
      </ul>
    </div>
    <div id="main">
<% if (my $message = flash 'message' ) { %>
      <p class="message"><%= $message %></p>
<% } %>
<% if (my $error = stash 'error' ) { %>
      <p class="error"><%= $error %></p>
<% } %>
      <%= content %>
    </div>
    <div id="sidebar">
    </div>
    <div id="footer">
      <p>MojoReq: [<a href="https://github.com/tardisx/mojoreq">https://github.com/tardisx/mojoreq</a>]</p>
    </div>
  </div>
</body>
</html>
