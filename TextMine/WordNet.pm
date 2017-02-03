
 #*--------------------------------------------------------------
 #*- WordNet.pm						
 #*- Description:
 #*-     A set of functions to search and fetch words from a
 #*-     WordNet database. The database contains words, synonym
 #*-     sets, relationships between words, and relationships
 #*-     between synonym sets
 #*--------------------------------------------------------------

 package TextMine::WordNet;

 use strict; use warnings;
 use Time::Local;
 use Config;
 use lib qw/../;
 use TextMine::DbCall;
 require Exporter;
 our @ISA = qw(Exporter);
 our @EXPORT = qw();
 our @EXPORT_OK = qw( in_dictionary similar_words base_words word_pos
     in_dict_table get_synset_words build_wnet_ptrs dtable get_rel_words);
 use vars qw ();

 #*-- set the constants     
 BEGIN 
  { }

 #*-----------------------------------------------------------------
 #*-   return the dictionary tables for a list of words
 #*-----------------------------------------------------------------
 sub dtable
  { my (@words) = @_; my @tables;

   foreach my $word (@words)
    {
     ($word = lc($word)) =~ s/\s/_/g; 
     CASE: 
     { if ($word =~ /^[t-z]/) { push(@tables, 'wn_words_t_z'); last CASE; } 
       if ($word =~ /^[q-s]/) { push(@tables, 'wn_words_q_s'); last CASE; } 
       if ($word =~ /^[m-p]/) { push(@tables, 'wn_words_m_p'); last CASE; } 
       if ($word =~ /^[h-l]/) { push(@tables, 'wn_words_h_l'); last CASE; } 
       if ($word =~ /^[e-g]/) { push(@tables, 'wn_words_e_g'); last CASE; } 
       if ($word =~ /^[c-d]/) { push(@tables, 'wn_words_c_d'); last CASE; } 
       push(@tables, 'wn_words_a_b'); }
    }
   return(@tables);
  }

 #*---------------------------------------------------------
 #*- return a T or F depending on whether the word exists
 #*- in the dictionary table (excluding base forms)
 #*- use the wn_words_all table that contains 2 lead characters
 #*- and associated words
 #*- lead_chars	....... words .................
 #*---------------------------------------------------------
 sub in_dict_table
 {
  my ($word, $dbh) = @_;
  return(0) unless ($word && $dbh);
  ($word = lc($word)) =~ s/\s/_/g; 
  (my $lchars) = $word =~ /^(.{1,2})/; $lchars = $dbh->quote($lchars);
  my $command = "select wnc_words from wn_words_all where " .
                "wnc_start_letters <= $lchars and "       .
                "$lchars           <= wnc_end_letters";
  (my $sth, my $db_msg) = $dbh->execute_stmt($command);
  return(0) if (!$sth || $db_msg);
  while ( (my $words) = $dbh->fetch_row($sth) )
   { foreach (split (/\s+/, $words) ) { return(1) if ($_ eq $word); } }

  return(0);
 }

 #*---------------------------------------------------------
 #*- return a T or F depending on whether the word exists
 #*- in the dictionary
 #*---------------------------------------------------------
 sub in_dictionary
 {
  my ($word, $dbh) = @_;

  #*-- check if it is in the dictionary tables
  return(0) unless ($word && $dbh);
  ($word = lc($word)) =~ s/\s/_/g; 
  return (1) if (&in_dict_table($word, $dbh));

  #*-- get the base words and look up in dictionary
  my %base_words = &base_words($word, $dbh);
  return(2) if (keys %base_words);
  return(0);

 }

 #*---------------------------------------------------------
 #*- Return a list of words associated with synsets   
 #*---------------------------------------------------------
 sub get_synset_words
 {
  my ($synset,	#*-- list of 9 character synonym sets
      $dbh,	#*-- database handle
      $full,	#*-- get all the words with all synsets 
      $pos	#*-- optional part of speech
     ) = @_;

  return('') unless ($synset);
  my $words = ''; $pos = 'm' if ($pos && ($pos =~ /[cipod]/));
  foreach (split/\s+/, $synset)
  { 
    s/_.*$//; #*-- strip out the tag count
    (my $etype) = $synset =~ /^(.)/;      #*-- check the entity type
    next if ($pos && ($pos ne $etype) );  #*-- and skip if entity type
                                          #*-- does not match option pos
    my $command = "select wnc_words from wn_synsets where wnc_synset = '$_'";
    my ($sth, $db_msg) = $dbh->execute_stmt($command);
    return ('') if (!$sth || $db_msg);
    my ($wnc_words) = $dbh->fetch_row($sth);
    $words .= $wnc_words . " " if ($wnc_words); 
    last unless $full;
  }
  return ($words);
 }

 #*---------------------------------------------------------
 #*- Return a list of similar word from the dictionary   
 #*---------------------------------------------------------
 sub similar_words
 {
  my ($word,	#*-- find words similar to this word
      $dbh,	#*-- database handle
      $full,	#*-- get all the words with all synsets 
      $pos	#*-- optional part of speech
     ) = @_;

  my ($command, $sth, $db_msg);
  ($word = lc($word)) =~ s/\s/_/g; 
  
  #*-- if it is in the dictionary, then fetch the synsets and
  #*-- associated words
  my %similar_words = (); my $s_words = '';
  if (&in_dict_table($word, $dbh) )
   {
    $command = "select wnc_synsets from " . (&dtable($word))[0] .
               " where wnc_word = " . $dbh->quote($word); 
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    return(keys %similar_words) unless ($sth);
    while ( (my $synsets) = $dbh->fetch_row($sth) )
     { $s_words .= &get_synset_words($synsets, $dbh, $full, $pos); }
   }
  else
   {
    #*-- try the base word forms
    my %b_words = &base_words($word, $dbh);
    foreach (keys %b_words)
    { $command = "select wnc_synsets from " . (&dtable($word))[0] .
                 " where wnc_word = " . $dbh->quote($_); 
      ($sth, $db_msg) = $dbh->execute_stmt($command);
      return(keys %similar_words) unless ($sth);
      while ( (my $synsets) = $dbh->fetch_row($sth) )
       { $s_words .= &get_synset_words($synsets, $dbh, 1, $pos) . " "; }
    } #*-- end of for
   } #*-- end of if

  #*-- remove dups
  foreach (split/\s+/, $s_words) { next if /$word/i; $similar_words{$_}++; }

  #*-- if we did not find any similar words, then try with
  #*-- the full option
  return (&similar_words($word, $dbh, 1))
         unless ($full || (keys %similar_words) );

  #*-- otherwise return the list
  return (sort keys %similar_words);
 }

 #*---------------------------------------------------------
 #*- Return a list of base words for a given word
 #*---------------------------------------------------------
 sub base_words
 {
  my ($word,	#*-- find base words for this word
      $dbh,	#*-- database handle
      $exc_only #*-- use the exclusion table alone
     ) = @_;

  #*-- first get any base words from the exclusion table
  my %done = (); 
  my $command = "select wnc_type, wnc_base_word from wn_exc_words where " .
                " wnc_excl_word = " . $dbh->quote($word);
  (my $sth, my $db_msg) = $dbh->execute_stmt($command);
  return(%done) if (!$sth || $db_msg);
  while ( my ($type, $base_word) = $dbh->fetch_row($sth) )
   { $done{$base_word} .= $type; }

  #*-- return if only an exclusion words should be selected
  return(%done) if ( (keys %done) && $exc_only);

  #*-- use the suffix rules to get the base form 
  #*-- substitute the suffix with the replacement 
  #*-- format: suffix_replacement suffix_POS type (noun/verb/adj.)
  my $t_word = '';
  foreach my $spatt (qw/s__n      ses_s_n xes_x_n zes_z_n  ches_ch_n shes_sh_n
                        men_man_n ies_y_n s__v    ies_y_v  es_e_v    es__v 
                        ed_e_v    ed__v   ing__v   ing_e_v er__a     est__a 
                        er_e_a    est_e_a/)
   { 
     #*-- add the base word to the hash, if the word with the replaced
     #*-- suffix exists in the dictionary and the POS matches
     my ($suffix, $repl, $type) = split/_/, $spatt;
     $done{$t_word} .= "$type"
     if ( ( ($t_word = $word) =~ s/$suffix$/$repl/) && 
          &in_dict_table($t_word, $dbh)             &&    
          (&word_pos($t_word, $dbh) =~ /$type/) ); }

  return (%done);
 }

 #*---------------------------------------------------------
 #*- get_rel_words
 #*-  Get related words based on the type of relationships
 #*---------------------------------------------------------
 sub get_rel_words
  {
   my ($word,  #*-- fetch the words related to this word
       $rel,   #*-- list of required relationships for words or '*' for all	
       $dbh,   #*-- database handle 
       $pos    #*-- optional POS for related words
      ) = @_;
  
   #*-- check for a valid word and valid relationship
   my %results = ();
   my ($command, $in_dict); 
   return (%results) unless ($word && $rel && $dbh && ($word =~ /^[a-zA-Z]/) );
   return (%results) unless ($in_dict = &in_dictionary($word,$dbh));
   $rel = lc($rel); 
   (undef, my $wnet_rel) = &build_wnet_ptrs(); my %wnet_rel = %$wnet_rel;
   my @rels = ($rel eq '*') ? keys %wnet_rel: split/\s+/, $rel;
   $_ = lc foreach (@rels);
   foreach (@rels) { return (%results) unless $wnet_rel{$_}; }

   #*-- for a word not in the dictionary but a valid exclusion word
   if ($in_dict == 2)
    { my %g_results = (); my %b_words = &base_words($word, $dbh);
      $g_results{$_} = '' foreach (@rels);
      foreach my $b_word (keys %b_words)
       { %results = &get_rel_words($b_word, $rel, $dbh, $pos);
         $g_results{$_} .= $results{$_} foreach (keys %results); }
      return(%g_results);
    }
   
   #*-- loop thru all the requested relationships
   #*-- first get the synsets for the word
   my @synsets = ();
   $command = "select wnc_synsets from " . (&dtable($word))[0] .
              " where wnc_word = " . $dbh->quote($word);
   my ($sth, $db_msg) = $dbh->execute_stmt($command);
   return(%results) if (!$sth || $db_msg);
   while ( (my $synsets) = $dbh->fetch_row($sth) )
     { $synsets =~ s/_(\d+)//g; push (@synsets, split/\s+/, $synsets); }

   foreach my $rel (@rels)
    { 
      $results{$rel} = '';
      #*--- check if it is a word relationship
      if ($rel =~ /^antonym|pertainym|participle|also_see$/)
       { $command = "select wnc_word_b from wn_words_rel where " . 
                    "wnc_rel    = '$rel' and "                   .
                    "wnc_word_a = " . $dbh->quote($word);   
         my ($sth, $db_msg) = $dbh->execute_stmt($command);
         return(%results) if (!$sth || $db_msg);
         while ( (my $word_b) = $dbh->fetch_row($sth) )
          { $results{$rel} .= "$word_b " if ($word_b); }
       }
      #*--- it is a synset relationship
      else 
       { 
        foreach my $synset (@synsets)
         {
          $command = "select wnc_synset_b from wn_synsets_rel where " . 
           "wnc_rel = '$rel' and wnc_synset_a = '$synset'";
          my ($sth, $db_msg) = $dbh->execute_stmt($command);
          return(%results) if (!$sth || $db_msg);
          while ( (my $synset_b) = $dbh->fetch_row($sth) )
           { $results{$rel} .= &get_synset_words($synset_b, $dbh, 1, $pos) 
                     if ($synset_b); }
         } #*-- end of foreach
       } #*-- end of if
    } #*-- end of foreach

   return(%results);
  }

 #*---------------------------------------------------------
 #*- Return the POS for a word in the dictionary table
 #*- Used only for words that are known to be in the table
 #*---------------------------------------------------------
 sub word_pos
 {
  my ($word, $dbh) = @_;
  my $command = "select wnc_pos from " . (&dtable($word))[0] .
                " where wnc_word = "    . $dbh->quote($word);
  my $types = '';
  my ($sth, $db_msg) = $dbh->execute_stmt($command);
  return($types) if (!$sth || $db_msg);
  while ((my $type) = $dbh->fetch_row($sth)) { $types .= $type; }
  return ($types);
 }

 #*-----------------------------------------------------------
 #*- Build the wordnet pointer cross reference hashes
 #*-----------------------------------------------------------
 sub build_wnet_ptrs
 {
  my %ptr_symbols = ( '!'  => 'antonym',
                   '@'  => 'hypernym',
                   '~'  => 'hyponym',
                   '#m' => 'member_holonym',
                   '#s' => 'substance_holonym',
                   '#p' => 'part_holonym',
                   '%m' => 'member_meronym',
                   '%s' => 'substance_meronym',
                   '%p' => 'part_meronym',
                   '='  => 'attribute',
                   '*'  => 'entailment',
                   '>'  => 'cause',
                   '^'  => 'also_see',
                   '$'  => 'verb_group',
                   '&'  => 'similar_to',
                   '<'  => 'participle_of_verb',
                   '\\'  => 'pertainym or adj._derivation'
                 );
  my %ptr_names = ( 'antonym'		=> '!',
                    'hypernym',		=> '@',
                    'hyponym'		=> '~',
                    'member_holonym'	=> '#m',
                    'substance_holonym'	=> '#s',
                    'part_holonym'	=> '#p',
                    'member_meronym'	=> '%m',
                    'substance_meronym'	=> '%s',
                    'part_meronym'	=> '%p',
                    'attribute'		=> '=',
                    'entailment'	=> '*',
                    'cause'		=> '>',
                    'also_see'		=> '^',
                    'verb_group'	=> '$',
                    'similar_to'	=> '&',
                    'participle_of_verb'	=> '<',
                    'pertainym'		=> '\\',
                    'adj._derivation'	=> '\\'
                  );

  return(\%ptr_symbols, \%ptr_names);
 }

1;
=head1 NAME

WordNet - TextMine interface to WordNet

=head1 SYNOPSIS

use TextMine::WordNet;

=head1 DESCRIPTION

 WordNet is open source software from Princeton University.
 This is one of the many interfaces to WordNet in Perl.
 All the data is maintained in database tables.
 
 Table: wn_exc_words contains a list of exclusion words
 and the corresponding base word + part of speech type

 Tables: wn_words_a_b wn_words_c_d wn_words_e_g wn_words_h_l
         wn_words_m_p wn_words_q_s wn_words_t_z 

 These tables contain the dictionary words. The word
 is followed by a 1 char POS, followed by a flag for
 an entity type (means that the word usually starts
 with upper case), followed by a list of synsets to
 which the word belongs. 

 Table: wn_words_rel;

 This table contains the relationships between words.
 A word is followed by another word and the corresponding
 relationship between the words.

 Table: wn_synsets;

 This table contains a synset and its words with some
 examples of the usage of the words in sentences.

 Table: wn_synsets_rel

 This table has a synset followed by another synset
 and the relationship between the 2 synsets.

 Table: wn_words_all

 This table is an index to the words in the dictionary
 using the first 2 letters of the word. The purpose of
 this table to look up words quickly without searching
 the word tables.

=head2 in_dictionary

 Function accepts a word and returns T or F depending on whether
 the word (or a derived form) exists in the dictionary.

 Example:
 for (qw/jump jumper jumped jumping jumpen/)
  { print ("$_ is ", ( &in_dictionary($_, $dbh) ) ? 
           "in\n": "out\n"); }
 generates
 ----------------------------------------------------------
 jump is in
 jumper is in
 jumped is in
 jumping is in
 jumpen is out
 ----------------------------------------------------------

=head2 similar_words

 Find words similar to a word, i.e. find the synsets in
 which the word participates and locate all the member 
 words for the synset. Optionally use a flag to get all
 words from all synsets and a part of speech.

 @s_words = &similar_words('jump', $dbh);
 print "Common words similar to jump: @s_words\n";

 @s_words = &similar_words('jump', $dbh, 1);
 print "All words similar to jump: @s_words\n";

 @s_words = &similar_words('jump', $dbh, 1, 'n');
 print "All nouns similar to jump: @s_words\n";

 generates
 -----------------------------------------------------------
 Common words similar to jump: bound leap spring

 All words similar to jump: alternate bound climb_up derail leap 
 leap_out parachuting pass_over rise saltation skip skip_over 
 spring stand_out start startle stick_out

 All nouns similar to jump: leap parachuting saltation start startle
 -----------------------------------------------------------
 
=head2 get_rel_words

 Get words related to the word from either the word relationship
 table or the synset relationship table

 Example:

 for (qw/antonym hypernym similar_to hyponym/)
  { %r_words = &get_rel_words('normal', $_, $dbh);
    print "$_ of normal: $r_words{$_}\n"; }

 generates
 -----------------------------------------------------------
 antonym of normal: abnormal paranormal
 hypernym of normal: practice
 similar_to of normal: average mean connatural inborn inbred 
                       native median average modal average 
                       natural regular typical perpendicular
 hyponym of normal: mores code_of_conduct code_of_behavior
 -----------------------------------------------------------

=head1 AUTHOR

Manu Konchady <mkonchady@yahoo.com>
