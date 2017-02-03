
 #*--------------------------------------------------------------
 #*- Index.pm						
 #*-
 #*-    Description: A set of Perl functions to perform functions
 #*-    such as extracting tokens, creating an index, maintaining
 #*-    an index and to match text with a boolean expression
 #*--------------------------------------------------------------

 package TextMine::Index;

 use strict; use warnings;
 use Time::Local;
 use Config;
 use lib qw/../;
 use TextMine::DbCall;
 use TextMine::Tokens    qw(assemble_tokens build_stopwords);
 use TextMine::Constants qw($ISEP); 
 require Exporter;
 our @ISA =       qw(Exporter);
 our @EXPORT =    qw(content_words add_index rem_index tab_word text_match);
 our @EXPORT_OK = qw(parse_file $CHAR_LIMIT );
 use vars qw ( $CHAR_LIMIT );

 #*-- set the constants     
 BEGIN 
  { $CHAR_LIMIT = 255; }

 #*------------------------------------------------------------
 #*- break up the text into words, optionally skip
 #*- stopwords. By default stopwords will not be returned
 #*------------------------------------------------------------
 sub content_words
 {
  my ($rtext, 		#*- reference to a text string
      $ftype, 		#*- type of string (email, web, news, or '')
      $dbh, 		#*- database handle
      $skip_stopwords, 	#*- optional flag to skip stopwords 
      $hash_refs, 	#*- optional reference to tables for token extraction
      $query_words) 	#*- optional flag to handle query fuzzy words 
  = @_;
               
  #*-- set defaults
  my @words = ();
  return (\@words) unless($$rtext && $dbh); 
  $ftype  = ''     unless ($ftype);

  #*-- build the stopwords depending on the type of document     
  my %stopwords = ();
  &build_stopwords(\%stopwords, $ftype) unless ($skip_stopwords);

  #*-- get the assembled tokens
  my $add_tchars = ($query_words) ? '*': '';
  my ($rtok, $rloc) = &assemble_tokens($rtext, $dbh, $hash_refs, 
                                       undef, undef, $add_tchars);
  
  #*-- keep only the alphabetic tokens
  foreach (@$rtok)
   {
    next unless /^[a-zA-Z.$add_tchars]/; #*-- must start with alphabetic char 
    next if (length($_) < 3); 	#*-- skip short words
    next if $stopwords{lc($_)}; #*-- skip stop words 
    push(@words, $_); 
   }

  return(\@words);
 }

 #*-----------------------------------------------------------------
 #*-   return the index table for the word
 #*-----------------------------------------------------------------
 sub tab_word
  { my $table;
    $table = "_index"; #*-- set a default index table or
                       #*-- set the table depending on the 1st letter
                       # $table = '?????' if ($_[0] =~ /^[a-zA-Z]/);
    return($table);
  }

 #*-----------------------------------------------------------------
 #*-   create an index in the appropriate table
 #*-   pass the id of the document, the contents, the table prefix
 #*-   and the database handle
 #*-----------------------------------------------------------------
 sub add_index
  {
   my ($id,		#*- id associated with the passed descr. string 
       $descr, 		#*- text to be indexed
       $tab_prefix, 	#*- table prefix for the type of index
       $dbh, 		#*- database handle
       $ftype, 		#*- type of string
       $skip_stopwords	#*- optional flag to keep stopwords in the index
      ) = @_;

   my ($len, $inc_ids, $ref_val, $command, $sth, $db_msg);

   #*-- get the content words in the passed text
   my %words = ();
   $words{"\L$_"}++ 
     foreach (@{&content_words(\$descr, $ftype, $dbh, $skip_stopwords)} );
   
   #*-- split collocations into separate index words and add to hash
   foreach (keys %words)
    { next unless (/\s/);
      foreach my $word (split/\s/, $_) { $words{$word}++; }
    }

   #*-- for each content word make an index entry
   WORD: 
   foreach my $word( keys %words)
   {
    #*-- use a limit on the word length
    next if (length($word) > 35);
    my $table = $tab_prefix . &tab_word($word);
    my $e_word = $dbh->quote($word);

    #*-- check if an entry exists
    $command = "select count(*) from $table where inc_word = $e_word";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    return("Command: $command failed --> $db_msg") unless ($sth);

    #*-- if a row exists, check if there is enough space to add
    #*-- a new id in the list of entries
    if ( ($dbh->fetch_row($sth))[0] )
     { 
      $command = "select length(inc_ids), inc_ids from $table ";
      $command .= "where inc_word = $e_word";
      ($sth, $db_msg) = $dbh->execute_stmt($command);
      return("Command: $command failed --> $db_msg") unless ($sth);
      while ( ($len, $inc_ids) = $dbh->fetch_row($sth) )
       {
        if ($len < ($CHAR_LIMIT - 10) )
         {
          #*-- skip the addition of the id, if it is already present
          next WORD if ($inc_ids =~ /\b$id\b(?!$ISEP)/); 
          (my $rep_ids = $inc_ids) .= ($inc_ids =~ /\d+/) ? 
             ",$id" . $ISEP . $words{$word}: $id . $ISEP . $words{$word};
          $command  = "update $table set inc_ids = '$rep_ids' ";
          $command .= "where inc_word = $e_word and inc_ids = '$inc_ids'";
          (undef, $db_msg) = $dbh->execute_stmt($command);
          return("Command: $command failed --> $db_msg") if ($db_msg);
          next WORD;
         }
       } #*-- end of while
     } #*-- end of if

    #*-- create a new entry for the word in the index
    my $ival = $id . $ISEP . $words{$word};
    $command = "insert into $table values ($e_word, '$ival')";
    (undef, $db_msg) = $dbh->execute_stmt($command);
    return("Command: $command failed --> $db_msg") if ($db_msg);

   } #*-- end of foreach
  
  return('');

 }

 #*-----------------------------------------------------------------
 #*-   remove an index from the appropriate table
 #*-   pass the id of the document, the contents, the table prefix
 #*-   and the database handle
 #*-----------------------------------------------------------------
 sub rem_index
  {
   my ($id,		#*- id associated the descr string
       $descr,		#*- string to be indexed
       $tab_prefix,	#*- table prefix for the index of this string
       $dbh, 		#*- database handle
       $ftype,		#*- type of string
       $skip_stopwords	#*- optional flag to keep stopwords in the index
      ) = @_;

   my ($len, $inc_ids, $ref_val, $command, $sth, $db_msg);

   #*-- extract the content words from the passed text
   my %words = ();
   $words{"\L$_"}++ 
     foreach (@{&content_words(\$descr,$ftype,$dbh, $skip_stopwords)} );
   
   #*-- split collocations into separate index words and add to hash
   foreach (keys %words)
    { next unless (/\s/);
      foreach my $word (split/\s/, $_) { $words{$word}++; }
    }

   #*-- loop thru the words and delete each word from the index
   DWORD: 
   foreach my $word( keys %words)
   {
    next if (length($word) > 35);
    my $table = "$tab_prefix" . &tab_word($word);
    my $e_word = $dbh->quote($word);
    $command = "select inc_ids from $table where inc_word = $e_word";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    return("Command: $command failed --> $db_msg") unless ($sth);
    my $suffix = $ISEP . "\\d+"; my $rep_ids;
    while ( ($inc_ids) = $dbh->fetch_row($sth) )
     {
      if ($inc_ids =~ /$id . $ISEP/)
       { 
        ($rep_ids = $inc_ids) =~ s/(?:^$id$suffix,?|$id$suffix,|,$id$suffix$)//;
        $command  = ($rep_ids =~ /[\d]+/) ?
                    "update $table set inc_ids = '$rep_ids' ":
                    "delete from $table ";
        $command .= "where inc_word = $e_word and inc_ids = '$inc_ids'";
        (undef, $db_msg) = $dbh->execute_stmt($command);
        return ("Command: $command failed --> $db_msg") if ($db_msg);
        next DWORD;
       } #*-- end of if
     } #*-- end of while
   } #*-- end of foreach

   return('');

  }

 #*----------------------------------------------------------------
 #*- recursively, check if the text satisfies a boolean query
 #*----------------------------------------------------------------
 sub text_match
  {
   my ($rtext,		#*- reference to a text string
       $query_terms, 	#*- boolean query
       $fuzzy,		#*- optional fuzzy search
       $case_i,		#*- optional case sensitivity
      ) = @_;

   my (@words, @t_words,$word, $retval, $wmatches, $match_val, 
       $text, $reg, %keys, $i);

   #*-- is there sufficient text/query terms to match
   $text = $$rtext;
   return(0) if (length($text) < 2);
   return(1) unless ($query_terms);
   $query_terms =~ s/^\s+//;$query_terms =~ s/\s+$//;
   $query_terms =~ s/\s+/ /g; #*-- clean up query
   $case_i = '' unless ($case_i);

   #*-- make sure the number of parens match in the query
   my $left_paren  = 0; while ($query_terms =~ /\(/g) { $left_paren++; }
   my $right_paren = 0; while ($query_terms =~ /\)/g) { $right_paren++; }
   return(0) if ($left_paren != $right_paren); 

   #*-- process the sub-queries in parens and replace with a numeric result
   #*-- 0 or 1 and remove the sub query from the main query
   while ($query_terms =~ /\(([^()]*)\)/g)
    { $retval = &text_match(\$text, $1, $fuzzy, $case_i); 
      $query_terms =~ s/\($1\)/$retval/; } 
   return($query_terms) if ( ($query_terms =~ /^\d+$/) );

   #*-- process the boolean expressions, if any, handle the AND operator
   if ($query_terms =~ /\bAND\b/i)
    {
     @words = split(/\bAND\b/i, $query_terms); $wmatches = 0;
     foreach $word (@words)
      { return(0) if ($word =~ /^\s?0\s?$/); 
        $fuzzy++ if ($word =~ /[*]/);
        return(0) unless($match_val = 
                  &text_match(\$text, $word, $fuzzy, $case_i)); 
        $wmatches += $match_val; }
     return ( ($wmatches) ? 1:0);
    }

   if ($query_terms =~ /\bOR\b/i)
    {
     @words = split(/\bOR\b/i, $query_terms); $wmatches = 0;
     foreach $word (@words)
      { if ($word =~ /^\s?(\d+)\s?$/) { $wmatches += $1; }
        else { $fuzzy++ if ($word =~ /[*]/);
               $wmatches += &text_match(\$text, $word, $fuzzy, $case_i); } 
        return(1) if ($wmatches); }
     return ( ($wmatches) ? 1:0);
    }

   #*-- build a temporary word array containing phrases and
   #*-- other query terms
   @t_words = ();
   @words = split(/\bNOT\b/i, $query_terms); $wmatches = 0;
   for $i (0..$#words)
    {
     push (@t_words, "NOT") if ($i != $#words);
     push (@t_words, $1) while ($words[$i] =~ /"(.*?)"/g); 
     push (@t_words, $1) while ($words[$i] =~ /'(.*?)'/g);
     $words[$i] =~ s/".*?"//g; $words[$i] =~ s/'.*?'//g;
     push (@t_words, split(/\s/, $words[$i])); 
    }

   #*-- remove invalid words
   @words = ();
   for $i (0..$#t_words)
   { #*-- keep the number 0 in the array
     push(@words, $t_words[$i]) 
        if (($t_words[$i]) || ($t_words[$i] eq '0')); }

   #*-- handle the NOT
   my $word_count = 0;
   for $i (1..$#words)
    { if (defined($words[$i-1]) && $words[$i - 1] =~ /NOT/i)
       { if ($words[$i] =~ /^0|1$/) { $wmatches += ($words[$i]) ? -1: 1; }
         else 
          { $fuzzy++ if ($words[$i] =~ s/[*]/\\w\*/g);
            my $t_word = ($fuzzy) ? "$words[$i]": '\b' . "$words[$i]" . '\b';
            if ($case_i) { $wmatches++ unless ($text =~ /$t_word/);  }
            else         { $wmatches++ unless ($text =~ /$t_word/i); } 
          }
         splice(@words, ($i - 1), 2); $word_count++; }
    }

   foreach $word (@words)
    {             
      #*-- first try a strict match of the word/phrase 
      next unless($word); $word_count++;
      $fuzzy++ if ( ($word =~ s/[*]/[\\w-]\*/g) || ($word =~ /'|"/) );
      my $word_reg = ($fuzzy) ? "$word": '\b' . "$word" . '\b';
      if ($case_i) { if ($text =~ /$word_reg/s )  { $wmatches++; next; } }
      else         { if ($text =~ /$word_reg/si)  { $wmatches++; next; } }

      #*-- next try a match of the word with non-alphabetic chars such
      #*-- dash or period
      $reg = '.{1,2}'; $word =~ s/[^a-zA-Z0-9.*\\]/$reg/g;
      $word_reg = ($fuzzy) ? "$word": '\b' . "$word" . '\b';
      if ($case_i) { $wmatches++ if ($text =~ /$word_reg/s); }
      else         { $wmatches++ if ($text =~ /$word_reg/si); }
    }

   #*-- use an implicit AND for multiple words without boolean operators
   return( ($wmatches == $word_count) ? 1: 0);
  } 

 #*---------------------------------------------
 #*- Return words associated with the file name
 #*- Used for indexing files that do not have
 #*- any metadata or text
 #*----------------------------------------------
 sub parse_file
 {
  my ($file) = @_;

  my @words = ();
  while ($file =~ m%(.*?)[\\/]%g)         { push (@words, $1); }
  if    ($file =~ m%[\\/]([^\\/]*)\..*$%) { push (@words, $1); }
  elsif ($file =~ m%[\\/]([^\\/]*)$%)     { push (@words, $1); }

  #*-- clean up the words list
  my @nwords = ();
  foreach (@words)
   { 
     #*-- skip unless start with alphanumeric char
     next unless /^[0-9a-zA-Z]/; 
                                                                                
     #*-- skip drive names in Windows
     next if /^[a-zA-Z]:/;

     #*-- break on underscores
     if (/_/) { push (@nwords, split/_/, $_); }
     else     { push (@nwords, $_); }
   }
     
  return(join(' ', @nwords));
 }


1;
=head1 NAME

Index - TextMine Index Utilities

=head1 SYNOPSIS

use TextMine::Index;

=head1 DESCRIPTION

=head2 content_words
 
 Pass a reference to a text string and receive an a array
 of words. An optional file type indicates the type of
 the text (email, web, news, or null). The stopwords
 are removed from the text and the remaining content
 words are returned.

=head2 add_index

 Pass an id associated with a string, a text string, a 
 table prefix for the index, a database handle, the
 type of text string, and an optional flag to skip 
 stopwords. The content words of the text string are 
 extracted and saved with the associated id in the
 index table.

=head2 rem_index

 Pass an id associated with a string, a text string, a 
 table prefix for the index, a database handle, the
 type of text string, and an optional flag to skip 
 stopwords. The content words of the text string are 
 extracted and removed from the index table for the
 the associated id.

=head2 text_match

 Pass a reference to a string, a boolean query, and
 optional flag for a fuzzy search. A true or false
 is returned depending on whether the text matches
 the query or not.

=head1 EXAMPLE

  $text = <<"EOT";
The growing popularity of Linux in Asia, Europe, and the U.S.
is a major concern for Microsoft. It costs less than 1 USD
a month to maintain a Linux PC in Asia. By 2007, over 500,000
PCs sold in Asia maybe Linux based.
EOT

 print &text_match(\$text, 'Linux AND Asia','', 1) ?
     "Did match\n": "Did not match\n";
 print &text_match(\$text, 'linux AND Asia','', 1) ?
     "Did match\n": "Did not match\n";
 print &text_match(\$text, '"costs less"',) ?
     "Did match\n": "Did not match\n";

 generates the following output
 ----------------------------------------------------------------
 Did match
 Did not match
 Did match
 -------------------------------------------------------------------

=head1 AUTHOR

Manu Konchady <mkonchady@yahoo.com>
