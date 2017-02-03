#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*-----------------------------------------------------------------------
 #*- split_wnet.pl
 #*-   
 #*-   Read the dictionary file and write to the appropriate file
 #*-----------------------------------------------------------------------
 use strict; use warnings;
 use TextMine::WordNet qw/dtable/;

 print("Started splitting dictionary table\n");

 #*-- get the list of tables
 my %tables = (); $tables{$_}++ foreach (&dtable('a'..'z'));

 #*-- open the input dictionary file
 open (IN, "wn_words.dat") || die ("Unable to open wn_words.dat $!\n");
 foreach my $table (sort keys %tables)
  {
   open (OUT, ">$table" . ".dat") || die ("Unable to open $table file $!\n");
   binmode OUT, ":raw";
   seek(IN, 0, 0);
   while (my $inline = <IN>)
    {
     #*-- get the name of the table and print to the appropriate file
     my ($letter) = $inline =~ /^(.)/; my ($i_tab) = &dtable($letter); 
     print OUT $inline if ($table eq $i_tab) ;
    }
   close(OUT);
   print "finished $table table\n";
  }
 close(IN);

 print("End splitting dictionary table\n");
 exit(0);
