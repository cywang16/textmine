
 #*--------------------------------------------------------------
 #*- Pos.pm						
 #*-    Description: A set of Perl functions to extract parts of         
 #*-    speech tags from text
 #*--------------------------------------------------------------

 package TextMine::Pos;

 use strict; use warnings;
 use Time::Local;
 use Config;
 use lib qw/../;
 use TextMine::DbCall;
 use TextMine::WordNet qw(in_dict_table dtable base_words);
 use TextMine::Tokens  qw(assemble_tokens);
 require Exporter;
 our @ISA = qw(Exporter);
 our @EXPORT = qw();
 our @EXPORT_OK = qw(lex_tagger get_pos pos_tagger); 

 #*-- set the constants     
 BEGIN 
  { }

 #*------------------------------------------------------------------
 #*- get the parts of speech for a word in the dictionary
 #*- return a string of all possible parts of speech for the word
 #*------------------------------------------------------------------
 sub get_pos
 {
  my ($pword, $dbh) = @_;

  return('')  unless ($pword && $dbh);

  #*-- return punctuation for a single non-alphabetic character
  return('u') if ( (length($pword) == 1) && ($pword =~ /[^a-zA-Z]/) );

  #*-- replace spaces with underscore
  (my $word = lc($pword)) =~ s/\s/_/g; 
  my %pos_tags = ();

  #*-- inner subroutine to build the pos_tags hash, first
  #*-- check if the word is in the dictionary. If POS type
  #*-- is provided use it to fetch the row for the word.
  #*-- Weight the tags using the tag count in the dictionary
  #*-- a higher weight for the POS which is used more frequently
  #*-- parameter 1: the word
  #*-- parameter 2: the optional POS
  my $bld_tags = sub {
    if (&in_dict_table($_[0], $dbh)) 
     {  
       my $command = "select wnc_pos, wnc_synsets, wnc_etype from " . 
         (&dtable($_[0]))[0] . " where wnc_word = " . $dbh->quote($_[0]);
       $command .= ($_[1]) ? " and wnc_pos = '$_[1]'" : '';
       my ($sth, $db_msg) = $dbh->execute_stmt($command);
       return("Command: $command failed --> $db_msg") unless ($sth);
       while ( my ($w_type, $synsets, $etype) = $dbh->fetch_row($sth) )
        { foreach (split/\s+/, $synsets)
           { my ($type, $tag_cnt) = m%(.).*_(\d+)$%; 
             next unless ($type && defined($tag_cnt) );
             if ($pword =~ /^[A-Z]/)              #*-- higher wt. for entities
              { $tag_cnt += ($etype eq 'y') ? 100: 25; }
             $type = $w_type if ($type eq 'm');   #*-- use the word tag type
             $pos_tags{$type} += $tag_cnt; }      #*-- instead of synset tag
        } #*-- end of while 			  #*-- type for misc. words
     } #*-- end of if
  }; #*-- end of sub bld_tags

  #*-- get the tags and assoc. sense count for the word
  $bld_tags->($word); 

  #*-- consider base words as well -- some words such as 'are' appear
  #*-- in the dictionary table and the exclusion table. 'are' is also
  #*-- an exclusion word for the verb 'be' and more often used as a verb
  #*-- only one type should be returned for an exclusion word
  #*-- use the exclusion table alone for the base words
  #*-- Consider base words only if we have not found a POS tag in the dictionary
  unless (keys %pos_tags)
   { my %base_words = &base_words($word, $dbh, 1); 
     $bld_tags->($_, $base_words{$_}) foreach (keys %base_words); }

  #*-- set a default noun type
  $pos_tags{'n'} = 0 unless (keys %pos_tags); 

  #*-- return the hash if requested 
  if (wantarray() ) { return(%pos_tags); }
  elsif (defined wantarray() ) 	#*-- return a scalar if requested
   { my $types = join('', sort keys %pos_tags); return ($types); }
  else { return(''); }
 }

 #*---------------------------------------------------------
 #*-  lex_tagger            
 #*-    Lexical tagger using the simple table lookup
 #*-    POS Codes:
 #*-     'a' - adjective	'o' - preposition
 #*-     'c' - conjunction	'p' - pronoun
 #*-     'd' - determiner       'r' - adverb
 #*-     'i' - interjetion      'v' - verb
 #*-     'n' - noun             'u' - punctuation
 #*---------------------------------------------------------
 sub lex_tagger 
  {
   my ($rtext, 		#*-- reference to text
       $dbh,		#*-- database handle
       $hash_refs,	#*-- reference to token tables
       $want_cnt,	#*-- optional tag count
       $expand		#*-- optional field to expand short forms
      ) = @_;

   #*-- extract tokens from the text
   my ($rt, $rl, $rp) = &assemble_tokens($rtext, $dbh, $hash_refs, $expand);
   my @tokens = @$rt; my @loc = @$rl; my @t_types = @$rp;
   my @types = ();
   
   foreach my $i (0..$#tokens)
    {  
     #*-- set the punctuation types
     if ( ($t_types[$i] eq 'u') || 
          ( ($tokens[$i] =~ /^\W/) && (length($tokens[$i]) == 1) ) )
      { $types[$i] = 'u_0'; next; }

     #*-- set adjectives for numeric types
     if ($t_types[$i] eq 'n') { $types[$i] = 'a_0'; next; } 

     #*-- set nouns for abbreviations, combined, emoticons, 
     #*-- or Internet types
     if ($t_types[$i] =~ /[bei]/) { $types[$i] = 'n_0'; next; } 

     #*-- use the dictionary to get the pos
     if ( (length($tokens[$i]) == 1) && ($tokens[$i] =~ /[^a-zA-Z]/) )
      { $types[$i] = $t_types[$i] . '_0'; }
     else { my %types = &get_pos($tokens[$i], $dbh); 
            foreach (keys %types) { $types[$i] .= $_ . "_" . $types{$_}; }
          }
    } #*-- end of for tokens

   #*-- any unfilled tokens are punctuation
   foreach (@types) { next if $_; $_ = 'u_0'; } 

   #*-- return tag counts only on request
   unless ($want_cnt) 
    { s/_\d+//g foreach (@types); 
      foreach (@types) { $_ = join('', sort split//, $_); }
    } 
   
   return ($rt, $rl, \@types);
  }

 #*----------------------------------------------------------------
 #*-  POS Tagger    
 #*-   1. Read the rule table into memory
 #*-   2. Call the lexical tagger and tag the unambiguous words
 #*-   3. Use the rule table to tag the ambiguous words
 #*----------------------------------------------------------------
 sub pos_tagger
  {
   my ($rtext,		#*-- reference to text
       $dbh, 		#*-- database handle
       $hash_refs,	#*-- optional reference to token tables
       $expand		#*-- optional flag to expand short forms
      ) = @_;

   #*-- check parameters
   return (\[],\[],\[]) unless ($$rtext && $dbh);

   #*-- inner subroutine to get the max. freq and max. type
   my $word_rule = sub {

        #*-- get the tag with the highest frequency
        my ($command, $stags) = @_;
        my $max_freq = 0; my $max_type = '';
        my ($sth) = $dbh->execute_stmt($command);
        while (my ($tag, $w_tag, $freq) = $dbh->fetch_row($sth) )
         { if ($freq && ($freq > $max_freq) && ($stags =~ /$w_tag/) ) 
             { $max_freq = $freq; $max_type = $tag; }  
         } #*-- end of while
        return ($max_type, $max_freq);

     };

   #*-- get the list of words mentioned in the forward and
   #*-- backward rules
   my %twords = (); 
   my $command = "select ruc_type, ruc_part1, ruc_part2 from co_rulepos";
   my ($sth) = $dbh->execute_stmt($command);
   while (my ($type, $part1, $part2) = $dbh->fetch_row($sth) )
    { my $tword = ($type =~ /B$/) ? $part1: $part2;
      $twords{$tword}++; }

   #*-- use the lexical tagger to get the list of candidate tags
   my ($rt, $rl, $rg) = &lex_tagger($rtext, $dbh, $hash_refs, 1, $expand);

   #*-- save the most frequent tag and other tags in an array
   #*-- assign a default frequency of 100 for non-content words
   my @tokens = @$rt; foreach (@tokens) { tr/A-Z/a-z/; }
   my @most_f = my @stags = (); my @rg = @$rg;
   for my $i (0..$#rg)
    { my $max_fre = -1; $stags[$i] = '';
      while ($rg[$i] =~ /(.)_(\d+)/g)
       { my ($type, $freq) = ($1, $2);
         if ($freq > $max_fre)   { $most_f[$i] = $type; $max_fre = $freq; }
         if ($type =~ /[cipod]/) { $most_f[$i] = $type; $max_fre = 100; }
         $stags[$i] .= $type; } #*-- end of while
    }

   #*-- resolve tags in a loop from left to right in 1 pass
   for my $i (0..$#tokens)
    {
     #*-- skip, if no resolution necessary
     next if (length($stags[$i]) == 1);

     #*-- check if any rule to resolve the tag exists, i.e.
     #*-- is there a forward/backward rule that contains the word
     my $max_freq = -1; my $max_type = '';

     #*-- try the backword word rule
     if ( $tokens[$i+1] && $twords{$tokens[$i]} ) 
      {
       $command = "select ruc_wtag, ruc_part2, rui_frequency from " .
            " co_rulepos where ruc_part1 = " . $dbh->quote($tokens[$i]) .
            " and ruc_type = 'WB'";
       my ($type, $freq) = $word_rule->($command, $stags[$i+1]);
       if ($type && ($freq > $max_freq))
        { $max_freq = $freq; $max_type = $type; }
      }

     #*-- try the forward word rule
     if ( $tokens[$i-1] && $twords{$tokens[$i]} ) 
      {
       $command = "select ruc_wtag, ruc_part1, rui_frequency from " .
            " co_rulepos where ruc_part2 = " . $dbh->quote($tokens[$i]) .
            " and ruc_type = 'WF'";
       my ($type, $freq) = $word_rule->($command, $stags[$i-1]);
       if ($type && ($freq > $max_freq))
         { $max_freq = $freq; $max_type = $type; }
      } #*-- end of if 

      #*-- if a word rule was found, use it, otherwise use
      #*-- the most frequent type from the table
      $stags[$i] = ($max_freq == -1) ? $most_f[$i]: $max_type;

    } #*-- end of for i

   return ($rt, $rl, \@stags);
  }
1;

=head1 NAME

Pos - TextMine Parts of Speech Tagger

=head1 SYNOPSIS

use TextMine::Pos;

=head1 DESCRIPTION

 Three functions are used to generate POS tags for tokens.
 The get_pos function returns the possible tags for a token
 that exists in the dictionary. The lex_tagger function
 accepts text and returns a list of tokens with associated
 POS tags. The pos_tagger accepts text and returns a list
 of tokens with resolved POS tags.

=head2 get_pos

 Accept a word and return the possible parts of speech
 for the word from the dictionary.

=head3 Examples:

  %pos = &get_pos('check', $dbh);
  foreach (keys %pos) { print "$_: $pos{$_}"; }

  gives
  n: 28 v: 49
  
  The verb form of check is more frequently used than the noun form.

  $pos = &get_pos('check', $dbh);
  print "POS for check is $pos\n";
  
  gives
  POS for check is nv

=head2 lex_tagger

  Accept text and return the list of possible tags. Use the
  dictionary to list the possible tags for a word.

=head3 Example:

  $text = <<"EOT";
The growing popularity of Linux in Asia, Europe, and the U.S.
is a major concern for Microsoft.
EOT
  ($r1, $r2, $r3) = &lex_tagger(\$text, $dbh);
  for my $i (0..@$r1-1) { print "$$r1[$i]\t$$r3[$i]\n"; }

  gives
----------------------------------------------------------
The     d
growing an
popularity      n
of      o
Linux   n
in      anor
Asia    n
,       u
Europe  n
,       u
and     c
the     d
U.S.    n
is      v
a       dn
major   anv
concern nv
for     co
Microsoft       n
.       u
----------------------------------------------------------

 where
  'a' - adjective	'o' - preposition 'c' - conjunction	'p' - pronoun
  'd' - determiner      'r' - adverb      'i' - interjetion     'v' - verb
  'n' - noun            'u' - punctuation

=head2 pos_tagger

  Accept text and return the list of resolved tags.
  ($r1, $r2, $r3) = &pos_tagger(\$text, $dbh);
  for my $i (0..@$r1-1) { print "$$r1[$i]\t$$r3[$i]\n"; }

  gives
-----------------------------------------------------------
The     d
growing a
popularity      n
of      o
Linux   n
in      o
Asia    n
,       u
Europe  n
,       u
and     c
the     d
U.S.    n
is      v
a       d
major   a
concern n
for     o
Microsoft       n
.       u
-----------------------------------------------------------

=head1 AUTHOR

Manu Konchady <mkonchady@yahoo.com>
