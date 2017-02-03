#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*-------------------------------------------------------------
 #*- bld_ruleent.pl
 #*- Build the rule table for entities using the training data.
 #*- Each line of training data is a single sentence.
 #*-------------------------------------------------------------
 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Tokens qw/assemble_tokens load_token_tables/;
 use TextMine::WordNet qw/in_dictionary/;
 use TextMine::Utils qw/sum_array/;
 use TextMine::Constants qw/$DB_NAME @ETYPES/;

 #*-- get the database handle
 our ($command, $dbh, $sth);
 print ("Started building entity rules\n");
 ($dbh) = TextMine::DbCall->new ( 'Host' => '',
    'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => $DB_NAME);

 #*-- load the entity rule table and set entries to 0
 $dbh->execute_stmt("delete from co_ruleent");
 my @features = qw/in_person in_place in_org in_time in_currency 
    in_dimension in_tech sentence_start sentence_end in_dictionary/;
 foreach my $feature (@features)
  { $command = "insert into co_ruleent set ruc_feature = '$feature'";
    foreach (@ETYPES) { $command .= ", rui_$_ = 0"; }
    $dbh->execute_stmt($command); } 
 print "Initialized the entity rule table\n";

 #*-- preload the abbreviation table, the description includes
 #*-- the type of entity
 our %abbrev = (); my ($enc_name, $enc_description);
 $command = "select enc_name, enc_description from co_abbrev where " .
            "enc_type = 'a'";
 ($sth) = $dbh->execute_stmt($command);
 while ( ($enc_name, $enc_description) = $dbh->fetch_row($sth) )
  { $abbrev{$enc_name} .= $enc_description . " "; }
 print "Preloaded the abbreviation table\n";
                
 #*-- read the reuters training set
 open (IN, "r_train.txt") || 
      die ("Could not open reuters entity training file $!\n");
 my @lines = <IN>; close(IN);
 print ("Read the reuters training file\n");

 #*-- read the additional entities training set
 open (IN, "a_train.txt") ||
      die ("Could not open additional entity training file $!\n");
 push (@lines, <IN>); close(IN);
 print ("Read the additional training file\n");

 #*-- preload token tables
 my $hash_refs = &load_token_tables($dbh);

 #*-- process one line (sentence) at a time
 my $R_ETYPES = '^(' . join('|', map {uc($_)} @ETYPES) . ')($|_.*$)';
 $R_ETYPES = qr/$R_ETYPES/i;
 my $num_entities = 0;
 my $j = 0; my %count_etypes = ();
 foreach my $inline (@lines)
  { 
   next if ($inline =~ /^#/); #*-- skip comments
   chomp($inline);
   my ($rtok, undef, $rtype) = &assemble_tokens(\$inline, $dbh, $hash_refs); 
   my @tokens = @$rtok; my @types = @$rtype;
   for my $i (1..$#tokens-1)
    {
     #*-- check if have found an entity in sentence
     next unless ( ($tokens[$i-1] eq '<')                  && 
                   ($tokens[$i] =~ m%$R_ETYPES%i)          && 
                   ($tokens[$i+1] eq '>') );
     next unless ($tokens[$i+6]); 
     my $etype = lc($1); my $descr = ($2) ? $2: ''; $descr =~ s/^_//;
     next unless ( ($tokens[$i+3] eq '<')       && ($tokens[$i+4] eq '/') &&
                   ($tokens[$i+5] =~ /$etype/i) && ($tokens[$i+6] eq '>') );

     #*-- save the entity, token after, and token before
     $count_etypes{$etype}++;
     my $entity = $tokens[$i+2];

     #*-- verify that the entity exists in the tables
     &verify_etab($entity, $etype, $descr);

     #*-- get the before and after tokens
     my $atoken = ($tokens[$i+7]) ? lc($tokens[$i+7]) : '';
     my $btoken = ($tokens[$i-2]) ? lc($tokens[$i-2]) : '';

     #*-- set the punctuation tag
     my $atag = ( (($i+7) <= $#tokens) && (length($atoken) == 1) && 
                  ($atoken =~ /[^a-z]/i)) ? 'u':'';
     my $btag = ( (($i-2) >= 1)        && (length($btoken) == 1) && 
                  ($btoken =~ /[^a-z]/i)) ? 'u':'';

     #*-- use a different tag for numerics
     $atag = 'number' if ($tokens[$i+7] && ($types[$i+7] eq 'n') );
     $btag = 'number' if ($tokens[$i-2] && ($types[$i-2] eq 'n') );

     #*-- check in which entity table, the entity was found
     @features = ();
     foreach (@ETYPES) 
       { push (@features, "in_$_") if (&in_table($entity, $_)); }

     #*-- check other word features
     push (@features, 'in_dictionary')  if (&in_dictionary($entity, $dbh) );
     push (@features, 'all_up')         unless ($entity =~ /[^A-Z]/);
     push (@features, 'start_up')       if     ($entity =~ /^[A-Z]/);
     push (@features, 'sentence_start') 
          if ($inline =~ m%^\s*<$etype>$entity%i);
     push (@features, 'sentence_end') 
          if ($inline =~ m%$entity</$etype>\s*[\.\?!]$%i);
     
     #*-- add a tag or word feature
     if ($atag) { push (@features, 'atag_'  . $atag); } 
     elsif ($atoken =~ /^[a-zA-Z]/)
      { if ($atoken)            { push (@features, 'aword_' . $atoken); }
        if ($atoken =~ s/\.$//) { push (@features, 'aword_' . $atoken); } }

     if ($btag) { push (@features, 'btag_'  . $btag); } 
     elsif ($btoken =~ /^[a-zA-Z]/)
      { if ($btoken)            { push (@features, 'bword_' . $btoken); }
        if ($btoken =~ s/\.$//) { push (@features, 'bword_' . $btoken); } }

     #*-- update the rules for each feature of this entity type
     #*-- and keep a running total of the features
     &upd_rule($_, $etype) foreach (@features);
     $num_entities++;
      
    } #*-- end of for
   $j++; print ("Finished processing $j sentences\n") unless ($j % 10);
  } #*-- end of while
 close(IN);

 #*-- compute the weights for entity types based on the proportion 
 #*-- of training entity types
 my %ewt = ();
 $ewt{$_} = $count_etypes{$_} / $num_entities foreach (@ETYPES);

 #*-- each cell entry in the table represents the fraction of the number
 #*-- of times the particular feature was observed for the entity type
 print ("Updating the rule table\n");
 foreach (@ETYPES)
  { $command = "update co_ruleent set rui_$_" . "= rui_$_" .
               " / $count_etypes{$_}";
    $dbh->execute_stmt($command);   
    $command = "update co_ruleent set rui_$_" . "= rui_$_" .
               " * $ewt{$_}"; 
    $dbh->execute_stmt($command);   
  }

 #*-- manually added rules
 #*-- if preceded by a preposition, then entity is probably time
 $command = "insert into co_ruleent set ruc_feature = 'btag_o'";
 foreach (@ETYPES) { $command .= (/time/) ? ", rui_$_ = 1.0": ", rui_$_ = 0"; }
 $dbh->execute_stmt($command);

 #*-- dump the rules to a file
 print ("Dumping the rules to a file\n");
 $command = "select * from co_ruleent";
 ($sth, undef) = $dbh->execute_stmt($command);

 open (OUT, ">co_ruleent.txt") ||
   die ("Could not open ruleent.txt file $!\n");
 binmode OUT, ":raw";
 while ( my (@cols) = $dbh->fetch_row($sth) )
  { print OUT ("", join (':', @cols), ":\n"); }
 close(OUT);

 $dbh->disconnect_db($sth);
 print ("Finished building entity rules\n");

 exit(0);

 #*----------------------------------------------------------
 #*- return T or F if in the table
 #*----------------------------------------------------------
 sub in_table
 {
  my ($word, $etype) = @_;

  $word = lc($word); $word =~ s/\s/_/g; $word =~ s/\.$//;
  return (0) unless ($word && $etype);
  #*-- set the table based on the entity type
  my $table = ($etype =~ /^(?:PERSON|PLACE|ORG)$/i) ? 'co_' . $etype:
                                                      'co_entity';
  $command = "select enc_type from $table where enc_name = " .
             $dbh->quote($word);
  ($sth) = $dbh->execute_stmt($command);
  my ($enc_type) = $dbh->fetch_row($sth); 
  if ($enc_type)
   { $enc_type =~ s/_.*$//;
     return (1) if ( ($etype =~ /^(?:PERSON|PLACE|ORG)$/i) ||
                     ($enc_type =~ /$etype/i) ); }

  #*-- try an abbreviation
  return (1) if ($abbrev{$word} && ($abbrev{$word} =~ /$etype/i) );
  return (0);
 }

 #*----------------------------------------------------------
 #*- Add the rule to the table     
 #*----------------------------------------------------------
 sub upd_rule
 {
  my ($feature, $etype) = @_;

  #*-- check if the row for the feature exists
  $command = "select count(*) from co_ruleent where " .
             "ruc_feature = " . $dbh->quote($feature);
  ($sth) = $dbh->execute_stmt($command);
  unless ( ($dbh->fetch_row($sth))[0] )
   { $command = "insert into co_ruleent set ruc_feature = " . 
      $dbh->quote($feature) . "," . join (', ', map {"rui_$_ = 0"} @ETYPES);
     $dbh->execute_stmt($command); } 

  #*-- update the row
  my $rtype = 'rui_' . lc($etype);
  $command = "update co_ruleent set $rtype = $rtype + 1 where " .
             "ruc_feature = " . $dbh->quote($feature);
  $dbh->execute_stmt($command);
  return();
 }

 #*----------------------------------------------------------
 #*- Check if the entity exists in the database, if not
 #*- create an entry
 #*----------------------------------------------------------
 sub verify_etab
 {
  my ($entity, $etype, $d_etype) = @_;

  #*-- set the table based on the entity type
  #*-- skip miscellaneous and number
  return if ($etype =~ /^(number|miscellaneous)$/i);
  $entity = lc($entity); $entity =~ s/\.$//; $entity =~ s/\s+/_/g;
  my $suffix = ($etype =~ /^(?:PERSON|PLACE|ORG)$/i) ? $etype: 'entity';
  my $table  = 'co_'  . $suffix; my $p_etype = 'part' . $etype;
  $d_etype   = $etype unless ($d_etype);

  #*-- check if an entry exists in the table
  my $q_entity = $dbh->quote($entity);
  $command = "select enc_type from $table where enc_name = $q_entity";
  ($sth) = $dbh->execute_stmt($command);
  my ($enc_type) = $dbh->fetch_row($sth); 
  return() if ($enc_type);

  #*-- check the abbreviation table for entity of the same type
  return () if ($abbrev{$entity} && ($abbrev{$entity} =~ /$etype/i) );

  #*-- if not create an entry, first create the part entries
  if ($entity =~ /\s/)
   {
    #*-- check if the part entity exists in the table
    foreach (split/_/, $entity)
     { my $ename = $dbh->quote($_);
       $command = "select enc_type from $table where enc_name = $ename";
       ($sth) = $dbh->execute_stmt($command);
       ($enc_type) = $dbh->fetch_row($sth); 
       next if ($enc_type);

       #*-- otherwise, add the part entity to the table
       $command = <<"EOT";
         replace into $table set enc_name = $ename, 
                 enc_type = '$p_etype', enc_description = ''  
EOT
       ($sth) = $dbh->execute_stmt($command);
     } #*-- end of for
   } #*-- end of if

   $command = <<"EOT";
     replace into $table set enc_name = $q_entity, 
      enc_type = '$d_etype', enc_description = ''  
EOT
   ($sth) = $dbh->execute_stmt($command);

  return();
 }
