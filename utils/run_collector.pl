#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------------------
 #*- run_collector.pl
 #*-  
 #*-   Summary: Start the collection process        
 #*-
 #*----------------------------------------------------------------
 use strict; use warnings;
 use TextMine::Constants qw/$UTILS_DIR $OSNAME $PERL_EXE $DELIM/;
 use TextMine::MyProc;

 my $retval; my $stat_msg = ''; my $num_p = 2; #*-- no. of processes
 for my $i (0..($num_p-1))
  {
   print ("Started collection process $i\n");
   my @cmdline = ("$UTILS_DIR" . "ne_rss_collector.pl ", $i . $DELIM . $num_p);
   $retval = &create_process(\@cmdline, 1, 'Perl.exe', "$PERL_EXE");
   $stat_msg .= $retval if ($retval);
  }
 print ("Status: $stat_msg\n") if ($stat_msg);
 exit(0);
