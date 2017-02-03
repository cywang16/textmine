#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------------------
 #*- extract_doc.pl
 #*-   Extract documents based on categories listed below from
 #*-   Reuters collection
 #*----------------------------------------------------------------
 use strict; use warnings;

 #*-- Reuters directory for source files
 use constant REUTER_DIR => 'D:/cygwin/home/konchady/reuters/';
 use constant NUM_DOCS => 55; #*-- no. of documents

 #*-- get a new list of files or repeat 
 my @files = scramble(22);
 # my @files = (0..21);
 foreach (@files) 
  { $_ = (/^[0-9]$/) ? 'reut2-00' . $_ . '.sgm': 'reut2-0' . $_ . '.sgm'; }

 #*-- build the category list
 my %categories = ();
 $categories{$_}++ foreach (qw/cocoa sugar coffee/);
#   rice coconut cotton groundnut plywood potato veg-oil wheat rubber/);

 my $i = 0; my %cats = ();
 open (OUT, ">doc.txt") || die ("Unable to open doc.txt $!");
 binmode OUT, ":raw";
OLOOP:
 foreach my $file (@files)
  {
   print ("Processing File: $file......\n");
   my $ifile = REUTER_DIR . $file;
   open (IN, $ifile) || die ("Could not open $ifile $!\n");
   undef($/); my $inline = <IN>;
   close(IN);
   while ($inline =~ m%<TOPICS>.*?  <D>(.*?)</D> .*?</TOPICS>.*?
                         <BODY>(.*?) Reuter\s+ &#3;</BODY>%xisg)
    { (my $category, my $text) = ($1, $2);
      next unless($categories{$category});
      next if (length($text) < 1000); #*-- skip short documents
      print ("Processing Category: $category......\n");
      print OUT ("$i: $category: -- Document Separator -- $file\n");  
      print OUT ("$text\n"); 
      $cats{$category}++;
      last OLOOP if (++$i >= NUM_DOCS); #*-- limit the number of documents
    }
  }
 close(OUT);

 foreach (sort keys %cats)
   { print ("$cats{$_}:\t$_\n"); }

 exit(0);


 #*-------------------------------------------------------
 #*- return a scrambled array
 #*-------------------------------------------------------
 sub scramble
 {
  (my $size) = @_;
  my ($i, $j); my @arr;
  @arr[0..($size-1)] = (0..($size-1));
  
  for ($i = @arr; --$i; )
   { $j = int rand($i+1); next if ($i == $j); 
     @arr[$i,$j] = @arr[$j,$i]; }

  return(@arr);
 }
