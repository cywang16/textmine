#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------------------
 #*- bld_colloc.pl
 #*-  Collect the lead words for collocations   
 #*----------------------------------------------------------------
 use strict; use warnings;
 use Text::Wrap qw/$columns &wrap/;

 #*-- read the list of words
 print "Started building collocations\n";
 my %words = (); my $skip_period = '';
 open (IN, "wn_words.dat") || die ("Unable to open file wn_words $!\n");
 while (my $inline = <IN>)
  {
   chomp($inline);
   my ($word) = $inline =~ /^(.*?):.*/;
   next if ($word =~ /^[\d]/); #*-- skip number collocations
   if ($word =~ /^\.(.*)$/) 
    { $words{'.'} .= "$word "; $skip_period = 1; next; }
   if ($word =~ /(\w+?)[\/.'_-]/) 
    { my $p_word = $1;
      #*-- skip some collocations
      next if ($p_word =~ /^genus|family|order$/i); 
      $words{$p_word} .= "$word " unless ($word =~ /^capital_of/);
    }
  }
 close(IN);

 #*-- build the collocation lead words file
 open (OUT, ">co_colloc_lead.dat") || 
       die ("Unable to build colloc_lead file $! \n");
 binmode OUT, ":raw";
 my $line = '';
 foreach (sort keys %words)
  { 
    if (length($line . "$_ ") > 255)
     { print OUT ("$line:\n"); $line = "$_ "; }
    else { $line .= "$_ "; }
  }
 print OUT ("$line:\n") if ($line);
 close(OUT);

 #*-- build the collocation words file
 open (OUT, ">co_colloc.dat") || 
       die ("Unable to build colloc file $! \n");
 binmode OUT, ":raw";
 foreach my $word (sort keys %words)
  { 
   my @words = split/\s+/, $words{$word};
   (my $e_word = $word) =~ s/([:!])/!$1/g;
   $line = ''; my %dwords = ();
   foreach my $cword (sort @words)
    {
     next if ($dwords{$cword}); $dwords{$cword}++;

     #*-- count the number of non-word chars
     my $len = 0; 
     $len++ while ($cword =~ /[^a-zA-Z0-9]/g);
     $len++ while ($cword =~ /[a-zA-Z0-9]+/g);
     $cword =~ s/_/ /g;
     (my $e_cword = $cword) =~ s/([:!])/!$1/g;
     if (length($line . "$e_cword ") > 250)
      { print OUT ("$e_word:$line:\n"); $line = "$e_cword|||$len "; }
     else { $line .= "$e_cword|||$len "; }
    }
   print OUT ("$e_word:$line:\n") if ($line);
  }

 #*---------------------------------------------------------------------
 #*- scan the abbreviations table for emoticons and build collocations
 #*- and lead in chars
 #*--------------------------------------------------------------------
 my %lead_char = ();
 open (IN, "../../utils/data/co_abbrev.dat") 
      || die ("Unable to open co_abbrev.dat $!\n");
 while (my $inline = <IN>)
  { chomp($inline);
    if ($inline =~ /^(.*?):e:/ )
     { my $t_emo = my $emo = $1; 
       $t_emo =~ s/!:/:/g; $t_emo =~ s/!!/!/g; 
       my $lchar = substr($t_emo,0,1); my $len = length($t_emo);
       next unless ($len > 1);
       if ($lead_char{$lchar}) { $lead_char{$lchar} .= "$emo|||$len "; }
       else                    { $lead_char{$lchar} .= "$emo|||$len "; }
     }
  }
 close(IN);

 #*-- dump the emoticons to the collocations file
 $columns = 255;
 foreach my $lchar (sort keys %lead_char) 
  { my @out = &wrap('', '', ($lead_char{$lchar}) );
    $lchar =~ s/([:!])/!$1/;
    foreach ( split/\n/, "@out") 
     { s/([:!])/!$1/g; print OUT ("$lchar:$_:\n"); }
  }

 close(OUT);

 #*-- append the lead chars to the colloc_lead file
 open (OUT, ">>co_colloc_lead.dat") || 
       die ("Unable to build colloc_lead file $! \n");
 binmode OUT, ":raw";
 $line = '';
 foreach my $lchar (sort keys %lead_char)
  { 
    next if ( ($lchar eq '.') && $skip_period);
    $lchar =~ s/([:!])/!$1/;
    if (length($line . "$lchar ") > 255)
     { print OUT ("$line:\n"); $line = "$lchar "; }
    else { $line .= "$lchar "; }
  }
 print OUT ("$line:\n") if ($line);
 close(OUT);

 print "Finished building collocations\n";
 exit(0);
