#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
 #*----------------------------------------------------------------
 #*- sp_links.pl
 #*-  
 #*-   Summary: Show the links for a spider search  
 #*----------------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Constants;
 use TextMine::Utils;
 use TextMine::Index qw/content_words tab_word text_match/;
 use TextMine::MyURL qw/parse_HTML/;

 #*-- set the constants
 use vars (
  '$dbh',		#*-- database handle
  '$sth',		#*-- statement handle
  '$stat_msg',		#*-- status message for page
  '$db_msg',		#*-- database error message
  '$command',		#*-- SQL command var
  '$FORM',		#*-- name of form
  '$link_table',	#*-- name of the table of links for this crawl
  '%in',		#*-- hash for form fields 
  '$e_session',		#*-- URL encoded session
  '$results_per_page',	#*-- number of links to show per page 
  '$spc_descr',		#*-- Description of crawl
  '$body_html'		#*-- var for saving HTML for body of page
  );

 #*-- retrieve and set variables
 &set_vars();

 #*-- handle options
 &handle_return() if ($in{opshun} eq 'Return');
 &get_data();

 #*-- dump the header, status, body and tail html 
 &head_html();
 &msg_html($stat_msg) if ($stat_msg); 
 print ("$body_html\n");
 &tail_html(); 

 exit(0);


 #*-----------------------------------------------------
 #*- Set some global vars            
 #*-----------------------------------------------------
 sub set_vars
 {
  #*-- retrieve the passed parameters
  $0 =~ s%.*[/\\]%%; $FORM = "$CGI_DIR" . "$0";
  %in    = %{my $ref_val = &parse_parms};

  #*-- establish a DB connection
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
      'Userid' => $in{userid}, 'Password' => $in{password},
      'Dbname' => $DB_NAME);

  #*-- set the forgetful parms
  &mod_session($dbh, $in{session}, 'del', 'opshun');
  $e_session = &url_encode($in{session});
  $results_per_page = 12;

  #*-- get the description of the search
  $dbh->execute_stmt("lock tables sp_search read");
  ($sth, $db_msg) = $dbh->execute_stmt( 
         "select spc_descr from sp_search where spi_id = $in{spi_id}");
  &quit("$command failed: $db_msg") if ($db_msg);
  ($spc_descr) = ($dbh->fetch_row($sth))[0];
  $dbh->execute_stmt("unlock tables");
  my $descr = substr($spc_descr,0,20); $descr =~ s/[^A-Za-z]/o/g;

  $link_table    = "sp_" . $descr . "_links";
  $in{opshun} = 'Return' unless (&count_entries()); 
  $in{opshun} = 'View' unless ($in{opshun});
  foreach (qw/query cpage/) { $in{$_} = '' unless ($in{$_}); }
 }

 #*---------------------------------------------------------------
 #*- count the number of entries in the links table  
 #*---------------------------------------------------------------
 sub count_entries
 {
  #*-- count the number of links for the search
  $dbh->execute_stmt("lock tables $link_table read");
  $command = "select count(*) from $link_table where spc_status = 'Done'";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  $dbh->execute_stmt("unlock tables");
  &quit("$command failed: $db_msg") if ($db_msg);
  return ( ($dbh->fetch_row($sth))[0] );
 }

 #*---------------------------------------------------------------
 #*- Return to the spider search page 
 #*---------------------------------------------------------------
 sub handle_return
 { my $url  = $CGI_DIR . "sp_search.pl?session=$e_session&opshun=View"; 
   print "Location: $url", "\n\n"; exit(0); }

 #*---------------------------------------------------------------
 #*- Display the header HTML 
 #*---------------------------------------------------------------
 sub head_html
 {
  my $sp_image   = "$ICON_DIR" . "searchw.jpg";
  my $anchor = "$CGI_DIR" . "co_login.pl?session=$e_session";

  print "Content-type: text/html\n\n";
  print << "EOF";
   <html>
    <head> <title> Spider Search Page </title> </head>

    <body bgcolor=white>

     <form method=POST action="$FORM">

     <center>
      <table> <tr> <td> <a href=$anchor>
         <img src="$sp_image" border=0> </a> </td> </tr> </table>

      <table>

        <tr>
         <td> <font color=darkred size=+1> Description: </font></td>
         <td colspan=2> <font color=darkblue size=+1> $spc_descr </font></td>
        </tr>

        <tr>
         <td> <font color=darkred size=+1> Query: </font> </td>
         <td> 
       <textarea name=query rows=1 cols=60>$in{query}</textarea></td>
         <td> <input type=submit name=opshun value=Search> </td>
        </tr>
      </table>
EOF
 }

 #*---------------------------------------------------------------
 #*- get the list of links for the search
 #*---------------------------------------------------------------
 sub get_data
 {

  my (%files, $spi_lid);

  #*-- cannot handle NOT here
  (my $descr = substr($spc_descr,0,20)) =~ s/[^A-Za-z]/o/g;
  my @words = @{&content_words(\$in{query}, 'web', $dbh, undef, undef, 1)};
  if ( (@words) && ($in{query} !~ /\bNOT\b/i) )
   {
    foreach my $word (@words)
     {
      my $table = 'sp_' . $descr . &tab_word($word);
      my $where_c = ' where inc_word ';  #*-- build the where clause
      if ($word =~ /[*]/) 
      {
       (my $e_word = $word) =~ s/([._%])/\\$1/g;
       $e_word =~ s/[*]/\%/g; $e_word = $dbh->quote($e_word);
       $where_c .= "LIKE $e_word"; }
      else { $where_c .=  "= " . $dbh->quote($word); }

      $command = "select inc_ids from $table $where_c";
      ($sth, $db_msg) = $dbh->execute_stmt($command);
      &quit("Command: $command failed --> $db_msg") if ($db_msg);
      while ( ($spi_lid) = $dbh->fetch_row($sth) ) { $files{$spi_lid}++; }
     } #*-- end of for each word

     #*--- split the concatenated ids in files into individual ids
     my @id_strings = keys %files; %files = ();
     foreach my $id_string (@id_strings)
     {
      foreach my $id (split/,/, $id_string)
       { #*-- extract the optional weight
        ($spi_lid, my $null, my $wt) = $id =~ /(\d+)($ISEP(\d+))?/;
        $files{$spi_lid} += (defined($wt) ) ? $wt: 1;
       } #*-- end of inner for
     } #*-- end of outer for
   }
   #*-- for a blank description, retrieve every file
  else
   { my ($spf_relevance);
     $dbh->execute_stmt("lock tables $link_table read");
     $command = "select spi_lid, spf_relevance from $link_table";
     ($sth, $db_msg) = $dbh->execute_stmt($command);
     $dbh->execute_stmt("unlock tables");
     &quit("Command: $command failed --> $db_msg") if ($db_msg);
     while ( ($spi_lid, $spf_relevance) = $dbh->fetch_row($sth) ) 
      { $files{$spi_lid} = $spf_relevance; }
   } #*-- end of if @words


  undef($/);
  foreach my $spi_id (keys %files)
   {
    $dbh->execute_stmt("lock tables $link_table read");
    $command  = "select spc_html_file from $link_table where " .
                " spi_lid = $spi_id";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    (my $html_file) = $dbh->fetch_row($sth);
    $dbh->execute_stmt("unlock tables");
    unless ( open (IN, "<", &clean_filename($html_file)) )  
      { delete($files{$spi_id}); next; }
    my $html = <IN>; close(IN);
    (my $descr) = (&parse_HTML($html, ''))[0];

    #*-- check if the description for the file matches the query
    delete ($files{$spi_id}) unless (&text_match($descr,$in{query}));

   } #*-- end of for each keys %files

  #*-- compute the current page number
  my $num_ids = keys %files;
  my $num_pages = ($num_ids >= $results_per_page) ?
               int($num_ids / $results_per_page): 0;
  $num_pages++   if ( ($num_ids % $results_per_page) != 0);

  $in{cpage}++            if ($in{opshun} eq 'Next');
  $in{cpage}--            if ($in{opshun} eq 'Prev');
  $in{cpage} = 1          if ($in{opshun} eq 'First');
  $in{cpage} = $num_pages if ($in{opshun} eq 'Last');

  #*-- make sure that current page is in range
  $in{cpage} = 1          unless($in{cpage});
  $in{cpage} = $num_pages if ($in{cpage} > $num_pages);
  $in{cpage} = 1          if ($in{cpage} < 1);

  #*-- set the start file and save the current page number
  &mod_session($dbh, $in{session}, 'mod', 'cpage', $in{cpage});
  my $start_file = ($in{cpage} - 1) * $results_per_page;

  my @page_ids = ();
  my $i = 0; my $j = 0;
  foreach my $id ( sort {$files{$b} <=> $files{$a}} keys %files)
   { if (++$j > $start_file)
      { $page_ids[$i] = $id; last if (++$i >= $results_per_page); } }

  #*-- get the link description for the page
  my %link_d = my %relv_d = my %abs_d = my %file_d = ();
  foreach my $id (@page_ids)
   {
    $dbh->execute_stmt("lock tables $link_table read");
    $command = " select spc_link, spf_relevance, spc_abstract, spc_html_file " .
               " from $link_table where spi_lid = $id";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    $dbh->execute_stmt("unlock tables");
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    ($link_d{$id}, $relv_d{$id}, $abs_d{$id}, $file_d{$id}) = 
                        $dbh->fetch_row($sth);
   }

  #*-- build the html for the table
  $body_html .= <<"EOF";
   <br>
   <table cellspacing=0 cellpadding=0 border=0 bgcolor=white>
   <table cellspacing=4 cellpadding=0 border=0>
EOF

  my $e_query = $in{query} ? &url_encode($in{query}): '';
  foreach $i (0..$#page_ids)
   { 
    my $j = $i + 1 + $start_file;
    #my $anchor = "$CGI_DIR" . "sp_text.pl?session=$e_session" .
    #             "&query=$e_query&spi_id=$in{spi_id}&spi_lid=$page_ids[$i]";
    my $anchor = 'file://' . $file_d{$page_ids[$i]};
    $body_html .= <<"EOF";
     <tr>
       <td valign=top><font color=darkred> $j. </font> </td>
       <td><font color=darkblue> $abs_d{$page_ids[$i]} </font></td> 
     </tr>
     <tr>
       <td> &nbsp; </td>
       <td> <a href=$anchor> Cached Page </a>
        &nbsp; <font color=darkred> Relevance: </font>
               <font color=darkblue> $relv_d{$page_ids[$i]} </font> &nbsp;
        &nbsp; <font color=darkred> Link: </font>
               <font color=darkblue> $link_d{$page_ids[$i]} </font> </td>
     </tr>
     <tr> <td colspan=2> &nbsp; </td> </tr>
EOF
   }

  $body_html .= <<"EOF";
    <tr><td colspan=2 align=center> <br> <hr>
    <tr><td colspan=2 align=center> <br> 
      <font color=darkred> Page $in{cpage} of $num_pages </font> 
                           &nbsp; &nbsp;
      <input type=submit name=opshun value=Next> &nbsp;
      <input type=submit name=opshun value=Prev> &nbsp;
      <input type=submit name=opshun value=First> &nbsp;
      <input type=submit name=opshun value=Last> &nbsp;
    </td></tr> 
    </table> 
    <tr><td align=center> <br> 
      <input type=submit name=opshun value=Return></td></tr>
    </td> </tr> 
   </table>
EOF
  return();

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
