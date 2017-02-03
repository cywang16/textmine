#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

#*----------------------------------------------------------------
#*- bld_dict.pl
#*-  
#*-   Summary: Read the Wordnet index and data files and create
#*-            the list of wordforms, list of synsets, list of
#*-            word form relationships, and the list of synset
#*-            relationships
#*-
#*----------------------------------------------------------------

 use strict; use warnings;
 use TextMine::Constants;
 use TextMine::WordNet qw/build_wnet_ptrs/;
 use Text::Wrap qw($columns &wrap); $columns = 256;

 print "Started bld_dict.pl\n";

 #*-- check if the WordNet env. var is set
 my $WNET_DIR = $ENV{WNHOME} . '/dict/';
 if ($WNET_DIR eq '/dict/')
   { print "Cannot find WordNet files.. check environment \n" .
           "variable WNHOME\n"; exit(0); }
 (my $ptr_symbols) = &build_wnet_ptrs(); my %ptr_symbols = %$ptr_symbols;

 #*-- compile the regex to check for pointers in a line
 local $" = '|'; my @symbols = keys %ptr_symbols;
 foreach (@symbols) { s/([._%*\@\$\^\\])/\\$1/g; }
 our $ptr_regex = qr/(@symbols)\s(\d{8})\s(.)\s(\d{4})/;
 local $" = " ";

PASS1:
 #*------------------------------------------------------------------
 #*- Pass 1
 #*-   Read the index files one line at a time and build the
 #*-   output file for the word forms. Scan the data files
 #*-   to check for entity type
 #*------------------------------------------------------------------

 #*- read the sense index into a hash. Use the hash to rank
 #*- synsets based on frequency of use.
 my %s_type = ('1' => 'n', 
               '2' => 'v',
               '3' => 'a',
               '4' => 'r',
               '5' => 'a');
 my %s_idx = ();
 my $s_file = ($OSNAME =~ /win/i) ? "sense.idx": "index.sense";
 print "Reading the $s_file.....\n";
 open (IN, "$WNET_DIR$s_file") || die ("Could not $s_file $!");
 while (my $inline = <IN>)
  { chomp($inline);
    my ($word, $type, $offset, $tag_cnt) = $inline =~
       /^(.*?)%(.).*?\s(\d{8})\s\d+\s(\d+)/;
    $s_idx{"$word!!!$s_type{$type}$offset"} = $tag_cnt; 
  }
 close(IN);

 my %skipped = ();
 open (OUT, ">wn_words.dat") || die ("Could not open words.dat $!\n");
 binmode OUT, ":raw";
 foreach my $ftype (qw/adj adv noun verb misc/)
  {
   my ($dfile, $ifile);
   if ($OSNAME =~ /win/)
    { $dfile = $ftype . ".dat"; $ifile = $ftype . ".idx"; }
   else 
    { $dfile = "data." . $ftype ; $ifile = "index." . $ftype; }
   $dfile = "$WNET_DIR$dfile" unless ($ftype eq 'misc');
   $ifile = "$WNET_DIR$ifile" unless ($ftype eq 'misc');

   my $prefix  = &get_prefix($ftype);

   open (DAT, "$dfile") || die ("Unable to open $dfile $!\n");
   open (IDX, "$ifile") || die ("Unable to open $ifile $!\n");
   while (my $inline = <IDX>)
    {
     next if ($inline =~ /^\s/); chomp($inline);

     #*-- format for index file is
     #*-- word type num_of_synsets num_pointers [num_of_pointers ptr] 
     #*-- num_of_synsets num_of_senses [num_of_synsets offset] 
     #*-- e.g. a_posteriori a 2 3 ! & ^ 2 0 00142736 00827758

     #*-- get the word, syntactic type, and offsets for the synsets
     my ($word, $pos) = $inline =~ /^(\S+)\s(.)/;

     #*-- restrict the max. length of words to 35
     if (length($word) > 35) { $skipped{$pos}++; next; }
     pos($inline) = length($word) + 2;

     my @synsets = (); push (@synsets,$1) while ($inline =~ /\G.*?(\d{8})/g);
     my $e_type; #*-- entity type flag
     my %t_sense = (); #*-- tag sense count
     foreach (@synsets)
      { 
       seek(DAT, $_, 0); my $line = <DAT>;  $_ = $prefix . $_;

       #*-- format for data file is
       #*-- 8_digit_offset 2_digit_num 1_char_code 2_char_hex_word_count 
       #*-- [word 1_digit_num] (word_count)
       (my $w_word) =
          ($line =~ /^\d{8}\s\d{2}\s.\s[0-9a-fA-F]{2}\s(\S+)\s/);

       #*-- check if it is an entity
       $e_type = 'n';
       if ($w_word)
        { if ($w_word =~ /^[A-Z]/)
           { $e_type = 'y'; }
          else
           { (my $t_word) = ($line =~ /($word)/i);
             $e_type = 'y' if ($t_word =~ /^[A-Z]/);
           }
        } #*-- end of outer if
          
       #*-- assign the tag sense count, default 0, except for misc. (1)
       $t_sense{$_} = defined($s_idx{"$word!!!$_"}) ?  $s_idx{"$word!!!$_"}: 
                      ($prefix eq 'm') ? 100: 0;
      } #*-- end of for

     @synsets = ();
     foreach (sort {$t_sense{$b} <=> $t_sense{$a}} keys %t_sense)
      { push (@synsets, $_ . '_' . $t_sense{$_}); }
     print OUT "$word:$pos:$e_type:@synsets:\n";
     
    } #*-- end of while

   close(IDX); close(DAT);
  }

 %s_idx = (); #*-- release the space
 close(OUT);
 print "Created the wordform file\n";

PASS2:
 #*------------------------------------------------------------------
 #*- Pass 2
 #*-   Read the data files one line at a time and build the
 #*-   output file for the synsets.
 #*------------------------------------------------------------------

 open (OUT, ">wn_synsets.dat") || die ("Could not open synset.dat $!\n");
 binmode OUT, ":raw";
 foreach my $ftype (qw/adj adv noun verb misc/)
  {
   my $dfile = ($OSNAME =~ /win/) ? $ftype . ".dat": "data." . $ftype;
   my $prefix  = &get_prefix($ftype);
   $dfile = "$WNET_DIR$dfile" unless ($ftype eq 'misc');

   open (DAT, "$dfile") || die ("Unable to open $dfile $!\n");
   while (my $inline = <DAT>)
    {
     next if ($inline =~ /^\s/); chomp($inline);

     (my $offset) = ($inline =~ m%^(\d{8})%);
     my @syn_words = &get_words($inline, 0);

     #*-- remove adj. syntactic markers
     s%\((?:p|a|ip)\)%%g foreach (@syn_words);

     (my $gloss) = $inline =~ m%\G.*\|(.*)$%g;
     print OUT "$prefix$offset:@syn_words:$gloss:\n";
     #if (length($gloss) < 255)
     # { print OUT "$prefix$offset:@syn_words:$gloss:\n"; }
     #else
     # { foreach my $part (split/\n/, wrap('', '', $gloss))
     #    {  print OUT "$prefix$offset:@syn_words:$part\n"; }}

    } #*-- end of while
   close(DAT);

  } #*-- end of for

 close(OUT);
 print "Created the synset file\n";

PASS3:
 #*------------------------------------------------------------------
 #*- Pass 3
 #*-   Read the data files one line at a time and build the
 #*-   output file for the relations between word forms.
 #*-   i.e. the lexical relations
 #*------------------------------------------------------------------

 #*-- get file handles for all 4 data files and save
 #*-- in the dfh hash with the prefix
 my %dfh = ();
 foreach my $ftype (qw/adj adv noun verb/)
  {
   my $prefix = &get_prefix($ftype);
   my $dfile = ($OSNAME =~ /win/) ? $ftype . ".dat": "data." . $ftype;
   open ($dfh{$prefix}, "$WNET_DIR$dfile") || 
        die ("Could'nt open $dfile $!\n"); 
   binmode $dfh{$prefix}, ":raw"; } 

 my %olines = ();
 open (OUT, ">wn_words_rel.dat") || die ("Could'nt open words_rel.dat $!\n");
 binmode OUT, ":raw";
 foreach my $ftype (qw/adj adv noun verb/)
  {
   my $dfile = ($OSNAME =~ /win/) ? $ftype . ".dat": "data." . $ftype;
   my $prefix  = &get_prefix($ftype);

   open (DAT, "$WNET_DIR$dfile") || die ("Unable to open $dfile $!\n");
   binmode DAT, ":raw";
   while (my $inline = <DAT>)
    {
     next if ($inline =~ /^\s/); chomp($inline);

     my %ptrs = &get_pointers($inline);
     foreach (keys %ptrs)
      { 
        my ($pos, $offset) = $_ =~ /^(.)(.*)$/;
        my ($ptr, $source, $target) = $ptrs{$_} =~ /^(\S+)\s(\d\d)(\d\d)/;
        next if ($source eq '00'); 
        my $word_a = &get_words($inline, $source);
        $word_a =~ s%\((?:p|a|ip)\)%%; $word_a = lc($word_a);
        my $word_b = &get_words(&get_line($dfh{$pos}, $offset), $target );
        $word_b =~ s%\((?:p|a|ip)\)%%; $word_b = lc($word_b);
        my $ptype = $ptr_symbols{$ptr};
        if ($ptr =~ /\\/)
         { $ptype = ($pos eq 'n') ? 'pertainym': 'adj._derivation'; } 
        $olines{"$word_a:$word_b:$ptype"}++ if ($word_a ne $word_b);
      } #*-- end of for

    } #*-- end of while
   close(DAT);
    
  } #*-- end of for

 close($dfh{$_}) foreach (keys %dfh);

 #*-- dump the word form pointers
 print OUT "$_\n" foreach (keys %olines);
 close(OUT);
 print "Created the word_rel file\n";

PASS4:
 #*------------------------------------------------------------------
 #*- Pass 4
 #*-   Read the data files one line at a time and build the
 #*-   output file for the relations between synsets.
 #*-   i.e. the semantic relations
 #*------------------------------------------------------------------

 #*-- get file handles for all 4 data files and save
 #*-- in the dfh hash with the prefix
 %dfh = ();
 foreach my $ftype (qw/adj adv noun verb/)
  {
   my $prefix = &get_prefix($ftype);
   my $dfile = ($OSNAME =~ /win/) ? $ftype . ".dat": "data." . $ftype;
   open ($dfh{$prefix}, "$WNET_DIR$dfile") || 
        die ("Could'nt open $dfile $!\n"); 
   binmode $dfh{$prefix}, ":raw"; } 

 open (OUT, ">wn_synsets_rel.dat") || 
      die ("Could'nt open synset_rel.dat $!\n");
 binmode OUT, ":raw";
 foreach my $ftype (qw/adj adv noun verb/)
  {
   print "Generating synset relations for $ftype....\n";
   my $dfile = ($OSNAME =~ /win/) ? $ftype . ".dat": "data." . $ftype;
   my $prefix  = &get_prefix($ftype);

   my %olines = ();
   open (DAT, "$WNET_DIR$dfile") || die ("Unable to open $dfile $!\n");
   binmode DAT, ":raw";
   while (my $inline = <DAT>)
    {
     next if ($inline =~ /^\s/); chomp($inline);
     (my $s_offset) = $inline =~ /^(\d{8})/; $s_offset = $prefix . $s_offset;

     my %ptrs = &get_pointers($inline);
     foreach (keys %ptrs)
      { 
       my ($ptr, $source) = $ptrs{$_} =~ /^(\S+)\s(\d\d)/;
       next unless ($source eq '00'); 
       my $ptype = $ptr_symbols{$ptr};
       if ($ptype =~ / or /)
        { $ptype =~ s/ or.*$//  if ($prefix eq 'n'); 
          $ptype =~ s/^.* or // if ($prefix eq 'a'); }
       $olines{"$s_offset:$_:$ptype"}++ if ($s_offset ne $_);
      } #*-- end of for
    } #*-- end of while
   close(DAT);

   #*-- dump the synset pointers
   print OUT "$_\n" foreach (keys %olines);
    
  } #*-- end of for

 close($dfh{$_}) foreach (keys %dfh);
 close(OUT);
 print "Created the synset_rel file\n";

EXIT:

 print "Ended bld_dict.pl\n";
 exit(0);

 #*------------------------------------------------------
 #*- return a prefix depending on the type of the file
 #*------------------------------------------------------
 sub get_prefix
 {

   $_ = $_[0]; my $prefix = '';
   PREFIX: 
   {  /^adj/  && do { $prefix = 'a'; last PREFIX; };
      /^adv/  && do { $prefix = 'r'; last PREFIX; };
      /^noun/ && do { $prefix = 'n'; last PREFIX; };
      /^verb/ && do { $prefix = 'v'; last PREFIX; };
      /^misc/ && do { $prefix = 'm'; last PREFIX; };}
   return($prefix);
 }


 #*-----------------------------------------------------------
 #*- return the words for the synset line or a specific word
 #*- if an index into the synset is passed
 #*-----------------------------------------------------------
 sub get_words
 {
  my ($line, $index) = @_;
  (my $w_count) = ($line =~ m%^\d{8}\s\d{2}\s.\s([0-9a-fA-F]{2})%) ?
                  (hex($1)):('00');
  if ($w_count eq '00') { print "Bad line: $line\n"; exit(0); }

  my @syn_words = (); pos($line) = 16;
  for (my $i = 0; $i < $w_count; $i++)
   { push (@syn_words, $1) if ($line =~ /\G.*?(\S+)\s[0-9a-fA-F]/g); }

  return(@syn_words) unless ($index);
  return ( (0 < $index) && ($index <= @syn_words) ?
           $syn_words[$index-1]: @syn_words );
 }

 #*-----------------------------------------------------------
 #*- return the pointers and offsets for the line
 #*-----------------------------------------------------------
 sub get_pointers
 { my %ptr = ();
   $ptr{$3 . $2} = "$1 $4" while ($_[0] =~ /$ptr_regex/g); 
   return(%ptr); }

 #*-----------------------------------------------------------
 #*- Get the line from the data file at the passed offset
 #*-----------------------------------------------------------
 sub get_line (*$)
 { my ($fh, $offset) = @_;
   seek($fh, $offset, 0); my $inline = <$fh>;
   return ($inline); }
