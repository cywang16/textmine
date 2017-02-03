#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------------------
 #*- perlfaq.pl
 #*-  
 #*- Summary: Load the perlfaq database table using a text file 
 #*----------------------------------------------------------------
 use strict; use warnings; 
 use Config;
 use TextMine::DbCall;
 use TextMine::Quanda qw(get_inouns get_iwords);
 use TextMine::Tokens qw(load_token_tables assemble_tokens);
 use TextMine::WordUtil qw(gen_vectors sim_val normalize);
 use TextMine::Constants qw($DB_NAME $DELIM $EQUAL); 

 print ("Started creating the perlfaq table\n");
 our ($dbh) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => $DB_NAME);

 #*---------------------------------------------------
 #*-- Create the temporary perlfaq file
 #*---------------------------------------------------
 &gen_perlfaq();

 #*---------------------------------------------------
 #*-- load the perlfaq table
 #*---------------------------------------------------
 my $command = "delete from qu_perlfaq";
 $dbh->execute_stmt("$command");
 $command = "load data local infile 'qu_perlfaq.dat'  " .
            "replace into table qu_perlfaq fields     " .
            "terminated by ':' escaped by '!'";
 $dbh->execute_stmt("$command");

 &load_sim_vals();
 &dump_file();
 $dbh->disconnect_db();
 print ("Finished loading perlfaq ...\n");
 exit(0);

 #*-------------------------------------------------------------
 #*- create the perlfaq file         
 #*-------------------------------------------------------------
 sub gen_perlfaq
 {
  #*-- read the questions and answers into arrays
  print "Started reading questions and answers\n";
  open (IN, "./data/perlfaq.txt"); my %in = (); my ($inline);
  my $q_str = my $a_str = ''; my @qs = my @as = ();
  while ($inline = <IN>)
   { $inline =~ s/\cM$//;   #*-- remove any control Ms
     $inline =~ s/\n/ EOL/g; #*-- replace newlines

     #*-- start of a question
     if ($inline =~ s/^Q://) 
      { push(@as, $a_str) if ($a_str && $in{"answer"}); $a_str = '';
        $in{"question"} = 1; $in{"answer"} = 0; }

     #*-- start of an answer
     if ($inline =~ s/^A://) 
      { push(@qs, $q_str) if ($q_str && $in{"question"}); $q_str = '';
        $in{"question"} = 0; $in{"answer"} = 1; }

     $q_str .= "$inline" if ($in{"question"});
     $a_str .= "$inline" if ($in{"answer"});
   }
  push (@as, $a_str) if ($in{"answer"});
  close(IN);
  print "Finished reading questions and answers\n";

  #*-- generate vectors for the questions
  print "Started generating vectors\n";
  my (@docs, @doc_ids); my @vectors = ();
  @docs = (); my $limit = 250;
  for my $i (0..$#qs) { push (@docs, \"$qs[$i] $as[$i]"); }
  (my $rmatrix, my $rterms) = &gen_vectors('idf', 1, '', \@docs, $dbh);
  print "Finished generating vectors\n";
  my %matrix = %$rmatrix; my @terms = @$rterms; 
  for my $doc_i (0..$#docs)
   { my $j = 0; my $vector = '';
     for my $i (sort
       { $matrix{$terms[$b]}{$doc_i} <=> $matrix{$terms[$a]}{$doc_i} } 
         (0..$#terms) )
      {
        last if (++$j > $limit); #*-- limit the vector len.
        (my $wt = $matrix{$terms[$i]}{$doc_i}) =~ s/(\....).*/$1/; 
        $vector .= "$terms[$i]$EQUAL$wt$DELIM" if ($wt); }
     push (@vectors, $vector);
   }
  undef(%matrix); undef(@terms);
  
  #*-- get the other attributes for the questions
  open (OUT, ">qu_perlfaq.dat") || die ("Unable to open qu_perlfaq.dat");
  binmode OUT, ":raw";
  my $hash_refs = &load_token_tables($dbh);
  my @inouns = my @iphrases = my @iwords = ();
  for my $i (0..$#qs)
   { 
    #*-- get the interrogatory nouns
    my %vec = %{&get_inouns($qs[$i], $dbh, $hash_refs)}; &normalize(\%vec,5);
    my $inouns = join($DELIM, map {"$_$EQUAL$vec{$_}"} keys %vec);

    #*-- get the interrogatory words
    %vec = ();  map { $vec{$_}++ } split/\s+/, &get_iwords($qs[$i]);
    &normalize(\%vec, 5);
    my $iwords = join($DELIM, map {"$_$EQUAL$vec{$_}"} keys %vec);

    #*-- get the interrogatory phrases
    my ($r1) = &assemble_tokens(\$qs[$i], $dbh, $hash_refs);
    my @tokens = @$r1; my @phrases = ();
    foreach my $iword (keys %vec)
     { for my $j (0..$#tokens)
       { push(@phrases, lc("$tokens[$j] $tokens[$j+1]") )
         if ( ($tokens[$j]   =~ /\b$iword\b/i) && ($j < $#tokens) &&
              ($tokens[$j+1] =~ /^[a-z]/i) ); } 
     }
    %vec = (); map { $vec{$_}++ } @phrases; &normalize(\%vec, 5);
    my $iphrases = join($DELIM, map {"$_$EQUAL$vec{$_}"} keys %vec);
    $vectors[$i] =~ s/!/!!/g; $qs[$i] =~ s/!/!!/g; $as[$i] =~ s/!/!!/g;
    $vectors[$i] =~ s/:/!:/g; $qs[$i] =~ s/:/!:/g; $as[$i] =~ s/:/!:/g;

    print OUT "0::$qs[$i]:$as[$i]:$inouns:$iwords:$iphrases:$vectors[$i]\n";

   } #*-- end of outer for
  close(OUT);

 }

 #*-----------------------------------------------------
 #*- load the similarity values for each doc
 #*-----------------------------------------------------
 sub load_sim_vals
 {

  #*-- get the qids in an array
  my @qids = ();
  my $command = "select qui_qid from qu_perlfaq order by 1";
  (my $sth) = $dbh->execute_stmt($command); 
  while (my ($qid) = $dbh->fetch_row($sth) ) { push (@qids, $qid); }

  foreach my $qid (@qids)
   { 
    print "Processing $qid.....\n";
    $command = "select quc_vector from qu_perlfaq where qui_qid = $qid";
    ($sth) = $dbh->execute_stmt($command); 
    my ($vector_1) = $dbh->fetch_row($sth); $vector_1 =~ s/\cM$//;
    my %vec1 = ();
    map {m%(.*?)$EQUAL(.*)%, $vec1{$1} = $2 } split/$DELIM/, $vector_1;

    my @sim = ();
    foreach my $id (@qids)
     {
      if ($id == $qid) { $sim[$id] = 0; next; }
      $command = "select quc_vector from qu_perlfaq where qui_qid = $id";
      ($sth) = $dbh->execute_stmt($command); 
      my ($vector_2) = $dbh->fetch_row($sth); $vector_2 =~ s/\cM$//;

      my %vec2 = ();
      map {m%(.*?)$EQUAL(.*)%, $vec2{$1} = $2} split/$DELIM/, $vector_2;
      $sim[$id] = &sim_val(\%vec1, \%vec2);
     }

    #*-- find the top 10 similar questions
    my $count = 0; my $sim_ids = '';
    foreach my $i ( sort { $sim[$b] <=> $sim[$a] } @qids )  
     { last if (++$count > 10); 
       my $sim = sprintf("%4.2f", $sim[$i]); $sim_ids .= "$i$EQUAL$sim,"; }
    $sim_ids =~ s/,$//;
    
    $command = "update qu_perlfaq set quc_sim_ids = '$sim_ids' " . 
               " where qui_qid = $qid";
    (undef) = $dbh->execute_stmt($command); 
    print ("Finished processing $qid....\n");
    
   } #*-- end of outer for

 }

 #*---------------------------------------------------------------
 #*- Dump the table to a file
 #*---------------------------------------------------------------
 sub dump_file
 {

  open (OUT, ">qu_perlfaq.dat") || die ("Could not open qu_perlfaq.dat $!");
  binmode OUT, ":raw";
  my $command = "select * from qu_perlfaq order by qui_qid asc";
  my ($sth) = $dbh->execute_stmt($command); 
  while (my @data = $dbh->fetch_row($sth))
   { foreach (@data) { s/!/!!/g;  s/:/!:/g; }
     my $out = join (':', @data); $out =~ s/\cM$//;
     print OUT "$out\n";
   }
  close(OUT);

 }
