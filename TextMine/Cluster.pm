 #*--------------------------------------------------------------
 #*- Cluster.pm						
 #*-  
 #*-  Cluster documents based on content. Accept a list of 
 #*-  text documents and return a list of clusters. Each
 #*-  cluster consists of a list of member documents.
 #*-  The miscellaneous cluster contains all documents that
 #*-  could not be placed in a cluster.
 #*--------------------------------------------------------------

 package TextMine::Cluster;

 use strict; use warnings;
 use Config;
 use lib qw/../;
 use TextMine::Utils qw/sum_array min_max/;
 use TextMine::Constants;
 use TextMine::WordUtil qw/sim_matrix/;
 require Exporter;
 our @ISA = qw(Exporter);
 our @EXPORT = qw(cluster);
 our @EXPORT_OK = qw();  
 our ($THRESHOLD, $NUM_SOLUTIONS, $NUM_ITERATIONS, $NUM_MUTATIONS);

 #*-- set the constants for the genetic algorithm
 BEGIN
  { $NUM_SOLUTIONS = 100; $NUM_ITERATIONS = 100; $NUM_MUTATIONS = 10; }

 #*------------------------------------------------------------
 #*- cluster the documents using a genetic algorithm 
 #*------------------------------------------------------------
 sub cluster
 {
  my ($rdocs,	  #*-- reference to an array of references to strings 
      $itype,	  #*-- indexing method (fre, lsi, or idf)
      $dbh,	  #*-- database handle
      $ftype,	  #*-- optional type of text web, news, email, or ''
      $link_type, #*-- optional full_link, half_link, or one_link
      $thresh,	  #*-- optional threshold for cluster membership
      $debug	  #*-- optional debug flag
     ) = @_;

  #*-- set the default values
  my @docs = @$rdocs; my $total_time = time();
  $ftype = ''             unless($ftype);
  $debug = ''             unless($debug);
  $itype = 'idf'          unless ($itype); 
  $link_type = 'one_link' unless ($link_type);
  $THRESHOLD = ($thresh) ? $thresh: 0.2;

  #*-- calculate the similarity matrix
  my ($ref_val); my $matrix_time = time();
  my @matrix = @{$ref_val = &sim_matrix($itype, 1, $ftype, $rdocs, $dbh)};
  $matrix_time = time() - $matrix_time;

  #*-- zero the diagonal
  for my $i (0..$#matrix) { $matrix[$i][$i] = 0.0; }

  #*-- check if there are sufficient no. of elements over threshold
  my $over = 0;
  for my $i (0..($#matrix-1))
   { for my $j (($i+1)..$#matrix)
      { $over++ if ($matrix[$i][$j] > $THRESHOLD); } } 
  my $num_elements = @matrix * (@matrix - 1);

  #*-- use the passed threshold or
  #*-- reduce the threshold if few elements > threshold
  #*-- otherwise assign a default of 0.2
  $THRESHOLD = ($thresh) ? $thresh:
               ( ( ($over * 2) / $num_elements) < 0.05) ? 0.15: 0.2;
  print ("Threshold: $THRESHOLD\n") if ($debug);

  #*-- build the range hash for the similarity matrix
  #*-- show a histogram of the values 
  my %range = (); $range{'0.9 - 1.0'} = 0;
  for my $i (0..8) 
    { $range{'0.' . $i . ' - ' . '0.' . ($i + 1)} = 0; }

  #*-- compute the sum of similarities for each document and
  #*-- check for any misc. documents
  my @sim_total= my @misc = my @cdocs = (); my $below_threshold = 0; 
  for my $i (0..$#docs) 
   { my $not_mdoc = $sim_total[$i] = 0;
     for my $j (0..$#docs) 
       {  
         $sim_total[$i] += $matrix[$i][$j]; 
         my $value = sprintf("%3.1f", $matrix[$i][$j]);
         $value = "0.0" unless ($value);
         my $range_key = (0.9 <= $value) ?  '0.9 - 1.0': 
                         "$value" . ' - ' . ($value + 0.1);        
         $range{"$range_key"}++;        
         if ($matrix[$i][$j] >= $THRESHOLD) { $not_mdoc++; }
         else                               { $below_threshold++; } 
       } #*-- end of inner for 

     #*-- cluster documents which have sufficient text
     if  ($not_mdoc && (length(${$docs[$i]}) > 50) ) { push (@cdocs, $i); }
     #*-- put others in the miscellaneous cluster
     else         { push (@misc, $i); } 
   } #*-- end of outer for

  $below_threshold = ($below_threshold / (@docs * @docs) ) * 100.0;

  #*-- dump the similarity matrix
  if ($debug)
   { printf ("Percentage of docs below threshold: %8.3f\n", $below_threshold);
     &dump_array(\@matrix, 2, "Similarity Matrix:"); 
     my @range_arr = map {"$_ ". "$range{$_}"} sort keys %range;
     &dump_array(\@range_arr, 1, "Matrix value ranges:", "string"); } 

  #*-- if we don't have sufficient documents to perform clustering, return
  local $" = ","; my @clusters = ();
  if (@cdocs < 5) 
   { @misc = (0..$#docs); push(@clusters, "@misc");
     return (\@clusters, \@matrix) if wantarray; return(\@clusters); }

  #*-- create random solutions. Each element of the sols array
  #*-- is a string of indexes to the cdocs array
  my $ga_time = time();
  my @sols = (); my $num_docs = @cdocs;
  for my $i (0..$NUM_SOLUTIONS) 
   { my @sol = map { $cdocs[$_] } @{$ref_val = &scramble($num_docs)};
     $sols[$i] = "@sol";  }

  my @s_fitness = (); my $times = my $prev_max = my $best_val = 0;
  my $best_sol = '';
  #*-- run some iterations
  for my $i (0..$NUM_ITERATIONS)
   { 
     #*-- create the fitness scores
     for my $j (0..$NUM_SOLUTIONS) 
      { $s_fitness[$j] = &sol_fitness("$sols[$j]", \@matrix); }

     #*-- generate the distribution of fitness
     my $total = &sum_array(\@s_fitness); my @distr = ();
     (undef, my $max, undef, my $max_ind) = &min_max(\@s_fitness);
     if ($debug) 
      { printf ("Sum, Max. of scores %3d: %8.3f %8.3f \n", $i,$total,$max); }

     #*-- is there convergence ?
     last if ( ($times > 5) && ($max <= $prev_max) );
     $times = ( abs($max - $prev_max) > 0.01) ? 0: ($times + 1);
     $prev_max = $max;

     #*-- save the best solution
     if ($best_val < $max)
      { $best_sol = $sols[$max_ind]; $best_val = $max; }

     for my $j (0..$#s_fitness) 
      { $distr[$j] = ($s_fitness[$j] / $total); }

     #*-- create a distribution proportionate to the values
     #*-- the range is from 0.01 to 0.99, 
     #*-- higher values for solutions of higher fitness
     (my $min_v, my $max_v) = &min_max(\@distr);
     my $range = $max_v - $min_v + 0.0000001;
     foreach (@distr) { $_ = 0.01 + ($_ - $min_v) * 0.98 / $range ; }

     #*-- create the next generation
     my @new_sols = ();
     for my $j (0..$NUM_SOLUTIONS)
      { 
       #*-- select 2 parents based on the prob. distr.
       my ($pa, $pb);
       do
        { $pa = &select_aparent(\@distr, $i); 
          $pb = &select_aparent(\@distr, $i); }
       while ( ($pa != -1) && ($pb != -1) && ($pa == $pb) );

       #*-- skip crossover if we did not find suitable parents
       if ( ($pa == -1) || ($pb == -1) )
        { push (@new_sols, $best_sol); } #*-- propagate best solution, so far
       else
        { push (@new_sols, &crossover("$sols[$pa]", "$sols[$pb]")); } 
      }
     
     #*-- run mutations on alternate iterations
     unless ($i % 2)
      { for my $j (0..$NUM_SOLUTIONS)
         { &mutation("$new_sols[$j]", \@matrix, $i); }
      }

     #*-- replace the previous generation with the new generation
     @sols = @new_sols;

   } #*-- end of for i

  #*-- create the final fitness scores and find the index
  #*-- of the best solution
  for my $i (0..$NUM_SOLUTIONS) 
   { $s_fitness[$i] = &sol_fitness("$sols[$i]", \@matrix); 
     if ($best_val < $s_fitness[$i])
      { $best_sol = "$sols[$i]"; $best_val = $s_fitness[$i]; }
   }


  #*-- Dump debug information to check how well documents are located
  #*-- compared to their nearest neighbor
  my @b_docs = split/,/,$best_sol;
  if ($debug)
   { print ("\nBest Fitness Score: ", $best_val, "\n");
     print ("\nInter-document solution sim. and Max sim. values: \n");
     for my $i(1..$#b_docs) 
      { (undef, my $max) = &min_max($matrix[$b_docs[$i-1]]);
        printf ("%7.4f %7.4f (docs. %3d and %3d)\n", $matrix[$b_docs[$i-1]][$b_docs[$i]], $max, $b_docs[$i-1], $b_docs[$i]); }
     print ("\nBest Solution: $best_sol\n");
   }

  #*-- build the clusters, start with docs with the highest
  #*-- similarity to other docs
  my @assigned = (0) x @b_docs; $num_docs = @b_docs;
  my $range = int (sqrt($num_docs)) + 1;
  for my $i (sort {$sim_total[$b_docs[$b]] <=> $sim_total[$b_docs[$a]]} 
                  (0..$#b_docs) )
   { 
    next if $assigned[$i]; $assigned[$i]++;
    my @new_cluster = (); push (@new_cluster, $b_docs[$i]);
#  for (my $j = $i - $range; $j <= $i + $range; $j++)
    my $forward = 1;
    for my $step (1..(2*$range))
    {
     my $astep = ($step % 2) ? (($step-1) / 2) + 1: ($step / 2);
     my $j = ($forward) ? $i + $astep: $i - $astep; $forward = !$forward;

     #*-- implement a circular list
     my $ind = ($j < 0) ? ($num_docs - abs($j)):
             ($j > ($num_docs - 1) ) ? ($j - $num_docs): $j;
     next if ( $assigned[$ind] || ($ind == $i) );

     #*-- decide if $ind should join the cluster
     my $count = 0;
     foreach (@new_cluster) 
       { $count++ if ($matrix[$b_docs[$ind]][$_] >= $THRESHOLD); }
     if ( (($link_type =~ /full_link/i) && ($count == @new_cluster) )         ||
          (($link_type =~ /half_link/i) && ($count >= int(@new_cluster/2) ) ) ||
          (($link_type =~ /one_link/i)  && ($count >= 1) ) ) 
      { push (@new_cluster, $b_docs[$ind]); $assigned[$ind]++; }

    } #*-- end of for j
    if (@new_cluster > 1) { push (@clusters, "@new_cluster"); }
    else                  { push (@misc, $b_docs[$i]); } 
    
   } #*-- end of for i 
  $ga_time = time() - $ga_time;
  $total_time = time() - $total_time;
  my $misc_time = $total_time - ($matrix_time + $ga_time);

  my $matrix_pct = int($matrix_time * 100.0 / $total_time);
  my $ga_pct     = int($ga_time     * 100.0 / $total_time);
  my $misc_pct   = 100 - ($matrix_pct + $ga_pct);
  push (@clusters, "@misc"); #*-- make the misc. cluster the last cluster

  if ($debug)
   {
    print ("Clusters:\n");
    for my $i (0..($#clusters-1))
     { print ($i + 1, ": $clusters[$i]\n"); }
    print ("Misc.: $clusters[$#clusters]\n\n");
    print ("Performance:\n");
    print ("Time to compute matrix:\t$matrix_time secs. ($matrix_pct\%)\n");
    print ("Time to run GA        :\t$ga_time secs. ($ga_pct\%)\n");
    print ("Time for miscellaneous:\t$misc_time secs. ($misc_pct\%)\n");
    print ("Total time:\t$total_time secs.\n");
   }

  return(\@clusters, \@matrix) if wantarray;
  return(\@clusters);
  
 }

 #*-------------------------------------------------------------------
 #*- crossover operator 
 #*-   Input: Two parent strings of documents
 #*-   Output: A child string formed from the combination of parents
 #*-------------------------------------------------------------------
 sub crossover
 {
  my ($p1, $p2) = @_;
  my @p1_docs = split/,/, $p1;
  my @p2_docs = split/,/, $p2;

  #*-- the number of docs in both parents must be the same
  return($p1) unless (@p1_docs == @p2_docs);
  my $num_docs = @p1_docs;

  #*-- find a common starting doc in both parents
  my $x = int(rand($num_docs)); my $y = -1;
  for my $i (0..$#p1_docs)
   { $y = $i if ($p1_docs[$x] == $p2_docs[$i]); }
  return($p1) unless ($y >= 0);

  #*-- Acquire the longest possible sequence of parents
  my $child = $p2_docs[$y]; my $part_1 = my $part_2 = 1; my @finished;
  @finished = (0) x @p1_docs; $finished[$p2_docs[$y]] = 1;
  do
   {
    $x = ($x - 1) % $num_docs; $y = ($y + 1) % $num_docs;
    #*-- prepend as much of the parent's sub tour as possible to the child 
    if ($part_1)
     { if ($finished[$p1_docs[$x]]) { $part_1 = 0; }
       else { $child = "$p1_docs[$x],$child"; $finished[$p1_docs[$x]] = 1; }
     }
    #*-- append as much of the parent's sub tour as possible to the child 
    if ($part_2)
     { if ($finished[$p2_docs[$y]]) { $part_2 = 0; }
       else { $child .= ",$p2_docs[$y]"; $finished[$p2_docs[$y]] = 1; }
     }
   } while ($part_1 || $part_2);

  #*-- add the rest of unassigned docs in random
  foreach (@p1_docs) { next if ($finished[$_]); $child .= ",$_"; }
  return($child);

 }


 #*---------------------------------------------------------------------
 #*- Create a mutated string       
 #*-   Accept a solution and address of sim. matrix
 #*-   Return the mutated string
 #*---------------------------------------------------------------------
 sub mutation
 {
  my ($sol, $rmatrix, $iter) = @_;

  my ($x, $y);
  my $prob = &gen_prob($iter);
  my @docs = split/,/,$sol; my $num_docs = @docs;
  for my $i (0..$NUM_MUTATIONS)
   {
    #*-- pick 2 docs at random to swap
    do 
     { $x = int (rand(@docs)); $y = int (rand(@docs)); } 
    while ($x == $y);

    my $old_fitness = &doc_fitness($x, $num_docs, $rmatrix, \@docs) + 
                      &doc_fitness($y, $num_docs, $rmatrix, \@docs);
    @docs[$x,$y] = @docs[$y,$x];
    my $new_fitness = &doc_fitness($x, $num_docs, $rmatrix, \@docs) + 
                      &doc_fitness($y, $num_docs, $rmatrix, \@docs);
    
    #*-- accept if the new fitness is better, otherwise accept with
    #*-- prob. based on iteration.
    @docs[$x,$y] = @docs[$y,$x]  
      if ( ( ($new_fitness - $old_fitness) < 0) && (rand() > $prob) );

   } #*-- end of for

 } 

 #*---------------------------------------------------------------------
 #*- Calculate the fitness of the solution      
 #*-   Accept the solution and address of sim. matrix
 #*-   Return the fitness of the solution
 #*---------------------------------------------------------------------
 sub sol_fitness
 {
  my ($solution, $rmatrix) = @_;

  my @inds = split/,/, $solution;
  my $num_docs = @inds; my $fitness = 0;
  for my $i (0..$#inds)
   { $fitness += &doc_fitness($i, $num_docs, $rmatrix, \@inds); }
  return($fitness);

 }

 #*---------------------------------------------------------------------
 #*- Calculate the fitness of a single document
 #*-   Accept a document number, number of documents, and sim. matrix
 #*---------------------------------------------------------------------
 sub doc_fitness
 {
  my ($doc_i, $num_docs, $rmatrix, $rdocs) = @_;

  my $range = 1; my $fitness = 0;
  my ($i, $ind);
  for ($i = $doc_i - $range; $i <= ($doc_i + $range); $i++)
   {
    #*-- implement a circular array
    $ind = ($i < 0) ? ($num_docs - abs($i)):
           ($i > ($num_docs - 1) ) ? ($i - $num_docs): $i;
    next if ($ind == $doc_i);
    $fitness += $$rmatrix[$$rdocs[$doc_i]][$$rdocs[$ind]];
   }
  return($fitness);

 }

 #*---------------------------------------------------------------------
 #*- Select a parent using the prob. distribution      
 #*-   Accept a prob. distribution and return an element
 #*-   Use the size of the probability distr. and the iteration
 #*-   number to select a parent
 #*---------------------------------------------------------------------
 sub select_aparent
 {
  my ($rdistr, $iter) = @_;

  #*-- check for a valid prob. distribution, otherwise we may
  #*-- have an infinite loop
  return(-1) if (&sum_array($rdistr) < 0.9);
  my @pdistr = @$rdistr;

  #*--------------------------------------------------------------
  #*- pick a value for $r_val
  #*-  
  #*-  Iterations	Distribution Size
  #*-		   <=50		51-100		>100
  #*-	 0 - 25	    5		 6		 7
  #*-	26 - 50	    4		 5		 6
  #*-	51 - 75     3		 4		 5
  #*-	76 - 100    2		 3		 4
  #*--------------------------------------------------------------
  my $s_val = (@pdistr <= 50) ? 5: (@pdistr <= 100) ? 6: 7;
  my $r_val = ($iter <= 25) ? $s_val: ($iter <= 50) ? $s_val - 1: 
              ($iter <= 75) ? $s_val - 2: $s_val - 3;

  #*--------------------------------------------------------------
  #*- set the weight = (rand($r_val) - $r_val + 9 ) / 10
  #*- When weight = $r_val is 6 the range of probs. is 0.4 - 0.9
  #*- When weight = $r_val is 5 the range of probs. is 0.5 - 0.9
  #*- When weight = $r_val is 4 the range of probs. is 0.6 - 0.9
  #*--------------------------------------------------------------
  my $rweight = ( (int (rand $r_val) + 1) / 10) + 
                  (0.9 - ($r_val / 10) );
  my $i = 0; my $limit = int(@pdistr / 2);
  while (my $ind = int (rand(@pdistr)) )
   { return($ind) if ($pdistr[$ind] > $rweight); 
     last if (++$i > $limit); }

  return(-1);
 }

 #*------------------------------------------------------------
 #*- return a scrambled array
 #*------------------------------------------------------------
 sub scramble
 {
  my ($size) = @_;
  my ($i, $j);
  my @arr; @arr[0..($size-1)] = (0..($size-1));  #*-- initialize the array

  #*-- use the fisher_yates algorithm to shuffle the elements
  for ($i = @arr; --$i; )
   { $j = int rand($i+1); next if ($i == $j);
     @arr[$i,$j] = @arr[$j,$i]; } #*-- swap the 2 elements

  return(\@arr);
 }

 #*------------------------------------------------------------
 #*- return a prob. based on the iteration number, a higher
 #*- prob. for lower iteration number and lower prob. at
 #*- higher iterations
 #*------------------------------------------------------------
 sub gen_prob
 {
  my ($iter) = @_;
  return (0.5)  if ( ($iter >= 0)  && ($iter <= 10) );
  return (0.1)  if ( ($iter > 50)  && ($iter <= 100) );
  return (0.05) if ( ($iter > 100) && ($iter <= 200) );
  return (0.03) if ( ($iter > 200) && ($iter <= 500) );
  return (0.01) if ( ($iter > 500) && ($iter <= 1000) );
  return (0.00) if   ($iter > 1000)
 }

 #*-----------------------
 #*- dump the matrix 
 #*-----------------------
 sub dump_array
 { my ($rmatrix, $dim, $title, $sval) = @_;

   #*-- dump the matrix 
   print ("\n$title\n");
   if ($dim && ($dim > 1) )
    {
     my @matrix = @$rmatrix; my $rows = my $cols = $#matrix;
     for my $i (0..$rows) { my $str = "Doc $i"; printf ("%-7s", $str); }
     print ("\n");
     for my $i (0..$rows)
      { print ("Doc $i ");
        for my $j (0..$cols) { printf ("%7.4f", $matrix[$i][$j]); }
     print ("\n"); }
    }
   else
    { if ($sval) { foreach (@$rmatrix) { print ("$_\n"); } print ("\n"); }
      else { foreach (@$rmatrix) { printf ("%7.4f", $_); } print ("\n"); } 
    } #*-- end of else
    
 }

1;

=head1 NAME

Cluster - Automatically categorize documents

=head1 SYNOPSIS

use TextMine::Cluster;

my $r_clusters = &cluster(\@docs, 'fre', $dbh, 'news', 'full_link', $thresh, 
 'debug');

Input Parameters

  - Reference to an array. Each element of the array contains a 
    reference to a text string.

  - Type of indexing - 'fre' for frequency, 'idf' for inverse document 
    frequency, 'lsi' for latent semantic indexing 

  - Database handle

  - Type of text - 'new' for news articles, 'web' for web pages, 
    'email' for emails, and '' for none

  - Type of links between documents in a cluster - 'full_link' 
    for links between all possible pairs of documents in a cluster 
    (tight clusters), 'half_link' for links between a document and 
    at least half the documents in the cluster, and 'one_link' for 
    a link between a document and at least one document in the 
    cluster (loose cluster)
  
  - Similarity threshold to establish a link between 2 documents 
    (default is 0.2)

  - Debug parameter

Output

  - A reference to an array. Each element of the array contains
    a list of comma separated numbers. These number represent the
    document numbers of the cluster members. The document numbers
    are in the input docs array order 

=head1 DESCRIPTION

  The Cluster module can be used to group together documents based
  on content. A vector is created for each document. Vectors can
  differ based on the indexing method. Currently, there are 3 types
  of indexing - frequency based (fre), inverse document frequency
  (idf), and latent semantic indexing (lsi). 

=head2 Indexing

  Frequency based indexing is strictly a count of the number of 
  occurences of terms in a document. The counts are normalized per 
  document. Terms which occur frequently across all documents will
  be weighted similar to terms that occur more often in a few 
  documents. 

  Inverse document frequency weights terms that occur arcoss all
  document less than terms that occur in a few documents. IDF will
  find 'better discriminator' terms in the document collection which
  helps in comparing documents.

  Latent semantic indexing is a somewhat newer indexing scheme and
  is experimental, at least in this implementation. Try a search
  on LSI for more information.

=head2 Algorithm

  After generating a vector for every document, the similarity 
  matrix is computed. All unique pairs of documents are compared
  using a cosine similarity measure. A value of 1.0 means that
  the documents are identitical. A value of 0.0 means that both
  documents have nothing in common. Values between 0.0 and 1.0
  represent the degree of similarity.

  A genetic algorithm is used for finding an optimized arrangement
  of the documents. The documents are randomly arranged in a circle
  and the algorithm attempts to place documents that are similar
  closer to each other in the circle. 

  After arranging the documents in the circle, potential documents
  which have a high degree of similarity with other documents are
  chosen as cluster centers. Other member documents for every
  cluster are selected in the neighborhood of the cluster core
  document.

=head1 AUTHOR

Manu Konchady <mkonchady@yahoo.com>
