
 #*--------------------------------------------------------------
 #*- Summary.pm						
 #*- Description: A Perl function to summarize text
 #*--------------------------------------------------------------

 package TextMine::Summary;

 use strict; use warnings;
 use Config;
 use lib qw/../;
 use TextMine::Constants qw/E_CONSTANT/;
 use TextMine::Index     qw/content_words/;
 use TextMine::Pos	 qw/pos_tagger/;
 use TextMine::Tokens    qw/tokens assemble_tokens build_stopwords
                            load_token_tables stem/;
 use TextMine::WordUtil  qw/gen_vector sim_val text_split/;
 use TextMine::WordNet   qw/similar_words/;
 use TextMine::Utils	 qw/log2 factorial combo/;
 use TextMine::DbCall;
 use TextMine::Cluster;
 require Exporter;
 our @ISA = qw(Exporter);
 our @EXPORT = qw(summary phrases_ex);
 our @EXPORT_OK = qw(snippeter); 

 #*------------------------------------------------------------
 #*- summaryize the text  
 #*-   Input: Text, type of text, and type of summary
 #*-   Output: A summary string
 #*------------------------------------------------------------
 sub summary
 {
  my ($rtext,	  #*-- reference to text to be summarized
      $ftype, 	  #*-- type of text (emai, web, news or '')
      $dbh,	  #*-- database handle
      $hilite,	  #*-- optional flag to highlight key tokens in text
      $s_size,	  #*-- optional size of summary (no. of sentences)
      $hash_refs, #*-- optional reference to token tables
      $debug	  #*-- optional debug flag
     ) = @_;

  #*-- set the default values
  return('')       unless ($dbh);
  $s_size = 3      unless ($s_size); 
  $ftype = ''      unless($ftype); 
  my $text = $$rtext; 
  return(' ')      unless (length($text) > 50);
  $hash_refs = &load_token_tables($dbh) unless ($hash_refs);

  #*-- split the text into chunks depending on the type 
  my ($r_tchunks, $r_ranks) = &text_split($rtext, $ftype, $dbh);
  my @tchunks = @$r_tchunks; my @ranks = @$r_ranks;

  #*-- limit the number of summary sentences
  $s_size = ($s_size > (@tchunks / 2) ) ? int (@tchunks / 2): $s_size;

  #*-- build the docs array to pass to the clustering routine
  my @e_cdocs = my @cdocs = ();
  for my $i (0..$#tchunks) 
   { my $start = $i ? ($tchunks[$i-1] + 1): 0; my $end = $tchunks[$i];
     my $ctext = substr($text, $start, $end - $start + 1); 
     push (@cdocs, \"$ctext");  
     
     #*-- expand the text for full summaries
     my $s_words = my $ref_val = my $ex_ctext = $ctext;
     foreach my $pword (
             @{&content_words(\$ctext, $ftype, $dbh,'', $hash_refs)})
      { foreach (&similar_words($pword, $dbh))  
          { $_ = lc($_); $_ =~ s/_/ /g; $ex_ctext .= "$_ "} 
      } #*-- end of outer for
     push (@e_cdocs, \"$ex_ctext"); 
   } 

  #*-- compute the clusters
  my @clusters = @{my $ref_val = 
          &cluster(\@e_cdocs, 'fre', $dbh, $ftype, 'one_link', 0.10, $debug)};

  #*-- create the centroids for each cluster except misc.
  my @centroids = ();
  for my $i (0..$#clusters) 
   {
    #*-- skip the misc. cluster
    if ($i == $#clusters) { $centroids[$i] = ''; next; }

    #*-- combine the text of the cluster member documents
    my $ctext = ''; 
    foreach (split/,/, $clusters[$i]) { $ctext .= ${$cdocs[$_]}; }

    #*-- create a vector from the text
    my %vector = &gen_vector(\$ctext, 'idf', $ftype, $dbh);
    $centroids[$i] = \%vector;
    
   } #*-- end of for

  #*-- find the list of key sentences for each cluster
  #*-- and save in a hash
  my $s_num = 0; my %k_sentences = ();
  while ($s_num < $s_size)
   {

    #*-- loop through each cluster
    for my $i (0..$#clusters) 
     {

      my $max_sim = my $max_ind = -1; 
      #*-- handle the miscellaneous cluster separately
      if ($i == $#clusters)
       {
        FLOOP: foreach my $ind (split/,/, $clusters[$i])
         { 
          next if ($k_sentences{"$i!$ind"});
          $max_ind = $ind; last FLOOP;
         }
       }
      #*-- compare each member document with the centroid and find
      #*-- the document (sentence) most similar to the centroid
      else
       {
        foreach my $ind (split/,/, $clusters[$i])
         { 
          next if ($k_sentences{"$i!$ind"});
          my %vector = &gen_vector($cdocs[$ind], 'idf', $ftype, $dbh);
          my $sim_v = &sim_val(\%vector, $centroids[$i]) + $ranks[$ind];
          if ($max_sim < $sim_v) { $max_sim = $sim_v; $max_ind = $ind; }
         }
       } #*-- end of if
      
      if ($max_ind > -1)
       { $k_sentences{"$i!$max_ind"}++; $s_num++; }
      
     } #*-- end of outer for

    } #*-- end of while


  #*-- order the sentences by cluster for coherence
  my @key_sentence = ();
  foreach my $kval (sort { $a cmp $b } keys %k_sentences )
   { 
    my ($cnum, $ind) = split /!/, $kval;
    push (@key_sentence, ${$cdocs[$ind]});
   }

  #*-- clean up the key sentences
  foreach (@key_sentence) { s/^\s+//; s/\s+$//; s/\n/ /g; }

  #*-- build the summary using the key sentences
  my $summary = '';
  foreach my $i (0..($#key_sentence-1))
   { $summary .= $key_sentence[$i] . "<br>"; 
     last if ($i == ($s_size - 1) );  
   } #*-- end of foreach

  #*-- as a last resort, return the first sentence
  unless ($summary) { $summary = ${$cdocs[0]}; }
  return($summary);

 }

 #*------------------------------------------------------------
 #*- Return snippets of text using the keywords provided
 #*------------------------------------------------------------
 sub snippeter
 {
  my ($rtext,	#*-- reference to text from which to extract snippets
      $rwords,	#*-- keywords for locating snippets
      $hilite,	#*-- optional highlight keywords in text
      $length	#*-- length of snippet
     ) = @_;
  
  #*-- set the defaults
  my @words = @$rwords; my $text = $$rtext;
  $length = 60 unless($length); $hilite = '' unless ($hilite);
  return('') unless($text && @words);

  local $" = ' '; my @snippets = (); $length /= 2; 
  foreach my $word (@words)
   {
    #*-- find a matching word in the text and extract a window
    #*-- of text before and after the word
    my $q_word = quotemeta $word;
    while ( $text =~ /\b(.{1,$length}$q_word.{1,$length})\b/sig)
     { (my $snippet = $1) =~ s/[\cM\n]/ /g; my $max_overlap = 0;

       #*-- avoid overlapping sentences, the same parts of
       #*-- a sentence maybe repeated for a sentence containing
       #*-- more than 1 keyword
       foreach (@snippets)
        { my $overlap = &overlap($_, $snippet); 
          $max_overlap = $overlap if ($overlap > $max_overlap); }
       push (@snippets, "...$snippet...") if ($max_overlap < 0.25); 
       last if (@snippets == 5); }
   } #*-- end of foreach my word

  #*-- highlight keywords, if necessary
  if ($hilite)
   { my $last_word = ($#words > 10) ? 10: $#words; 
     foreach my $word (@words[0..$last_word])
      { my $q_word = quotemeta $word;
        for my $i (0..$#snippets)
         { $snippets[$i] =~ 
            s%\b($q_word)\b%<font color=darkred>$1</font>%sig; }
      } #*-- end of outer for
   } #*-- end of if

  return(@snippets);

 }

 #*------------------------------------------------------------
 #*- Return the degree of overlap between 2 strings
 #*- 1.0 means identitical strings and 0.0 means no overlap
 #*------------------------------------------------------------
 sub overlap
 {
  my ($str1, $str2) = @_;
  return(0) unless ($str1 && $str2);

  (my $rwords1) = &tokens(\$str1); (my $rwords2) = &tokens(\$str2);
  my @words1 = @$rwords1; my @words2 = @$rwords2;
  my $max_overlap = 0;
  for my $i (0..$#words1)
   {
    #*-- find all locations in string 2 with the same word from string 1
    my @locs = ();
    for my $j (0..$#words2)
     { push (@locs, $j) if ($words1[$i] eq $words2[$j]); }

    my $max_len = 0;
    for my $j (0..$#locs)
     { 
      my $l = 1; my $len = 1;
      for (my $k = $locs[$j]+1; $k < @words2; $k++)
       { last unless ($words2[$k] && $words1[$i+$l]);
         if ($words2[$k] eq $words1[$i+$l]) {$len++; $l++; next; }
         last; }
      $max_len = $len if ($len > $max_len);
     } #*-- end of for j

    $max_overlap = $max_len if ($max_len > $max_overlap);
   } #*-- end of for i

  $max_overlap /= (@words1 > @words2) ? @words2: @words1;
  return($max_overlap);
 }

 #*---------------------------------------------------------
 #*-  Phrase Extractor           
 #*-  Extract phrases from the passed text and return
 #*-  an array of phrases
 #*---------------------------------------------------------
 sub phrases_ex 
 {
  my ($rtext,		#*-- reference to text string 
      $max_phrases,	#*-- max. number of phrases
      $dbh,		#*-- database handle
      $use_pos,		#*-- optional flag for phrases using POS
      $dtype,		#*-- optional distribution type for computing
			#*-- phrases
      $r_keys		#*-- optional keywords for selecting phrases
     ) = @_;
  
  #*-- set default values
  return('')          unless($rtext && $dbh); 
  $max_phrases = 10   unless ($max_phrases);
  $dtype = 'binomial' unless ($dtype);
  my @keywords = ($r_keys) ? @$r_keys: ();

  #*-- get the parts of speech and words
  my (@words, @tag, @stems); my %stopwords = ();
  if ($use_pos)
   { my ($rwords, undef, $rtype) = &pos_tagger($rtext, $dbh, '', 1);
     @words = @$rwords; @tag = @$rtype; }
  else
   { my ($rt) = &assemble_tokens($rtext, $dbh); 
     @words = @$rt; @tag = (' ') x @words; 
     &build_stopwords(\%stopwords); 
     @stems = @{&stem(@words)};
   }
  return('') unless(@words);

  #*-- create hash of bigram locations
  my %bigrams = my %wcount = ();
  for my $i (0..($#words-1))
   { 
    #*-- skip bigrams starting with non-alphabetic chars
    $wcount{lc($words[$i])}++;
    next if (($words[$i]   =~ /^[^a-zA-Z]/) || 
             ($words[$i+1] =~ /^[^a-zA-Z0-9]/));  

    #*-- skip bigrams with short words
    next if ( (length($words[$i]) < 2) || (length($words[$i+1]) < 2) );

    if ($use_pos)
     { #*-- skip bigrams which are not Adj.- Noun or Noun - Noun
       next unless ( ($tag[$i] =~ /[an]/) && ($tag[$i+1] =~ /[n]/) ); }
    else
     { #*-- skip bigrams that start with lower case or are stopwords
       next if ($stopwords{"\L$words[$i]"} || $stopwords{"\L$words[$i+1]"});
       next if ($stopwords{"\L$stems[$i]"} || $stopwords{"\L$stems[$i+1]"});
       next unless ($words[$i] =~ /^[A-Z]/); }

    #*-- count the freq. of words and bigrams
    $bigrams{lc("$words[$i]!!!$words[$i+1]")}++; 

   } #*-- end of for

  #*-- count the last word
  $wcount{lc($words[$#words])} += ($words[$#words] =~ /^[A-Z]/) ? 2: 1;

  #*-- loop thru bigrams and create weights
  my $N = @words; my %bweight = ();
  foreach my $bword (keys %bigrams)
   {
    my ($word1, $word2) = $bword =~ /^(.*?)!!!(.*?)$/; 

    #*-- compute the weight of the bigrams
    $bweight{$bword} = ($wcount{$word1} / $N)                               *
     &lratio($wcount{$word1},$wcount{$word2}, $bigrams{$bword}, $N, $dtype) *
     $bigrams{$bword};

    #*-- assign a higher weight for bigrams with keywords
    foreach (@keywords) 
     { $bweight{$bword} *= 20.00 if ($_ && $bword =~ /\b$_\b/i); }
   }

  #*-- form a new truncated bigram array in rank order
  %bigrams = (); my $i = 0; my %new_bigrams = (); my %seen = ();
  foreach my $key (sort {$bweight{$b} <=> $bweight{$a}} keys %bweight)
   { 
     (my $word1, my $word2) = $key =~ /^(.*?)!!!(.*)$/;
     next if ($seen{$word1}); $seen{$word1}++;
     $new_bigrams{$key} = $bigrams{$key} = $bweight{$key}; 
   }  

  #*-- highlight phrases in the text
  my $start_tag = '<font color=red size=+1>'; my $end_tag = '</font>';
  for my $i (0..($#words - 1))
   {
    my $bkey = lc($words[$i]) . '!!!' . lc($words[$i+1]);
    if ($bigrams{$bkey})
     { $words[$i]   = "$start_tag $words[$i]";
       $words[$i+1] = "$words[$i+1] $end_tag"; }
   }
  my $text = "@words";

  #*-- combine bigrams, if possible till done
  my ($done, $phrase);
  do
   { $done = 1; 
     foreach my $bword1 (keys %bigrams)
     {
      (my $word1, my $word2) = $bword1 =~ /^(.*?)!!!(.*)$/;
      foreach my $bword2 (keys %bigrams)
       {
        (my $word3, my $word4) = $bword2 =~ /^(.*)!!!(.*?)$/;
        next unless ($word3 eq $word2);
        ($phrase = join('\s+', $word1, $word2, $word4)) =~ s/!!!/\\s+/g;
        if ($$rtext =~ /$phrase/si)
         { $new_bigrams{"$word1!!!$word2!!!$word4"} = 
                   ($bigrams{$bword1} + $bigrams{$bword2}) / 2.0; 
           delete($new_bigrams{$bword1}); delete($new_bigrams{$bword2}); 
           $done = 0; } 
       } #*-- end of inner for
     } #*-- end of outer for
     %bigrams = %new_bigrams;
   } while (!$done);

  #*-- create the phrases and make leading letters upper case
  my @phrases = (); $i = 0;
  foreach (sort {$new_bigrams{$b} <=> $new_bigrams{$a}} keys %new_bigrams) 
    { s/!!!/ /g; s/(^|\s+)(.)/$1 . ucfirst($2)/eg; push (@phrases, $_);
      last if (++$i == $max_phrases); }
  return(\@phrases, \$text);
  
 }

 #*---------------------------------------------------------
 #*- lratio
 #*-   Compute the likelihood ratio for Word 1 Word 2 
 #*-   c1: The number of occurrences of the word 1 in text
 #*-   c2: The number of occurrences of the word 2 in text
 #*-   c12: The number of occurrences of the 'word1 word2' in text
 #*-   N: The number of words in text
 #*-   d: The type of distribution (Binomial or Poisson)
 #*---------------------------------------------------------
 sub lratio
 {
  my ($c1, $c2, $c12, $N, $d) = @_;
  
  #*-- check parameters for validity
  return(0) unless ($N && $c1 && $c2 && $c12 && 
                   ($N > $c1) && ($c2 >= $c12));
  #*-- compute p(w1), p(w2) and p(w2 | w1)
  my $p = $c2 / $N; my $p1 = $c12 / $c1; my $p2 = ($c2 - $c12) / ($N - $c1);

  #*-- compute the ratio of the product of likelihoods
  my $numer = &lhood($c12, $c1, $p, $d) * &lhood($c2-$c12, $N-$c1, $p, $d);
  my $denom = &lhood($c12, $c1, $p1,$d) * &lhood($c2-$c12, $N-$c1, $p2,$d);
  return(0) unless ($numer && $denom);
  return ( (-2.0 * &log2( $numer / $denom ) ) );

 }

 #*---------------------------------------------------------
 #*- lhood
 #*-   Compute the likelihood of k, n, p
 #*-   The numbers maybe large for a binomial distribution
 #*-   The Poisson distribution will work in such cases
 #*---------------------------------------------------------
 sub lhood
 {
  my ($k,	#*-- no. of occurrences
      $n,	#*-- total number
      $p,	#*-- probability 
      $d	#*-- optional distribution type (poisson or binomial
     ) = @_;

  my $result;
  $d = 'poisson' if ($n > 100); #*-- use the Poisson approximation for large n 
  if ($d && ($d =~ /poisson/i) )
   { my $lambda = $n * $p;
     $result = (E_CONSTANT ** (-$lambda) * ($lambda ** $k) ) /
                 &factorial($k); }
  else #*-- binomial distribution
   { $result = ($p ** $k) * ( (1.0 - $p) ** ($n - $k) ); 
     $result *= &combo($n, $k);
   }

  $result = 0 if ($result =~ /IN(?:D|F)/); #*-- handle overflow
  return($result);
 }

1;
=head1 NAME

 Summary - TextMine Summarizer

=head1 SYNOPSIS

 use TextMine::Summary;

=head1 DESCRIPTION

=head2 summary

 Accept a reference to a text string, the type of text string,
 the summary type (brief or full), a flag to highlight keywords,
 the number of sentences and a debug flag. A summary is returned.

 The summarizer breaks the text into chunks using the text_split
 function. The content words of each text chunk are expanded
 using the similar words function. The text chunks are clustered.
 For each cluster, the document (text chunk) closest to the
 centroid is found and returned. 

 If the summary is brief, then only snippets of the text chunk
 centered around centroid keywords are returned.

=head3 Example

  $text = <<"EOT";
Eastman Kodak Co said it is introducing
four information technology systems that will be led by today's
highest-capacity system for data storage and retrieval.
    The company said information management products will be
the focus of a multi-mln dlr business-to-business
communications campaign under the threme "The New Vision of
Kodak."
........ text omitted ......

EOT

 print ("Full summary:\n");
 $summary = &summary(\$text, 'news', 'Full', 0, 2);
 @summary = split/<br>/, $summary;
 print "@summary\n\n";

 generates
------------------------------------------------------------
Full summary:
Eastman Kodak Co said it is introducing four information technology 
systems that will be led by today's highest-capacity system for 
data storage and retrieval.

Using one or two 12-inch manually loaded optical disk drives, 
it will sell for about 150,000 dlrs with deliveries beginning in mid-year.
------------------------------------------------------------

 and
 print ("Brief summary:\n");
 $summary = &summary(\$text, 'news', 'Brief', 0, 4);
 @summary = split/<br>/, $summary;
 print "@summary\n\n";

 generates
-------------------------------------------------------------
Brief summary:
... four information technology systems that will be led by today's ...
...highest-capacity system for data storage and ...
...Eastman Kodak Co said it is introducing ...
... to sell in the 700,000 dlr range...
-------------------------------------------------------------

=head2 phrases_ex

 Extract key phrases from the text. Order the phrases by
 importance in text based on frequency and type.

=head3 Example

 $text = <<"EOT";

Sun imagines world of virtual servers
By Stephen Shankland CNET News.com

SAN FRANCISCO--Sun Microsystems uncloaked "N1" on Thursday, a stealth 
project that the company hopes will ease operations at data centers 
filled with servers and storage systems.

As first reported by CNET News.com, the N1 project is an attempt to 
"virtualize" computing equipment, making servers and storage look 
like giant pools of resources with computing processes swimming within.

Sun Chief Technology Officer Greg Papadopoulos unveiled the concept 
Thursday at the company's analyst conference here. Essentially, N1 
describes what happens when a network of computers and storage systems 
is assembled into a much larger whole. "This is just like what an 
operating system did for a computer over the last 20 years. It's all 
the stuff we did in Unix and redid in Linux," he said.

The concept resembles efforts under way at some of Sun's biggest 
competitors. IBM is working on "grid" computing that unites servers 
and storage into a large pool. Grid computing grew out of academia, 
though, and focuses more on mathematical calculations than the business 
processes at the heart of N1.

Compaq Computer also is a fan of grid computing, and Sun itself has 
released its own grid software as an open-source project. Meanwhile, 
Hewlett-Packard has its own planetary computing initiative similar to 
the grid efforts.

Research group

IDC terms the concept behind N1 "service-centric infrastructure," said 
analyst Vernon Turner. "You won't organize boxes anymore, you'll 
organize resources." Papadopoulos said the trend is starting in storage. 
Some computing jobs require lots of storage, but others require little. 
When each server comes with its own directly attached storage system, 
some space goes unused, depending on the job. Through virtualization, 
storage space is pooled so its storage can be used more efficiently.
The next stage after storage will be to create a virtual world for 
computing resources, Papadopoulos said. In vogue today is a 
combination of large and small servers for data centers. The small, 
inexpensive "edge" servers handle chores such as sending 
Web pages or audio streams. And in the heart of the data center are 
large, expensive symmetric multiprocessing servers with 
many CPUs (central processing units) and high-end features.

N1 will understand all the components of this data center, 
Papadopoulos said. With it, administrators will be able to allocate 
more computing power to important tasks and better manage less important 
ones, a process similar in concept to the way high-end Unix servers 
and mainframes can be partitioned so they can run several jobs with 
shifting priorities.

But to fulfill the promise of N1, Sun will have to deal with computing 
hardware from other companies, Turner said. It's likely computing 
processes themselves will run using Sun's Java software and the 
industry-favored XML (Extensible Markup Language) data description 
language, because those technologies work well across different 
companies' products. But a company's data center is likely to be 
populated with many different companies' hardware.

Sun is well aware of this reality. Java runs on any major server, 
while Sun is working to spread its Sun One software plan to Linux. 
Additionally, the company sells software that enables sophisticated 
data-protection features that work with any storage system.

N1 has the potential to work on mammoth computing systems, Papadopoulos 
said. "This doesn't stop at hundreds of processors," he said, but 
rather spans all the way up to tens of thousands of CPUs as well as 
petabytes and exabytes of storage.

These mammoth systems will be needed to match the computing demand 
imposed by all the network-enabled devices Sun expects.  There are 
about 100 million desktop computers and servers in existence, but 
Papadopoulus expects about 100 billion Internet-enabled cell phones, 
cars, appliances and other devices soon, with about 100 trillion 
Internet-enabled thermostats, mail packages, articles of clothing 
and other devices in the more remote future.
EOT

 print (" Phrases w/o POS\n\n");
 ($r1, $r2) = &phrases_ex(\$text, 10, $dbh);
 foreach (@$r1) { print ("\t: $_\n"); }
 print ("----------------------------------------\n\n");

 generates
 
------------------------------------------------------------------
 Phrases w/o POS

        : N1 Project
        : Sun Microsystems Uncloaked
        : Sun's Java Software
        : Papadopoulus Expects
        : Vernon Turner
        : Compaq Computer
        : Grid Computing
        : Chief Technology Officer Greg Papadopoulos Unveiled
        : Unix Servers
        : Stephen Shankland Cnet News.com San Francisco
------------------------------------------------------------------

=head1 AUTHOR

Manu Konchady <mkonchady@yahoo.com>
