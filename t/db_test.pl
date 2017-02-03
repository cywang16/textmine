#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------------------
 #*- db_test.pl
 #*-  
 #*- Summary: Test the database connection and session management
 #*----------------------------------------------------------------

 use strict; use warnings;
 use Digest::MD5 qw/md5_base64/;
 use TextMine::DbCall;
 use TextMine::Utils qw(encode mod_session);
 use TextMine::Constants qw($DB_NAME $EQUAL $DELIM);

 print ("Start of diagnostics\n\n");
 &test_dbconnection();
 &test_session_mgmt();
 print ("\nEnd of diagnostics\n");
 
 exit(0);

 #*---------------------------------------------------------------
 #*- test the db connection and calls
 #*---------------------------------------------------------------
 sub test_dbconnection
 {
  my ($userid, $password) = ('tmadmin', 'tmpass');
  my ($dbh, $sth, $command, @tables, $db_msg);

  #*-- first make a connection
  print "Start of database test...........\n\n";
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '', 
   'Userid' => $userid, 'Password' => $password, 'Dbname' => $DB_NAME);
  if ($db_msg) { print ("DB Connection failed : $db_msg\n"); return(); }

  my @temp = $dbh->show_dbs();
  print ("Found ", scalar @temp, " databases\n");
  @temp = $dbh->show_tables();
  print ("Found ", scalar @temp, " tables in $DB_NAME\n");
  @temp = $dbh->show_columns("sp_search");
  print ("Table sp_search has ", scalar @temp, " columns.\n");
  my $temp = $dbh->show_keys("sp_search");
  print ("Table sp_search has the primary key @$temp.\n");

  ($sth, $db_msg) = $dbh->execute_stmt("select * from co_place");
  if ($db_msg) { print ("select test failed : $db_msg\n"); return(); }
  print ("Executed select * from co_place\n");

  (undef, $db_msg) = $dbh->execute_stmt("replace into co_place values " .
                                       "('aachen', 'city', 'blank') "); 
  if ($db_msg) { print ("replace test failed : $db_msg\n"); return(); }
  print ("Executed replace * from co_place\n");
   
  my $count = 0;
  $count++ while ( @_ = $dbh->fetch_row($sth));
  print ("Fetched $count rows from co_place\n");
  $temp = "\"John's box\"";
  $temp = $dbh->quote($temp);
  print ("Quoted string: $temp\n");

  $dbh->disconnect_db($sth);
  print "\nEnd of database test...........\n";

  return(0);

 }

 #*---------------------------------------------------------------
 #*- test session management
 #*---------------------------------------------------------------
 sub test_session_mgmt
 {
  my ($userid, $password) = ('tmadmin', 'tmpass');
  my ($dbh, $sth, $command, @tables, $db_msg);

  #*-- first make a connection
  print "Start of session management test...........\n\n";
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '', 
   'Userid' => $userid, 'Password' => $password, 'Dbname' => $DB_NAME);
  if ($db_msg) { print ("DB Connection failed : $db_msg\n"); return(); }

  #*-- create a dummy session id
  my $session  = md5_base64("1234567890" . "$userid");
  my $e_session = $dbh->quote($session);

  #*-- create some session data
  my %session_d = ('userid', $userid,  'parm1', 'parm1_d',
                   'parm2', 'parm2_d', 'parm3', 'parm3_d');
  my $sec_data = '';
  foreach (keys %session_d)
   { $sec_data .= "$_" . $EQUAL . "$session_d{$_}" . $DELIM; }
  $sec_data  = $dbh->quote(&encode($sec_data));
  my $expiry = time() + 86400;
  print ("Creating some session data\n");
  $command  = "replace into co_session set sec_session = $e_session, "
            . "sec_userid = '$userid', sei_expiry = $expiry, "
            . "sec_data = $sec_data ";
  (undef, $db_msg) = $dbh->execute_stmt($command);

  my $sdata = &mod_session($dbh, $session, 'all');
  my @k_sdata = keys %$sdata; my @v_sdata = values %$sdata;
  print ("All Session K/V: @k_sdata => @v_sdata\n");
 
  my @parm_data = qw(userid notdef parm1);
  $sdata = &mod_session($dbh, $session, 'ret', @parm_data);
  $" = ", ";
  print ("Fetch Session K/V: @parm_data => @$sdata\n");
 
  my @mod_parm_data = qw(userid new_root parm1 new_parm1_d);
  &mod_session($dbh, $session, 'mod', @mod_parm_data);
  $sdata = &mod_session($dbh, $session, 'ret', @parm_data);
  print ("Modify Session K/V: @parm_data => @$sdata\n");
 
  my @del_parm_data = qw(parm1 notdef parm2);
  &mod_session($dbh, $session, 'del', @del_parm_data);
  print ("Deleted session keys parm1 and parm2\n");
  $sdata = &mod_session($dbh, $session, 'all');
  @k_sdata = keys %$sdata; @v_sdata = values %$sdata;
  print ("All Session K/V: @k_sdata => @v_sdata\n");

  $dbh->disconnect_db();
 print "\nEnd of session management test...........\n";

 return(0);

 }
