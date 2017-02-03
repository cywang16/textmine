
 #*--------------------------------------------------------------
 #*- WordUtil.pm						
 #*-    Description: A set of functions to perform common word based
 #*-    functions such as creating vectors, and splitting
 #*-    text into chunks 
 #*--------------------------------------------------------------

 package TextMine::WordUtil;

 use strict; use warnings;
 use Time::Local;
 use Config;
 use lib qw/../;
 use TextMine::Constants qw($LSI_DIR $OSNAME clean_filename);
 use TextMine::DbCall;
 use TextMine::MyProc;
 use TextMine::Index   qw(content_words);
 use TextMine::Tokens  qw(assemble_tokens build_stopwords load_token_tables);
 use TextMine::Utils   qw(factorial log2 sum_array);
 use TextMine::WordNet qw(similar_words);
 require Exporter;
 our @ISA = qw(Exporter);
 our @EXPORT_OK = qw();
 our @EXPORT = qw( text_tiling normalize gen_vector expand_vec sim_jaccard_val
    truncate clean_text text_split  gen_vectors sim_matrix sim_val dump_matrix);
 use vars qw ();

 #*-- set the constants     
 BEGIN 
  { }

 #*-----------------------------------------------------------------------
 #*-  A sim. matrix generator 
 #*-  Input: index type, normalization flag, reference to documents
 #*-  Output: A sim. matrix
 #*-----------------------------------------------------------------------
 sub sim_matrix
 {
  my ($itype,	#*-- the type of indexing (lsi, idf, or fre) 
      $norm, 	#*-- a normalization flag
      $ftype,	#*-- type of file
      $rdocs,	#*-- reference to a list of references to documents
      $dbh	#*-- a database handle
     ) = @_;
  my ($r_matrix, $r_terms, $i, $j);
  
  my $num_docs = @$rdocs; return(0) unless($num_docs); 

  #*-- generate the term-document matrix for the indexing type
  ($r_matrix, $r_terms) = &gen_vectors($itype, $norm, $ftype, $rdocs, $dbh);
  my %td_matrix = %$r_matrix; my @terms = @$r_terms; 
  
  #*-- build the vectors array and the sum of the squares of the term wts.
  my @vectors = my @vsqr = ();
  for $i (0..$num_docs-1)
   {
    for $j (0..$#terms)
     {
      $vectors[$i] .= ',' . $td_matrix{"$terms[$j]"}{"$i"};
      $vsqr[$i] += ($td_matrix{"$terms[$j]"}{"$i"} * 
                    $td_matrix{"$terms[$j]"}{"$i"});
     } 
    $vectors[$i] =~ s/^,//;
   }

  #*-- compute the similarity matrix using the vectors
  my @sim_matrix = ();
  for $i (0..$num_docs-1)
   {
    for $j (0..$num_docs-1)
     {
      $sim_matrix[$i][$j] = ($i == $j) ? 1.0:
                            ($i >  $j) ? $sim_matrix[$j][$i]:
         &compute_sim(\$vectors[$i], \$vectors[$j], $vsqr[$i], $vsqr[$j]);
     }
   }

  return (\@sim_matrix);

 }

 #*-----------------------------------------------------------------------
 #*-  Compute the similarity between 2 normalized and ordered vectors
 #*-----------------------------------------------------------------------
 sub compute_sim
 {
  my ($vec1, $vec2, $sqr1, $sqr2) = @_;

  my @vec1 = split/,/, $$vec1; my @vec2 = split/,/, $$vec2;
  my $sum = 0;
  for my $i (0..$#vec1) { $sum+= ($vec1[$i] * $vec2[$i]); }
  $sum = 0 unless ($sum > 0); return(0) unless ($sqr1 && $sqr2);
  return ($sum / sqrt($sqr1 * $sqr2) );
 }

 #*-----------------------------------------------------------------------
 #*-  Compute the cosine similarity between 2 vectors
 #*-----------------------------------------------------------------------
 sub sim_val
 {
  my ($r1, $r2) = @_;
  return (0) unless ( (keys %$r1) && (keys %$r2) );
  &normalize($r1); &normalize($r2); 
  my %v1 = %$r1; my %v2 = %$r2;
  my $s1 = my $s2 = my $s3 = 0;
  foreach (keys %v1) 
   { $s1 += ($v1{$_} * $v1{$_}); }
  foreach (keys %v2) 
   { $s2 += ($v2{$_} * $v2{$_}); 
     $s3 += ($v2{$_} * $v1{$_}) if ($v1{$_}); }
  return($s3 / sqrt($s1 * $s2) );
 }


 #*-----------------------------------------------------------------------
 #*-  Compute the jaccard similarity between 2 vectors
 #*-----------------------------------------------------------------------
 sub sim_jaccard_val
 {
  my ($r1, $r2) = @_;
  return (0) unless ( (keys %$r1) && (keys %$r2) );
  &normalize($r1); &normalize($r2); 
  my %v1 = %$r1; my %v2 = %$r2;
  my $s1 = my $s2 = 0;
  
  #*-- compute s1 AND s2
  foreach (keys %v1) { $s1++ if ($v2{$_}); } 

  #*-- compute s1 OR s2
  $s2 = (keys %v1) + (keys %v2) - $s1;

  #*-- return the ratio
  return($s1 / $s2);
 }

 #*------------------------------------------------------------------
 #*- expand a vector by finding similar words (brief) from the dictionary
 #*------------------------------------------------------------------
 sub expand_vec
 { my ($rvec, $dbh) = @_;

  my %new_vec = ();
  foreach my $word (keys %$rvec)
   {
    next unless ($word =~ /^[a-zA-Z]/);
    $new_vec{$word} = $$rvec{$word};
    foreach my $rword (&similar_words($word, $dbh) )
     { $rword = lc($rword);
       if ($new_vec{$rword}) { $new_vec{$rword} += $$rvec{$word}; }
       else                  { $new_vec{$rword}  = $$rvec{$word}; }
     }
   }
  $rvec = \%new_vec; &normalize($rvec);
  return($rvec);
 }

 #*------------------------------------------------------------
 #*- truncate a vector after sorting based on vector values
 #*------------------------------------------------------------
 sub truncate
 { my ($rvec, $len) = @_;

   my %new_vec = ();
   return(%new_vec) unless (keys %$rvec && $len);

   #*-- generate a new vector of length $len
   my $i = 0;
   foreach (sort { $$rvec{$b} <=> $$rvec{$a} } keys %$rvec)
    { $new_vec{$_} = $$rvec{$_}; last if (++$i == $len); } 
   return(%new_vec);
 }

 #*-------------------------------
 #*- normalize a vector
 #*-------------------------------
 sub normalize
 { my ($rvec, $round_off) = @_;

   #*-- find the sum of the weights
   return unless (keys %$rvec);
   my $total_wt = 0; $total_wt += $$rvec{$_} foreach (keys %$rvec);

   #*-- recompute new weights
   $total_wt = 1 unless ($total_wt);
   $$rvec{$_} /= $total_wt foreach (keys %$rvec);
 
   #*-- round off the weights, if necessary
   if ($round_off)
    { my $digits = $round_off + 2;
      $$rvec{$_} = sprintf('%' . $digits . '.' . $round_off . 'f', 
                   $$rvec{$_}) foreach (keys %$rvec); }
 }

 #*-----------------------------------------------------------------------
 #*-  Input: A string and type of indexing
 #*-  Output: A vector
 #*-----------------------------------------------------------------------
 sub gen_vector
 {
  my ($rtext, 	#*-- a reference to a text string
      $itype,	#*-- indexing scheme (fre, idf, or lsi)
      $ftype,	#*-- file type (web, email, news, or '')
      $dbh,	#*-- database handle
      $limit	#*-- max. length of the vector
     ) = @_;

  #*-- generate the vector
  my @docs; $docs[0] = $rtext; $limit = 100 unless ($limit);
  (my $rmatrix, my $rterms) = &gen_vectors($itype, 1, $ftype, \@docs, $dbh);
  my %matrix = %$rmatrix; my @terms = @$rterms;
  my %vector = (); my ($i); my $j = 0; 
  for $i (sort
           {$matrix{$terms[$b]}{0} <=> $matrix{$terms[$a]}{0}} (0..$#terms) )
   { last if (++$j == $limit); #*-- limit the vector length to 100 terms
     ($vector{$terms[$i]} = $matrix{$terms[$i]}{0}) =~ s/(\....).*/$1/; }
  return(%vector);

 }

 #*-----------------------------------------------------------------------
 #*-  A document vector generator 
 #*-  Input: An array of documents, type of indexing, and type of files
 #*-  Output: An array of indexed documents 
 #*-----------------------------------------------------------------------
 sub gen_vectors
 {
  my ($itype,	#*-- indexing type
      $norm, 	#*-- normalization flag
      $ftype,	#*-- file type (web, news, email, or ''
      $rdocs,	#*-- reference to a list of references to documents
      $dbh	#*-- database handle
     ) = @_;
  my ($i, $j);
  
  return() unless ($itype =~ /^fre|idf|lsi$/i);
  my @docs = @$rdocs;

  #*-- build the term document and document frequency matrix
  my %td_matrix =	#*-- term document matrix 
  my %d_freq    =	#*-- number of documents in which word appears 
  my @t_freq    =    	#*-- total number of terms in document
               (); 

  my $ref_val; my $n_values = 0;

  #*-- compute the FRE weight for the term document matrix  
  #*-- count the number of word occurrences in the documents
  for $i (0.. $#docs)
   {
    #*-- extract the content words from the text, exclude the stopwords
    $t_freq[$i] = 0;
    my @words = @{&content_words(\${$docs[$i]}, $ftype, $dbh)};
    s/\s+/_/g foreach (@words);
    my %local_f = (); $local_f{"\L$_"}++ foreach (@words);

    #*-- update the column for the document in the term-document matrix
    #*-- update the word-document hash and track the no. of words in 
    #*-- the document
    foreach my $word (sort keys %local_f)
     { $td_matrix{"$word"}{"$i"} = $local_f{"$word"}; 
       $t_freq[$i] += $td_matrix{"$word"}{"$i"};
       $d_freq{"$word"}++; $n_values++; } 
   }

  #*-- compute the IDF weight for the term document matrix  
  if ($itype eq 'idf')
   {
    my $log2_d = &log2(scalar @docs); @t_freq = ();
    for $i (0.. $#docs)
     { $t_freq[$i] = 0;
       foreach my $word (sort keys %d_freq)
        { if ($td_matrix{"$word"}{"$i"})
           { $td_matrix{"$word"}{"$i"} *= ( $log2_d - 
                                          &log2($d_freq{$word}) + 1 ); }
          else { $td_matrix{"$word"}{"$i"} = 0; }
          $t_freq[$i] += $td_matrix{"$word"}{"$i"};
        } 
     } #*-- end of outer for
   } #*-- end of if type eq idf

  #*-- complete the TD matrix
  for $i (0..$#docs)
   { foreach my $word (sort keys %d_freq)
      { if ($td_matrix{"$word"}{"$i"} && $t_freq[$i])
         { $td_matrix{"$word"}{"$i"} /= $t_freq[$i] if ($norm); }
        else { $td_matrix{"$word"}{"$i"}  = 0; }
      } #*-- end of inner for
   } #*-- end of outer for
  my @terms = sort keys %d_freq;
  return (\%td_matrix, \@terms) unless ( ($itype eq 'lsi') && (@docs > 1) );

  #*---------------------------------------------------------------
  #*-- use LSI to index the documents. First, convert the td matrix 
  #*-- to the compressed Harwell Boeing format.
  #*---------------------------------------------------------------
  my $ofile = $LSI_DIR . 'matrix';
  open (OUT, ">", &clean_filename("$ofile")) || 
      return "Unable to open $ofile $!";  

  #*-- print header lines 1 and 2
  my $title = 'Term Document Matrix for LSI'; my $key = 'TDMATKEY';
  printf OUT ("%-72s%-8s\n#\n", $title, $key);

  #*-- print header lines 3 and 4
  my $n_rows = scalar keys %d_freq; my $n_columns = scalar @docs;
  printf OUT ("rra%25d%14d%14d%14d\n", $n_rows, $n_columns, $n_values, 0);
  my $iformat = '(10i8)'; my $fformat = '(8f10.3)';
  printf OUT ("%16s%16s%20s%20s\n", $iformat, $iformat, $fformat, $fformat);

  #*-- build the 3 logical records
  my $ind = 0; my $pind = 0; 
  my @pointr = my @rowind = my @value = ();
  my $pval = 1; $pointr[$pind++] = $pval; 
  for $i (0..$#docs)
   {
    for $j (0..$#terms)
     { if ($td_matrix{$terms[$j]}{$i})
        { $value[$ind] = $td_matrix{$terms[$j]}{$i};
          $rowind[$ind++] = ($j + 1); $pval++; }
     } #*-- end of inner for
    $pointr[$pind++] = $pval;
   } #*-- end of outer for

  #*-- print the pointr data
  for $i (0..$#pointr)
   { printf OUT ("%8d", $pointr[$i]); 
     printf OUT ("\n") unless ( ($i + 1) % 10); }
  print OUT ("\n") if ((scalar @pointr) % 10);

  for $i (0..$#rowind)
   { printf OUT ("%8d", $rowind[$i]); 
     printf OUT ("\n") unless ( ($i + 1) % 10); }
  print OUT ("\n") if ((scalar @rowind) % 10);

  for $i (0..$#value)
   { printf OUT ("%10.3f", $value[$i]); 
     printf OUT ("\n") unless ( ($i + 1) % 8);}
  print OUT ("\n") if ((scalar @value) % 8);
  close(OUT);

  #*-- dump the parameters for the SVD
  $ofile = $LSI_DIR . 'lap2';
  my $s_triplets = (@docs > 9) ? int(@docs/2): @docs; 
  open (OUT, ">", "$ofile") || return "Unable to open $ofile $!";  
  printf OUT "'$key' $s_triplets $s_triplets -1.0e-30 1.0e-30 TRUE 1.0e-6 0";
  close(OUT);

  #*-- check the parameters before running SVD
  return (\%td_matrix, \@terms) if ( ($n_columns >= 3000) || 
                                     ($n_values  >= 100000) );

  #*-- run the svd in a separate process
  my $stat_msg = '';
  if ($OSNAME eq 'win')
   { my @cmdline = ("$LSI_DIR");
     $stat_msg .= &create_process(\@cmdline, 0, 'las2.exe', 
                           "$LSI_DIR".  'las2.exe' ) ; }
  else
   { my @cmdline = ("$LSI_DIR" , 'las2', "$LSI_DIR"); 
     $stat_msg .= &create_process(\@cmdline, 0, 'las2', 
                                        "$LSI_DIR") ; }
  return (\%td_matrix, \@terms) if ($stat_msg);
  sleep(1); #*-- wait a second till all files have been written

  #*-- read the output file
  local $/ = "\n";
  open (IN, "<", "$LSI_DIR" . 'lao2') || return (\%td_matrix, \@terms);
  my @lines = <IN>;
  close(IN);

  #*-- get the number of terms, docs, and sigma values
  my ($num_t, $num_d, $num_s);
  $num_t = $num_d = $num_s = 0;
  foreach my $line (@lines)
   { 
    ($num_t)  = $line =~ /=\s+(\d+)/ if ($line =~ / OF TERMS/);
    ($num_d)  = $line =~ /=\s+(\d+)/ if ($line =~ / OF DOCUMENTS/);
    ($num_s)  = $line =~ /=\s+(\d+)/ if ($line =~ /NSIG/);
   }

  #*-- initialize the u, v, and sigma matrices
  my @u = my @v = my @s = ();
  for $i (0..($num_t-1)) { for $j (0..($num_s-1)) { $u[$i][$j] = 0; }}
  for $i (0..($num_s-1)) { for $j (0..($num_s-1)) { $s[$i][$j] = 0; }}
  for $i (0..($num_s-1)) { for $j (0..($num_d-1)) { $v[$i][$j] = 0; }}

  #*-- build the matrices from the output file 
  $i = 0; my $val; 
  do 
   {
    #*-- read in the v vectors
    if ($lines[$i] =~ /Start of V:/)
     { $i++;
       for my $k (reverse 0..($num_s - 1)) 
        { $j = 0;
          $v[$k][$j++] = $1 while ($lines[$i] =~ /([\d\.-]+)/g);
          $i++;
        } #*-- end of for
     } #*-- end of if start of V

    #*-- read in the u vectors
    if ($lines[$i] =~ /Start of U:/) 
     { $i++;
       for my $k (reverse 0..($num_s - 1)) 
        { $j = 0;
          $u[$j++][$k] = $1 while ($lines[$i] =~ /([\d\.-]+)/g);
          $i++;
        } #*-- end of for
     } #*-- end of if start of u

    #*-- read in the sigma values
    if ($lines[$i] =~ /Start of Sigma:/)
     { $i++; $j = $num_s - 1; 
       $s[$j][$j--] = $1 while ($lines[$i] =~ /([\d\.-]+)/g);
     }

    #*-- set the number of triplets
    if ($lines[$i] =~ /NSIG =\s+(\d+)/)
     { $s_triplets = $1;} 
    $i++;
   } until ($i > $#lines);

  #*-- truncate the u, v, and sigma matrices
  my $sdim = int(sqrt(@docs)); $s_triplets = $sdim if ($sdim < $s_triplets);
  for $i (0..($num_t - 1)) { $#{$u[$i]} = ($s_triplets - 1); } 
  for $i (0..($num_s - 1)) { $#{$s[$i]} = ($s_triplets - 1); } 
  $#s = ($s_triplets - 1); $#v = ($s_triplets - 1); 

  #*-- multiply the u, sigma, and v matrices
  #*-- copy to the td_matrix and return
  my @new_a = @{my $temp = &mult_matrix( &mult_matrix(\@u, \@s), \@v)};
  for $i (0..$#terms)
   { for $j (0..$#docs)
     { $td_matrix{$terms[$i]}{$j} = $new_a[$i][$j]; }
   }

  #*-- compute the frequency of terms in a document
  @t_freq = ();
  for $i (0.. $#docs)
   { $t_freq[$i] = 0;
     foreach my $word (sort keys %d_freq)
      { $t_freq[$i] += $td_matrix{"$word"}{"$i"}; } 
   }

  #*-- complete the TD matrix
  for $i (0..$#docs)
   { foreach my $word (sort keys %d_freq)
      { if ($td_matrix{"$word"}{"$i"} && $t_freq[$i])
         { $td_matrix{"$word"}{"$i"} /= $t_freq[$i] if ($norm); }
        else { $td_matrix{"$word"}{"$i"}  = 0; }
      } #*-- end of inner for
   } #*-- end of outer for

  return (\%td_matrix, \@terms);
  
 }

 #*-----------------------------------------------------------------
 #*- multiply 2 matrices a and b and return a matrix c.
 #*- check dimensions before multiplication.
 #*-----------------------------------------------------------------
 sub mult_matrix
  {
   my ($a, $b) = @_;

   #*-- get the rows and columns for both matrices
   my @a = @$a; my @b = @$b;
   my $ar = @a; my $ac = @{$a[0]}; 
   my $br = @b; my $bc = @{$b[0]};

   #*-- check for errors
   if ($ac != $br)
    { print ("Incompatible matrix multiplication ");
      print ("($ar X $ac) and ($br X $bc) \n"); return(1); }

   #*-- multiply the matrices a and b and store
   #*-- the result in matrix c
   my (@c);
   for my $i (0..($ar-1))
    {
     for my $j (0..($bc-1))
      {
       $c[$i][$j] = 0;
       for my $k (0..($br-1))
        { $c[$i][$j] += ($a[$i][$k] * $b[$k][$j]); }
      } #*-- end of for $j
    } #*-- end of for $i

   return (\@c);
  }

 #*-----------------------------------------------------------------
 #*- Print the rows and columns of the matrix 
 #*-----------------------------------------------------------------
 sub dump_matrix
 {
  my ($a, $title) = @_;
  my @a = @$a; 
  my $ar = @a; my $ac = @{$a[0]};
 
  print ("Matrix: $title ($ar X $ac)\n");
  for my $i (0..($ar-1))
   { print ("$i:\t");
     for my $j (0..($ac-1))
      { printf ("%5.2f ", $a[$i][$j]); }
     print ("\n");
   }
 }

 #*------------------------------------------------------------
 #*- split the text into chunks   
 #*-   Input: Text, type of text
 #*-   Output: End index of text sequences
 #*------------------------------------------------------------
 sub text_split
 {
  my ($rtext,	  #*-- reference to a text string
      $ftype,	  #*-- type of text string (email, web, news)
      $dbh, 	  #*-- database handle
      $hash_refs, #*-- optional reference to token tables
      $min_len,	  #*-- optional minimum length of sentences
      $overlap,	  #*-- optional overlap flag
      $min_alen	  #*-- optional minimum average length 
                  #*-- set for text with long sentences
     ) = @_;

  #*-- set the default values, text is stripped of newline chars
  my $text = $$rtext; &clean_text($text);
  $ftype   = '' unless ($ftype);

  #*-- restrict the min_len to range 50-100
  $min_len  = 50  unless ($min_len); $min_len = 100 if ($min_len > 100);
  $min_alen = 800 unless ($min_alen);
  my @split_loc = my @tchunks = (); #*-- end locations of text and
                                    #*-- associated text chunk
  #*-- return if text string is too short
  unless(length($text) > 50) 
   { $split_loc[0] = length($text) - 1; return(\@split_loc); }

  #*-- define the characters that separate and start sentences
  my $SEP_CHARS = '.?!;:';
  my $STR_CHARS = 'A-Z0-9"\'';

  #*-- use the tokenizer get a list of words
  my ($rwords, $rloc, $rtype) = &assemble_tokens(\$text, $dbh, $hash_refs);
  my @words = @$rwords; my @loc = @$rloc; my @w_type = @$rtype;

  #*-- scan the list of words 
  @tchunks = (); my ($start, $end);
  my $d_quotes = my $s_quotes = 0; #*-- track the number of quotes
  my $i = -1; 
  WORD: while (++$i <= $#words)
   { 
    #*-- count the number of quotes
    $d_quotes++ if ($words[$i] eq '"'); 
    $s_quotes++ if ($words[$i] eq "'");

    #*-- if a potential separator character
    if ( ($words[$i] =~ /^[$SEP_CHARS]$/) || ($words[$i] =~ /\.$/) ) 
     { 				        

      #*-- CASE 1: Keep abbreviations
      next WORD if ( ($w_type[$i] eq 'a') && $words[$i+1] );

      #*-- CASE 2: Handle initials that may be part of a name           
      next WORD if ( ($words[$i] eq '.') && (length($words[$i-1]) == 1) &&
                     ($words[$i-1] =~ /^\w/) ); 

      #*-- check if we are in the middle of a quote
      #next WORD if ($d_quotes    && ($d_quotes % 2) && 
      #              $words[$i+1] && ($words[$i+1] ne '"') );
      #next WORD if ($s_quotes && ($s_quotes % 2) && 
      #              $words[$i+1] && ($words[$i+1] ne "'") );

      #*-- CASE 3: A new sentence must start with sentence start chars
      next WORD if ($words[$i+1] && ($words[$i+1] =~ /^[^$STR_CHARS]/) );

      #*-- CASE 4: Handle cases where sentence does not end with period
      if ($words[$i+1] && $words[$i+1] =~ /^['"]$/)
       { 
        if ($words[$i+2] && $words[$i+2] =~ /^[$STR_CHARS]/)
         { 
           #*-- if this is the end of a quote, keep the quote in the sentence
           if    ($d_quotes && ( ($d_quotes+1) % 2) == 0) { $i++; } 
           elsif ($s_quotes && ( ($s_quotes+1) % 2) == 0) { $i++; } 
         }
        else { next WORD; }
       }

     #*-- assign the start and end of the chunk
     $start = $end ? $end + 1: 0; $end = $loc[$i];
     push (@tchunks, substr($text, $start, $end - $start + 1)); 
     push (@split_loc, $end); 
     $d_quotes = $s_quotes = 0;

     } #*-- end of if 

   } #*-- end of while

  #*-- add the last sentence, if any
  $start = $end ? $end + 1: 0; $end = $loc[$#words];
  if ($start < $end)
   { push (@tchunks, substr($text, $start, $end - $start + 1)); 
     push (@split_loc, $end); } 

  #*-- find the average length of sentences
  my $length = 0; $length += length($_) foreach (@tchunks);
  my $avg = (@tchunks) ? ($length / @tchunks) : 0;
  
  #*-- if the average is less than minimum average length, we have some
  #*-- decent sentences, otherwise, try text tiling
  if ($avg > $min_alen)
   { @split_loc =  &text_tiling(\$text, $dbh, $hash_refs); }
  #*-- if average is less than minimum length, then try
  #*-- combining sentences
  elsif ($avg < $min_len)
    { 
     my @n_loc = @tchunks = (); my $i = 0; my ($start, $end);
     while ($i < $#split_loc)
      { 
        $start = ($i) ? $split_loc[$i-1] + 1: 0;
        $end   = $split_loc[$i+1]; 
        push (@n_loc, ($overlap) ? "$start,$end": $end); 
        push (@tchunks, substr($text, $start, $end - $start + 1)); 
        $i+= ($overlap) ? 1: 2; }

     #*-- add the last sentence, if any
     $start = $end ? $end + 1: 0; $end = $loc[$#words];
     if ($start < $end)
       { push (@n_loc, $end);   
         push (@tchunks, substr($text, $start, $end - $start + 1)); } 
     @split_loc = @n_loc;
    } #*-- end of if

  #*-- compute the ranks for the chunks of text
  my @rank = (0) x @split_loc; 

  #*-- by default, assign high ranks to the first 2 chunks
  @rank[0..1] = (20, 10) if ($ftype =~ /^(?:news|email)/);

  #*-- handle the news type separately
  if ($ftype eq 'news')
   {
    local $" = '|';
    my @SUMMARY = ('conclusion', 'finally', 'lastly', 'summarize', 
                   'summary', 'sum up');
    my @ANAPHORIC   = qw/our this that those these us/; 
    my $closing_r   = qr/\b(?:@SUMMARY)\b/i;
    my $anaphoric_r = qr/\b(?:@ANAPHORIC)\b/i;
    for my $i (0..$#tchunks)
     {
      #*-- check for any summary word
      $rank[$i] += 5 / (length($1) + 1) 
                     if ($tchunks[$i] =~ /^(.*?)$closing_r/i);
     
      #*-- anaphoric references
      $rank[$i] -= 5 if ($tchunks[$i] =~ /^$anaphoric_r/i);

      #*-- longer sentences get a higher rank
      $rank[$i] += int(length($tchunks[$i]) / 100);

     } #*-- end of for
   } #*-- end of if ftype

  return(\@split_loc, \@rank);
 }

 #*------------------------------------------------------------
 #*- Use TextTiling to split up the web page
 #*------------------------------------------------------------
 sub text_tiling
 {
  my ($rtext, $dbh, $hash_refs) = @_;
  
  #*-- first split the text into tokens
  my @chunks = my @c_loc = (); my $tchunk = ''; my $i = 1;
  my ($rtokens, $rloc) = &assemble_tokens($rtext, $dbh, $hash_refs);
  my @tokens = @$rtokens; my @loc = @$rloc;

  #*-- next build chunks of upto 20 tokens
  foreach (@tokens)
   { if ($i % 20) { $tchunk .= " $_"; }
     else         { push (@chunks, $tchunk); $tchunk = "$_ "; 
                    push (@c_loc, $loc[$i]); }
     $i++; }

  #*-- make a separate entry for the last chunk, if it is large enough,
  #*-- otherwise, append to the last entry
  if ($tchunk)
   { 
     if (length($tchunk) > 50) 
      { push (@chunks, $tchunk); push (@c_loc, $loc[$#loc]); }
     else
      { if (@chunks) { $chunks[$#chunks] .= " $tchunk"; 
                       $c_loc[$#c_loc] = $loc[$#loc]; } 
        else { push (@chunks, $tchunk);  push (@c_loc, $loc[$#loc]); }
      }
   }

  #*-- compute the jaccard similarity between adjacent chunks
  my @t_score = (); return(@c_loc) if (@chunks <= 1);
  for my $i (0..($#chunks-1))
   { my %vec1 = &gen_vector(\$chunks[$i],   'fre', 'web', $dbh);
     my %vec2 = &gen_vector(\$chunks[$i+1], 'fre', 'web', $dbh);
     $t_score[$i] = &sim_jaccard_val(\%vec1, \%vec2);
   }

  #*-- use the scores of both neighbors
  my @score = ();
  for my $i (1..($#chunks-1))
   { $score[$i] = $t_score[$i-1] + $t_score[$i+1]; }
  $score[$#chunks] = $score[$#chunks - 1]; #*-- last score and next to
  $score[0] = $score[1];                   #*-- last score are the same

#*--------------- TEMP
#@t_score = (); return(@c_loc) if (@chunks <= 1);
#for my $i (0..($#chunks-1))
# { my %vec1 = &gen_vector(\$chunks[$i],   'fre', 'web', $dbh);
#   my %vec2 = &gen_vector(\$chunks[$i+1], 'fre', 'web', $dbh);
#   $t_score[$i] = &sim_val(\%vec1, \%vec2);
# }
#
##*-- use the scores of both neighbors
#my @jscore = ();
#for my $i (1..($#chunks-1))
# { $jscore[$i] = $t_score[$i-1] + $t_score[$i+1]; }
#$jscore[$#chunks] = $jscore[$#chunks - 1]; #*-- last score and next to
#$jscore[0] = $jscore[1];                   #*-- last score are the same
#for my $i (0..$#jscore) { print "$i $score[$i] $jscore[$i]\n"; }
#
#*-  TEMP

  #*-- smooth the scores using the two neighbours on left and right
  for my $i (1..($#chunks-1))
   { $score[$i] = ($score[$i-1] + $score[$i] + $score[$i+1]) / 3; }
  #*-- for the first and last chunks use just 1 neighbour
  $score[0] = ($score[1] + $score[2]) / 2 if ($score[1] && $score[2]);
  $score[$#score] = ($score[$#chunks - 1] + $score[$#chunks]) / 2;

  #*-- assign depth scores for each chunk
  #*-- depth_i = the sum of left chunk difference and the right chunk diff.
  my @depth = ();
  for my $i (1..($#score-1))
   { $depth[$i] = ($score[$i-1] - $score[$i]) + ($score[$i+1] - $score[$i]);}
  $depth[0] = $depth[$#score] = 0;

  #*-- compute the average of the depth scores
  my $average = &sum_array(\@depth) / @depth; 

  #*-- compute standard deviation of depth scores
  my $sd = 0; 
  foreach (@depth) { $sd += ( ($_ - $average) * ($_ - $average) ); }
  $sd = sqrt($sd); $sd /= @depth;

  #*-- build the chunks of text to return based on depth scores
  #*-- create a new chunk of text when the depth score exceeds
  #*-- the threshold
  my @r_loc = (); 
  my $threshold = $average - $sd;
  for my $i (0..$#depth)
   { if ( ($i == $#depth) || ($depth[$i] > $threshold) )
        { push (@r_loc, $c_loc[$i]); } }
  return(@r_loc);

 }

 #*---------------------------------------------
 #*-- subroutine to clean up a string
 #*---------------------------------------------
 sub clean_text
  { 
   # $_[0] =~ s/^\s+//; $_[0] =~ s/\s+$//; 
    $_[0] =~ s/[\n\r]/ /g; # $_[0] =~ s/\s+/ /g; 
  }

1; #return true 
=head1 NAME

WordUtil - TextMine Word Utilities

=head1 SYNOPSIS

use TextMine::WordUtil;

=head1 DESCRIPTION

   A bunch of utilities to create vectors from text and 
   compute the similarity matrix for a set of documents.
   Split text into sentences of chunks of text

=head2 gen_vectors

  Accept the indexing type (fre, lsi, or idf), a normalization
  flag, a reference to a list of references to text strings,
  and a database handle and return a matrix of terms and documents
  and a list of terms.

=head3 Example:

   #*-- Create a list of documents
   push (@docs, \'Human machine interface for ABC computer applications');
   push (@docs, \'A survey of user opinion of computer system response time');
   push (@docs, \'The EPS user interface management system');
   push (@docs, \'System and human system engineering testing of EPS');
   push (@docs, \'Relation of user perceived response time to error measurement'
);
   push (@docs, \'The generation of random, binary, ordered trees');
   push (@docs, \'The intersection graph of paths in trees');
   push (@docs, \'Graph minors IV: Widths of trees and well-quasi-ordering');
   push (@docs, \'Graph minors: A survey');

   #*-- generate the term document matrix
   my ($r1, $r2) = &gen_vectors('fre', 1, $ftype, \@docs, $dbh);
   %td_matrix1 = %$r1; @terms = @$r2;

   printf ("FRE TEST\n%-20s", 'Terms/Docs');
   for (1..@docs) { printf ("%6d", $_); } print ("\n");

   foreach my $i (0..$#terms)
    { printf ("%-20s", $terms[$i]);
     foreach my $j (0..$#docs)
      { printf ("%6.3f", $td_matrix1{$terms[$i]}{$j}); }
     print ("\n");
    }
 
 generates
 -----------------------------------------------------------------
 FRE TEST
 Terms/Docs               1     2     3     4     5     6     7     8     9
 abc                  0.167 0.000 0.000 0.000 0.000 0.000 0.000 0.000 0.000
 applications         0.167 0.000 0.000 0.000 0.000 0.000 0.000 0.000 0.000
 binary               0.000 0.000 0.000 0.000 0.000 0.200 0.000 0.000 0.000
 computer             0.167 0.000 0.000 0.000 0.000 0.000 0.000 0.000 0.000
 computer_system      0.000 0.200 0.000 0.000 0.000 0.000 0.000 0.000 0.000
 engineering          0.000 0.000 0.000 0.167 0.000 0.000 0.000 0.000 0.000
 eps                  0.000 0.000 0.250 0.167 0.000 0.000 0.000 0.000 0.000
 error                0.000 0.000 0.000 0.000 0.167 0.000 0.000 0.000 0.000
 generation           0.000 0.000 0.000 0.000 0.000 0.200 0.000 0.000 0.000
 graph                0.000 0.000 0.000 0.000 0.000 0.000 0.250 0.200 0.333
 human                0.167 0.000 0.000 0.167 0.000 0.000 0.000 0.000 0.000
 interface            0.167 0.000 0.000 0.000 0.000 0.000 0.000 0.000 0.000
 intersection         0.000 0.000 0.000 0.000 0.000 0.000 0.250 0.000 0.000
 machine              0.167 0.000 0.000 0.000 0.000 0.000 0.000 0.000 0.000
 management           0.000 0.000 0.250 0.000 0.000 0.000 0.000 0.000 0.000
 measurement          0.000 0.000 0.000 0.000 0.167 0.000 0.000 0.000 0.000
 minors               0.000 0.000 0.000 0.000 0.000 0.000 0.000 0.200 0.333
 opinion              0.000 0.200 0.000 0.000 0.000 0.000 0.000 0.000 0.000
 ordered              0.000 0.000 0.000 0.000 0.000 0.200 0.000 0.000 0.000
 paths                0.000 0.000 0.000 0.000 0.000 0.000 0.250 0.000 0.000
 perceived            0.000 0.000 0.000 0.000 0.167 0.000 0.000 0.000 0.000
 random               0.000 0.000 0.000 0.000 0.000 0.200 0.000 0.000 0.000
 relation             0.000 0.000 0.000 0.000 0.167 0.000 0.000 0.000 0.000
 response_time        0.000 0.200 0.000 0.000 0.167 0.000 0.000 0.000 0.000
 survey               0.000 0.200 0.000 0.000 0.000 0.000 0.000 0.000 0.333
 system               0.000 0.000 0.250 0.333 0.000 0.000 0.000 0.000 0.000
 testing              0.000 0.000 0.000 0.167 0.000 0.000 0.000 0.000 0.000
 trees                0.000 0.000 0.000 0.000 0.000 0.200 0.250 0.200 0.000
 user                 0.000 0.200 0.000 0.000 0.167 0.000 0.000 0.000 0.000
 user_interface       0.000 0.000 0.250 0.000 0.000 0.000 0.000 0.000 0.000
 well-quasi-ordering  0.000 0.000 0.000 0.000 0.000 0.000 0.000 0.200 0.000
 widths               0.000 0.000 0.000 0.000 0.000 0.000 0.000 0.200 0.000
 -----------------------------------------------------------------

 The vectors are built from the term document matrix

=head2 sim_matrix

 Compute the similarity between all pairs of documents. 
 The similarity between any 2 documents is a value between
 0 and 1. A value of 0 indicates no similarity at all and
 a value of 1 indicates identitcal documents. This similarity
 measure is called the cosine similarity measure.

 Pass the type of indexing, a normalization flag, the type
 of documents, and the database handle

=head3 Example

  #*-- call the similarity matrix function
  my ($r1) = &sim_matrix('fre', 1, $ftype, \@docs, $dbh);

  #*-- dump the matrix
  my @matrix = @$r1;
  print ("\n        ");
  for my $i (0..$#docs) { my $str = "Doc $i"; printf ("%-7s", $str); }
  print ("\n");
  for my $i (0..$#docs)
   { print ("Doc $i ");
    for my $j (0..$#docs)
     { printf ("%7.4f", $matrix[$i][$j]); }
    print ("\n");
   }

 generates
 --------------------------------------------------------------------
         Doc 0  Doc 1  Doc 2  Doc 3  Doc 4  Doc 5  Doc 6  Doc 7  Doc 8
 Doc 0  1.0000 0.0000 0.0000 0.1443 0.0000 0.0000 0.0000 0.0000 0.0000
 Doc 1  0.0000 1.0000 0.0000 0.0000 0.3651 0.0000 0.0000 0.0000 0.2582
 Doc 2  0.0000 0.0000 1.0000 0.5303 0.0000 0.0000 0.0000 0.0000 0.0000
 Doc 3  0.1443 0.0000 0.5303 1.0000 0.0000 0.0000 0.0000 0.0000 0.0000
 Doc 4  0.0000 0.3651 0.0000 0.0000 1.0000 0.0000 0.0000 0.0000 0.0000
 Doc 5  0.0000 0.0000 0.0000 0.0000 0.0000 1.0000 0.2236 0.2000 0.0000
 Doc 6  0.0000 0.0000 0.0000 0.0000 0.0000 0.2236 1.0000 0.4472 0.2887
 Doc 7  0.0000 0.0000 0.0000 0.0000 0.0000 0.2000 0.4472 1.0000 0.5164
 Doc 8  0.0000 0.2582 0.0000 0.0000 0.0000 0.0000 0.2887 0.5164 1.0000
 --------------------------------------------------------------------

=head2 text_split

 Accept a reference to a text string, the type of file (email, news,
 web, or ''), the database handle, an optional reference to the
 token tables, an optional minimum length of text chunks, and
 an optional overlap flag.

 The text_split function returns a set of sentences extracted from
 the text.

=head3 Example

 my $text = <<"EOT";
OTTAWA, March 3 - Canada's real gross domestic product,
seasonally adjusted, rose 1.1 pct in the fourth quarter of
1986, the same as the growth as in the previous quarter,
Statistics Canada said.
    That left growth for the full year at 3.1 pct, which is
down from 1985's four pct increase. The rise was also slightly
below the 3.3 pct growth rate Finance Minister Michael Wilson
predicted for 1986 in February's budget. He also forecast GDP
would rise 2.8 pct in 1987.
    Statistics Canada said final domestic demand rose 0.6 pct
in the final three months of the year after a 1.0 pct gain in
the third quarter.
    Business investment in plant and equipment rose 0.8 pct in
the fourth quarter, partly reversing the cumulative drop of 5.8
pct in the two previous quarters.
EOT

  my ($r1) = &text_split(\$text, 'news', $dbh);
  my @tchunks = @$r1;          #*-- end locations of text chunks
  for my $i (0..$#tchunks)
  { my $start = $i ? ($tchunks[$i-1] + 1): 0; my $end = $tchunks[$i];
    my $sentence = substr($text, $start, $end - $start + 1);
    $sentence =~ s/^\s+//; $sentence =~ s/\s+$//;
    print $i+1, ": $sentence\n\n";
  }

 generates
 --------------------------------------------------------------------

 1: OTTAWA, March 3 - Canada's real gross domestic product,
 seasonally adjusted, rose 1.1 pct in the fourth quarter of
 1986, the same as the growth as in the previous quarter,
 Statistics Canada said.
 
 2: That left growth for the full year at 3.1 pct, which is
 down from 1985's four pct increase.
 
 3: The rise was also slightly
 below the 3.3 pct growth rate Finance Minister Michael Wilson
 predicted for 1986 in February's budget.
 
 4: He also forecast GDP
 would rise 2.8 pct in 1987.
 
 5: Statistics Canada said final domestic demand rose 0.6 pct
 in the final three months of the year after a 1.0 pct gain in
 the third quarter.
 
 6: Business investment in plant and equipment rose 0.8 pct in
 the fourth quarter, partly reversing the cumulative drop of 5.8
 pct in the two previous quarters.

 --------------------------------------------------------------------
 
=head1 AUTHOR

Manu Konchady <mkonchady@yahoo.com>
