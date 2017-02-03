#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*-----------------------------------------------------------
 #*- Find the most suitable sense for a word from WordNet
 #*-----------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::WordNet   qw/in_dictionary get_rel_words similar_words dtable/;
 use TextMine::Tokens    qw/load_token_tables/;
 use TextMine::Index     qw/content_words/;
 use TextMine::Utils     qw/log2 clean_array/;
 use TextMine::Pos       qw/get_pos pos_tagger/;
 use TextMine::Constants qw/$DB_NAME/;

 my ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => "$DB_NAME");

 my $i = 0;
 my $hash_refs = &load_token_tables($dbh);
 while (my $word = <DATA>)
  { 
   chomp($word); 
   my $context = <DATA>; chomp($context);
   my $sense = &sense($word, $context, $hash_refs, $dbh);
   last if (++$i == 10);
  }

 $dbh->disconnect_db();

 exit(0);

 #*---------------------------------------------------------------
 #*- Accept a word and context, return the best sense for the
 #*- word using WordNet
 #*---------------------------------------------------------------
 sub sense
 {
  my ($word, $context, $hash_refs, $dbh) = @_;
  
  #*-- cannot handle unless the word is in the dictionary
  return(0) unless (&in_dictionary($word, $dbh));

  #*-- find the POS for the word in the context
  #*-- use the POS to find the associated sense of the word
  #my ($rtags, $rlocs, $r_stags) = &pos_tagger(\$context, $dbh, $hash_refs); 
  #my $pos = '';
  #foreach my $i (0..@$rtags-1)
  # { if (lc($$rtags[$i]) eq lc($word) )
  #    { $pos = $$r_stags[$i]; }
  # }

  #*-- assuming the word does not need to be stemmed
  my %s_words = ();
  my $command = "select wnc_synsets from " . (&dtable($word))[0] .
                " where wnc_word = " . $dbh->quote($word);
  my ($sth, $db_msg) = $dbh->execute_stmt($command);
  return("Command: $command failed --> $db_msg") unless ($sth);

  #*-- Build the array of synsets and associated frequencies for the word.
  #*-- The frequencies are associated with the tag sense count for that
  #*-- particular sense of the word from WordNet.
  my @synsets = my @s_freq = (); my $tot_tcount = 0;
  while (my ($synsets) = $dbh->fetch_row($sth))
   { foreach my $synset (split/\s+/, $synsets)
      { push (@synsets, $synset); 
        my ($tcount) = $synset =~ /_(\d+)/; push (@s_freq, $tcount + 1); 
        $tot_tcount += $tcount + 1; }
   } #*-- end of while

  #*--------------------------------------------------------
  #*-- for each synset get the synset words + gloss words
  #*-- optionally get hypernyms as well. Build the table
  #*-- Table
  #*--  Sense  Freq     
  #*--  ----------------------------------------
  #*--   i     @s_freq  %s_words (sense content words)  
  #*-                   @s_descr (sense description: synonyms + gloss)
  #*--   .......................................
  my @s_descr = ();
  for my $i (0..$#synsets)
   {
    (my $sense = $synsets[$i]) =~ s/_.*$//;
    $command = "select wnc_words, wnc_gloss from wn_synsets " .
               " where wnc_synset = '$sense'"; 
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    return("Command: $command failed --> $db_msg") unless ($sth);
    my ($words, $gloss) = $dbh->fetch_row($sth);
    $s_descr[$i] = "$words : $gloss";

    #*-- build the words array to describe the sense
    #*-- 1. Use the synset words
    #*-- Set the frequency of these words to the frequency for this 
    #*-- sense of the word.
    my @words = split/\s+/, $words; 
    foreach my $word (@words)
     { $s_words{$i . ',' . lc($word)} = $s_freq[$i]; }

    #*-- 2. Use the content words from the gloss
    #*-- Set the frequency of the content words in the gloss inversely 
    #*-- proportional to the number of gloss words
    my @gwords = @{&content_words(\$gloss, '', $dbh, 0, $hash_refs)};
    foreach my $word ( @gwords )
     { $word =~ s/_/ /g; 
       next unless (&get_pos($word, $dbh) =~ /[n]/);
       $s_words{$i . ',' . lc($word)} += ($s_freq[$i] / @gwords); }

    #*-- 3. Use hypernyms + hyponyms for 1 and 2
    my @hwords = ();
    foreach my $word (@words, @gwords)
     { my %rwords = &get_rel_words($word, 'hypernym hyponym', $dbh);
       if ($rwords{'hypernym'})
        { push (@hwords, $_) foreach (split/\s+/, $rwords{'hypernym'}); }
       if ($rwords{'hyponym'})
        { push (@hwords, $_) foreach (split/\s+/, $rwords{'hyponym'}); }
     } 
  
    #*-- Add the hypernyms to the sense words. The frequency of
    #*-- the hypernym is inversely proportional to the number
    #*-- of hypernyms.
    @hwords = &clean_array(@hwords);
    foreach my $word (@hwords)
     { $word =~ s/_/ /g; 
       $s_words{$i . ',' . lc($word)} += ($s_freq[$i] / @hwords); }

   } #*-- end of for my $i

  #*-- get the context words and keep only the nouns + adjs.
  my @temp = &clean_array(
           @{&content_words(\$context, '', $dbh, 0, $hash_refs)} );

  my @cwords = ();
  foreach (@temp) 
   { next unless (&get_pos($_, $dbh) =~ /[na]/);
     push (@cwords, $_); }
  $_ =~ s/_/ /g foreach (@cwords);

  #*-- loop thru the senses and assign a score
  my @scores = ();
  for my $i (0..$#synsets)
   {
    #*-- assign a base log probability for the sense
    $scores[$i] = &log2($s_freq[$i] / $tot_tcount);

    #*-- for every context word find the corresponding prob. of the
    #*-- the word for the current sense 
    my $prob = 0;
    for my $j (0..$#cwords)
     {
      #*-- skip the word for which we are defining a sense
      next if ($cwords[$j] eq lc($word));
   
      #*-- a sense frequency for the context word must exist
      #*-- otherwise, use absence as a negative indicator
      unless ($s_words{"$i,$cwords[$j]"}) { $prob -= 100; next; }

      #*-- compute the product of the probablities for each
      #*-- context word that was found for the sense. 
      $prob += &log2( ($s_words{"$i,$cwords[$j]"} / $tot_tcount) );
     }
    $scores[$i] += $prob;

   } #*-- end of for my $i synsets

  #*-- find the highest score
  my ($v1) = (sort {$scores[$b] <=> $scores[$a]} (0..$#scores) );
  print "-----------------------------------------------------------------\n";
  print "Sense for $word is\n-->$s_descr[$v1]<--\nin context:\n" .
        "-->$context<--\n";
 }

__DATA__
land
The pilot looked carefully at the airport and made a quick decision. He decided not to land the aircraft on the short runway and headed west instead towards Chicago.
land
Rainfall during the current rainy season has been far below average, ravaging all but the irrigated land of large commercial farmers.
drug
Children with the disease are consigned to live in a sterile environment, such as a plastic bubble, to avoid infection, the company said. The study of Enzon's drug, conducted at Duke University, showed that two children suffering from the disease were treated for 11 and seven months, respectively, and were free of serious infection during that time, the company said.
drug
The company said the Japanese customs bureau placed an initial 21 mln dlr order. The equipment is able to detect illegal drugs in cargo, the company said. The systems are made by British Aerospace.
state
The company said Executive Life Insurance Co gave the capital infusion to its subsidiary, Executive Life Insurance Co of New York. It said the new funds bring to 280 mln dlrs the company has received from its parent the past three years.  Executive Life Insurance Co of New York admitted a violation of state insurance law and paid a fine of 250,000 dlrs levied by the New York Insurance Department, according to the company.  
state
Banks hold securities for this purpose in safe custody accounts in the Landeszentralbank (LZB) regional central banks, which are the local offices of the Bundesbank at state level. Some 50 billion marks of securities are held in such accounts at the Hesse LZB, which covers the Frankfurt area.
state
The Commission said the industry would probably be unable to hold prices at current levels and that any increase would result in loss of sales and jobs. The so-called anti-dumping procedure opened by the Commission will allow all interested parties to state their cases to the authority.
