#!/usr/bin/env perl

################################################################################
# Define the 'email' command package.
package Mojolicious::Command::email;

# Subclass
use Mojo::Base 'Mojo::Command';

# Take care of command line options
use Getopt::Long 'GetOptions';

# Short description
has description => <<'EOF';
My first Mojo command.
EOF

# Short usage message
has usage => <<"EOF";
usage: $0 email [OPTIONS]

These options are available:
* TBA
EOF

sub run {
  my $self = shift;

  # Handle options
  local @ARGV = @_;
  # GetOptions('something' => sub { $something = 1 });

  # digest the email
  local $/ = undef;
  my $email = <>;

  warn "Unimplemented - sorry\n";
  exit 1;
}

################################################################################
# main package here
package main;

use Mojolicious::Lite;

use DBI;
use Data::Page;

my @request_fields = qw/id subject description complete product 
                        category created modified/;
my $config = plugin 'JSONConfig';

my @products       = @{ $config->{products} };
my @categorys      = @{ $config->{categories} };

my $dbname = $config->{db};

# get a DBH handle, initialising the DB if necessary.
my $db = initialise_db();

# initialise the pager
my $pager = Data::Page->new();
$pager->entries_per_page($config->{page_size});

# routes
get '/' => sub {
  my $self = shift;
  $self->redirect_to($self->url_for('liststate', state=>'open'));
};

get '/list/:state' => sub {
  my $self = shift;

  my $state = $self->param('state');
  my $args = { complete => $state eq 'open' ? 0 : 1 };

  my $list;
  if ($self->param('page') && $self->param('page') eq 'all') {
    $list = load_requests($args);
    $self->stash->{pager} = undef;
  }
  else {
    # use the pager
    $pager->total_entries(count_requests($args));
    $pager->current_page($self->param('page') || 1);
    $list = load_requests($args, $pager);
    $self->stash->{pager}    = $pager;
  }
  
  $self->stash->{requests} = $list;
  $self->render('list');
};

get '/req/:req' => [req => qr/\d+/]  => sub {
  my $self = shift;
  my $req_id = $self->param('req');

  $self->stash->{products}  = \@products;
  $self->stash->{categorys} = \@categorys;
  $self->stash->{log_sth}   = get_log_handle($req_id);

  eval {
    load_param_from_request_id($self, $req_id);
  };
  
  if ($@ =~ /no row/) {
    $self->stash->{error} = "no such request";
    $self->render('error');
    return;
  }

  else {
    $self->render('req');
    return;
  }
};

get '/req/add' => sub {
  my $self = shift;

  $self->stash->{products} = \@products;
  $self->stash->{categorys} = \@categorys;

  $self->render('req_add');
};

post '/req/:req' => [req => qr/\d+/]  => sub {
  my $self = shift;
  my $req_id = $self->param('req');

  $self->stash->{products} = \@products;
  $self->stash->{categorys} = \@categorys;

  eval {
    my $id = $self->param('req');
    my $old = load_db($id);
    save_request_from_param($self);
    my $new = load_db($id); 
    foreach my $diff (differences($old, $new)) {
      add_audit($id, 'change', $diff);
    }
  };
  
  if ($@ =~ /no row/) {
    $self->stash->{error} = "no such request";
    $self->render('error');
  }
  elsif ($@) {
    $self->stash->{error} = $@;
    # load the logs again since we are going to redisplay
    $self->stash->{log_sth} = get_log_handle($req_id);
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
    $self->flash(message => "Request " .$self->param('id') . " created"); 
    $self->redirect_to('/req/'.$self->param('id'));
  }
};

app->start;

sub save_request_from_param {
  my $self = shift;

  my $req_save;

  # don't mess with the created date
  my @fields = grep !/created/, @request_fields;
  
  foreach (@fields) {
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
    $req_save->{created} = time();
    my $id = insert_db($req_save);
    $self->param('id', $id);  # set the id
  }

  add_audit($self->param('id'), 'log', $self->param('log')) 
    if ($self->param('log'));

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

sub get_log_handle {
  my $id = shift;
  my $sth = 
    $db->prepare("SELECT * FROM request_audit WHERE rid = ? ORDER BY ts")
    || die $db->errstr;
  $sth->execute($id) || die $db->errstr;
  return $sth;
}

sub update_db {
  my $hash = shift;
  my @fields = grep !/^id$|^created$/, @request_fields;

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

sub count_requests {
  my $args = shift || {};

  $args->{complete} = 0 if (! $args->{complete});
  
  my $sth = $db->prepare("SELECT count(*) FROM request WHERE complete = ?")
    || die $db->errstr;
  $sth->execute($args->{complete}) || die "query failed: " . $db->errstr;

  return $sth->fetchrow_arrayref->[0];
}


sub load_requests {
  my $args = shift || {};
  my $pager = shift;

  $args->{complete} = 0 if (! $args->{complete});
  
  my $sth;
  if ($pager) {
    $sth = $db->prepare("SELECT * FROM request WHERE complete = ? LIMIT ?, ?") 
      || die $db->errstr;
    $sth->execute($args->{complete}, $pager->skipped, $pager->entries_per_page);
  }
  else {
    $sth = $db->prepare("SELECT * FROM request WHERE complete = ?")
      || die $db->errstr;
    $sth->execute($args->{complete});
  } 

  my @list;
  
  while (my $row = $sth->fetchrow_hashref()) {
    push @list, $row;
  }
  
  return \@list;
}

sub differences {
  my ($old, $new) = @_;
  my @diffs;
  foreach (@request_fields) {
    if ($old->{$_} ne $new->{$_}) {
        push @diffs, "$_: changed from $old->{$_} to $new->{$_}";
    }
  }
  return @diffs;
}
  
sub add_audit {
  my ($id, $type, $entry) = @_;
  # ignore some things
  return if ($entry =~ /^modified/);
  my $sth = $db->prepare("INSERT INTO request_audit (rid, ts, type, entry) VALUES (?, ?, ?, ?)")
    || die $db->errstr;
  $sth->execute($id, time(), $type, $entry) || die $db->errstr;
  return;    
}

sub initialise_db {

  my $initdb = 0;
  if (!-e $dbname) {
    $initdb = 1;
  }
  
  my $db = DBI->connect("dbi:SQLite:dbname=$dbname") || die DBI->errstr;

  if ($initdb) {
    $db->do('
CREATE TABLE request (
  id          INTEGER PRIMARY KEY,
  subject     TEXT NOT NULL,
  product     TEXT NOT NULL,
  category    TEXT NOT NULL,
  description TEXT NOT NULL,
  created     INTEGER NOT NULL,
  modified    INTEGER NOT NULL,
  complete    BOOLEAN DEFAULT 0
);
') || die "Could not initialise DB: " . $db->errstr;

    $db->do('
CREATE TABLE request_audit (
  id        INTEGER PRIMARY KEY,
  rid       INTEGER REFERENCES request(id),
  ts        INTEGER NOT NULL,
  type      TEXT NOT NULL,
  entry     TEXT NOT NULL
);
') || die "Could not initialise DB: " . $db->errstr;

    warn "Database initialised.\n";

  }
  return $db;
}

################################################################################

__DATA__

@@ index.html.ep
% layout 'default';
% title 'Welcome';
Welcome to Mojolicious!

@@ error.html.ep
% layout 'default';
% title 'Error';

<p>Sorry, an error occurred.</p>

@@ req.html.ep
% layout 'default';
% title 'Request ' . param('id') . ' - ' . param('subject');
<%= include 'req_form' %>
<%= include 'req_logs' %>

@@ req_logs.html.ep
% use Time::Duration qw/ago concise/;
<table>
% while (my $log = $log_sth->fetchrow_hashref) {
<tr>
  <th>
    <%= $log->{type} %>
  </th>
  <td>
    <%= concise(ago(time()-$log->{ts})) %>
  </td>
  <td>
    <%= $log->{entry} %>
  </td>
</tr>
% }
</table>

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

% my $size_adjust = 0;
% if ($self->req->headers->user_agent =~ /iPhone/) {
%   $size_adjust = 20;
% }

<table>
  <tr>
    <th>Subject:</th>
    <td><%= text_field 'subject', class => 'span12' %></td>
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
    <td><%= text_area 'description', class => 'span12', rows => 8 %></td>
  </tr>

  <tr>
    <th>Complete?:</th>
    <td><%= check_box 'complete' => 1 %></td>
  </tr>

  <tr>
    <th>Log:</th>
    <td><%= text_area 'log', class => 'span12', rows => 8 %></td>
  </tr>
</table>

<%= submit_button 'Save changes', class => 'btn primary' %>

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

% if (stash 'pager') {
%   if ($pager->previous_page) {
[ <a href="<%= url_for('current')->query(page => $pager->previous_page) %>">Prev</a> ]
%   }
%   if ($pager->next_page) {
[ <a href="<%= url_for('current')->query(page => $pager->next_page) %>">Next</a> ]
%   }
% }

@@ layouts/default.html.ep
<!doctype html><html>
  <head>
    <title><%= title %></title>
    <link rel="apple-touch-icon" href="/apple.png" />
    <link rel="shortcut icon" href="/mojoreq.ico" />
% if ($self->req->headers->user_agent =~ /iPhone/) {
    <meta name="viewport" content="user-scalable=no, width=device-width" />
% }
    <link rel="stylesheet" href="http://twitter.github.com/bootstrap/1.4.0/bootstrap.min.css">
  </head>
  <body style="padding-top: 40px;">

  <!-- Topbar -->
  <div class="topbar" data-scrollspy="scrollspy" >
    <div class="topbar-inner">
      <div class="container">
        <a class="brand" href="/">Mojoreq</a>
        <ul class="nav">
          <li><a href="<%= url_for('reqadd') %>">Add Request</a></li>
          <li><a href="<%= url_for('liststate', state => 'open') %>">Open Requests</a></li>
          <li><a href="<%= url_for('liststate', state => 'closed') %>">Closed Requests</a></li>
        </ul>
      </div>
    </div>
  </div>

  
  <div class="container">
    <h1><%= title %></h1>
<% if (my $error = stash 'error' ) { %>
    <div class="alert-message error">
      <p><%= $error %></p>
    </div>
<% } %>

<% if (my $message = flash 'message' ) { %>
    <div class="alert-message success">
      <p><%= $message %></p>
    </div>
<% } %>

    <%= content %>
  </div>
  </body>
    
  <footer class="footer">
      <div class="container">
        <p class="pull-right"><a href="#">Back to top</a></p>
        <p>MojoReq: [<a href="https://github.com/tardisx/mojoreq">https://github.com/tardisx/mojoreq</a>]</p>
      </div>
  </footer>


</html>

@@ apple.png (base64)
iVBORw0KGgoAAAANSUhEUgAAAIEAAACBCAIAAABowk4HAAAgAElEQVR4AbWdB5hdVfXFMzOZ9IQQ
QgJJCBEQFGlSRIqC0kREURAREDF26SoCgn8QETBYQBQQUaSKCCigdBUBUQhID70TSgghIT3T/r/7
1pv19pzz7psXhPPlO9ln7bX3Oe+ee0+/d1quuOKKlkoYMGAA/yuui1hVJpTh0W0ZJ8dtlaiczAlG
LDQgW1UmGM+9WVUmlOHRFRyFVv7rqQQJQhMkJpHNyW3NTLxFplUmy6eTkZyolMwJCWIr4zliVZlg
/H+xxYn8KI6uKpoiajXaQEjsYZqcqJw0ocKt8ZUUzeQkGW0TFckccRbRuZ3YJCJmlnkzLqGurZ3U
FWxYZgtBoagDkySgSJAkKQKggpPyqDiqEkKZCjy3FVmqRI5u6xIi2C85ITRj69KW2Zpgb5EpLXHa
FsF2iAaATlo2YqFMlRPq5iKayXmygUpZR0JurkyNR7JL3oxgQ5ON9CuYIFuSaVskhnmJQDJH8GV3
loUkyQa2YtqqjGmChciUbCTxaZMGgm0RJCvOTSr6tCtVjlY1aVt9Dsx2ZnUdiWZykrSthYRp3AIE
cSxEFXJ3d3cZITLFiQiyk8sl2JWtjERBckTMR7CcEIxHofYcwC4zyFUJMyc4D0ZjyEpCmzdv3gc/
+MF999330UcflYqrvNtuu8lh4vYPf/jDnnvuqWqoS5DbivtaU9kM0xwL0QmgcPs3Yjyqltc28Vbr
k+XdefQrREKZbWtr6+c+9zm0IlDWf/3rX8TPPPPM9773ve222+7222/fcccdX3nlFROicOWVVz71
1FN4SH5kTCIX3psbR4iWm8uJ8brezCkyywb0tm0s2DB6q/XJEW3sKGfmiDI78cQT11tvPcmK77jj
jgkTJiAfccQRixcvPvzwwxcuXEhy0aJFVFhkIj/xxBO77LLLww8/TPyb3/ymLJdYWnmIzH6RSJar
HEmcmGAhEiRHRG6NJ6pqW5SgMWnL6CjmLcKCBQtOOeUUZCVF+Oc//7nffvvJUMixxx47depUOIce
eijxkCFDVlhhBQSeiS233PKTn/zksmXLxKSSaIWuueYatC+//PJaa60lPyRFcFKIksQPPvhgojLB
gskJQtKIhCSJYRkCnqiSZJlt7TlIDJy0pZFcmD9//mc/+9mbbrrpt7/9rfnPPvvs0qVLx4wZY4T2
55xzzrnooovwoFY+VltXV9dLL730iU98YubMmeedd97NN9+sjIjXX3/9D3zgA0raG0khr7/++oEH
Hmj8hz/8IdVJMgYxQSQ42QDJVVjJULEJCA6JKibLbGt9Ml6igZI5oswi3tHR8d3vfpf7F5BelF5X
tieffDK97sCBA8GXLFnCwtStt956wQUXPP300yAKPBbwe1PF/1xQqueMM86YMmWKHhHABx54gMtK
N44cC0Dym9/85jbbbLPDDjtIRczdMHfuXLlVSaKJEZiEqMqRxuTmbcWM3qJtnybYpAaCBzPyQsxV
Pv30092aH3/88XAIjz/+ODc+F5Q7etddd/3FL36hH+m4vb19zpw5TlqgIocPH/773/9+4403NvjV
r3517bXXpr47OzuVNSqE//73v8SDBw8mFvmss85C+Na3viXEuJPNIzBFriuoAA0IVqlg0Um0HYiC
66VYCiWRERKE2/nzn/+8bnlUEydO/PjHP04d0ASpbQGkOf773/++7bbbYs4wFDKNg7UQHHbaaSdo
3/72t41IuOyyy1ZaaaXp06fTnVi12mqrffrTn541a9Ytt9wCqJ+H8Mc//nH77bc/8sgjQSje7373
O9rAu+66a/PNN//pT3/6xS9+cejQodQQTP9M2/aLiCBbZRoRXTR5A69LaMqW1hl7uehXoALeeOMN
+fUvIZkEamXUqFEMeP7yl79w1b7yla8g43zQoEE0+tzI5q+xxhoMTAG5fAa32morbvlzzz3XiIS2
tjZaM5yQxBtJDGnZ9thjj4Q5efLk5557jjLw3DD6+slPfvLRj34UE8qMlcwVAybJHDGzgcqcxJvx
MlsIpX2yLjGxhRdeeEEVgNlmm21GTJBrfjPNdwUoIq4yjcz+++/P7b/yyitPmzYNkCb7r3/964or
rmgaAsN/rjicCMKh2kaMGBFB2rp//OMf1K7LwxNGMfIKwOr555/n4fv3v/997bXXkqR4xBgeddRR
N954Y/GT6nV+wq2SiZJRNiGq+iXYKmc26pNthsAd953vfAd7hbvvvlsC9xcCz/vIkSOrut7/GGhi
SGCYD3bvvfe++uqrs2fP7tVX/z/mmGO4sglI5dH4RPC4445Tk8JMAp+oqJXrrrsucqJ8zz33QKN2
uUvWXXddZARGXIwCeChJEuBHwUmr5DByJJsQVTaX4GRCjkn5r9MnJy5I8muZTPFQy4aYKpHMrY1A
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
c2v44wAAAABJRU5ErkJggg==

@@ mojoreq.ico (base64)
AAABAAEAEBAAAAAAAABoBQAAFgAAACgAAAAQAAAAIAAAAAEACAAAAAAAAAEAAAAAAAAAAAAAAAEA
AAAAAAAAAAAAsLCwAA8jngChoaEAkpKSAIODgwDb29sAdHR0AL29vQCurq4An5+fAPf39wCQkJAA
6OjoANnZ2QC7u7sArKysADY2NgCOjo4Af39/ABgYGABwcHAACQkJAMjIyAC5ubkAqqqqAJubmwDz
8/MAjIyMALGzugDk5OQA1dXVAMbGxgCoqKgAKjumAJmZmQCKiooAe3t7ANPT0wDExMQAtbW1AKam
pgCXl5cAiIiIAODg4AB5eXkA0dHRAMLCwgCzs7MApKSkAPz8/ACVlZUA7e3tAN7e3gAQEBAAAQEB
AMDAwACxsbEAhISEAI+UugB1dXUAzc3NAGZmZgC+vr4Ar6+vAKCgoAD4+PgAkZGRAOnp6QDa2toA
y8vLAGRkZAC8vLwAra2tAKOmuQCenp4Aj4+PAICAgADY2NgAwMPSAAoKCgAmN6QAurq6AKurqwCc
nJwANTU1AOXl5QB+fn4A1tbWAG9vbwDHx8cACAgIALi4uACpqakAmpqaAPLy8gCLi4sA4+PjANTU
1AAVFRUAxcXFABw0xwC2trYAiYmJAHp6egBra2sAw8PDALS0tAClpaUAlpaWAO7u7gDf398A0NDQ
AAICAgAYLrgAsrKyAKOjowCUlJQAhYWFAN3d3QDOzs4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAPmkVPCVNdmAMM14KbBlAKGkVPGgTdiRMM15xABlAaxhZVWgTOiRMdSNxAAAJQGU/BwAAOmcS
dQAAAAAZMB1lai0AACsSAAAAAABJKFw7chdXAAASAAAANyFJMAICAiI9BQAABAAAACFJQAIILwJR
LisAFksAAABJc0oCL1oCAlgcACpUdAAARw9IAgJGAlgGQwBbAykQOQAAOCACAk9FLG1xBWxTOWYP
AABGcB9Fb1YaADYZASgPOGQAAB9Fbx5EQQAAADBSOCcAFmIONR5EbjERAAAAAAAAY1AONWFEbhtd
QGtcFAAWeCZONWENNBtCCTBcP2oXeCZOd2ENNF8LMgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
