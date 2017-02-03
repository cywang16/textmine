
 #*--------------------------------------------------------------
 #*- Quanda.pm						
 #*- Description: A set of Perl functions for question and answer
 #*- processing.
 #*--------------------------------------------------------------

 package TextMine::Quanda;

 use strict; use warnings;
 use lib qw/../;
 use TextMine::Constants qw/@QWORDS $DELIM @QTYPES $EQUAL $ISEP/;
 use TextMine::Entity    qw/entity_ex load_entity_tables/;
 use TextMine::Index     qw/content_words/;
 use TextMine::Pos       qw/get_pos pos_tagger/;
 use TextMine::Tokens    qw/assemble_tokens load_token_tables/; 
 use TextMine::WordNet   qw/get_rel_words similar_words in_dictionary/;
 use TextMine::WordUtil  qw/gen_vector sim_val normalize text_split clean_text/;
 use TextMine::Utils     qw/log2 f_date/;
 require Exporter;
 our @ISA = qw(Exporter);
 our @EXPORT = qw(get_iwords get_qcat get_re_qcat INODES HNODES ONODES
                  IBIAS HBIAS I_SIM P_SIM Q_SIM V_SIM N_SIM YES NO);
 our @EXPORT_OK = qw(word_neighbours expand_query doc_query get_inouns
                     verify_qfile parse_query %cat_terms); 

 #*-- global variables
 our (%cat_terms);

 BEGIN
 { 
  #*-- neural net parameters
  use constant INODES    => 5;           #*-- no. of input nodes
  use constant HNODES    => 4;           #*-- no. of hidden nodes
  use constant ONODES    => 2;           #*-- no. of output nodes
  use constant IBIAS     => INODES+1;    #*-- no. for the input bias node
  use constant HBIAS     => HNODES+1;    #*-- no. for the hidden bias node
  use constant I_SIM     => 1;           #*-- Interr. word similarity
  use constant P_SIM     => 2;           #*-- Phrase similarity
  use constant Q_SIM     => 3;           #*-- Query entities similarity
  use constant V_SIM     => 4;           #*-- vector similarity
  use constant N_SIM     => 5;           #*-- Interr. noun similarity
  use constant YES       => 1;           #*-- Output node accept
  use constant NO        => 2;           #*-- Output node reject

  #*-- build a list of root terms to describe a category
  %cat_terms = ();
  $cat_terms{'currency'}  = 'currency money finance cost investment bank';
  $cat_terms{'dimension'} = 'dimension size';
  $cat_terms{'number'}    = 'number quantity magnitude amount';
  $cat_terms{'org'}       = 'organization company establishment institution';
  $cat_terms{'person'}    = 'person name';
  $cat_terms{'place'}     = 'place location country city continent';
  $cat_terms{'time'}      = 'time date period day week month year minute ' .
                            'hour second';
  $cat_terms{'miscellaneous'} = '';
 }

 #*------------------------------------------------------------
 #*- Get the category for the query using the neural net
 #*------------------------------------------------------------
 sub get_qcat
 {
  my ($query, $dbh) = @_;

  #*-- get the neural net weights for the categories
  my ($command, $sth);
  my %wt_ih = #*-- weights from input to hidden nodes
  my %wt_ho = #*-- weights from hidden to output nodes
             (); 
  my $hash_refs = &load_token_tables($dbh);

  #*-- for each category, build the weights from the input to
  #*-- hidden nodes and the weights from the hidden to output
  #*-- nodes. Read the weights from the DB table
  foreach my $category (@QTYPES)
   {
    $command = "select quc_weights from qu_categories where " .
                  "quc_ans_ents = '$category'";
    ($sth) = $dbh->execute_stmt($command);
    my ($weights) = $dbh->fetch_row($sth);
    my @weights = split/$EQUAL/, $weights;

    for my $i (1..IBIAS)
     { for my $h (1..HNODES)
        { $wt_ih{"$category,$i,$h"} = shift @weights; }
     }

    for my $h (1..HBIAS)
     { for my $o (1..ONODES)
        { $wt_ho{"$category,$h,$o"} = shift @weights; }
     }
   } #*-- end of foreach category

  #*-- get the interrogatory words
  my $q_iwords = &get_iwords($query);

  #*-- get the nouns following the interrogatory words
  my $q_inouns = &get_inouns($query, $dbh, $hash_refs, 1);

  #*-- extract the bigrams from the query text
  my $q_phrases = '';
  my ($r1) = &assemble_tokens(\$query, $dbh, $hash_refs); my @tokens = @$r1;
  foreach (split/\s+/, $q_iwords)
   { for my $j (0..$#tokens)
      { if ( ($tokens[$j]   =~ /\b$_\b/i) && ($j < $#tokens) &&
             ($tokens[$j+1] =~ /^[a-z]/i) )
          { $q_phrases .= lc("$tokens[$j] $tokens[$j+1]$DELIM"); }
      } #*-- end of inner for
   } #*-- end of middle for

  #*-- build and expand the vector for the query text
  #*-- find the hypernyms of the query tokens
  my %qterms = &gen_vector(\$query, 'fre', '', $dbh, 500);
  foreach (keys %qterms) { delete($qterms{$_}) if /^\d/; }
  foreach my $qterm (keys %qterms)
   { my %vec = &get_rel_words($qterm, 'hypernym', $dbh);
     next unless ($vec{'hypernym'});
     foreach (split/\s+/, $vec{'hypernym'})
       { $qterms{"\L$_"} = $qterms{$qterm} if (/\S/); }
   }
  #*-- Normalize the query vector
  &normalize(\%qterms);

  #*-- get the expanded query nouns
  my %e_query = &expand_query($query, $dbh);

  #*--------------------------------------------------------------------- 
  #*-- Loop through each category and compute the YES/NO
  #*-- weights using the neural net
  #*-- The input weights to the neural net are vector comparisons of
  #*--   a) query phrases such as what time, which place, when did, ...
  #*--   b) query interrogatory words such as what, when, why, how, ...
  #*--   c) nouns following the query interrogatory word weighted
  #*--      by distance from interrogatory word
  #*--   d) expanded query nouns with associated weights
  #*--   e) vector for the query
  #*-- with category equivalents from the query categories table
  #*--------------------------------------------------------------------- 
  my %parms = my %evec = my %qvec = my %results = ();
  $command = "select quc_ans_ents, quc_que_phrases, quc_cat_terms, " .
             " quc_iwords, quc_inouns, quc_vector from qu_categories";
  ($sth) = $dbh->execute_stmt($command);
  while (my ($category, $phrases, $terms, $iwords, $inouns, $vector) = 
            $dbh->fetch_row($sth) )
   {
    #*-- compare query phrase and phrase for category
    %evec = %qvec = (); my %outi = ();
    map { m%(.*?)$EQUAL(.*)%, $evec{$1} = $2 } split/$DELIM/, $phrases;
    %qvec = (); map { $qvec{$_}++ } split/$DELIM/,$q_phrases;
    $outi{'' . P_SIM} = &sim_val(\%evec, \%qvec);

    #*-- compare query iwords and iwords for category
    %evec = %qvec = ();
    map { m%(.*?)$EQUAL(.*)%, $evec{$1} = $2 } split/$DELIM/, $iwords;
    %qvec = (); map { $qvec{$_}++ } split/\s+/,$q_iwords;
    $outi{'' . I_SIM} = &sim_val(\%evec, \%qvec);

    #*-- compare query inouns and inouns for category
    %evec = %qvec = ();
    map { m%(.*?)$EQUAL(.*)%, $evec{$1} = $2 } split/$DELIM/, $inouns;
    %qvec = %{$q_inouns};
    $outi{'' . N_SIM} = &sim_val(\%evec, \%qvec);

    #*-- compare query terms and terms for category
    %evec = %qvec = ();
    map { m%(.*?)$EQUAL(.*)%, $evec{$1} = $2 } split/$DELIM/, $terms;
    $outi{'' . Q_SIM} = &sim_val(\%evec, \%e_query);

    #*-- compare query vector and vector for category
    %evec = %qvec = ();
    map { m%(.*?)$EQUAL(.*)%, $evec{$1} = $2 } split/$DELIM/, $vector;
    $outi{'' . V_SIM} = &sim_val(\%evec, \%qterms);

    #*-- run the forward pass
    #*-- initialize the input layers and compute the hidden layer values
    my %outh = my %outo = ();

    for my $h (1..HNODES)
     {
      my $sum = $wt_ih{"$category," . IBIAS . ",$h"};
      for my $i (1..INODES) 
        { $sum += $wt_ih{"$category,$i,$h"} * $outi{"$i"}; }
      $outh{"$h"} = 1.0 / (1.0 + exp(-$sum) );
     }

    #*-- compute the output layer values
    for my $o (1..ONODES)
     {
      my $sum = $wt_ho{"$category," . HBIAS . ",$o"};
      for my $h (1..HNODES) { $sum += $wt_ho{"$category,$h,$o"} * $outh{"$h"}; }
      $outo{"$o"} = 1.0 / (1.0 + exp(-$sum) );
     }

    #*-- check if outputs are over the threshold for the category
    next unless ( ($outo{''.YES} > 0.5) && ($outo{''.NO} < 0.5) );
    $results{$category} = $outo{''.YES} - $outo{''.NO};

   } #*-- end of while 

  #*-- if question could not be categorized, return miscellaneous
  my $num_types = scalar keys %results; my %new_results = ();
  unless ($num_types)
   { %new_results = ('miscellaneous', 1); return(%new_results); }

  #*-- if only one category was selected, done....
  return(%results) if ($num_types == 1);

  #*-- otherwise, find the top 2 categories
  my ($first, $second) = sort { $results{$b} <=> $results{$a} } keys %results;
  if ($first && $second)
   { %new_results = ("$first", $results{$first}, "$second", $results{$second});}
  else
   { %new_results = ("$first", $results{$first});}
  return(%new_results);

 }

 #*------------------------------------------------------------
 #*- Get the category for the query using regular expressions
 #*------------------------------------------------------------
 sub get_re_qcat
 {
  my ($query) = @_;

  my $q_iwords = &get_iwords($query); my %results = ();
  foreach (split/\s+/, $q_iwords)
   {
    CATEGORY: 
     {
      if (/^when/i)  { $results{'time'}   = 1; last CATEGORY; }
      if (/^where/i) { $results{'place'}  = 1; last CATEGORY; }
      if (/^who/i)   { $results{'person'} = 1; last CATEGORY; }
     }
   }
  unless (keys %results) { %results = ('miscellaneous', 1); }
  return(%results);
 }

 #*------------------------------------------------------------
 #*- return the top ranked sentences for a query
 #*- input format for text
 #*- ^###source of text###$
 #*- .... assoc. text ...
 #*------------------------------------------------------------
 sub doc_query
 {
  my ($rtext,	#*- reference to a text string containing 1 or more sources
      $rquery,	#*- reference to a query
      $ftype,	#*- type of text string (email, web, or news)
      $dbh,	#*- database handle
      $overlap	#*- flag for overlapping sentences
     ) = @_;

  #*-- set defaults
  use constant DEBUG => 0;
  next unless ($$rtext && $$rquery);
  $overlap = '' unless ($overlap);

  #*-- get the category of the query and the answer entities
  my $ltime = time();
  my %cats = &get_qcat($$rquery, $dbh); my @a_entities = keys %cats;
  if (DEBUG) 
    { print "Time to categorize question: ", time() - $ltime, " secs.\n"; }

  #*-- pre load some tables needed to create tokens
  $ltime = time();
  my $hash_refs = &load_token_tables($dbh);  
  my $tab_refs  = &load_entity_tables($dbh);
  if (DEBUG) 
    { print "Time to load tables: ", time() - $ltime, " secs.\n"; }

  #*-- split the source text and assign to a hash
  my %s_text = (); my $source = '';
  foreach (split/\n/, $$rtext)
   { if (/^$ISEP(.*)$ISEP$/) { $source = $1; $s_text{$source} = ''; next; }
     else { $s_text{$source} .= $_ . ' '; } }

  #*-- compute the frequency of tokens in all the text and
  #*-- the doc. frequency for tokens
  $ltime = time();
  my %t_freq = my %d_freq = (); my $num_docs = 0;
  foreach (keys %s_text)
   { my ($r1) = &content_words(\$s_text{$_}, $ftype, $dbh, 0, $hash_refs);
     my %ld_freq = ();
     foreach my $token (@$r1) 
      { $token = lc($token);
        $t_freq{$token}++; $ld_freq{$token} = 1 unless ($ld_freq{$token}); } 
     foreach my $token (keys %ld_freq) { $d_freq{$token}++; }
     $num_docs++;
   }

  #*-- compute the idf frequency of tokens in the text
  my $log2_d = &log2($num_docs);
  foreach my $token (keys %t_freq)
   { $t_freq{$token} *= ( $log2_d - &log2($d_freq{$token}) + 1 ); 
     $t_freq{$token} *= 2 if ($token =~ /\s/); #*-- double the count for
   }                                           #*-- a collocation
  &normalize(\%t_freq);

  if (DEBUG) 
    { print "Time to compute IDF: ", time() - $ltime, " secs.\n"; }

  #*-- get the unigrams, bigrams, and trigrams of the query
  $ltime = time();
  my ($r1, $r2, $r3) = &parse_query($rquery, $dbh, $hash_refs);
  my @unigram = @$r1;  my @bigram = @$r2; my @trigram = @$r3;
  if (DEBUG) 
    { print "Time to parse query: ", time() - $ltime, " secs.\n"; }

  #*-- get the interrogative nouns
  $ltime = time();
  my %inouns = %{&get_inouns($$rquery, $dbh, $hash_refs, 1)};
  &normalize(\%inouns);
  if (DEBUG) 
    { print "Time to get inouns: ", time() - $ltime, " secs.\n"; }

  #*-- get the sentences in the text and compute the score of
  #*-- each sentence
  my %rank = (); my $min_len = 100; #*-- minimum sentence legth
  foreach my $source (keys %s_text)
   {
    #*-- split the text into sentences or text chunks
    #*-- and for each sentence assign a score
    $ltime = time();
    ($r1) = 
     &text_split(\$s_text{$source}, $ftype, $dbh, $hash_refs,$min_len,$overlap);
    my @loc = @$r1;          #*-- end locations of text chunks
    if (DEBUG) 
    { print "Source: $source, time to split text: ", time()-$ltime," secs.\n"; }

    #*-- extract the entities
    $ltime = time();
    my (undef, undef, undef, $r2) = 
     &entity_ex(\$s_text{$source},$dbh,$tab_refs,$ftype,$min_len,$overlap);
    my @sent_ents = @$r2;
    if (DEBUG) 
    { print "Source: $source, time to extr. ent.: ", time()-$ltime," secs.\n"; }

    #*-- parse one sentence at a time 
    my %debug = ();
    for my $j (0..$#loc)
     {
      my ($start, $end);
      if ($overlap)
       { $loc[$j] =~ /^(.*?),(.*)$/;  ($start, $end) = ($1, $2); }
      else
       { $start = $j ? ($loc[$j-1] + 1): 0; $end = $loc[$j]; }
      &clean_text($s_text{$source});
      my $sentence = substr($s_text{$source}, $start, $end - $start + 1);

      #*-- count the number of answer entities
      my $ent_score = 0;
      foreach my $entity (@a_entities)
       { next if ($entity =~ /miscellaneous/i);
         $ent_score++ if ($sent_ents[$j] =~ /$entity/i); }

      #*-- count the number of common unigrams
      my $unigram_score = 0; my $qr_word;
      foreach my $word (@unigram)
       { next unless ($word); $word = lc($word); 
         my $t_word = quotemeta $word; $qr_word = qr/\b$t_word\b/i;
         if ($t_freq{$word})
          { $unigram_score += $t_freq{$word} 
              while ($sentence =~ /$qr_word/ig); }
       }

      #*-- count the number of common bigrams
      my $bigram_score = 0; my $bigram_wt = 1.0 / @bigram;
      foreach my $word (@bigram)
       { next unless ($word); my $t_word = quotemeta $word; 
         $qr_word = qr/$t_word/i;
         unless (DEBUG)
          { $bigram_score += $bigram_wt while ($sentence =~ /\b$qr_word\b/ig);}
         else
          { while ($sentence =~ /\b$qr_word\b/ig) 
             { $bigram_score += $bigram_wt; print "Bigram $qr_word\n"; } }
       } #*-- end of for

      #*-- count the number of common trigrams
      my $trigram_score = 0; my $trigram_wt = 1.0 / @trigram;
      foreach my $word (@trigram)
       { next unless ($word); my $t_word = quotemeta $word; 
         $qr_word = qr/$t_word/i;
         unless (DEBUG)
          {$trigram_score += $trigram_wt while ($sentence =~ /\b$qr_word\b/ig);}
         else
          { while ($sentence =~ /\b$qr_word\b/ig)
             { $trigram_score += $trigram_wt; print "Trigram $qr_word\n"; } }
       } #*-- end of for

      my $noun_score = 0;
      foreach my $word (keys %inouns)
       { next unless ($word); my $t_word = quotemeta $word; 
         $qr_word = qr/$t_word/i;
         $noun_score+= $inouns{$word} while ($sentence =~ /$qr_word/g); }

      #*-- compute the rank of the sentence
      my $score = (1.0  * $unigram_score + 1.5 * $bigram_score + 
                   4.0  * $trigram_score + 8.0 * $ent_score    +
                   16.0 * $noun_score);

      if (DEBUG)
       { $debug{"U: $unigram_score B: $bigram_score T: $trigram_score " .
                "E: $ent_score N: $noun_score SE: $sentence"} = $score; }

      #*-- set the score in the rank hash
      $rank{$source . $ISEP. $sentence} = $score;

     } #*-- end of for j

    #*-- debug answers
    if (DEBUG)
     { foreach (sort {$debug{$b} <=> $debug{$a}} keys %debug)
        { print "Score: $debug{$_} $_\n"; } }

   } #*-- end of for source

  #*-- rank and return the top 10 sentences with the assoc. score
  my $num_sentences = 0; my @results = ();
  for (sort {$rank{$b} <=> $rank{$a}} keys %rank)
   { push(@results, $_); last if (++$num_sentences == 10); }

  return (@results);  

 }

 #*---------------------------------------------------------------
 #*- Parse a query and return the unigrams, bigrams, and trigrams
 #*---------------------------------------------------------------
 sub parse_query
 {
  my ($rquery, $dbh, $hash_refs) = @_;

  #*-- clean up the query
  $$rquery =~ s/^\s+//; $$rquery =~ s/\s+$//; $$rquery =~ s/\s+/ /; 
  my ($r1) = &assemble_tokens($rquery, $dbh, $hash_refs); my @tokens = @$r1;

  #*-- build the unigrams
  my %unigrams = my @unigrams = ();
  foreach (@tokens) { next unless /^[a-zA-Z]/; $unigrams{$_}++; } 
  @unigrams = keys %unigrams;

  #*-- build the bigrams
  my %bigrams = my @bigrams = ();
  for my $i (1..$#tokens) 
   { next unless ( ($tokens[$i]   =~ /^[a-zA-Z]/) && 
                   ($tokens[$i-1] =~ /^[a-zA-Z]/) );
     $bigrams{"$tokens[$i-1] $tokens[$i]"}++; } 
  @bigrams = keys %bigrams;

  #*-- build the trigrams
  my %trigrams = my @trigrams = ();
  for my $i (2..$#tokens) 
   { next unless ( ($tokens[$i]   =~ /^[a-zA-Z]/) && 
                   ($tokens[$i-1] =~ /^[a-zA-Z]/) &&
                   ($tokens[$i+1] =~ /^[a-zA-Z]/) );
      $trigrams{"$tokens[$i-2] $tokens[$i-1] $tokens[$i]"}++; }
  @trigrams = keys %trigrams;

  return(\@unigrams, \@bigrams, \@trigrams);
  
 }

 #*---------------------------------------------------------------
 #*- Get the nouns after the first i-word of the query           
 #*---------------------------------------------------------------
 sub get_inouns
 {
  my ($query,		#*- question
      $dbh,		#*- database handle
      $hash_refs,	#*- reference to token tables
      $prop		#*- flag for proportionate weights for nouns
     ) = @_;

  #*-- find the first nouns following the interrogative word
  my ($r1, undef, $r2) = &pos_tagger(\$query, $dbh, $hash_refs);
  my @tokens = @$r1; my @tags = @$r2; my $noun = '';
  foreach (split/\s+/, &get_iwords($query) )
   { my $i_word = $_; my $i = 0;
     while ( ($i <= $#tokens) && ($tokens[$i] !~ /$i_word/i) ) { $i++; }
     $i++;

     #*-- try to get 2 nouns, for proportionate weights, assign
     #*-- a higher weight to the noun closer to the i-word
     for (0..1)
      { my $wt = ($prop) ? (256 / 2 ** $_): 128;
        while ( ($i <= $#tokens) && ($tags[$i] ne 'n') ) { $i++; }
        $noun .= " $tokens[$i]$ISEP$wt" 
             if ( ($i <= $#tokens) && ($tags[$i] eq 'n') &&
                  &in_dictionary($tokens[$i], $dbh) );
        $i++; }
     last;
   }

  #*-- get the words similar to the nouns
  my %nouns = &word_neighbours($noun, $dbh, 'n');
  return(\%nouns);
 }

 #*------------------------------------------------------------
 #*- Given a word, return its noun synonyms and hypernyms
 #*------------------------------------------------------------
 sub word_neighbours
 {

  my ($words, $dbh) = @_;

  #*-- for each word in the list
  my %words = ();
  foreach my $word (split/\s+/, $words)
   {
    #*-- find all similar nouns
    next unless ($word);
    $word = lc($word); $word =~ s/\s/_/g; 

    #*-- assign a weight to the word
    $words{$word} = ($word =~ s/$ISEP(\d+)//) ? $1: 128;
    foreach my $word1 (&similar_words($word, $dbh, 1, 'n'), $word )
     {
      #*-- assign a higher weight to synonyms
      next unless ( ($word1 =~ /^[a-zA-Z]/) && !$words{$word1});
      $words{$word1} = 64; 
      my %w_h1 = &get_rel_words($word1, 'hypernym', $dbh, 'n');

      #*-- get first level hypernyms
      if ($w_h1{'hypernym'})
        { 
         #*-- assign a lower weight to hypernyms
         foreach my $word2 (split/\s+/, $w_h1{'hypernym'}) 
          { 
           next unless ( ($word2 =~ /^[a-zA-Z]/) && !$words{$word2});
           $word2 = lc($word2); $word2 =~ s/\s/_/g; 
           $words{$word2} = 8;
          } #*-- end of for word 2 
        } #*-- end of if w_h1

     } #*-- end of foreach similar words
    } #*-- end of outer for
  return(%words);
 }

 #*------------------------------------------------------------
 #*- Given a query, return its expanded version in a hash
 #*- Only expand the nouns in the query and assign a weight
 #*- to the terms
 #*------------------------------------------------------------
 sub expand_query
 {

  my ($query, $dbh) = @_;

  my %equery = ();
  my ($r1) = &assemble_tokens(\$query, $dbh); my @tokens = @$r1;
  for my $i (0..$#tokens)
   {
    next unless (&get_pos($tokens[$i], $dbh) =~ /[n]/); 
    my %words = &word_neighbours($tokens[$i], $dbh, 'n');
    foreach (keys %words) 
      { if ($equery{$_}) { $equery{$_} += $words{$_}; } 
        else             { $equery{$_}  = $words{$_}; }
      }
   } #*-- end of for tokens
  return(%equery);
 }

 #*------------------------------------------------------------
 #*- return the query interrogatory words
 #*------------------------------------------------------------
 sub get_iwords
 {
  my ($question) = @_;

  local $" = '|'; my $qreg = qr/(@QWORDS)/i; local $" = ' ';
  $question =~ s/^\s+//; $question =~ s/\s+$//; $question =~ s/\s+/ /g;

  #*-- first check for any of the question words
  my $qtype = ''; 
  if ($question =~ s/^$qreg//)   { $qtype .= "\L$1"; }   #*-- check the 1st word
  while ($question =~ /$qreg/g)  { $qtype .= " \L$1"; }  #*-- try the remainder
  $qtype =~ s/^\s+//;
  #$qtype = 'what' unless($qtype); #*-- default type    
  return($qtype);
 }

 #*------------------------------------------------------------
 #*- Verify the format of the question file
 #*------------------------------------------------------------
 sub verify_qfile
 {
  my ($qfile) = @_; #*-- name of the question file

  local $" = '|'; my $qr_en = qr/(@QTYPES)/i; local $" = ' ';
  my %dup_q = ();
  open (IN, $qfile) || die "Unable to open $qfile $! \n";
  while (my $inline = <IN>)
   {
    #*-- skip comments and blank lines
    next if ($inline =~ /^(#|\s*$)/); chomp($inline);

    #*-- check if the question number exists
    print "No number for question $inline\n" unless $inline =~ s/^(\d+): //;
    my $qno = $1; print "Duplicate question no. $qno\n" if ($dup_q{$qno});
    $dup_q{$qno}++;

    #*-- check if the answer exists
    $inline = <IN>; chomp($inline);
    print "Q: $qno Answer not in correct format: $inline"
        unless $inline =~ /^(.*)###(.*)$/;

    #*-- check if the answer type exists
    print "Q: $qno Incorrect answer $2\n" unless ($2 =~ /$qr_en/i);
   }
  close(IN);

  return(0);
 }

1;
=head1 NAME

Quanda - TextMine Question & Answer Processing

=head1 SYNOPSIS

use TextMine::Quanda;

=head1 DESCRIPTION

  A number of functions for processing questions and answers.
  The features of questions are extracted and the type of
  question is evaluated. Text is split into sentences and
  the most appropriate sentence that may answer a question
  is selected.

=head2 get_iwords

  Get the interrogative word associated with a question. The
  interrogative words are who, what, when, how, etc. There
  maybe more than 1 interrogative word in a question.

=head2 get_qcat

  Get the category for a question. The category for a question
  can be time, number, dimension, person, place, org, or
  miscellaneous. The category of the question is used to
  evaluate candidate answer sentences. 

=head2 get_re_qcat

  Get the category for a question using regular expressions

=head2 get_inouns

  Get the nouns following the interrogative word in the query.
  The weight of the first noun can be made higher than the
  second noun (if any).

=head2 word_neighbours

  For any word find all the synonyms. For every synonym, find
  all hypernyms. Weigh the synonyms lower than the original
  word and weight the hypernyms still lower.

=head2 parse_query

  Accept a query and return references to 3 arrays. The
  first array is the list of unigrams, the second array
  is the list of bigrams, and the third array is the list
  of trigrams 

=head2 expand_query

  Find all the nouns in a query and expand each noun using
  the word_neighbours function. Return a hash containing
  the expanded words and their weights

=head2 doc_query

  Accept a reference to a text string, a reference to a query,
  the type of text string and return the sentences with 
  associated source that may answer the question in order.

=head1 Examples:

 1.  $question = "When did Vesuvius last erupt ?";
     %cat = get_qcat($question, $dbh);
     print "Category for $question: ", keys %cat, "\n";
  
     gives
     Category for When did Vesuvius last erupt ?: time

 2.  $cat = get_iwords($question, $dbh);
     print "Iwords for $question: $cat\n";
 
     gives
     Iwords for When did Vesuvius last erupt ?: when

 3.  $question = "When is the next Olympics ?";
     $cat = get_inouns($question, $dbh); @inouns = keys %$cat;
     print "Inouns for $question: @inouns\n";

     gives
     Inouns for When is the next Olympics ?: athletic_contest 
     celebration olympics period Olympic_Games athletics festivity 
     Olympiad period_of_time time_period athletic_competition

 4.  $words = "next Olympics";
     %cat = word_neighbours($words, $dbh); @words = keys %cat;
     print "Neighbours for $words: @words\n";

     gives
     Neighbours for next Olympics: athletic_contest celebration 
     olympics period Olympic_Games athletics next festivity 
     Olympiad period_of_time time_period athletic_competition
     
=head1 AUTHOR

Manu Konchady <mkonchady@yahoo.com>
