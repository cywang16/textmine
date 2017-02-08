#!/usr/bin/perl

use strict;
use warnings;
use DBI;

# Connect to the database.
my $dbh = DBI->connect("DBI:mysql:database=keycloak;host=mysql",
          "keycloak", "test",
          {'RaiseError' => 1});
$dbh->do("CREATE TABLE foo (id INTEGER, name VARCHAR(20))");
