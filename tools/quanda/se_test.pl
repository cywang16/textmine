#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*-----------------------------------------------------------------
 #*- se_test.pl
 #*-    Test sentence extraction from HTML pages
 #*-----------------------------------------------------------------
 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Constants qw/$DB_NAME $ISEP/;
 use TextMine::Quanda    qw/doc_query/;
 use TextMine::MyURL     qw/parse_HTML/;

 print "Started se_test.pl\n";
 my ($dbh, $command, $table);
 ($dbh) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => $DB_NAME);

 #*-- read the data files associated with queries
 undef($/); my $dir = './data/q4'; my $d_text = ''; my @questions;
 opendir (DIR, $dir) || die ("Could not open data dir. $!\n");
 while (my $file = readdir(DIR) )
  {
   if ($file eq 'questions')
    { my $ifile = $dir . "/$file";
      open (IN, $ifile) || die ("Could not open $ifile $!\n");
      my $inline = <IN>; close(IN);
      @questions = split/\n/, $inline;
    }
   next unless ( ($file =~ /\.html$/) || ($file =~ /\.txt$/) );

   #*-- build the text and header file
   my $ifile = $dir . "/$file";
   open (IN, $ifile) || die ("Could not open $ifile $!\n");
   my $txt = <IN>; close(IN);

   #*-- extract the text for HTML files
   #*-- and build the text string
   if ($file =~ /\.html$/)
    { my ($source) = $txt =~ m%<rspider_url src=(.*?)>%;
      my ($rtext) = &parse_HTML($txt, $source);
      $d_text .= "$ISEP$source$ISEP\n$$rtext\n"; }
   else
    { my $source = "Text File: $file";
      $d_text .= "$ISEP$source$ISEP\n$txt\n"; }
   
  }
 closedir(DIR);
 print "Finished reading questions and answers\n";

 #*-- submit the text to get the top sentences
 my $ofile = $dir . "/results";
 open (OUT, ">$ofile") || die ("Could not open $ofile $!\n");
 binmode OUT, ":raw";
 foreach my $query (@questions)
  {
   #*-- dump the results
   next if ($query =~ /^#/);
   my $overlap = '0';
   my @results = &doc_query(\$d_text, \$query, 'news', $dbh, $overlap);
   print OUT "\nQUESTION: $query\n";
   for my $i (0..$#results) 
    { my ($source, $answer) = $results[$i] =~ /^(.*?)$ISEP(.*)$/;
      my $ans = $i + 1;
      print OUT " Source: $source\n Answer $ans: $answer\n\n"; 
      last if ($ans == 5); }
   print "Finished query $query\n";
  }

 close(OUT);
 print "Finished se_test.pl\n";
 $dbh->disconnect_db();
 exit(0);
