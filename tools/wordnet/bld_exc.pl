#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*---------------------------------------------------------------
 #*- bld_exc.pl
 #*-   
 #*-   Create an word exclusion file to load the word exclusion table
 #*-   Run after creating wn_words.dat with bld_dict.pl
 #*---------------------------------------------------------------
 use strict; use warnings;

 print "Started extracting exclusion words\n";

 #*-- read in the words in the dictionary
 my %dwords = ();
 open (IN, "wn_words.dat") || die "could not open wn_words.dat $!\n";
 while (my $inline = <IN>) { $inline =~ /^(.*?):/; $dwords{$1}++; }
 close(IN);

 #*-- check if the WordNet env. var is set
 my $WNET_DIR = $ENV{WNHOME} . '/dict/';
 if ($WNET_DIR eq '/dict/')
   { print "Cannot find WordNet files.. check environment \n" .
           "variable WNHOME\n"; exit(0); }
 my %words = my %ewords = ();
 open (OUT, ">wn_exc_words.dat") || 
      die ("Could not open exclusion file $!\n");
 binmode OUT, ":raw";
 for (qw/noun adj adv verb/)
  {
    open (IN, "$WNET_DIR$_" . ".exc") || 
         &quit("Could not open $_ exc file $!\n");
    my $type = ($_ eq 'noun') ? 'n':
               ($_ eq 'adj') ?  'a':
               ($_ eq 'adv') ?  'r': 'v';
    ITER: while (my $inline = <IN>)
     {
      chomp($inline);
      my ($exc_word, $base_word) = $inline =~ /^(.*)\s(.*)$/;
      $exc_word =~ s/:/\\:/g; $base_word =~ s/:/\\:/g;
    
      #*-- check for spaces in the exclusion word
      if ($exc_word =~ /\s/)
       { my ($word1, $word2) = split/\s+/, $exc_word;
         $words{$word1 . $type}++;
         $ewords{"$word1:$base_word:$type"}++ 
             unless ($words{$word1 . $type} > 1);
         $words{$word2 . $type}++;
         $ewords{"$word2:$base_word:$type"}++ 
             unless ($words{$word2 . $type} > 1);
         next ITER;
       }
         
      #*-- force a single base word per word and type
      $words{"$exc_word" . "$type"}++;
      $ewords{"$exc_word:$base_word:$type"}++ 
        unless ($words{$exc_word . $type} > 1);
     }
    close(IN);
  }

 foreach (keys %ewords)
  { print OUT "$_\n"; } 

 close(OUT);
 print "Finished extracting exclusion words\n";

 exit(0);
