#!/usr/bin/env perl

use Mojolicious::Lite;
use DBI;
use Data::Dumper;

my @request_fields = qw/id subject description complete modified/;

my $db = DBI->connect('dbi:SQLite:dbname=mojoreq.db') || die DBI->errstr;

get '/' => sub {
  my $self = shift;
  my $list = load_requests();
  $self->stash->{requests} = $list;
  $self->render('list');
};

get '/req/:req' => [req => qr/\d+/]  => sub {
  my $self = shift;
  my $req_id = $self->param('req');

  load_param_from_request_id($self, $req_id);

  $self->render('req');
};

get '/req/add' => sub {
  my $self = shift;
  $self->render('req_add');
};

post '/req/:req' => [req => qr/\d+/]  => sub {
  my $self = shift;
  eval { 
    save_request_from_param($self);
  };
  if ($@) {
    $self->stash->{error} = $@;
    $self->render('req');
  }
  else {
    $self->render('req');
  }
};

post '/req/add' => sub {
  my $self = shift;
  my $request;
  eval { 
    save_request_from_param($self);
  };
  if ($@) {
    $self->stash->{error} = $@;
    $self->render('req_add');
  }
  else {
    $self->redirect_to('/req/'.$self->param('id'));
  }
};

get '/welcome' => sub {
  my $self = shift;
  $self->render('index');
};

app->start;

=pod

CREATE TABLE request (
  id       INTEGER PRIMARY KEY,
  subject  TEXT NOT NULL,
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

  # some special cases / default values
  $req_save->{subject} = '[no subject]' if (! $req_save->{subject});
  $req_save->{modified} = time();

  # fix booleans
  $req_save->{complete} = 0 if (! $req_save->{complete});

  warn "UPDATING: " .Dumper $req_save;

  if ($req_save->{id}) {
    warn "ITS AN UPDATE!";
    update_db($req_save);
  }
  else {
    warn "ITS AN INSERT";
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
    warn "SETTING $_ to $request->{$_}";
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

  warn "EXECUTING $sql";

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
  my @list;
  my $sth = $db->prepare("SELECT * FROM request WHERE complete = 0");
  $sth->execute();
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
% title 'Request ' . param('id');
<p>Looking at record <%= param('id') %>?</p>
<%= include 'req_form' %>

@@ req_add.html.ep
% layout 'default';
% title 'Add Request';
<p>Add that request!</p>
<%= include 'req_form' %>

@@ req_form.html.ep
% my $form_dest = param('id') ? param('id') : 'add';
<%= form_for $form_dest => (method => 'post') => begin %>

% if (param('id')) {
  <%= hidden_field 'id' => param('id') %>
  <p>Record: <%= param('id') %></p>
% } else {
  <p>Record: New</p>
% }

<table>
  <tr>
    <td>Subject:</td>
    <td><%= text_field 'subject', size => 80 %></td>
  </tr>

  <tr>
    <td>Complete?:</td>
    <td><%= check_box 'complete' => 1 %></td>
  </tr>
  <tr>
    <td>Description:</td>
    <td><%= text_area 'description', rows => 8, cols => 80 %></td>
  </tr>
</table>

<%= submit_button %>

<% end %>

% if (stash('error')) {
<h4><%= stash('error') %></h4>
% }

@@ list.html.ep
% layout 'default';
% title 'List';
<table>
% foreach (@$requests) {
<tr>
  <th><%= $_->{id} %></th>
  <td><a href="/req/<%= $_->{id} %>"><%= $_->{subject} =%></a></td>
  <td><%= scalar localtime ($_->{modified}) %></td>
</tr>
% }
</table>

@@ layouts/default.html.ep
<!doctype html><html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>
