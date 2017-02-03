#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
 #*----------------------------------------------------------------
 #*- sp_text.pl
 #*-  
 #*-   Summary: Show the page for cached page   
 #*----------------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Utils qw(parse_parms clean_array mod_session url_encode);
 use TextMine::Constants qw($CGI_DIR $DB_NAME $ICON_DIR clean_filename);
 use TextMine::MyURL qw(sub_HTML);

 #*-- set the constants
 use vars (
  '$dbh',		#*-- database handle
  '$sth',		#*-- statement handle
  '$stat_msg',		#*-- status message for the page
  '$db_msg',		#*-- database error message
  '$command',		#*-- field for SQL command
  '$FORM',		#*-- name of form
  '$link_table',	#*-- name of table for crawl containing list of links
  '%in',		#*-- hash for form fields
  '$e_session',		#*-- URL encoded session
  '$spc_descr',		#*-- description of crawl
  '$spc_keywords',	#*-- query keywords
  '$body_html'		#*-- HTML for body of page
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
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $in{userid}, 'Password' => $in{password},
       'Dbname' => $DB_NAME);

  #*-- set the forgetful parms
  &mod_session($dbh, $in{session}, 'del', 'opshun');
  $e_session = &url_encode($in{session});
  $dbh->execute_stmt("lock tables sp_search");
  ($sth, $db_msg) = $dbh->execute_stmt(  
         "select spc_keywords, spc_descr " .
         " from sp_search where spi_id = $in{spi_id}");
  $dbh->execute_stmt("unlock tables");
  &quit("$command failed: $db_msg") if ($db_msg);
  ($spc_keywords, $spc_descr) = $dbh->fetch_row($sth);

  (my $descr = substr($spc_descr,0,20)) =~ s/[^A-Za-z]/o/g;
  $link_table    = "sp_" . $descr . "_links";
  $in{opshun} = 'View' unless ($in{opshun});
 }

 #*---------------------------------------------------------------
 #*- Return to the spider search page 
 #*---------------------------------------------------------------
 sub handle_return
 { my $url  = $CGI_DIR . "sp_links.pl?session=$e_session&opshun=View&" .
              "spi_id=$in{spi_id}"; 
   print "Location: $url", "\n\n"; exit(0); }

 #*---------------------------------------------------------------
 #*- fetch the small files based on page number and display
 #*---------------------------------------------------------------
 sub head_html
 {
  my $sp_image   = "$ICON_DIR" . "searchw.jpg";
  my $anchor = "$CGI_DIR" . "co_login.pl?session=$e_session";

  print "Content-type: text/html\n\n";
 }

 #*---------------------------------------------------------------
 #*- get the list of links for the search
 #*---------------------------------------------------------------
 sub get_data
 {

  $dbh->execute_stmt("lock tables $link_table read");
  $command = "select spc_link, spc_parent_link, spc_html_file from " .
             " $link_table where spi_lid = $in{spi_lid}";
  ($sth, $db_msg) = $dbh->execute_stmt($command); 
  $dbh->execute_stmt("unlock tables");
  &quit("$command failed: $db_msg") if ($db_msg);
  my ($spc_link, $spc_parent_link, $spc_html_file) = $dbh->fetch_row($sth);
  open (IN, "<", &clean_filename($spc_html_file)) || 
        &quit("Unable to open $spc_html_file $!");
  undef($/); my $html = <IN>; close(IN);
  $html = "<html> <body bgcolor=\"#FFFFFF\"> <b> Link: $spc_link </b> <br>" .
    "<b> Parent: $spc_parent_link </b> <br> <hr> </body> </html>\n" . $html;

  #*-- highlight the search terms, build the patterns for
  #*-- replacement
  my @patts = (); my $star = quotemeta '*'; my $dotstar = '.*?\b';
  foreach my $patt (
     &clean_array(split/\s+/, "$in{query} $spc_keywords") )
   { next if $patt =~ /^(?:AND|OR|NOT)/i;
     $patt =~ s/$star/$dotstar/g; $patt = '(' . $patt . ')';
     push(@patts, $patt); }

  $body_html = &sub_HTML($html, \@patts);
  
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
 }
