#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------------------
 #*- bld_all_words.pl
 #*-  Collect all words in the wn_all_words table.
 #*-  Bugs:
 #*-   Added code to replace underscore with space in f_chars and l_chars
 #*-   (Feb 3, 2005)
 #*----------------------------------------------------------------
 use strict; use warnings;

 print ("Started collecting all words\n");
 my %words = ();
 open (IN, "wn_words.dat") || die ("Unable to open file wn_wform $!\n");
 while (my $inline = <IN>)
  { chomp($inline);
    my ($word) = $inline =~ /^(.*?):.*/;
    $words{$word}++; }
 close(IN);

 #*-- build the all words file
 open (OUT, ">wn_words_all.dat") || 
       die ("Unable to build all words file $! \n");
 binmode OUT, ":raw";
 my $line = my $f_chars = my $l_chars = '';
 foreach my $word (sort keys %words)
  { 
    (my $chars) = $word =~ /^(.{1,2})/;

    #*-- dump a line, if ready
    if (length($line . "$word ") > 255)
     { $f_chars =~ s/_/ /; $l_chars =~ s/_/ /;
       print OUT ("$f_chars:$l_chars:$line:\n"); $line = ''; }


    #*-- for a new line
    unless ($line) { $f_chars = $chars; }

    $l_chars = $chars; $line .= "$word ";
  }
 print OUT ("$f_chars:$l_chars:$line:\n") if ($line);
 close(OUT);

 print ("Ended collecting all words\n");
 exit(0);
