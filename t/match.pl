#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*------------------------------------------------------------
 #*- match.pl
 #*-  test code for the text match function
 #*------------------------------------------------------------
 use strict; use warnings;
 use TextMine::Index qw/text_match/;

 my $text = 'This is bunch of text for testing data mining' .
    ' with more e-business data "warehouse stuff" and miscellaneous junk';
 print ("Regular Match Tests:\n\n");
 print "Text: $text\n\n";
 print "No.\tAnswer\tResult\tQuery\n";

 #*-- generate the queries and answers
 my @queries = (); my @ans = ();
 push(@ans, 1); push(@queries, 'data mining');
 push(@ans, 1); push(@queries, '"data mining"');
 push(@ans, 1); push(@queries, '"data mining" testing');
 push(@ans, 0); push(@queries, '"data mining" test');
 push(@ans, 1); push(@queries, '("data mining") AND text');
 push(@ans, 0); push(@queries, '("data mining") AND test');
 push(@ans, 0); push(@queries, '("data minning")');
 push(@ans, 1); push(@queries, '("data minning") OR text');
 push(@ans, 0); push(@queries, '("data minning") OR test');
 push(@ans, 1); push(@queries, '("data mining") AND "warehouse stuff"');
 push(@ans, 0); push(@queries, '("data mining" AND test) OR ("warehouse stuff" AND unknown)');
 push(@ans, 1); push(@queries, '("data mining" AND test) OR ("warehouse stuff" OR unknown)');
 push(@ans, 1); push(@queries, '("data mining" OR test) AND ("warehouse stuff" OR unknown)');
 push(@ans, 1); push(@queries, '("warehouse stuff" AND (text AND "data mining" ) )');
 push(@ans, 0); push(@queries, '("warehouse stuff" AND (text AND "data mining" info) )');
 push(@ans, 0); push(@queries, '("warehouse stuff" AND (test AND "data mining") )');
 push(@ans, 1); push(@queries, '("warehouse stuff" AND (text AND "data mining" AND (bunch OR informatics) ) )');
 push(@ans, 1); push(@queries, 'e-business');
 push(@ans, 1); push(@queries, 'e_business');
 push(@ans, 1); push(@queries, '"e-business"');
 push(@ans, 0); push(@queries, '"e--business"');
 push(@ans, 0); push(@queries, 'NOT data');
 push(@ans, 0); push(@queries, 'NOT "data mining"');
 push(@ans, 1); push(@queries, 'NOT "data minning"');
 push(@ans, 0); push(@queries, 'NOT "data minning" test');
 push(@ans, 1); push(@queries, 'NOT "data minning" text');
 push(@ans, 1); push(@queries, 'NOT "data minning" OR test');
 push(@ans, 1); push(@queries, '(NOT "data minning" OR test) AND text');
 push(@ans, 0); push(@queries, '(NOT "data minning" OR test) AND test');
 push(@ans, 1); push(@queries, '(NOT "data minning" OR test) AND testing');
 push(@ans, 1); push(@queries, '(NOT "data minning" OR test) AND (testing)');
 push(@ans, 1); push(@queries, '(NOT "data minning" OR test) AND ("testing")');
 push(@ans, 0); push(@queries, '(NOT "data minning" OR test) AND (NOT "testing")');
 push(@ans, 1); push(@queries, '(NOT "data minning" OR test) AND (text OR NOT "testing")');
 push(@ans, 0); push(@queries, 'NOT ("data mining")');
 push(@ans, 1); push(@queries, 'NOT ("data mining") OR e-business');
 push(@ans, 1); push(@queries, 'NOT ("data minning" OR test)');
 push(@ans, 0); push(@queries, 'NOT ("data mining" AND e-business)');
 push(@ans, 1); push(@queries, 'NOT ("data mining" AND test) OR e-business');
 push(@ans, 1); push(@queries, '("warehouse stuff" AND (text AND "data mining" AND NOT (bunch AND informatics) ) )');

 #*---- run the regular tests
 my $errs = ''; 
 for my $i (0..$#queries)
  { 
    my $result = &text_match(\$text, $queries[$i]); 
    print ("$i.\ta: $ans[$i]\ta:$result\tq:$queries[$i] \n"); 
    $errs .= "\tNo. $i wrong \n" 
             if ( ( ($ans[$i]) && (!$result) ) ||
                  ( (!$ans[$i]) && ($result) ) );
  }
 print "\n\nErrors:\n$errs" if ($errs);

 print ("\n\nFuzzy Match Tests:\n\n");
 print "Text: $text\n\n";
 print "No.\tAnswer\tResult\tQuery\n";

 #*-- generate the queries and answers
 @queries = (); @ans = ();
 push(@ans, 1); push(@queries, 'data min');
 push(@ans, 1); push(@queries, '"data mining"');
 push(@ans, 1); push(@queries, '"data mining" testing');
 push(@ans, 1); push(@queries, '"data mining" test');
 push(@ans, 1); push(@queries, '("data mining") AND text');
 push(@ans, 1); push(@queries, '("data mining") AND test');
 push(@ans, 0); push(@queries, '("data minning")');
 push(@ans, 1); push(@queries, '("data minning") OR text');
 push(@ans, 1); push(@queries, '("data minning") OR test');
 push(@ans, 1); push(@queries, '("data mining") AND "warehouse stuff"');
 push(@ans, 1); push(@queries, '("data mining" AND test) OR ("warehouse stuff" AND unknown)');
 push(@ans, 1); push(@queries, '("data mining" AND test) OR ("warehouse stuff" OR unknown)');
 push(@ans, 1); push(@queries, '("data mining" OR test) AND ("warehouse stuff" OR unknown)');
 push(@ans, 1); push(@queries, '("warehouse stuff" AND (text AND "data mining" ) )');
 push(@ans, 0); push(@queries, '("warehouse stuff" AND (text AND "data mining" info) )');
 push(@ans, 1); push(@queries, '("warehouse stuff" AND (test AND "data mining") )');
 push(@ans, 1); push(@queries, '("warehouse stuff" AND (text AND "data mining" AND (bunch OR informatics) ) )');
 push(@ans, 1); push(@queries, 'e-business');
 push(@ans, 1); push(@queries, 'e_business');
 push(@ans, 1); push(@queries, '"e-business"');
 push(@ans, 1); push(@queries, '"e--business"');
 push(@ans, 0); push(@queries, 'NOT data');
 push(@ans, 0); push(@queries, 'NOT "data mining"');
 push(@ans, 1); push(@queries, 'NOT "data minning"');
 push(@ans, 1); push(@queries, 'NOT "data minning" test');
 push(@ans, 1); push(@queries, 'NOT "data minning" text');
 push(@ans, 1); push(@queries, 'NOT "data minning" OR test');
 push(@ans, 1); push(@queries, '(NOT "data minning" OR test) AND text');
 push(@ans, 1); push(@queries, '(NOT "data minning" OR test) AND test');
 push(@ans, 1); push(@queries, '(NOT "data minning" OR test) AND testing');
 push(@ans, 1); push(@queries, '(NOT "data minning" OR test) AND (testing)');
 push(@ans, 1); push(@queries, '(NOT "data minning" OR test) AND ("testing")');
 push(@ans, 0); push(@queries, '(NOT "data minning" OR test) AND (NOT "testing")');
 push(@ans, 1); push(@queries, '(NOT "data minning" OR test) AND (text OR NOT "testing")');
 push(@ans, 0); push(@queries, 'NOT ("data mining")');
 push(@ans, 1); push(@queries, 'NOT ("data mining") OR e-business');
 push(@ans, 0); push(@queries, 'NOT ("data minning" OR test)');
 push(@ans, 0); push(@queries, 'NOT ("data mining" AND e-business)');
 push(@ans, 1); push(@queries, 'NOT ("data mining" AND test) OR e-business');
 push(@ans, 1); push(@queries, '("warehouse stuff" AND (text AND "data mining" AND NOT (bunch AND informatics) ) )');

 #*---- run the fuzzy match tests
 $errs = ''; 
 for my $i (0..$#queries)
  { 
    my $result = &text_match(\$text, $queries[$i], 1); 
    print ("$i.\ta: $ans[$i]\ta:$result\tq:$queries[$i] \n"); 
    $errs .= "\tNo. $i wrong \n" 
             if ( ( ($ans[$i]) && (!$result) ) ||
                  ( (!$ans[$i]) && ($result) ) );
  }
 print "\n\nErrors:\n$errs" if ($errs);

 #*-- generate the fuzzy word queries and answers
 print ("\n\nFuzzy Word Match Tests:\n\n");
 print "Text: $text\n\n";
 print "No.\tAnswer\tResult\tQuery\n";
 @queries = (); @ans = ();
 push(@ans, 1); push(@queries, 'data mining*');
 push(@ans, 1); push(@queries, '"data min*"');

 #*---- run the fuzzy word match tests
 $errs = ''; 
 for my $i (0..$#queries)
  { 
    my $result = &text_match(\$text, $queries[$i], 0); 
    print ("$i.\ta: $ans[$i]\ta:$result\tq:$queries[$i] \n"); 
    $errs .= "\tNo. $i wrong \n" 
             if ( ( ($ans[$i]) && (!$result) ) ||
                  ( (!$ans[$i]) && ($result) ) );
  }
 print "\n\nErrors:\n$errs" if ($errs);

 exit(0);
