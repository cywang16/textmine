#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------------
 #*-- entry_debug.pl
 #*--   Description: Find discrepancies in the file data for 
 #*--   the tables and the row data for the files
 #*---------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Constants;
 
 our ($dbh, $db_msg, $sth);

 #*-- establish a connection with the db
 ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
    'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => $DB_NAME);
 &quit("Connect failure: $db_msg") if ($db_msg);

 my $TABLE = 'wn_words_m_p';
 my $FILE  = $TABLE . '.dat';

 #*-- read the file data for the table
 my %fdata = ();
 open (IN, $FILE) || die ("Unable to open $FILE $!\n");
 while (my $inline = <IN>)
  { chomp($inline); $inline =~ /^(.*?):(.):/;
    if ($1 && $2) { print "Dup: $1 with POS $2\n" if $fdata{"$1,$2"};
                    $fdata{"$1,$2"}++; }
    else { print "Bad Line: $inline\n"; } 
  }
 close(IN);

 #*-- read the row data for the table and verify with the file data
 my %tdata = ();
 my $command = "select wnc_word, wnc_pos from $TABLE";
 ($sth) = $dbh->execute_stmt($command, $dbh);
 while ( my ($word, $pos) = $dbh->fetch_row($sth) )
  { print "File Missing $word and $pos\n" unless ($fdata{"$word,$pos"}); 
    $tdata{"$word,$pos"}++; }

 #*-- compare the file data with the row data
 foreach (keys %fdata)
  { print "Table missing $_\n" unless ($tdata{$_}); }

 $dbh->disconnect_db($sth);
 exit(0);
