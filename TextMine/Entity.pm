
 #*--------------------------------------------------------------
 #*- Entity.pm						
 #*- 
 #*- Description: Perl functions to extract entities (people, place,
 #*- orgs, misc.) from text.
 #*--------------------------------------------------------------

 package TextMine::Entity;

 use strict; use warnings;
 use lib qw/../;
 use TextMine::DbCall;
 use TextMine::Tokens    qw(load_token_tables assemble_tokens build_stopwords);
 use TextMine::Pos       qw(get_pos);
 use TextMine::Utils     qw(log2);
 use TextMine::WordNet   qw(in_dict_table base_words dtable in_dictionary);
 use TextMine::WordUtil  qw(text_split);
 use TextMine::Constants qw( @ETYPES ); 
 require Exporter;
 our @ISA = qw(Exporter);
 our @EXPORT_OK = qw(get_etype);
 our @EXPORT =    qw(load_entity_tables entity_ex); 
 use vars qw ();

 #*-- set the constants     
 BEGIN 
  { } 

 #*------------------------------------------------------------------
 #*- Get the entity type for a word. Accept a word and return y/n.
 #*------------------------------------------------------------------
 sub get_etype
 {
  my ($word, $dbh) = @_;

  return('n') unless ($word && $dbh);
  ($word = lc($word)) =~ s/\s/_/g; 

  #*-- build an array of equivalent words
  my @words = ();
  if (&in_dict_table($word, $dbh)) { push (@words, $word); }
  else
   { my %base_words = &base_words($word, $dbh); 
     push (@words, keys %base_words); }  

  #*-- check tables, if any one of the dictionary words is an entity,
  #*-- return true
  my $etype; 
  WORD: foreach my $word (@words)
   {
    my $command = "select wnc_etype from " . (&dtable($word))[0] .
                  " where wnc_word = "    . $dbh->quote($word);
    my ($sth, $db_msg) = $dbh->execute_stmt($command);
    return("Command: $command failed --> $db_msg") unless ($sth);
    while ( ($etype) = $dbh->fetch_row($sth) ) { last WORD if ($etype); }
   }
  $etype = 'y' unless($etype);
  return($etype);
 }

 #*----------------------------------------------------------
 #*- Load the tables to extract entities and return the
 #*- address of the hashes in an array
 #*----------------------------------------------------------
 sub load_entity_tables
 {
  my ($dbh) = @_;

  #*----------------------------------------------------------
  #*-- build the list of abbreviations and associated descriptions
  #*----------------------------------------------------------
  my %in_abbrev = ();
  my $command = "select enc_name, enc_description from co_abbrev where " .
             " enc_type = 'a'";
  my ($sth) = $dbh->execute_stmt($command);
  while ((my $enc_name, my $enc_description) = $dbh->fetch_row($sth)) 
   { $in_abbrev{$enc_name} = ($enc_description =~ /(\S+)/) ?
                               $1 : 'abbreviation'; }

  #*----------------------------------------------------------
  #*-- build the list of places and types
  #*----------------------------------------------------------
  my %in_place = ();
  $command = "select enc_name, enc_type from co_place";
  ($sth) = $dbh->execute_stmt($command);
  while ((my $enc_name, my $enc_type) = $dbh->fetch_row($sth)) 
   { $enc_type =~ s/_.*$//;
     $in_place{$enc_name} = $enc_type; }

  #*----------------------------------------------------------
  #*-- build the list of people and types
  #*----------------------------------------------------------
  my %in_person = ();
  $command = "select enc_name, enc_type from co_person";
  ($sth) = $dbh->execute_stmt($command);
  while ((my $enc_name, my $enc_type) = $dbh->fetch_row($sth)) 
   { $enc_type =~ s/_.*$//;
     $in_person{$enc_name} = $enc_type; }

  #*----------------------------------------------------------
  #*-- build the list of orgs and descriptions
  #*----------------------------------------------------------
  my %in_org = ();
  $command = "select enc_name, enc_type from co_org";
  ($sth) = $dbh->execute_stmt($command);
  while ((my $enc_name, my $enc_type) = $dbh->fetch_row($sth)) 
   { $enc_type =~ s/_.*$//;
     $in_org{$enc_name} = $enc_type; }

  #*----------------------------------------------------------
  #*-- build the list of other entities
  #*----------------------------------------------------------
  my %in_entity = ();
  $command = "select enc_name, enc_type from co_entity";
  ($sth) = $dbh->execute_stmt($command);
  while ((my $enc_name, my $enc_type) = $dbh->fetch_row($sth))
   { $in_entity{$enc_name} .= $enc_type . ' '; }

  #*-- save the references to the entity tables in a hash
  my $hash_refs = { 'in_abbrev'   => \%in_abbrev,
                    'in_place'    => \%in_place,
                    'in_person'   => \%in_person,
                    'in_org'      => \%in_org,
                    'in_entity'   => \%in_entity};

  return ($hash_refs);
 }


 #*---------------------------------------------------------
 #*-  Entity Extractor           
 #*-     Extract entities from the passed text and return
 #*-     an array of entities, associated types, and a 
 #*-     sentence - entity cross reference
 #*-
 #*-  Tables used:
 #*-   co_person:	First and last names of people
 #*-   co_place:	place and part place names
 #*-   co_org:		organizations and company names
 #*-   co_abbrev:	Abbreviations
 #*-   co_entity:	Names for time, dimension, and currency
 #*---------------------------------------------------------
 sub entity_ex 
  {
   my ($rtext,		#*-- reference to text for extraction
       $dbh, 		#*-- database handle 
       $tab_refs,	#*-- optional: reference to entity tables
       $ftype,		#*-- optional: type of text (news, web, email)
       $min_len,	#*-- optional: minimum length of sentences
       $overlap 	#*-- optional: allow overlap of sentences
      ) = @_;
   my ($command, $sth, @used, @words, %entities);

   #*-- set defaults
   return() unless ($$rtext && $dbh);
   $ftype   = '' unless ($ftype);
   $min_len = 50 unless ($min_len);
   $overlap = '' unless ($overlap);

   #*-- re for all entity types person, place, org, dim., curr., time, 
   #*-- misc., no., and tech
   my $r_etypes = '(' . join('|', @ETYPES) . ')'; 
   $r_etypes = qr/$r_etypes/i;

   #*-- re for topp entity types
   my $p_etypes = '(' . join('|', qw/tech org person place/).')'; 
   $p_etypes = qr/$p_etypes/i;

   #*-- re for excluded entity types
   my $x_etypes = '(' . join('|', 
      qw/abbreviation internet number pronoun punctuation/) . ')'; 
   $x_etypes = qr/$x_etypes/i;

   #*-- build the stopword list for the type of text
   my %stopwords = (); &build_stopwords(\%stopwords, $ftype);

   #*-- check if token tables have been loaded       
   #*-- and set the addresses of the tables in hashes
   $tab_refs  = &load_entity_tables($dbh) unless ($tab_refs);
   my %in_abbrev = %{$$tab_refs{in_abbrev}};
   my %in_place  = %{$$tab_refs{in_place}};
   my %in_person = %{$$tab_refs{in_person}};
   my %in_org    = %{$$tab_refs{in_org}};
   my %in_entity = %{$$tab_refs{in_entity}};

   #*-------------------------------------------------------------
   #*-- inner subroutine to check for valid abbreviation tokens
   #*-- accept a token and return the possible entity types
   #*-------------------------------------------------------------
   my $in_abb = sub { 

      (my $tok = $_[0]); 

      #*-- return if token starts with lower case and does not end with .
      return('') if ( ($tok =~ /^[a-z]/) && ($tok !~ /\.$/) );

      #*-- if in the abbreviation table, then get all matching entity types
      $tok =~ s/\.$//; my $retval = '';
      if ($in_abbrev{lc($tok)})
       {
        my $command = "select enc_description from co_abbrev where " .
                   "enc_name = '$tok'";
        my ($sth) = $dbh->execute_stmt($command); return('') unless $sth;
        while ( (my $description) = $dbh->fetch_row($sth) )
         { 
           #*-- the first part of the abbreviation description includes
           #*-- the entity type, if any. concatenate more than 1 descr.
           $description =~ m%^(\S+)%; next unless ($1); 
           $retval .= "$1 " if ($1 =~ /^$r_etypes$/i); }
       } #*-- end of if

      return($retval); };

   #*-------------------------------------------------------------
   #*-- inner subroutine to check for combinations of entities in
   #*-- the place, org, or entity tables. Check if the token is
   #*-  any one of the entity tables and return the assoc. entity type
   #*-------------------------------------------------------------
   my $in_top = sub { 
     my $ent = $_[0]; $ent =~ s/\s/_/g; $ent = lc($ent); 
     return ( $in_place{$ent} ? 'place': $in_org{$ent} ? 'org': 
              $in_entity{$ent} ? $in_entity{$ent}: ''); };

   #*-------------------------------------------------------------
   #*-- inner subroutine to get the stem word for words with quotes
   #*-- such as I'll, would'nt, etc.
   #*-------------------------------------------------------------
   my $in_stem = sub { 
      (my $token = lc($_[0]) ) =~ s/'(s|m|t|ll|nt)//;
       $token =~ s/\s/_/g; return($token); };

   #*-- pre load some tables needed to create tokens
   my $hash_refs = &load_token_tables($dbh);

   #*-- split the text into sentences and initialize global arrays
   my ($r1) = &text_split($rtext, $ftype, $dbh, $hash_refs, $min_len, $overlap);
   my @tchunks = @$r1; 		#*-- end locations of text chunks
   my $current_start = 0;	#*-- starting location for a text chunk
   my @gtokens =		#*-- global list of tokens
   my @gloc = 			#*-- global list of token locations
   my @gtypes = ();		#*-- global list of entity types
   my %tok_type_xref = ();	#*-- cross ref of tokens and entity types
   my @sent_ent_xref = ('') x @tchunks; #*-- list of entities in each text chunk

   #*--------------------------------------------------------
   #*-- parse one sentence at a time for entities
   #*-- Start of main loop
   #*--------------------------------------------------------
   OLOOP: for my $j (0..$#tchunks)
   { 
    my ($start, $end);
    if ($overlap)
     { $tchunks[$j] =~ /^(.*?),(.*)$/;  ($start, $end) = ($1, $2); }
    else
     { $start = $j ? ($tchunks[$j-1] + 1): 0; $end = $tchunks[$j]; }
    my $text = substr($$rtext, $start, $end - $start + 1);

    #*-- get the tokens for the text
    my ($r1, $r2, $r3) = &assemble_tokens(\$text, $dbh, $hash_refs);
    my @tokens = @$r1; my @loc = @$r2; my @types = @$r3;
    for (@types) { s/[abcx]//; } #*-- remove some token types - abbreviations,
				 #*-- combined token, colloc., unknown
   
    #*-- pass 1
    #*-- identify and categorize the potential entities in the text
    for my $i (0..$#tokens)
     {
      my $token = $in_stem->($tokens[$i]);

      #*-- check for abbreviations
      if ($i) 
       { $types[$i] .= $in_abb->($tokens[$i]); }
      #*-- at the beginning of a sentence, abbrev must end with .
      else
       { $types[$i] .= $in_abb->($tokens[$i]) if ($tokens[$i] =~ /\.$/); }

      #*-- skip numbers
      if ($types[$i] eq 'n')  { $types[$i] = 'number'; next; }

      #*-- skip punctuation
      if ($types[$i] eq 'u')  { $types[$i] = 'punctuation'; next; }

      #*-- skip internet tokens
      if ($types[$i] eq 'i')  { $types[$i] = 'internet'; next; }

      #*-- skip stopwords except the ones in the entity tables
      if ($stopwords{$token}    && !$in_entity{$token} 
          && !$in_place{$token} && !$in_org{$token} ) 
        { $types[$i] = ''; next; }

      #*-- set place entities
      if ( ($tokens[$i] =~ /^[A-Z]/) && $in_place{$token} && 
           ($types[$i] !~ /place/) )  
       { $types[$i] .= ($in_place{$token} =~ /^part/) ? 
                       " partplace ": " place " ; }

      #*-- set person entities, allow lower case
      if ( ($tokens[$i] =~ /^[A-Za-z]/) && $in_person{$token} &&
           ($types[$i] !~ /person/) ) 
       { $types[$i] .= ($tokens[$i] =~ /^[a-z]/) ? " partperson" : 
                                           " $in_person{$token} "; }

      #*-- set org entities
      if ( ($tokens[$i] =~ /^[A-Z]/) && $in_org{$token} &&
           ($types[$i] !~ /org/) )   
       { $types[$i] .= ($in_org{$token} =~ /^part/) ? 
                       " partorg ": " $in_org{$token} " ; }

      #*-- set other entities
     if ($in_entity{$token} && ($tokens[$i] =~ /^[A-Z]/) ) 
      { 
       if ($in_entity{$token} =~ /^(.*?)_(.*)/g)
        { 
         my ($etype, $description) = ($1, $2);
         #*-- skip time prepositions and qualifiers
         if ($etype eq 'time')
          { next if ($description =~ /^[qualifier|preposition]/); }
            $types[$i] .= " $etype "; 
          }  
        else
         { $types[$i] .= " $in_entity{$token} "; }
        $types[$i] =~ s/pronoun//; #*-- remove the pronoun type
      }

      #*-- recursively scan tokens that have embedded spaces
      if ($tokens[$i] =~ /\s/) 
       { $types[$i] = ''; my %seen = ();
         foreach (split/\s+/, $tokens[$i]) 
          { my (undef, undef, $r1) = 
               &entity_ex(\"$_", $dbh, $tab_refs, $ftype); 
            foreach (@$r1)
             { $types[$i] .= "$_ " unless ($seen{$_}); $seen{$_}++; }
          } #*-- end of outer for
       } #*-- end of if


      #*-- set all other entities as misc.
      if ($tokens[$i] =~ /^[A-Z]/) { $types[$i] .= " miscellaneous "; }
       
     } #*-- end of for $i ...

    #*-- pass 2 
    #*-- add part place, org, tech entities that could be in lower case
    #*-- and have a left/right token of the same type
    for my $i (1..($#tokens-1))
     {
       my $token = $in_stem->($tokens[$i]);
       $types[$i] .= ' partorg '
            if ( ($types[$i-1] =~ /org/)   && ($types[$i+1] =~ /org/) &&
                 $in_org{$token} );
       $types[$i] .= ' partplace '
            if ( ($types[$i-1] =~ /place/) && ($types[$i+1] =~ /place/) &&
                 $in_place{$token} );
       $types[$i] .= ' parttech '
            if ( ($types[$i-1] =~ /tech/)  && ($types[$i+1] =~ /tech/) &&
                 ($in_entity{$token} =~ /tech/) );
     }

    #*-- pass 3
    #*-- resolve the part entities
    for my $i (0..$#tokens)
    { 
      next unless ($types[$i] =~ /part/i);
      RESOLVE: for my $type (qw/org place person tech/)
                                                #*-- fix only nouns/adj.
       { for my $j($i-2..$i+2)                  #*-- look at two words on 
          { next if ( ($j < 0) || ($j == $i) ); #*-- either side of the word
            if ($types[$j] && ($types[$j] =~ /$type\b/) 
                 && (&get_pos($tokens[$i], $dbh) =~ /[an]/) ) 
              { $types[$i] =~ s/part$type/$type/; next RESOLVE; }
          } #*-- end of inner for
       } #*-- end of outer for

      $types[$i] =~ s/part(?:org|place|person|tech)//g;  #*-- remove the part  
    } #*-- end of outermost for

    #*-- clean up the types
    for (@types) { s/\s+/ /g; next unless /\S/; s/_.*?\s/ /g; 
      s/^\s+//; s/\s+$//; } 

    #*-- pass 4
    #*-- classify the entities with 2 or more types using the co_entity table
    for my $i (0..$#tokens)
     {
      next unless ($types[$i]);

      #*-- skip entities that have been classified with a single type
      next if ($types[$i] =~ m%^$r_etypes$%i); 

      #*-- skip some word types (abbrev, internet, number, pronoun, punct.)
      if ($types[$i] && $types[$i] =~ /$x_etypes/) { $types[$i] = $1; next; }

      #*---------------------------------------------------------------
      #*-- get the features of this entity based on the entity tables
      #*-- Features:
      #*--  1: Find the entity tables in which the entity is found 
      #*--  2: The tags of the word before and after the entity
      #*--  3: Starts with upper case                          
      #*--  4: All upper case letters                          
      #*--  5: Found at the start of a sentence                  
      #*--  6: Found at the end of a sentences               
      #*---------------------------------------------------------------
      my @features = ();
      my $token = $in_stem->($tokens[$i]);
      push (@features, 'in_currency') 
       if ($in_entity{$token} && ($in_entity{$token} =~ /(^|\s)curr/i));
      push (@features, 'in_dimension') 
       if ($in_entity{$token} && ($in_entity{$token} =~ /(^|\s)dime/i));
      push (@features, 'in_time') 
       if ($in_entity{$token} && ($in_entity{$token} =~ /(^|\s)time/i));
      push (@features, 'in_tech') 
       if ($in_entity{$token} && ($in_entity{$token} =~ /(^|\s)tech/i));
      push (@features, 'in_org')    if ($in_org{$token});
      push (@features, 'in_place')  if ($in_place{$token});
      push (@features, 'in_person') if ($in_person{$token});
      
      #*-- use the context to check for features the word, punctuation,
      #*-- or number before/after the word
      if ($types[$i-1])
       { my $token = $in_stem->($tokens[$i-1]);
         push (@features, ($types[$i-1] eq 'punctuation') ?  "btag_u": 
                          ($types[$i-1] eq 'number'     ) ?  "btag_number":
                           "bword_$token"); } 
      if ($types[$i+1])
       { my $token = $in_stem->($tokens[$i+1]);
         push (@features, ($types[$i+1] eq 'punctuation') ?  "atag_u": 
                          ($types[$i+1] eq 'number'     ) ?  "atag_number":
                           "aword_$token"); } 

      #*-- check if preceding token was a time preposition
      if ($tokens[$i-1])
       { my $token = $in_stem->($tokens[$i-1]);
         if ($in_entity{$token} && ($in_entity{$token} =~ /preposition/) )  
           { push (@features, "btag_o"); } }

      push (@features, 'start_up') if ($tokens[$i] =~ /^[A-Z]/);
      push (@features, 'all_up') unless ($tokens[$i] =~ /[a-z]/);
      push (@features, 'sentence_start') unless ($i);
      push (@features, 'sentence_end')   if ( ( ($i+1) == $#tokens) && 
                                         ($types[$i+1] eq 'punctuation') );

      #*-- check the best fit entity type based on the features
      #*-- use a Naive Bayesian Model
      #*-- 1. Initialize the scores for the possible entity types
      #*-- 2. Add the log of the probabilities of features for entity types
      #*-- 3. Find the entity type with the highest score
      my %score = (); 
      foreach (@ETYPES) { $score{$_} = 0 if (/$types[$i]/); }
      foreach my $feature (@features)
       {
        my $command = "select * from co_ruleent where ruc_feature = " .
                      $dbh->quote($feature);
        ($sth) = $dbh->execute_stmt($command);
        my %rule = (); my $s;
        %rule = %$s if ($s = $dbh->fetch_row($sth, 1));
        
        #*-- accumulate the score for the entity
        foreach my $etype (map {lc($_) } split/\s+/, $types[$i])
         { 
           next unless ($etype && ($etype =~ m%^$r_etypes$%i) );
           next if ($etype eq 'miscellaneous'); #*-- but skip the misc. type

           $score{$etype} += &log2($rule{"rui_" . $etype}) 
                             if ($rule{"rui_" . $etype}); 
         }
        
       } #*-- end of foreach features

      #*-- if the rules were used to find the entity with the highest score
      my ($max_type) = sort {$score{$b} <=> $score{$a}} keys %score;
      if ($max_type && defined($score{$max_type})) 
         { $types[$i] = $max_type; next; }

     } #*-- end of for i

    #*-- pass 5
    #*-- verify entities that exist in the dictionary
    #*-- get the probabilities of an entity type existing in 
    #*-- the dictionary based on the training data
    $command = "select " . join(',', map { 'rui_' . $_} @ETYPES) .
               " from co_ruleent where ruc_feature = 'in_dictionary'";
    ($sth) = $dbh->execute_stmt($command);
    my %e_prob = %{my $ep = $dbh->fetch_row($sth, 1)}; #*-- fetch a hash ref
    for my $i (0..$#tokens)
     { 
      next unless ($types[$i]);

      #*-- skip excluded types
      next if ($types[$i] =~ /$x_etypes/);	

      #*-- skip if the prob. of being in the dictionary is > 0.5
      #*-- look for strong evidence of an entity - starts with
      #*-- upper case and it is only a noun
      next unless ($e_prob{'rui_' . $types[$i]});
      next if     ($e_prob{'rui_' . $types[$i]} > 0.5);
      if (&in_dictionary($tokens[$i], $dbh))
       { 
         #*-- keep type if just a noun
         next if (&get_pos($tokens[$i], $dbh) eq 'n');

         #*-- keep if starts with upper case and not start of sentence
         next if ($i && $tokens[$i] =~ /[A-Z]/);

         #*-- keep if its an entity in the dictionary
         next if ($i && (&get_etype($tokens[$i], $dbh) eq 'y') );
         
         #*-- otherwise, remove it
         $types[$i] = '';
       }
     } #*-- end of for i

    #*-- remove the punctuation types
    foreach (@types) { s/punctuation//i; }

    #*-- pass 6
    #*-- Try to resolve the misc. tokens
    #*-- Scan from the right to left looking at right token
    #*-- if the right token is 'ppot', then set the same type
    #*-- for this token if it is a noun/adj. 
    for my $i (reverse 0..$#tokens)
     {
      next unless ($types[$i] =~ /^(miscellaneous)/);

      #*-- try the right neighbors and check for ppot types
      if ($types[$i+1] && $types[$i+1] =~ /^$p_etypes$/i) 
       { my $ptype = $1;
         my $type = &get_pos($tokens[$i], $dbh);
         $types[$i] = $ptype if ($type =~ /[na]/i); 
         next; }   
     }

    #*-- Scan from the left to right 
    for my $i (0..$#tokens)
     {
      next unless ($types[$i] =~ /miscellaneous/);

      #*-- check for combinations to the left and right
      my $j = $i; my $c_token = ''; my ($start, $end); my $cflag = '';
      while ($j && $types[$j-1]) 
       { $c_token = $tokens[$j-1] . '_' . $c_token; $j--; $cflag++; }
      $start = $j; $j = $i; $c_token .=  $tokens[$i];
      while ($j && $types[$j+1]) 
       { $c_token = $c_token . '_' . $tokens[$j+1]; $j++; $cflag++; }
      $end = $j;
      $c_token =~ s/^_//; $c_token =~ s/\.$//; $c_token = lc($c_token);

      #*-- strip some standard org suffixes
      if ($cflag) 
       {
        $c_token =~ s/_(?:co|ltd|corp|inc|org|inst)$//;
        if ($in_org{$c_token}) 
          { @types[$start..$end] = ('org')    x ($end - $start + 1); next; }
        if ($in_place{$c_token}) 
          { @types[$start..$end] = ('place')  x ($end - $start + 1); next; }
        if ($in_person{$c_token}) 
          { @types[$start..$end] = ('person') x ($end - $start + 1); next; }
        if ($in_entity{$c_token}) 
          { (my $etype = $in_entity{$c_token}) =~ s/_.*$//;
            @types[$start..$end] = ($etype)   x ($end - $start + 1); next; }
       } #*-- end of if

      #*-- try the left neighbor and check for ppot types
      #*-- and the current token is a noun/adj.
      if ($types[$i-1] && (&get_pos($tokens[$i],$dbh) =~ /[na]/) &&
          ($types[$i-1] =~ /^$p_etypes$/i) )
       { $types[$i] = $1; next; }

      #*-- otherwise, discard a token found in the dictionary
      #*-- and not an entity type
     if (&in_dictionary($tokens[$i], $dbh) &&
        (&get_etype($tokens[$i], $dbh) eq 'n') )
         { $types[$i] = ''; }
    } #*-- end of for

    #*-- remove blank entries
    s/^\s+$// foreach (@types);

    #*-- pass 7
    #*-- build the entity - type xref hash
    for my $i (0..$#tokens)
     { 
       next unless ($types[$i]); 
       my $token = $in_stem->($tokens[$i]);

       #*-- resolve conflicting token types
       if ($tok_type_xref{$token})
        { 
         #*-- When neither of the types is misc., set the multiple type
         if ( ($tok_type_xref{$token} ne $types[$i])      &&
              ($tok_type_xref{$token} ne 'miscellaneous') &&
              ($types[$i]             ne 'miscellaneous') )
          { 
            #*-- A single token has more than one assigned entity type
            #*-- and both are not misc. So, set the entity type 
            #*-- of the non-matching token to the first occurrence
            #*-- entity type.
           # $tok_type_xref{$token} = 'Multiple'; 
            $types[$i] = $tok_type_xref{$token};
          } 
         #*-- Override the misc. type
         else
          { $tok_type_xref{$token} = $types[$i] if
              ($types[$i] !~ /miscellaneous/i); }
        }
       else { $tok_type_xref{$token} = $types[$i]; }
     } #*-- end of for $i...
    
    foreach (@loc) { $_ += $current_start; }
    $current_start += $end - $start + 1;

    #*-- build the global arrays
    push (@gtokens, @tokens); push (@gloc, @loc); push (@gtypes,  @types);

    #*-- populate the sentence entity cross reference
    foreach (@types)
     { next unless ($_); $sent_ent_xref[$j] .= "$_ "; }

   } #*-- end of OLOOP

  #*-- make sure that all entities are resolved consistently
  for my $i (0..$#gtokens)
   { 
    my $token = $in_stem->($gtokens[$i]);

    #*-- skip unless token has an entity type
    next unless (my $type = $tok_type_xref{$token});

    #*-- skip tokens that begin with lower case or are misc.
    next if (($gtokens[$i] =~ /^[^A-Z]/) || ($type eq 'miscellaneous'));

    #*-- skip tokens that have been resolved
    next unless ( ($gtypes[$i] eq '') || ($gtypes[$i] eq 'miscellaneous') );

    #*-- set type to misc. when the token was not resolved 
    #*-- consistently (person + org)
    #*-- otherwise, set it to the type assigned elsewhere in the text
    if ($tok_type_xref{$token} eq 'Multiple')
     { $gtypes[$i] = 'miscellaneous' 
        if ( ($gtypes[$i] =~ /^\s*$/) && (&get_pos($token, $dbh) =~ /[na]/) ); }
    else
     { $gtypes[$i] = $tok_type_xref{$token}; }

    } #*-- end of for

  #*-- check for words between org types and set
 # for my $i (1..$#gtokens-1)
 #  { $gtypes[$i] = 'org' 
 #    if ( ($gtypes[$i-1] eq 'org') && ($gtypes[$i+1] eq 'org') ); }

  return(\@gtokens, \@gloc, \@gtypes, \@sent_ent_xref);
 }

1;
=head1 NAME

Entity - TextMine Entity Extractor

=head1 SYNOPSIS

use TextMine::Entity;

=head1 DESCRIPTION

=head2 entity_ex

  Extract entities from the passed text. Pass a reference to 
  the text, a database handle, an optional reference to entity
  tables, the type of text (email, news, web, or ''), the 
  optional minimum length of a sentence, and an overlap flag.

  References to a list of tokens, the locations in the text,
  the type of the token, and a sentence-entity cross reference
  are returned. The lists of tokens, locations, and types 
  are related. The type and location of the third token can
  be found in the third element of the types and locations 
  array. 

  The sentence entity cross reference returns an array
  with list of entity types found in each sentence.

=head1 EXAMPLE

  $text = <<"EOT";
The growing popularity of Linux in Asia, Europe, and the U.S.
is a major concern for Microsoft. It costs less than 1 USD
a month to maintain a Linux PC in Asia. By 2007, over 500,000
PCs sold in Asia maybe Linux based.
EOT

 ($r1, $r2, $r3, $r4) = &entity_ex(\$text, $dbh);
 @r1 = @$r1; @r2 = @$r2; @r3 = @$r3; @r4 = @$r4;
 printf ("%-10s%10s\n", 'Token', 'Type');
 for my $i (0..$#r1)
  { printf ("%-10s%10s\n", $r1[$i], $r3[$i]) if ($r3[$i]); }
 $" = "\n"; print "@r4";

 generates the following output
 ----------------------------------------------------------------
 Token           Type
 Linux           tech
 Asia           place
 Europe         place
 U.S.           place
 Microsoft        org
 1             number
 USD         currency
 Linux           tech
 PC              tech
 Asia           place
 2007          number
 500,000       number
 PCs       miscellaneous
 Asia           place
 Linux           tech
 tech place place place org
 number currency tech tech place
 number number miscellaneous place tech
 -------------------------------------------------------------------

 The entity tokens are extracted from the text and categorized. 
 The entity types are currency, dimension, miscellaneous, number
 org, person, place, time, and tech. Tables and rules are used
 to classify entities.

 Following the list of tokens and types is an array of the tokens
 founds in each sentence of the text. This is useful in finding
 key sentences that may answer questions.

=head1 AUTHOR

Manu Konchady <mkonchady@yahoo.com>
