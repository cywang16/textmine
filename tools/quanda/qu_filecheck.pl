#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*---------------------------------------------------------
 #*- qu_filecheck.pl
 #*-  verify the format for the question files
 #*---------------------------------------------------------

 open (IN, "test.txt") || die ("Unable to open test.txt");
 while ($inline = <IN>)
  {
    next if ($inline =~ /^(#|\s*$)/); chomp($inline);

    #*-- save the question text, iwords and entities
    print "No number for question $inline\n" unless $inline =~ s/^(\d+): //;
    $qno = $1;

    $inline = <IN>; chomp($inline); 
    print "Q: $qno Answer not in correct format: $inline" 
        unless $inline =~ /^(.*)###(.*)$/;

    $a_type = $2;
    print "Q: $qno Incorrect answer $a_type\n" unless ($a_type =~ /
     (currency|person|place|org|miscellaneous|time|dimension)/ix); 
   }
 close(IN);

 exit(0);
