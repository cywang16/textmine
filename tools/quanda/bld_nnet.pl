#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*-----------------------------------------------------------
 #*- bld_nnet.pl
 #*-   Create the node weights for the neural network for
 #*-   each query category        
 #*-----------------------------------------------------------
 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Constants qw/@QTYPES $EQUAL/;
 use TextMine::Quanda;

 print "Started bld_nnet.pl\n";

 #*-- define the constants for the neural net
 use constant ERROR 	=> 0.02; 	#*-- error threshold to exit
 use constant ETA	=> 0.10;	#*-- learning coefficient (0.05 - 0.2)
 use constant ALPHA	=> 0.60;	#*-- momentum coefficient (0.5 - 0.9)
 use constant ITERS	=> 1000;	#*-- max no. of iterations	
 use constant DEBUG	=> 1;		#*-- debug constant	

 #*-- global variables
 our $NPATTERNS = 0; 

 #*-- declare hashes for the neural net
 our (%outi,  	  #*-- input layer nodes 
     %outh,  	  #*-- hidden layer nodes 
     %outo,  	  #*-- output layer nodes 
     %target,  	  #*-- target for pattern 
     %wt_ih,   	  #*-- input - hidden layer weights
     %wt_ho,  	  #*-- hidden - output layer weights
     %delta_ih,   #*-- error signal in hidden layer 
     %delta_ho,   #*-- error signal in output layer 
     %odelta_ih,  #*-- old error signal in hidden layer 
     %odelta_ho); #*-- old error signal in output layer 

 #*-- read the query categories into a hash
 our %catline = (); &read_qcat();
 open (OQC, ">qu_categories.dat") || die ("Could not open qu_categories $!\n");
 binmode OQC, ":raw";

 #*-- loop through all categories and create the weights for
 #*-- the neural nets
 for my $category (@QTYPES)
# for my $category (qw/person/)
  {
   #*-- read the pattern file and initialize the target hash
   print "Started $category\n";
   &read_patterns($category);

   #*-- load the initial weights for the connections between layers
   &gen_weights();

   #*-- iterate till completion
   LOOP: for my $iter (1..ITERS)
    {
     #*-- run a forward and backward pass for each pattern
     for my $patt (1..$NPATTERNS)
      { &forward_pass($patt); &backward_pass($patt); }

     #*-- adjust the weights for all patterns
     &adapt_weights();

     #*-- check if it is time to terminate
     my $error = &compute_error(); 
     if ($error < ERROR)
      { print "Iter.: $iter E: $error \n";
        last LOOP; }

     if (DEBUG && !($iter % 10) )
      { #&dump_state($iter) unless ($iter % 100);
        print "Iter.: $iter E: $error \n"; } 
        
     if ( ($error > 0.02) && ($iter > ITERS) ) 
      { print "Having trouble reducing error in the $category category\n";
        print "Fix training questions ?\n"; 
        last LOOP; }

    } #*-- end of LOOP

   #*-- print the results
   &dump_weights($category); 
  
   print "Finished creating net for $category\n";

  } #*-- end of for $category

 close(OQC);
 print "Ended bld_nnet.pl\n";
 exit(0);

 #*----------------------------------------------------------
 #*- Submit a pattern and calculate the output values       
 #*----------------------------------------------------------
 sub forward_pass
 {  
  my ($p) = @_;

  #*-- compute the hidden layer values
  for my $h (1..HNODES)
   { 
    my $sum = $wt_ih{IBIAS . ",$h"};
     for my $i (1..INODES) { $sum += $wt_ih{"$i,$h"} * $outi{"$p,$i"}; }
    $outh{"$p,$h"} = 1.0 / (1.0 + exp(-$sum) );
   }

  #*-- compute the output layer values
  for my $o (1..ONODES)
   { 
    my $sum = $wt_ho{HBIAS . ",$o"};
    for my $h (1..HNODES) { $sum += $wt_ho{"$h,$o"} * $outh{"$p,$h"}; }
    $outo{"$p,$o"} = 1.0 / (1.0 + exp(-$sum) );
   }

 }

 #*-------------------------------------------------------------
 #*- Calculate the error values for the pattern and accumulate
 #*-------------------------------------------------------------
 sub backward_pass
 {  
  my ($p) = @_;

  #*-- compute the output weight delta
  for my $o (1..ONODES)
   { $delta_ho{"$p,$o"} = ($target{"$p,$o"} - $outo{"$p,$o"}) *
                             $outo{"$p,$o"} * (1.0 - $outo{"$p,$o"}); 
   }

  #*-- compute the hidden weight delta
  for my $h (1..HNODES)
   { 
     my $sum = 0.0;
     for my $o (1..ONODES) { $sum += $delta_ho{"$p,$o"} * $wt_ho{"$h,$o"}; }
     $delta_ih{"$p,$h"} = $sum * $outh{"$p,$h"} * (1.0 - $outh{"$p,$h"});
   }

 }

 #*-------------------------------------------------------------
 #*- Adjust the weights for each iteration 
 #*-------------------------------------------------------------
 sub adapt_weights
 {  
  my ($p) = @_;

  #*-- adjust the hidden :: output weights
  for my $o (1..ONODES)
   {
    #*-- sum the total output weight deltas
    my $sum = 0.0; for my $p (1..$NPATTERNS) { $sum += $delta_ho{"$p,$o"}; }

    #*-- compute the new bias weight
    my $dw = ETA * $sum + ALPHA * $odelta_ho{HBIAS . ",$o"};
    $wt_ho{HBIAS . ",$o"} += $dw; $odelta_ho{HBIAS . ",$o"} = $dw;
    
    #*-- calculate the new weights
    for my $h (1..HNODES)
     {
      my $sum = 0.0; 
      for my $p (1..$NPATTERNS) { $sum += $delta_ho{"$p,$o"} * $outh{"$p,$h"}; }

      $dw = (ETA * $sum) + (ALPHA * $odelta_ho{"$h,$o"});
      $wt_ho{"$h,$o"} += $dw; $odelta_ho{"$h,$o"} = $dw;
     }
   }

  #*-- adjust the input :: hidden weights
  for my $h (1..HNODES)
   {
    #*-- sum the total output weight deltas
    my $sum = 0.0; for my $p (1..$NPATTERNS) { $sum += $delta_ih{"$p,$h"}; }

    #*-- compute the new bias weight
    my $dw = ETA * $sum + ALPHA * $odelta_ih{HBIAS . ",$h"};
    $wt_ih{IBIAS . ",$h"} += $dw; $odelta_ih{HBIAS . ",$h"} = $dw;
    
    #*-- calculate the new weights
    for my $i (1..INODES)
     {
      my $sum = 0.0; 
      for my $p (1..$NPATTERNS) 
        { $sum += $delta_ih{"$p,$h"} * $outi{"$p,$i"}; }
      $dw = (ETA * $sum) + (ALPHA * $odelta_ih{"$i,$h"});
      $wt_ih{"$i,$h"} += $dw; $odelta_ih{"$i,$h"} = $dw;
     }
   }

 }

 #*-------------------------------------------------------------
 #*- Compute the error and return
 #*-------------------------------------------------------------
 sub compute_error
 {  
  my $error = 0.0;
  for my $p (1..$NPATTERNS)
   {
    #*-- compute sigma of the square error
    for my $o (1..ONODES) 
     { $error += ($target{"$p,$o"} - $outo{"$p,$o"}) * 
                 ($target{"$p,$o"} - $outo{"$p,$o"}); }
   }
  $error /= ($NPATTERNS * ONODES);
  return($error);

 }

 #*-------------------------------------------------------------
 #*- Print the final weights  
 #*-------------------------------------------------------------
 sub dump_weights
 {  
  my ($category) = @_;

  my $out = ''; 

  #*-- save the weights for the input :: hidden nodes
  for my $i (1..IBIAS)
   { for my $h (1..HNODES)
      { $out .= sprintf("%9.6f$EQUAL", $wt_ih{"$i,$h"}); }
   }

  #*-- save the weights for the hidden :: output nodes  
  for my $h (1..HBIAS)
   { for my $o (1..ONODES)
      { $out .= sprintf("%9.6f$EQUAL", $wt_ho{"$h,$o"}); }
   }

  print OQC "$catline{$category}:$out\n";

 }

 #*----------------------------------------------------------
 #*- Read the patterns from the pattern file and initialize
 #*- the target hash
 #*----------------------------------------------------------
 sub read_patterns
 {  
  my ($category) = @_;

  #*-- initialize the global vars
  %outi = %outh = %outo = %target = %wt_ih = %wt_ho = %delta_ih = 
  %delta_ho = %odelta_ih = %odelta_ho = ();	
    ();
  open (IN, "pfile") || die ("Unable to open pfile $!\n");
  my $npat = 1;
  while (my $inline = <IN>)
   {
    chomp($inline);
 
    #*----------------------------------------------------------
    #*- pfile format
    #*-  Question no.: phrase sim.: category terms sim.:
    #*-  interrogation word sim.: vector sim.: answer entity: 
    #*-  YES/NO 
    #*-  1:0.00000:0.32798:0.00000:0.01983:person:NO:
    #*-  initialize the input nodes and the target
    #*----------------------------------------------------------

    #*-- skip unless the category matches
    my ($entity, $target) = $inline =~ /:(\w+):(\w+):$/;
    next unless ($category =~ /$entity/i); 

    #*-- set the input parameters
    ($outi{"$npat," . P_SIM}, $outi{"$npat," . Q_SIM},
     $outi{"$npat," . I_SIM}, $outi{"$npat," . N_SIM},
     $outi{"$npat," . V_SIM}) = 
     $inline =~ /^\d+:	#*-- question id
             ([\d\.]+):	#*-- phrase similarity
             ([\d\.]+):	#*-- category terms similarity
             ([\d\.]+):	#*-- interr. word similarity
             ([\d\.]+):	#*-- interr. noun similarity
             ([\d\.]+):	#*-- vector similarity
             \w+:	#*-- entity type
             \w+:/x;	#*-- yes or no

    #*-- set the expected output 
    if ($target =~ /YES/i)
        { $target{"$npat," . YES} = 1; $target{"$npat," . NO} = 0; }
    else 
        { $target{"$npat," . YES} = 0; $target{"$npat," . NO} = 1; }
    $npat++;
    
   }
  close(IN);
  $NPATTERNS = $npat - 1;

 }

 #*----------------------------------------------------------
 #*- read the query categories into a hash
 #*----------------------------------------------------------
 sub read_qcat  
 {  
  #*-- read the query categories file and save the lines in catline
  open (IN, "qu_cat_temp.txt") || 
       die ("Could not open qu_cat_temp.txt $!\n");
  while (my $inline = <IN>)
   { chomp($inline); chop($inline);
     (my $cat) = $inline =~ /^\d+:(.*?):/; $catline{$cat} = $inline; }
  close(IN);
 }

 #*----------------------------------------------------------
 #*- generate weights for the connections
 #*----------------------------------------------------------
 sub gen_weights
 {  
  #*-- generate weights for the connections from the input to hidden layers
  for my $i (1..INODES)
   { for my $h (1..HNODES) 
      { $wt_ih{"$i,$h"} = &gen_iweight(); $odelta_ih{"$i,$h"} = 0.0; } }
  for my $h (1..HNODES) 
   { $wt_ih{IBIAS . ",$h"} = 1.0; $odelta_ih{IBIAS . ",$h"} = 0.0; }

  #*-- generate weights for the connections from the hidden to output layers
  for my $h (1..HNODES)
   { for my $o (1..ONODES) 
      { $wt_ho{"$h,$o"} = &gen_iweight(); $odelta_ho{"$h,$o"} = 0.0; } }
  for my $o (1..ONODES) 
   { $wt_ho{HBIAS . ",$o"} = 1.0; $odelta_ho{HBIAS . ",$o"} = 0.0; }
 }

 #*----------------------------------------------------------
 #*- generate an initial weight between +0.3 and -0.3
 #*----------------------------------------------------------
 sub gen_iweight
 { my $wt = rand(6); $wt -= 3; $wt /= 10.0; return($wt); }

 #*----------------------------------------------------------
 #*- dump the state of the network in Pajek format
 #*----------------------------------------------------------
 sub dump_state
 {
  my ($iter) = @_;

  $iter = 1 unless (defined($iter)); my $vcount = 1;
  my $file = "state_$iter" . '.net';
  open (OUT, ">$file") || die ("Could not open $file $!\n");

  #*-- preload the coordinate positions for this network
  my @loc = ('0.1895    0.7621    0.5000',
 	'0.1846    0.5271    0.5000', '0.1846    0.3077    0.5000',
 	'0.1777    0.0556    0.5000', '0.4873    0.1325    0.5000',
 	'0.4932    0.4402    0.5000', '0.4932    0.7564    0.5000',
 	'0.5932    0.5402    0.5000', '0.5932    0.7564    0.5000',
 	'0.7314    0.4402    0.5000', '0.8314    0.4402    0.5000');

  #*-- print the input, hidden, and output nodes
  print OUT '*Vertices ', INODES + HNODES + ONODES, "\n";
  my @icount = my @hcount = my @ocount = ();
  print OUT "$vcount \"I_I_SIM\" $loc[$vcount-1]\n"; 
  push(@icount, $vcount); $vcount++;
  print OUT "$vcount \"I_P_SIM\" $loc[$vcount-1]\n"; 
  push(@icount, $vcount); $vcount++;
  print OUT "$vcount \"I_Q_SIM\" $loc[$vcount-1]\n"; 
  push(@icount, $vcount); $vcount++;
  print OUT "$vcount \"I_V_SIM\" $loc[$vcount-1]\n"; 
  push(@icount, $vcount); $vcount++;
  print OUT "$vcount \"I_N_SIM\" $loc[$vcount-1]\n"; 
  push(@icount, $vcount); $vcount++;
  for (1..HNODES)
   { print OUT "$vcount \"H_$_\" $loc[$vcount-1]\n"; 
     push(@hcount, $vcount); $vcount++; }
  for (1..ONODES)
   { print OUT "$vcount \"O_$_\" $loc[$vcount-1]\n"; 
     push(@ocount, $vcount); $vcount++; }

  #*-- print the links between the nodes
  print OUT "*Arcs\n";
  for my $i (1..INODES)
   { for my $h (1..HNODES) 
       { print OUT "$icount[$i-1] $hcount[$h-1] $wt_ih{\"$i,$h\"}\n"; }
   }
  for my $h (1..HNODES)
   { for my $o (1..ONODES) 
       { print OUT "$hcount[$h-1] $ocount[$o-1] $wt_ho{\"$h,$o\"}\n"; }
   }
  close(OUT);
 }
