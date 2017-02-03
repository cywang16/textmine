#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*-----------------------------------------------------------------
 #*- sp_b_log.pl
 #*-   Accept a spider id and dump the log for the spiders    
 #*----------------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Utils qw(f_date);
 use TextMine::Constants qw($DB_NAME $EQUAL);

 our ($dbh, $sth, $command);

 my $userid = 'tmadmin'; my $password = 'tmpass';
 ($dbh) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $userid, 'Password' => $password, 'Dbname' => $DB_NAME);

 (my $spi_id) = $ARGV[0] =~ /(\d+)/;
 $command = "select pri_start_time, prc_logdata from co_proctab where " .
            " prc_sub_tid = '$spi_id' order by 1 asc";
 ($sth, my $db_msg) = $dbh->execute_stmt($command);
 print ("Command: $command failed $db_msg\n") if ($db_msg);
 our $log; $" = "\n"; our $start_time;
 while ( ($start_time, $log) = $dbh->fetch_row($sth) )
  {                                 
    $start_time = &f_date($start_time, 1, 1, 1);
    print "Started on ", $start_time, "\n";
    my @ldata = split/$EQUAL/, $log;
    print ("\n@ldata\n----------------------------------------------\n"); }
 $dbh->disconnect_db($sth);
 exit(0);
