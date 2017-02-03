#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
 #*----------------------------------------------------------------
 #*- wn_dict.pl
 #*-  
 #*-   Summary: A Wordnet based dictionary       
 #*----------------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Utils qw(clean_array parse_parms mod_session url_encode log10);
 use TextMine::Constants qw($CGI_DIR $DB_NAME $ICON_DIR);
 use TextMine::WordNet qw(in_dictionary dtable get_synset_words base_words);

 #*-- set the constants
 use vars (
  '$dbh',		#*-- database handle
  '$sth',		#*-- statement handle
  '$db_msg',		#*-- database error message
  '$command',		#*-- SQL command field
  '$FORM',		#*-- name of form
  '%in',		#*-- hash for form fields
  '$e_session',		#*-- URL encoded session field
  '$body_html',		#*-- body of HTML page
  '$ref_val',		#*-- reference variable
  '$stat_msg',		#*-- status message for page
  '$word'		#*-- search word for dictionary
  );

 #*-- retrieve and set variables
 &set_vars();

 #*-- handle the options
 &handle_new()    if ($in{opshun} eq 'New');
 &handle_search() if ($in{opshun} eq 'Search');
 &handle_expand() if ($in{opshun} eq 'Expand');

 #*-- dump the header, body and tail html 
 &head_html(); &body_html(); &tail_html(); 

 exit(0);

 #*-----------------------------------------------------
 #*- Set some global vars            
 #*-----------------------------------------------------
 sub set_vars
 {
  #*-- retrieve the passed parameters
  $0 =~ s%.*[/\\]%%; $FORM = "$CGI_DIR" . "$0";
  %in    = %{$ref_val = &parse_parms};

  #*-- establish a DB connection
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $in{userid}, 'Password' => $in{password},
       'Dbname' => $DB_NAME);
  &quit("Could not establish DB connection: $db_msg") if ($db_msg);

  #*-- set the forgetful parms
  $in{opshun} = 'New' unless (defined($in{opshun}));
  $body_html = $stat_msg = '';
  &mod_session($dbh, $in{session}, 'del', 'opshun' );

  #*-- set some variables
  $e_session = &url_encode($in{session});
  $word = ($in{word}) ? lc($in{word}): ''; 
  $word =~ s/^\s+//; $word =~ s/\s+$//; $word =~ s/\s+/_/g;
 }

 #*---------------------------------------------------------------
 #*- Fill in fields for startup    
 #*---------------------------------------------------------------
 sub handle_new
 {
  $stat_msg = 'Enter a word and press Search';
  $in{word} = '';
 }

 #*---------------------------------------------------------------
 #*- Seach in the dictionary for the word
 #*---------------------------------------------------------------
 sub handle_search
 {

  #*-- first check if the word exists in the dictionary
  $body_html = '';
  unless (&in_dictionary($word, $dbh))
   { $stat_msg = "The word $word does not exist in the dictionary"; 
     return unless ($word); 
     
     #*-- look for at least 10 'similar' words
     my $i = 0;
     my %words = (); my $num_words = 0;
     while ($num_words < 10)
      {
       my $dword = $word . '%';
       $command = "select wnc_word from " . (&dtable($word))[0] . 
                  " where wnc_word LIKE '$dword'";
       ($sth, $db_msg) = $dbh->execute_stmt($command);
       return("Command: $command failed --> $db_msg") unless ($sth);
       while (my ($wnc_word) = $dbh->fetch_row($sth)) 
        { $words{$wnc_word}++; $num_words = keys %words;
          last if ($num_words >= 12); } 
       $word =~ s/.$//;      #*-- strip the last character and try again
       last if ($i++ == 10); #*-- avoid infinite loop
      } #*-- end of while
     $body_html = '<table border=0 cellspacing=2 cellpadding=2 width=80%>';
     $body_html .= "<tr> <td bgcolor=lightyellow align=left colspan=4> " .
       "<font color=darkred  size=4> Alternate Words: </font> </tr> <tr>";
     my $r_count = 1;
     foreach (keys %words)
      { 
       my $e_word = &url_encode($_); 
       $body_html .= << "EOT"; 
       <td bgcolor=lightyellow align=left>
       <a href=$FORM?word=$e_word&session=$e_session&opshun=Search> 
       <font color=darkblue size=4> $_ </font>  </a> <br> </td>
EOT
       $body_html .= "</tr><tr> " unless ($r_count++ % 4);
      }
     $body_html .= "</table>";
     return;
   }

  #*-- get all the synsets for the word
  my @synsets = ();
  $command = "select wnc_pos, wnc_synsets from " . (&dtable($word))[0] . 
             " where wnc_word = " . $dbh->quote($word);
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  return("Command: $command failed --> $db_msg") unless ($sth);

  $body_html = '<table border=0 cellspacing=2 cellpadding=2 width=80%>';
  my $sense = 1; 
  while (my ($pos, $synsets) = $dbh->fetch_row($sth)) 
   {  

    #*-- get the POS type and expand the abbreviation
    my $tpos = &tran_pos($pos);
    $body_html .= <<"EOF";
     <tr>
       <td bgcolor=lightyellow align=left> 
         <font color=darkred size=4> $tpos </td>
     </tr>
EOF

    #*-- get the words and examples assoc. with each synset
    foreach (split/\s+/, $synsets)
     { 
      #*-- must be in synset format
      next unless (/^([marvn]\d{8}).(\d+)/); 
      my ($synset, $tag) = ($1, $2);

      $command = "select wnc_words, wnc_gloss from wn_synsets where " .
                 "wnc_synset = '$synset'";
      (my $ssth, $db_msg) = $dbh->execute_stmt($command);
      return("Command: $command failed --> $db_msg") unless ($ssth);
      my ($words, $gloss) = $dbh->fetch_row($ssth);
      push (@synsets, $synset);
      foreach (split/\s+/, $words)
       { $gloss =~ s%\b$_\b%<font color=red>$_</font>%g; }
      $words =~ s/ /, /g; $words =~ s/_/ /g;
      $words = "($tag) $words" if ($tag);
    
      $body_html .= <<"EOF";
       <tr>
         <td bgcolor=lightyellow align=left> 
           <font color=darkred  size=3> Sense $sense: 
           <font color=darkblue size=4> $words </td>
       </tr>

       <tr>
         <td bgcolor=lightblue> 
           <font color=darkred  size=3> Description: 
           <font color=darkblue size=4> $gloss </td>
       </tr>

EOF
      $sense++;
     } #*-- end of for
   } #*-- end of while

  #*-- if we did'nt find any words in the table, then try the base words
  if ($sense == 1)
   {
    my %base_words = &base_words($word, $dbh);
    my $base_words = '';
    foreach (keys %base_words)
     { my $e_word = &url_encode($_); 
       $base_words .= 
        "<a href=$FORM?word=$e_word&session=$e_session&opshun=Search> $_ " . 
                      " </a> <br>"; }

    $body_html .= <<"EOF";
       <tr>
         <td bgcolor=lightyellow align=left> 
           <font color=darkred  size=3> Try: </font> <br>
           <font color=darkblue size=4> 
           $base_words </td>
       </tr>
EOF
    
   } #*-- end of if


  unless ($in{opshun} eq 'Expand')
   {
    $body_html .= << "EOF";
    <tr>
      <td align=center colspan=2><br>
       <input type=submit name=opshun value=Expand>
      </td>
    </tr>

    </table>
EOF
    }

  return(@synsets); 
 }

 #*---------------------------------------------------------------
 #*- Get the expanded version of the word
 #*---------------------------------------------------------------
 sub handle_expand
 {

  #*-- first do the search and get the synsets for the word
  my @synsets = &handle_search(); my %relations = ();
 
  #*--------------------------------------------------------------
  #*-- find all word relationships in which the word participates
  #*--------------------------------------------------------------
  $command = "select wnc_word_a, wnc_word_b, wnc_rel from wn_words_rel " .
             "where wnc_word_a = '$word'";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  return("Command: $command failed --> $db_msg") unless ($sth);
  while ( my ($word_a, $word_b, $rel) = $dbh->fetch_row($sth) )
   {
    my $r_word = ($word eq $word_a) ? $word_b: $word_a;
    $relations{$rel} .= " $r_word";
   } #*-- end of while

  #*--------------------------------------------------------------
  #*-- find all synset relationships in which the word participates
  #*--------------------------------------------------------------
  foreach my $synset (@synsets)
   {
    $command = "select wnc_synset_a, wnc_synset_b, wnc_rel from " .
               "wn_synsets_rel where wnc_synset_a = '$synset'";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    return("Command: $command failed --> $db_msg") unless ($sth);
    while ( my ($synset_a, $synset_b, $rel) = $dbh->fetch_row($sth) )
     {
      my $r_synset = ($synset eq $synset_a) ? $synset_b: $synset_a;
      my $words = &get_synset_words($r_synset, $dbh);
      $relations{$rel} .= " $words";
     } #*-- end of while
   } #*-- end of for

  #*-- dump the results
  $body_html .= <<"EOF";
       <tr>
         <td bgcolor=lightyellow align=left colspan=2> 
           <font color=darkred  size=4> Relationships for $in{word}: </td>
       </tr>
EOF
  foreach my $rel (sort keys %relations)
   {
    my $words = $relations{$rel};
    $words =~ s/^\s+//; $words =~ s/\s+$//; $words =~ s/\s+/ /g;

    #*-- remove dups from the words
    my @words = &clean_array(split/\s+/, $words);
    $words = join(', ', @words); $words =~ s/_/ /g; 
    
    #*-- remove dups in the list
    my $suffix = ($rel =~ /^(also_see|similar_to)$/i) ? ' ': ' of ';
    $rel =~ s/_/ /g; $rel .= $suffix;
    $body_html .= <<"EOF";
       <tr>
         <td bgcolor=lightyellow align=left> 
           <font color=darkred  size=3> $rel: 
           <font color=darkblue size=4> $words </td>
       </tr>
EOF
   }

 }

 #*---------------------------------------------------------------
 #*- dump some header html
 #*---------------------------------------------------------------
 sub head_html
 {
  my $wn_image = "$ICON_DIR" . "wnet.jpg";
  my $anchor   = "$CGI_DIR/co_login.pl?session=$e_session";

  print "Content-type: text/html\n\n";
  print << "EOF";
   <html>
    <head> <title> WordNet Dictionary </title> </head>

    <body bgcolor=white>

     <form method=POST action="$FORM">

     <center>
      <table> <tr> <td> <a href=$anchor>
              <img src="$wn_image" border=0> </a> </td> </tr> </table>
EOF
 }

 #*---------------------------------------------------------------
 #*- Show the body of the html page
 #*---------------------------------------------------------------
 sub body_html
 {
  print <<"EOF";

    <table cellspacing=2 cellpadding=0 border=0>
    <tr> <td> <br> </td> </tr>
    <tr> <td colspan=3 align=center> <font color=darkblue size=+1> 
          $stat_msg </font> 
         </td> </tr>

    <tr> 
      <td> <font color=darkred size=+1> Word: </font> </td> 
      <td> <textarea name=word cols=40 rows=1>$in{word} </textarea> </td>
      <td> <input type=submit name=opshun value="Search"> </td>
    </tr>
    </table>

    $body_html

EOF

 }


 #*---------------------------------------------------------------
 #*- Dump the end of the html page 
 #*---------------------------------------------------------------
 sub tail_html
 {
  $dbh->disconnect_db($sth);
  print << "EOF";
    </center>
    <input type=hidden name=session value=$in{session}>
   </form>
  </body>
  </html>
EOF
 }

 #*---------------------------------------------------------------
 #*- Exit with a message
 #*---------------------------------------------------------------
 sub quit
 { &head_html(); &msg_html($_[0] . "<br>$stat_msg"); &tail_html(); exit(0); }

 #*---------------------------------------------------------------
 #*- Dump an error message
 #*---------------------------------------------------------------
 sub msg_html
 {
  my ($msg) = @_;
  $msg =~ s/,$//;
  print << "EOF";
    <table> <tr> <td bgcolor=lightyellow>
                 <font color=darkred size=4> $msg </font> </td>
    </tr> </table>
EOF
 }

 #*---------------------------------------------------------------
 #*- Translate the POS    
 #*---------------------------------------------------------------
 sub tran_pos
 {
  my ($pos) = @_;
  return ( ($pos eq 'c') ? 'Conjunction':
           ($pos eq 'i') ? 'Interjection':
           ($pos eq 'p') ? 'Pronoun':
           ($pos eq 'o') ? 'Preposition':
           ($pos eq 'd') ? 'Determiner':
           ($pos eq 'n') ? 'Noun':
           ($pos eq 'a') ? 'Adjective':
           ($pos eq 'v') ? 'Verb':
           ($pos eq 'r') ? 'Adverb': '');

 }
