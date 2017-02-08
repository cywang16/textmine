
 #*--------------------------------------------------------------
 #*- DbCall.pm						
 #*- 
 #*- Description: A set of Perl functions to execute database statements.
 #*- These functions can be modified for individual databases
 #*- without changing the source code that uses DbCall
 #*--------------------------------------------------------------

 package TextMine::DbCall;

 use strict; use warnings;
 use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
 use DBI;
 use Exporter;
 $VERSION = '1.0';
 @ISA = qw(Exporter);
 @EXPORT    = qw(disconnect_db execute_stmt fetch_row quote);
 @EXPORT_OK = qw(last_id create_db drop_db show_dbs show_tables 
                 show_columns show_keys);

 #*------------------------------------------------------
 #*- connect to the database and return the handle
 #*- Port number 3306 is used for mysql, the connect
 #*- stmt. will need to be modified for other databases
 #*------------------------------------------------------
 sub new 
 { 
  my ($class) = shift;

  $class = ref($class) || $class; #*-- extract the class of class ref.
  my ($self) = {};                #*-- initialize the hash

  #*-- set hash values  Mandatory: Dbname
  #*-- Optional : Host, Userid, Password, Debug
  my (%hash) = @_;
  foreach (keys %hash) { $self->{$_} = $hash{$_}; }

  #*-- set defaults and open optional debug file
  # $self->{'Host'} = 'localhost' unless ($self->{'Host'});
  $self->{'Host'} = 'mysql' unless ($self->{'Host'});

  #*-- try establishing a connection
  #*-- Fix by Jeff Gentes, Feb 5, 2005: 
  #*-- Added mysql_local_infile=1 to allow load data local stmt. 
  # my $dbh = DBI->connect("DBI:mysql:database=$self->{'Dbname'};host=$self->{'Host'}" .
  #  ";mysql_local_infile=1", "$self->{'Userid'}", "$self->{'Password'}");
  my $dbh = DBI->connect("DBI:mysql:database=tm;host=$self->{'Host'}" .
   ";mysql_local_infile=1", "$self->{'Userid'}", "$self->{'Password'}");
  DBI->trace(1, $self->{'DebugFile'}) if ($self->{'DebugFile'});

  #*-- return if an error
  return ('', "DBI error from connect to DB:$self->{'Dbname'} at " .
              " Host:$self->{'Host'}: $DBI::errstr") unless $dbh;

  #*-- save the handle and return
  $self->{'dbh'} = $dbh; 
  bless($self, $class);
  return($self, $DBI::errstr);
 }

 #*-------------------------------------------------
 #*- disconnect from the database
 #*-------------------------------------------------
 sub disconnect_db 
  { 
   my( $self, $sth, $ssth) = @_;
   my $result = $sth->finish() if ($sth); 
   $result   .= $ssth->finish() if ($ssth);
   $result   .= $self->{'dbh'}->disconnect();
   return($result);
  }

 #*---------------------------------------------------------
 #*- Execute a SQL statement using the passed db handle
 #*- Optionally ignore any errors
 #*---------------------------------------------------------
 sub execute_stmt 
 {
   my( $self, $statement, $ignore ) = @_;
   $ignore = 1 if ( !$ignore && ($statement =~ /^\s*drop/i) );
   
   #*-- do a prepare for select/show statements
   #*-- commented out code because of problems with the
   #*-- do call in MySql version 4.* (Feb 7th, 2005)
   my $sth; my $errstr = '';
   #if ($statement =~ /^\s*s(?:elect|how)/i)
   # {
     $sth = $self->{'dbh'}->prepare("$statement");
     return ('', "DBI error from prepare\n:$statement") 
             unless $sth;
     $sth->execute;
     return ('', "DBI error from execute\n:$statement: $sth->errstr")
             unless ($sth || $ignore);
     $errstr = $sth->errstr;
   # }
   #else
   # { $sth = $self->{'dbh'}->do("$statement"); }
   return($sth, $errstr);
 }

 #*---------------------------------------------------------
 #*- Fetch a row given the SQL statement handle
 #*- Return a hash if requested
 #*---------------------------------------------------------
 sub fetch_row
 { my ($self, $sth, $hash_fetch) = @_;
   return ($sth->fetchrow_hashref()) if ($hash_fetch);
   return($sth->fetchrow_array()); }

 #*-------------------------------------------------
 #*- return a quoted string
 #*-------------------------------------------------
 sub quote
  { my( $self, $str) = @_; return($self->{'dbh'}->quote($str)); }

 #*---------------------------------------------------------
 #*- Fetch the last id of an autoincrement field
 #*---------------------------------------------------------
 sub last_id
 { (my $self) = @_;
   (my $sth) = &execute_stmt($self, "select LAST_INSERT_ID()");
   return ( (&fetch_row($self, $sth))[0] ); }

 #*---------------------------------------------------------
 #*- Create a database after checking if it exists
 #*---------------------------------------------------------
 sub create_db
 { 
  my ($dbname, $userid, $pass) = @_;

  #*-- check for a duplicate db
  # my $dbh = DBI->connect("DBI:mysql:mysql:localhost:3306","$userid","$pass");
  my $dbh = DBI->connect("DBI:mysql:database=tm;host=mysql","$userid","$pass");
  my @dbs = $dbh->func('_ListDBs');
  foreach my $db (@dbs) 
   { if ($db eq $dbname) { $dbh->disconnect(); return(); } }

  #*-- create the db
  $dbh->do("create database $dbname"); $dbh->disconnect();
  return();
 }

 #*---------------------------------------------------------
 #*- Drop a database   
 #*---------------------------------------------------------
 sub drop_db
 { 
  my ($dbname, $userid, $pass) = @_;
  # my $dbh = DBI->connect("DBI:mysql:mysql:localhost:3306","$userid","$pass");
  my $dbh = DBI->connect("DBI:mysql:database=tm;host=mysql","$userid","$pass");
  $dbh->do("drop database $dbname"); $dbh->disconnect();
  return();
 }

 #*--------------------------------
 #*- Return the list of databases  
 #*--------------------------------
 sub show_dbs
  { my ($self) = @_;
    my @dbs = $self->{'dbh'}->func('_ListDBs'); return(sort @dbs); }

 #*---------------------------------------------------------
 #*- Return a list of tables for the database handle passed
 #*---------------------------------------------------------
 sub show_tables
  { my ($self) = @_; 
    my (@tables);
    (my $sth) = &execute_stmt($self, "show tables");
    push(@tables, $_[0]) while (@_ = &fetch_row($self, $sth));
    return (sort @tables);
  }
   

 #*---------------------------------------------------------
 #*- Return a list of columns for the table in the database
 #*---------------------------------------------------------
 sub show_columns
  { my ($self, $table) = @_; 
    my (@cols, @ctype);
    (my $sth) = &execute_stmt($self, "show columns from $table");
    while (@_ = &fetch_row($self, $sth))
     { push(@cols, $_[0]); push(@ctype, $_[1]); } 
    return (\@cols, \@ctype);
  }

 #*-------------------------------------------------------------
 #*- Return a list of columns for the primary key for the table
 #*-------------------------------------------------------------
 sub show_keys
  { my ($self, $table) = @_;
    my (@cols);
    (my $sth) = &execute_stmt($self, "show columns from $table");
    while (@_ = &fetch_row($self, $sth))
     { push (@cols, $_[0]) if ($_[3] eq 'PRI'); }
    return (\@cols);
  }

1;

=head1 NAME

DbCall - TextMine DbCall

=head1 SYNOPSIS

use TextMine::DbCall;

=head1 DESCRIPTION

 A group of functions to administer, retrieve, and manage 
 database tables.

=head2 new, disconnect_db
 
 new: Pass the database name, userid, password and other 
 optional parameters. A database handle or an error message 
 is returned. 

 disconnect_db: Release the database and statement handles 
 for the database.

=head2 execute_stmt, fetch_row

 execute_stmt: Execute a SQL statement. If the statement is 
 a select or show statement, then the statement is prepared 
 before execution.  Otherwise, the do function is used to 
 execute the statement. A statement handle and an error message 
 is returned.

 fetch_row: Fetch a row corresponding to the passed statement 
 handle. If a hash is requested, then return a hash containing 
 data for all columns of the table.

=head2 create_db, drop_db, show_dbs

 create_db: Create a new database. Pass the database name, 
 userid, and password. Check if a duplicate database exists.

 drop_db: Pass a database name, userid, and password. The database 
 will be dropped if possible.

 show_dbs: Return a list of the database names for this 
 database server. 

=head2 show_tables, show_columns, show_keys

 show_tables: Pass a database handle and receive an array of tables 
 for the database
 
 show_columns: Pass a database handle and a table and receive an array
 of the column names for the table

 show_keys: Pass a database handle and a table and receive an array
 of the primary key column names for the table

=head1 Examples

 1. Create a database handle:
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
   'Userid' => $userid, 'Password' => $password, 'Dbname' => $DB_NAME);

 2. Execute a sql statement
 ($sth, $db_msg) = $dbh->execute_stmt("select * from mysql");

 3. Use a statement handle to fetch a row in an array
 @columns = $dbh->fetch_row($sth);

 4. Use a statement handle to fetch a row in a hash
 %columns = $dbh->fetch_row($sth,1);

=head1 AUTHOR

Manu Konchady <mkonchady@yahoo.com>
