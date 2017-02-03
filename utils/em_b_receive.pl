#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------------------
 #*- em_b_receive.pl
 #*-  
 #*-   Summary: Receive, parse, and store e-mails in batch 
 #*-
 #*----------------------------------------------------------------

 use Getopt::Std;
 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Constants;
 use TextMine::MailUtil;

 #*-- set the constants
 our ($dbh,	#*-- database handle
      $stat_msg,	#*-- status message
      $db_msg, 		#*-- database message
      $inline,		#*--  
      @FILES,		#*-- files array
      %opt		#*-- options 
     );

 my $userid = 'tmadmin'; my $password = 'tmpass';
 ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $userid, 'Password' => $password, 'Dbname' => $DB_NAME);

 #*-- parse the arguments
 getopt('vh', \%opt);
 if ($opt{h})
  { print "Usage: em_b_receive.pl [-help -verbose]\n"             .
     "\t The verbose option will print statements to show emails recvd.\n";
    exit(0); }

 #*-- build the @FILES array
 while ($inline = <DATA>) { chomp($inline); push (@FILES, $inline); }
 print ("Built the array of files\n") if ($opt{v});
 $stat_msg = '';

 #*-- read the e-mail files
 foreach my $file ( @FILES)
  { my $email = '';
    open (IN, "<", &clean_filename("$file")) 
         or die ("Unable to open $file $! \n");
    while (<IN>) { $email .= $_; } close(IN);
    $email =~ s/\cM//g; #*-- strip out control Ms
    $stat_msg = &save_email($dbh, $email, "\n");
    print ("Processed $file\n$stat_msg\n");
  }

 $dbh->disconnect_db();
 exit(0);


#*-- list of files containing received e-mail messages
__DATA__
/home/manuk/Desktop/recvd16.txt
