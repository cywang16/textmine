#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------------------
 #*- em_b_delete.pl
 #*-  
 #*-   Summary: Delete e-mails that have been marked for deletion
 #*----------------------------------------------------------------

 use Getopt::Std;
 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Constants;
 use TextMine::MailUtil qw/delete_email/;

 #*-- set the constants
 our ($dbh, 	#*-- database handle
      $sth, 	#*-- statement handle
      $db_msg,	#*-- database error message
      $command	#*-- Variable for SQL command
     );

 #*-- establish a DB connection
 my $userid = 'tmadmin'; my $password = 'tmpass';
 ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $userid, 'Password' => $password, 'Dbname' => $DB_NAME);

 #*-- get the ids of deleted e-mail ids
 print ("Started email delete\n");
 my @d_ids = ();
 $command = "select emi_id, emc_dflag from em_email";
 ($sth, $db_msg) = $dbh->execute_stmt($command);
 die("Command: $command failed --> $db_msg") if ($db_msg);
 while (my ($emi_id, $emc_dflag) = $dbh->fetch_row($sth) )
  { next unless ($emc_dflag && $emc_dflag eq 'D'); push (@d_ids, $emi_id); }

 foreach (@d_ids) { &delete_email($dbh, $_); print ("Deleted email $_ ...\n"); }

 print ("Ended email delete\n");
 $dbh->disconnect_db();
 exit(0);
