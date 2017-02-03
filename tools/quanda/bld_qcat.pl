#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*-----------------------------------------------------------
 #*- bld_qcat.pl
 #*-   Build the pattern file to train the neural network
 #*-   Use the training data in training.txt
 #*-----------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Constants qw/$DB_NAME $DELIM @QTYPES $EQUAL/;
 use TextMine::Entity    qw/load_entity_tables entity_ex/;
 use TextMine::WordUtil  qw/gen_vector expand_vec sim_val normalize truncate/;
 use TextMine::Tokens    qw/load_token_tables assemble_tokens/;
 use TextMine::WordNet   qw/get_rel_words/;
 use TextMine::Quanda    qw/get_iwords word_neighbours expand_query get_inouns
  verify_qfile %cat_terms P_SIM N_SIM I_SIM Q_SIM V_SIM/;

 print "Started bld_qcat.pl\n";
 use constant QNUM => 900;  #*-- number of training questions
 my ($dbh, $command, $table);
 ($dbh) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => $DB_NAME);

 print "Started reading ", QNUM, " questions and answers + ents.\n";
 my $i = 1;
 my %a_text 	= #*-- answer text
 my %q_phrases 	= #*-- question phrases using the iwords
 my %q_text 	= #*-- question text
 my %q_iwords 	= #*-- question interrogation words
 my %q_inouns 	= #*-- question noun words
 my %c_terms 	= #*-- category terms
 my %a_entities = #*-- questions assoc. with answers by entity type
 my %a_ents 	= (); #*-- answer entities by question

 #*---------------------------------------------------
 #*-- read the list of training questions & answers
 #*---------------------------------------------------
 my $tab_refs  = &load_entity_tables($dbh);
 my $hash_refs = &load_token_tables($dbh);
 local $" = '|'; my $qr_en = qr/(@QTYPES)/i; local $" = ' ';

 my $QFILE = "training.txt";

 #*-- first verify that the questions are in the right format
 &verify_qfile($QFILE);

 open (IN, $QFILE) || die "Unable to open $QFILE $! \n";
 while (my $inline = <IN>)
  { 
    next if ($inline =~ /^(#|\s*$)/); chomp($inline);

    #*-- save the question text, iwords and entities
    $inline =~ s/^\d+: //;
    $q_text{$i}   = $inline; 
    $q_iwords{$i} = &get_iwords($inline);
    $q_inouns{$i} = &get_inouns($inline, $dbh, $hash_refs);

    $inline = <IN>; chomp($inline); 
    ($a_text{$i}, $a_ents{$i}) = $inline =~ /^(.*)###(.*)$/;
    foreach (split/\s+/, $a_ents{$i}) { $a_entities{$_} .= "$i "; }
    $i++; }
 close(IN);

 print "Finished reading ", QNUM, " questions and answers + ents.\n";

 #*---------------------------------------------------
 #*-- get the interrogative word phrases, if possible
 #*---------------------------------------------------
 print "Start extracting query phrases....\n";
 for my $i (1..QNUM)
  {
   $q_phrases{$i} = '';
   my ($r1) = &assemble_tokens(\$q_text{$i}, $dbh, $hash_refs);
   my @tokens = @$r1; 
   foreach my $iword (split/\s+/, $q_iwords{$i})
    { for my $j (0..$#tokens)
       { if ( ($tokens[$j]   =~ /\b$iword\b/i) && ($j < $#tokens) &&
              ($tokens[$j+1] =~ /^[a-z]/i) )
          { $q_phrases{$i} .= lc("$tokens[$j] $tokens[$j+1]$DELIM"); }
       } #*-- end of inner for
    } #*-- end of middle for
  } #*-- end of outer for
 print "Finished extracting query phrases....\n";

 #*---------------------------------------------------
 #*-- build a hash of entity types and the corresponding questions
 #*---------------------------------------------------
 my %ent_questions = ();
 foreach my $qtype (@QTYPES)
  { $ent_questions{$qtype} = '';
    for my $a_ents (keys %a_entities)
     { $ent_questions{$qtype} .= $a_entities{$a_ents} . ' ' 
        if ($a_ents =~ /$qtype/i); }
  }

 #*---------------------------------------------------
 #*-- Create the table row for each question category
 #*---------------------------------------------------
 print "Started building file qu_cat_temp....\n";
 open (OUT, ">qu_cat_temp.txt") || die "Could not open qu_cat_temp $!\n";
 binmode OUT, ":raw";
 foreach my $etype (sort keys %ent_questions)
  {
   #*-- get the list of questions for the category
   #*-- build the interrogative words and entities hashes
   my %iwords = my %inouns = (); my $q_phrases = my $iwords = my $qtext = '';
   my $num_questions = 0;
   foreach my $qno (split/\s+/, $ent_questions{$etype})
    { 
     next unless ( (1 <= $qno) && ($qno <= QNUM) );
     map { $iwords{$_}++ } split/\s+/, $q_iwords{$qno};
    # $iwords{$q_iwords{$qno}}++; 
     $q_phrases .= $q_phrases{$qno};
     foreach my $noun (keys %{$q_inouns{$qno}} ) 
       { $inouns{$noun} += ${$q_inouns{$qno}}{$noun};}
     $qtext     .= $q_text{$qno};
     $num_questions++;
    }

   #*-- a category must have at least 10 questions
   next unless ($num_questions > 9); 

   #*-- get the interrogatory words
   my %dups = ();  map { $dups{$_}+= $iwords{$_} } keys %iwords;
   &normalize(\%dups, 5); 
   $iwords = join($DELIM, map {"$_$EQUAL$dups{$_}"} keys %dups);

   #*-- get the query phrases
   %dups = (); map { $dups{$_}++ } split/$DELIM/,$q_phrases; 
   %dups = &truncate(\%dups, 500); &normalize(\%dups, 5);
   $q_phrases = join($DELIM, map {"$_$EQUAL$dups{$_}"} keys %dups);

   #*-- get the interrogatory nouns
   %inouns = &truncate(\%inouns, 500); &normalize(\%inouns, 5);
   my $inouns = join($DELIM, map {"$_$EQUAL$inouns{$_}"} keys %inouns);

   #*-- get the category terms
   %dups = &word_neighbours($cat_terms{$etype}, $dbh, 'n');
 #%dups = ();
 #foreach (split/\s+/, $cat_terms{$etype})
 # {
 #  my %vec = &get_rel_words($_, 'hypernym', $dbh);
 #  next unless ($vec{'hypernym'});
 #  foreach (split/\s+/, $vec{'hypernym'}) 
 #    { $dups{"\L$_"}++ if (/\S/); } 
 # }
   &normalize(\%dups, 5); 
   my $c_terms = join($DELIM, map {"$_$EQUAL$dups{$_}"} keys %dups);
 
   #*-- build the vector for the query text
   #*-- Normalize and truncate the query terms
   my %qterms = &gen_vector(\$qtext, 'fre', '', $dbh);
   foreach (keys %qterms) { delete($qterms{$_}) if /^\d/; }
   &truncate(\%qterms, 500); &normalize(\%qterms, 5);
   my $qvector = join($DELIM, map {"$_$EQUAL$qterms{$_}"} 
                 sort {$qterms{$b} <=> $qterms{$a}} keys %qterms);

   print OUT "0:$etype:$q_phrases:$c_terms:$iwords:$inouns:$qvector:\n";

  }
 close(OUT);
 print "Finished building file qu_cat_temp....\n";

 #*---------------------------------------------------
 #*-- load the qu_categories table
 #*---------------------------------------------------
 $command = "delete from qu_categories";
 $dbh->execute_stmt("$command");
 $command = "load data local infile 'qu_cat_temp.txt'  " .
            "replace into table qu_categories fields     " .
            "terminated by ':' escaped by '!'";
 $dbh->execute_stmt("$command");

 #*---------------------------------------------------
 #*-- create the pattern file for input to the neural net 
 #*---------------------------------------------------
 our (%qvec1, %qvec2, %qvec3, %qvec4, %qvec5);
 print "Started creating the pattern file\n";
 open (OUT, ">pfile") || die ("Could not create pfile\n");
 binmode OUT, ":raw";
 my %patterns = my %evec = ();
 for my $qno (1..QNUM)
  {
   $a_ents{$qno} =~ s/^\s+//; $a_ents{$qno} =~ s/\s+$//;
   %qvec2 = &expand_query($q_text{$qno}, $dbh);
   %qvec4 = (keys %{$q_inouns{$qno}}) ? %{$q_inouns{$qno}}: ();
   %qvec5 = &gen_vector(\$q_text{$qno}, 'fre', '', $dbh, 500);
   foreach (keys %qvec5) { delete($qvec5{$_}) if /^\d/; }
   foreach my $category (split/\s+/, $a_ents{$qno})
    {
     next unless ($category =~ /^$qr_en$/i); my $a_ent = $1;

     %qvec1 = (); 
     map { $qvec1{$_}++ } split/$DELIM/,$q_phrases{$qno} if $q_phrases{$qno};
     %qvec3 = (); 
     map { $qvec3{$_}++ } split/\s+/,$q_iwords{$qno} if $q_iwords{$qno};

     $command = "select quc_que_phrases, quc_cat_terms, quc_iwords, " .
       "quc_inouns, quc_vector from qu_categories where quc_ans_ents ";

     #*----------------------------------------------------------
     #*- create two entries in the pattern file 
     #*- one for a matching entry and the other for a non-matching entry
     #*- pfile format
     #*-  Question no.: phrase sim.: query terms sim.:
     #*-  interrogation word sim.: interr. noun sim: vector sim.: 
     #*-  answer entity: YES/NO 
     #*----------------------------------------------------------
     for my $match (0..1)
      { 
       (my $n_command = $command) .= $match ? "  = '$category'": 
           ($category =~ /miscellaneous/i) ? 
          " != 'miscellaneous'": " = 'miscellaneous'";
       my %p = &compute_patterns($n_command,$dbh, $match); 
       my $outp = join(':', $p{'' . P_SIM}, $p{'' . Q_SIM}, 
                            $p{'' . I_SIM}, $p{'' . N_SIM}, $p{'' . V_SIM});
       print OUT "$qno:$outp:$a_ent:";
       print OUT $match ? "YES:\n": "NO:\n";
      } #*-- end of inner for etype

    } #*-- end of middle for
 
   print "Completed $qno questions\n" unless ($qno % 10);
  } #*-- end of outer for

 close(OUT);
 print "Finished creating the pattern file\n";
 print "Ended bld_qcat.pl\n";
 $dbh->disconnect_db();
 exit(0);

 #*-------------------------------------------------------------------
 #*- compute parameters for the pattern
 #*-------------------------------------------------------------------
 sub compute_patterns
 {
  my ($command, $dbh, $match) = @_;

  my ($sth, $db_msg) = $dbh->execute_stmt($command);
  if (!$sth && $db_msg) { print "$command failed ! \n"; return(); }
  my ($phrases, $c_terms, $iwords, $inouns, $vector) = $dbh->fetch_row($sth);
    
  #*-- build a vector for the phrases and get a similarity value
  %evec = (); my %outi = ();
  map {m%(.*?)$EQUAL(.*)%, $evec{$1} = $2} split/$DELIM/, $phrases if $phrases;
  $outi{''.P_SIM} = &sim_val(\%evec, \%qvec1);

  #*-- build a vector for the category terms and get a similarity value
  %evec = ();
  map {m%(.*?)$EQUAL(.*)%, $evec{$1} = $2} split/$DELIM/, $c_terms if $c_terms;
  $outi{''.Q_SIM} = &sim_val(\%evec, \%qvec2);
    
  #*-- build a vector for the iword and get a similarity value
  %evec = ();
  map {m%(.*?)$EQUAL(.*)%, $evec{$1} = $2} split/$DELIM/, $iwords if $iwords;
  $outi{''.I_SIM} = &sim_val(\%evec, \%qvec3);
    
  #*-- build a vector for the inouns and get a similarity value
  %evec = ();
  map {m%(.*?)$EQUAL(.*)%, $evec{$1} = $2} split/$DELIM/, $inouns if $inouns;
  $outi{''.N_SIM} = &sim_val(\%evec, \%qvec4);

  #*-- build a vector for the query text
  %evec = ();
  map {m%(.*?)$EQUAL(.*)%, $evec{$1} = $2} split/$DELIM/, $vector if $vector;
  $outi{''.V_SIM} = &sim_val(\%evec, \%qvec5);

  #*-- for non-matches reduce the weight of features
  #*-- increase the weight for matches
  my $weight = ($match) ? 2.0: 0.25;
  foreach (keys %outi) { $outi{$_} *= $weight; }
  foreach (keys %outi) { $outi{$_} = sprintf("%7.5f", $outi{$_}); }
  return (%outi);

 }
