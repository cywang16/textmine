#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*-----------------------------------------------------------------
 #*- qu_test.pl
 #*-    Read the test questions and answers and compute the 
 #*-    precision of the question categorizer
 #*-----------------------------------------------------------------
 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Constants qw/$DB_NAME @QTYPES/;
 use TextMine::Entity    qw/entity_ex/; 
 use TextMine::Quanda    qw/get_qcat get_re_qcat verify_qfile/;

 print "Started qu_test.pl\n";
 my ($dbh, $command, $table);
 ($dbh) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => $DB_NAME);

 my $QFILE = "testing.txt";
 my $questions = my $correct = my $error = 0;
 my %correct = my %error = my %diff = my %catq = my %fpos = my %missed = ();
 foreach (@QTYPES) 
   { $_ = lc($_); $correct{$_} = $error{$_} = $diff{$_} = $catq{$_} = 0; }
 local $" = '|'; my $qr_en = qr/(@QTYPES)/i; local $" = ' ';

 #*-- check the format of the file
 &verify_qfile($QFILE);

 open (IN, $QFILE) || die ("Could not open $QFILE $!\n");
 while (my $inline = <IN>)
  {
   chomp($inline);

   #*-- skip blank lines and comments
   next if ( ($inline =~ /^\s*$/) || ($inline =~ /^#/) ); 

   #*-- get the question and answer text + answer entity
   $inline =~ s/^(\d+): //; my $qno = $1;
   my $q_text = $inline; $inline = <IN>; chomp($inline);
   my ($a_text, $a_ents) = $inline =~ /^(.*)###(.*)$/;
   $a_ents =~ s/\s+$//; $a_ents = lc($a_ents); $catq{$a_ents}++;

   #*-- get the question category
   my %categories = &get_qcat($q_text, $dbh); 
#   my %categories = &get_re_qcat($q_text, $dbh); 
   my @cats = keys %categories; my $match = '';
   foreach (keys %categories) { $match = $_ if ($a_ents =~ /$_/i); }

   #*-- if one of the 2 categories was correct
   if ($match) 
    { $correct{$match}++; $correct++; 
      $diff{$match} += (1.0 - $categories{$match}); }
   else        
    { $error{$a_ents}++;   $error++; $fpos{$cats[0]}++;
      $missed{"$a_ents,$cats[0]"} .= "$qno ";
      $diff{$a_ents} += 1.0; }
   
   print " Q$qno: $q_text\n A: $a_text\n"; 
   print " Entities: $a_ents Categories: @cats\n"; 
   my $precision = 100.0 * $correct / ($correct + $error);
   $precision = sprintf("%6.4f", $precision);
   print " Correct: $correct Error: $error Precision: $precision\n\n";
   $questions++; 

  }

 close(IN); 

 printf "%15s%15s%15s%15s%15s\n", 
         "Category", "Correct", "Error", "Total", "Avg. Diff.";
 my $dash = '-' x 80; 
 print "$dash\n"; my $n_prec = 0;
 foreach (keys %catq) 
   { $diff{$_} = $diff{$_} / ($catq{$_} + 0.0000001);
     printf "%15s%15d%15d%15d%15.5f\n", 
             $_, $correct{$_}, $error{$_}, $catq{$_}, $diff{$_}; 
     $n_prec += ($correct{$_} / ($catq{$_} + 0.0000001) );
   }

 print "$dash\n";
 printf "%15s%15d%15d%15d\n", 
        'Total', $correct, $error, $questions; 
 print "$dash\n\n";

 my $prec = sprintf("%8.3f", $correct / $questions); $prec *= 100;
 print "Total percent correct : $prec%\n";

 $prec = sprintf("%8.3f", $n_prec /= keys %catq); $prec *= 100;
 print "Normalized Percent correct : $prec%\n";

 print "\nFalse Positives:\n";
 foreach (sort {$fpos{$b} <=> $fpos{$a}} keys %fpos)
  { printf "%15s: %6d\n", $_, $fpos{$_}; }

 print "\nCategorization Errors:\n";
 printf("%5s%15s%15s%45s\n", 'No.', 'Correct', 'Error', 'Questions');
 print "$dash\n"; my $tot_errors = 0;

 #*-- create a hash for sorting
 my %sort_missed = ();
 for my $key (keys %missed)
  { my @num_errors = split/\s+/, $missed{$key}; 
    $sort_missed{$key} = scalar @num_errors; }
 
 for my $key (sort { $sort_missed{$b} <=> $sort_missed{$a} } keys %sort_missed)
  {
   my ($correct, $error) = $key =~ /^(.*?),(.*)$/; 
   printf "%5d%15s%15s", $sort_missed{$key}, $correct, $error; 
   if (length($missed{$key}) > 45) { printf "\n%80s\n", $missed{$key}; }
   else                            { printf "%45s\n",   $missed{$key}; } 
   $tot_errors += $sort_missed{$key};
  }
 print "$dash\n";
 print "Total Errors: $tot_errors\n";

 print "Finished qu_test.pl\n";
 $dbh->disconnect_db();
 exit(0);
