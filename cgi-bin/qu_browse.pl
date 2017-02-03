#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
 #*----------------------------------------------------------------
 #*- qu_browse.pl
 #*-  
 #*-   Summary: Browse the Perl FAQ using natural language queries  
 #*----------------------------------------------------------------

 use strict; use warnings;
 use Text::Wrap qw(wrap 80);
 use TextMine::DbCall;
 use TextMine::Constants qw($DB_NAME $CGI_DIR $ICON_DIR $EQUAL $DELIM);
 use TextMine::Tokens    qw(load_token_tables assemble_tokens);
 use TextMine::WordUtil  qw(normalize sim_val gen_vector);
 use TextMine::Quanda    qw(get_inouns get_iwords);
 use TextMine::Index     qw(text_match);
 use TextMine::Utils;

 #*-- set the constants
 use vars (
  '$dbh',		#*-- database handle
  '$sth',		#*-- statement handle
  '$stat_msg',		#*-- status message for page
  '$db_msg',		#*-- database error message
  '$command',		#*-- var for SQL command
  '$ref_val',		#*-- reference variable
  '$FORM',		#*-- name of form 
  '%in',		#*-- hash for form fields 
  '$body_html',		#*-- variable for HTML in body of page
  '$e_session'		#*-- URL encoded session variable
   );

 #*-- set some global variables
 &set_vars();

 #*-- handle the options
 &handle_search()   if ($in{opshun} eq 'Search');
 &handle_related()  if ($in{opshun} eq 'Related');

 #*-- dump the header, body, status and tail html 
 &head_html();
 &msg_html($stat_msg) if ($stat_msg); 
 print "$body_html\n";
 &tail_html(); 

 exit(0);

 #*---------------------------------------------------------------
 #*- set global variables              
 #*---------------------------------------------------------------
 sub set_vars
 {
  #*-- retrieve the passed parameters
  $0 =~ s%.*[/\\]%%; $FORM = "$CGI_DIR" . "$0";
  %in    = %{$ref_val = &parse_parms};
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $in{userid}, 'Password' => $in{password},
       'Dbname' => $DB_NAME);

  &mod_session($dbh, $in{session}, 'del', 'opshun');
  unless ($in{opshun})
   { $in{opshun} = 'New'; $stat_msg = 'Please enter a query'; } 
  $e_session  = &url_encode($in{session});
  $body_html = '';
 }

 #*---------------------------------------------------------------
 #*- Show the search documents
 #*---------------------------------------------------------------
 sub handle_search
 {
  #*-- clean up the query
  (my $query = $in{query}) =~ s/^\s+//; 
  unless ($query) { $stat_msg = 'Please enter a query'; return; }

  $query =~ s/\s+$//; $query =~ s/\s*\?$//;
  my $hash_refs = &load_token_tables($dbh);

  #*-- get the interrogatory nouns
  my %inouns = %{&get_inouns($query, $dbh, $hash_refs)}; 
  &normalize(\%inouns,5);

  #*-- get the interrogatory words
  my %iwords = ();  map { $iwords{$_}++ } split/\s+/, &get_iwords($query);
  &normalize(\%iwords, 5);

  #*-- get the interrogatory phrases
  my ($r1) = &assemble_tokens(\$query, $dbh, $hash_refs);
  my @tokens = @$r1; my @phrases = ();
  foreach my $iword (keys %iwords)
   { for my $j (0..$#tokens)
      { push(@phrases, lc("$tokens[$j] $tokens[$j+1]") )
        if ( ($tokens[$j]   =~ /\b$iword\b/i) && ($j < $#tokens) &&
             ($tokens[$j+1] =~ /^[a-z]/i) ); }
    }
  my %iphrases = (); map { $iphrases{$_}++ } @phrases if (@phrases); 
  &normalize(\%iphrases, 5);

  #*-- get the vector for the query
  my %vector = &gen_vector(\$query, 'fre', '', $dbh);
  &normalize(\%vector, 5);

  #*-- get the attributes for every query and compare with the query
  my %scores = (); my $count = 0;
  $command = "select * from qu_perlfaq";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed") if ($db_msg || !$sth);
  while (my $qu = $dbh->fetch_row($sth, 1))
   {
    my %qu = %$qu; my %vec = ();
    map {m%(.*?)$EQUAL(.*)%, $vec{$1} = $2 } split/$DELIM/, $qu{quc_inouns}
        if $qu{quc_inouns};
    my $inoun_s = &sim_val(\%vec, \%inouns);

    %vec = ();
    map {m%(.*?)$EQUAL(.*)%, $vec{$1} = $2 } split/$DELIM/, $qu{quc_iphrases}
        if $qu{quc_iphrases};
    my $iphrase_s = &sim_val(\%vec, \%iphrases);

    %vec = ();
    map {m%(.*?)$EQUAL(.*)%, $vec{$1} = $2 } split/$DELIM/, $qu{quc_iwords}
        if $qu{quc_iwords};
    my $iword_s = &sim_val(\%vec, \%iwords);

    %vec = (); $qu{quc_vector} =~ s/\cM$//;
    map {m%(.*?)$EQUAL(.*)%, $vec{$1} = $2 } split/$DELIM/, $qu{quc_vector}
        if $qu{quc_vector};
    my $vector_s = &sim_val(\%vec, \%vector);
    $inoun_s    += 50.0 * &sim_val(\%vec, \%inouns);

    $scores{$qu{qui_qid}} = 0.25 * $inoun_s + 0.25 * $iphrase_s +
                            0.25 * $iword_s + 0.25 * $vector_s;

    $scores{$qu{qui_qid}} = 100 if ($qu{quc_question} =~ /$query/i);

   } #*-- end of while

  #*-- sort the results by weight and keep the top 10
  my $i = 0; my @ids = ();
  foreach (keys %scores) { $scores{$_} = sprintf("%4.2f", $scores{$_}); }
  foreach my $id ( sort {$scores{$b} <=> $scores{$a}} keys %scores)
   { push (@ids, "$id$EQUAL$scores{$id}"); last if (++$i == 10); }

  $body_html .= '<table border=0 cellspacing=0 cellpadding=0>';
  &body_html(\@ids, 10, \%inouns);  
  $body_html .= '</table';
  return();

 }


 #*---------------------------------------------------------------
 #*- Show the related documents     
 #*---------------------------------------------------------------
 sub handle_related
 {
  $command = "select quc_question, quc_sim_ids from qu_perlfaq where " .
             "qui_qid = $in{relid}";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  my ($question, $relids) = $dbh->fetch_row($sth);

  my %inouns = %{&get_inouns($question, $dbh)};
  my @ids = split/,/, $relids;
  ($in{query} = $question) =~ s/ EOL/\n/g; 
  $body_html .= '<table border=0 cellspacing=0 cellpadding=0>';
  &body_html(\@ids, 10, \%inouns);  
  $body_html .= '</table';
  return();
 }

 #*---------------------------------------------------------------
 #*- dump the header html
 #*---------------------------------------------------------------
 sub head_html
 {
  my $query_image = "$ICON_DIR" . "query.jpg";
  my $anchor = "$CGI_DIR/co_login.pl?session=$e_session";
  $in{query} = ' ' unless ($in{query});

  print "Content-type: text/html\n\n";
  print <<"EOF";
   <html>
    <head>
     <title> Page for Query </title>
    </head>

    <body bgcolor=white>
     <form method=POST action="$FORM">

     <center>
    <table> <tr> <td> <a href=$anchor>
              <img src="$query_image" border=0> </a> </td> </tr> </table>
    <br>
    <table border=0 cellspacing=2 cellpadding=2>
     <tr><td> <font color=darkred size=+1> Query: </font> </td>
       <td> <textarea name=query cols=70 rows=1>$in{query}</textarea></td>
       <td valign=bottom><input type=submit name=opshun value='Search'> </td>
     </tr> 

     <tr> <td colspan=3> <hr> </td> </tr>
    </table> <br>
EOF

 }

 #*---------------------------------------------------------------
 #*- Generate the body HTML for the individual sources
 #*---------------------------------------------------------------
 sub body_html
 {
  my ($rids, $limit, $r_inouns) = @_; 
  my @ids = @$rids; return unless (@ids);
  my %inouns = %$r_inouns;
  $limit = 10 unless ($limit); my $i = 1;
  foreach (@ids)
   { 
     my ($id, $score) = (/^(.*?)$EQUAL(.*)$/) ? ($1, "($2)"): ($_, ''); 
     $command = "select quc_question, quc_answer " .
                "from qu_perlfaq where qui_qid = $id";
     ($sth, $db_msg) = $dbh->execute_stmt($command);
     &quit("$command failed: $db_msg") if ($db_msg);
     (my $query, my $answer) = $dbh->fetch_row($sth);
     $answer =~ s/EOL/\n/g; $query =~ s/EOL/\n/g;
     $answer = &wrap('', '', $answer);

     #*-- highlight the nouns
     foreach (keys %inouns)
      { $answer =~ s%\b$_\b%<font color=darkred size=+1>$_</font>%g; }

     my $rel_link = "$CGI_DIR" . 
        "qu_browse.pl?session=$e_session&opshun=Related&relid=$id";
     $body_html .= <<"EOF";
        <tr> <td> <br> </td> </tr>
        <tr> <td bgcolor=azure> <font color=darkred> $i $score. </font>
             <font color=darkblue> $query </font> &nbsp; 
             <a href=$rel_link> Related </a> 
        </td> </tr>
        <tr> <td bgcolor=lightyellow> <font color=darkblue> 
              <pre> $answer </pre>  </font> </td> </tr>
        <tr> <td> <hr> </td> </tr>
EOF
    last if ($i++ == $limit); #*-- show a max. of 10 sources
   } #*-- end of for
 }

 #*---------------------------------------------------------------
 #*- Exit with a message            
 #*---------------------------------------------------------------
 sub quit
 {
  &head_html();
  &msg_html($_[0] . "<br>$stat_msg"); 
  &tail_html(); 
  exit(0);
 }

 #*---------------------------------------------------------------
 #*- Dump an error message           
 #*---------------------------------------------------------------
 sub msg_html
 {
  my ($msg) = @_;
  $msg =~ s/,\s+$//;
  print << "EOF";
    <center> <table> <tr> <td bgcolor=lightyellow>
                 <font color=darkred size=4> $msg </font> </td>
    </tr> </table> </center>
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
