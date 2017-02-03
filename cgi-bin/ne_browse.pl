#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
 #*----------------------------------------------------------------
 #*- ne_browse.pl
 #*-  
 #*-   Summary: Display the clusters and associated articles for
 #*-            the recent news collection
 #*----------------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Constants;
 use TextMine::Utils;
 use TextMine::Index qw/content_words/;

 #*-- global variables
 use vars ('$dbh',		#*-- database handle
           '$sth',		#*-- statement handle
           '$stat_msg',		#*-- status message
           '$db_msg',		#*-- database error message
           '$command',		#*-- SQL command
           '$ref_val',		#*-- reference value
           '$FORM',		#*-- name of this form
           '%in',		#*-- hash for form fields
           '$body_html',	#*-- body of the page
           '$e_session'		#*-- URL encoded session
          );

 #*-- set some global variables
 &set_vars();

 #*-- handle the options
 &handle_clusters() if ($in{opshun} eq 'Show Clusters');
 &handle_search()   if ($in{opshun} eq 'Search');
 &handle_related()  if ($in{opshun} eq 'Related');
 &handle_sources()  if ($in{opshun} eq 'Sources');

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
  #*-- Set the form name 
  $0 =~ s%.*[/\\]%%; $FORM = "$CGI_DIR" . "$0";

  #*-- Retrieve the passed parameters
  %in    = %{$ref_val = &parse_parms};
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $in{userid}, 'Password' => $in{password},
       'Dbname' => $DB_NAME);

  #*-- set the default option
  &mod_session($dbh, $in{session}, 'del', 'opshun');
  $in{opshun} = 'Show Clusters' unless ($in{opshun});
  $e_session  = &url_encode($in{session});
  $body_html = '';
  
 }

 #*---------------------------------------------------------------
 #*- Show the clusters     
 #*---------------------------------------------------------------
 sub handle_clusters
 {
  #*-- get the cluster information and build the associated html
  $command = "select nec_members, nec_title from " .
             "ne_clusters order by nei_size desc";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  my @members = my @titles = ();
  while ( (my $nec_members, my $nec_title) = $dbh->fetch_row($sth) )
   { push (@members, $nec_members); push (@titles, $nec_title); }

  #*-- show the title of the cluster and the member information
  $body_html .= '<table border=0 cellspacing=0 cellpadding=0 width=80%>';
  for my $i (0..$#titles)
   {
    $body_html .= <<"EOF";
     <tr>
       <td bgcolor=white> <br> 
          <font size=+1 color=darkred> $titles[$i] </font> <br> </td>
    </tr>
EOF
    my @members = split/,/, $members[$i]; &body_html(\@members);
   } #*-- end of for i
  $body_html .= "</table>";

 }

 #*---------------------------------------------------------------
 #*- Show the documents that match a search query
 #*---------------------------------------------------------------
 sub handle_search
 {
  my @ids = ();
  my %files = (); my @words = 
     @{&content_words(\$in{query}, 'news', $dbh, undef, undef, 1)};
  if ( (@words) && ($in{query} !~ /\bNOT\b/i) )
   {
    foreach my $word (@words)
     {
      my $table = 'ne_index';
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
      while ( (my $id) = $dbh->fetch_row($sth) ) { $files{$id}++; }
     } #*-- end of for each word

     #*--- split the concatenated ids in files into individual ids
     my @id_strings = keys %files; %files = ();
     foreach my $id_string (@id_strings)
     {
      foreach my $id (split/,/, $id_string)
       { #*-- extract the weight
        (my $id, my $null, my $wt) = $id =~ /(\d+)($ISEP(\d+))?/;
        $files{$id} += (defined($wt) ) ? $wt: 1;
       } #*-- end of inner for
     } #*-- end of outer for

     #*-- sort the results by weight and keep the top 10
     my $i = 0;
     foreach my $id ( sort {$files{$b} <=> $files{$a}} keys %files)
      { push (@ids, $id); last if (++$i == 10); }

   } 
  else
   { 
     $command = "select nei_nid from ne_articles";
     ($sth, $db_msg) = $dbh->execute_stmt($command);
     &quit("$command failed: $db_msg") if ($db_msg);
     while ( (my $id) = $dbh->fetch_row($sth) ) { push @ids, $id; }

   } #*-- end of if

  $body_html .= '<table border=0 cellspacing=0 cellpadding=0 width=80%>';
  &body_html(\@ids);  
  $body_html .= '</table';
  return();

 }


 #*---------------------------------------------------------------
 #*- Show the related documents     
 #*---------------------------------------------------------------
 sub handle_related
 {
  $command = "select nec_similar_ids from ne_articles where " .
             "nei_nid = $in{relid}";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  (my $relids) = $dbh->fetch_row($sth);
  my @ids = split/,/, $relids;
  $body_html .= '<table border=0 cellspacing=0 cellpadding=0 width=80%>';
  &body_html(\@ids);  
  $body_html .= '</table';
  return();
 }

 #*---------------------------------------------------------------
 #*- Link to the sources script     
 #*---------------------------------------------------------------
 sub handle_sources
 { my $url  = $CGI_DIR . "ne_view.pl?session=$e_session&opshun=View";
   print "Location: $url", "\n\n"; exit(0); }

 #*---------------------------------------------------------------
 #*- dump the header html
 #*---------------------------------------------------------------
 sub head_html
 {
  #*-- get the date of the last collection
  $command = "select nei_cdate from ne_articles";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  (my $cdate) = $dbh->fetch_row($sth); 
  $cdate = ($cdate) ? &f_date($cdate, 1, 1, 1): "No collection yet";
  my $news_image = "$ICON_DIR" . "news.jpg";
  my $anchor = "$CGI_DIR/co_login.pl?session=$e_session";
  $in{query} = ' ' unless ($in{query});

  print "Content-type: text/html\n\n";
  print <<"EOF";
   <html>
    <head>
     <title> View Page for News Sources </title>
    </head>

    <body bgcolor=white>
     <form method=POST action="$FORM">

     <center>
    <table> <tr> <td> <a href=$anchor>
              <img src="$news_image" border=0> </a> </td> </tr> </table>
    <br>
    <table border=0 cellspacing=2 cellpadding=2>
     <tr><td valign=center> <font color=darkred size=+1> Collected: 
                            </font> </td>
       <td valign=center>   <font color=darkblue size=+1> on $cdate 
                            </font> </td>
       <td valign=bottom> <input type=submit name=opshun 
                           value='Show Clusters'> </td>
     </tr> 
     <tr><td> <font color=darkred size=+1> Query: </font> </td>
       <td> <textarea name=query cols=70 rows=1>$in{query}</textarea></td>
       <td valign=bottom><input type=submit name=opshun value='Search'> </td>
     </tr> 

     <tr> <td colspan=3> <hr> </td> </tr>
    </table> <br>
EOF

 }

 #*---------------------------------------------------------------
 #*- Generate the HTML for the individual cluster members
 #*---------------------------------------------------------------
 sub body_html
 {
  my ($rids, $limit) = @_; 

  #*-- get the list of ids and optional limit on the number
  #*-- of sources (default 10)
  my @ids = @$rids; return unless (@ids);
  $limit = 10 unless ($limit);
  my $i = 1;
  foreach (@ids)
   { $command = "select nei_size, nec_abstract, nec_local_url " .
                "from ne_articles where nei_nid = $_";
     ($sth, $db_msg) = $dbh->execute_stmt($command);
     &quit("$command failed: $db_msg") if ($db_msg);
     (my $size, my $abstract, my $l_url) = $dbh->fetch_row($sth);
     $abstract =~ s/<br>/ /g; #$size /= 1000 if ($size); 
     $size = sprintf("%5.1f", $size/= 1000) if ($size);
     my $rel_link = "$CGI_DIR" . 
        "ne_browse.pl?session=$e_session&opshun=Related&relid=$_";
     my $cac_link = "$l_url";
     $body_html .= <<"EOF";
        <tr> <td> <br> </td> </tr>
        <tr> <td> <font color=darkred> $i. </font>
             <font color=darkblue> $abstract </font> <br>
             <a href=$rel_link> Related </a> &nbsp;
             <font color=darkred> $size Kb </font> &nbsp;
             <a href=$cac_link> Cached </a>
        </td> </tr>
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
    <br>
    <input type=submit name=opshun value=Sources>
    </center>
    <input type=hidden name=session value=$in{session}>
   </form>
  </body>
  </html>
EOF
 }
