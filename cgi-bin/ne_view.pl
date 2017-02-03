#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
 #*----------------------------------------------------------------
 #*- ne_view.pl
 #*-  
 #*-   Summary: Show the news sources and add/update/delete sources 
 #*----------------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Constants;
 use TextMine::Utils;

 #*-- global variables 
 use vars (
       '$dbh',		#*-- database handle
       '$sth',		#*-- statement handle
       '$stat_msg',	#*-- status message for the page
       '$db_msg',	#*-- database message
       '$command',	#*-- SQL Command 
       '$ref_val',	#*-- a reference var
       '%esq',		#*-- escaped and quoted fields in a hash
       '$FORM',		#*-- name of the script
       '%in'		#*-- hash that contains the form fields and values
      );

 #*-- set some global variables
 &set_vars();

 #*-- handle the options
 &add_entry()    if ($in{opshun} eq 'Save');
 &upd_entry()    if ($in{opshun} eq 'Update');
 &del_entry()    if ($in{opshun} eq 'Delete');
 &fil_entry()    if ($in{opshun} eq 'Edit');
 &clr_entry()    if ($in{opshun} eq 'New');
 &see_clusters() if ($in{opshun} eq 'Browse');
 
 #*-- dump the header, body, status and tail html 
 &head_html();
 &msg_html($stat_msg) if ($stat_msg); 
 print ${$ref_val = ($in{opshun} eq 'View') ? &view_html(): &entry_html()};
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

  #*-- make the opshun field a forgetful parameter
  &mod_session($dbh, $in{session}, 'del', 'opshun');

  #*-- check if this is the first entry in the ne_sources table
  $command = "select count(*) from ne_sources";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  unless ($in{opshun})
  { $in{opshun} = ( ($dbh->fetch_row($sth))[0]) ? 'View': 'New'; }
  $in{nec_url} =~ s%^http://%%i if ($in{nec_url});
  
 }

 #*---------------------------------------------------------------
 #*- add an entry if possible and set the status message
 #*---------------------------------------------------------------
 sub add_entry
 {

  #*--- check for mandatory entries
  unless ($in{nec_description} && $in{nec_url})  
   { $stat_msg .= " The Description and URL fields are mandatory,"; 
     return(); }

  #*-- check for a duplicate
  &escape_q(); 
  $command = "select count(*) from ne_sources where nec_url = " .
             "$esq{nec_url}";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  if (($dbh->fetch_row($sth))[0])
   { $stat_msg .= "-- Source " . $in{nec_url} . " exists in the table,"; 
     $stat_msg .= " press Update<br> "; 
     return(); }  

  #*-- build the insert statement
  $command  = <<"EOF";
    insert into ne_sources set nei_nid = 0, 
     nec_description = $esq{nec_description}, nec_url = $esq{nec_url},
     nec_match_condition = $esq{nec_match_condition},
     nec_get_images = $esq{nec_get_images}
EOF
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  $stat_msg .= "-- Source " . $in{nec_url} . " was added,<br>";

 }

 #*---------------------------------------------------------------
 #*- Update an existing entry 
 #*---------------------------------------------------------------
 sub upd_entry
 {

  #*--- check for mandatory entries
  unless ($in{nec_description} && $in{nec_url})  
   { $stat_msg .= " The Description and URL fields are mandatory,"; 
     return(); }

  #*-- check if the entry exists
  &escape_q(); 
  $command = "select count(*) from ne_sources where nec_url = " .
             "$esq{nec_url}";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  unless (($dbh->fetch_row($sth))[0])
   { $stat_msg .= "-- Source " . $in{nec_url} . 
                  " does not exist in the Table,<br>";
     return(); }

  #*-- build the update statement
  my $set_arr = join (",", map {"$_ = $esq{$_}"}
           qw/nec_description nec_match_condition nec_get_images/);
  $command = "update ne_sources set $set_arr ";
  $command .= " where nec_url = $esq{nec_url}";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  $stat_msg .= "-- Source $in{nec_url} was changed successfully,<br>";
 }

 #*---------------------------------------------------------------
 #*- Delete an existing entry 
 #*---------------------------------------------------------------
 sub del_entry
 {
  #*--- check for mandatory entries
  unless ($in{nec_url}) 
   { $stat_msg .= "-- The URL field is mandatory,<br>"; return(); }
  &escape_q(); 

  #*-- delete the entry in the appropriate abook table
  $command = "delete from ne_sources where nec_url = $esq{nec_url}";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  $stat_msg .= "-- The Source " . $in{nec_url} . " entry was deleted,<br>";

  $command = "select count(*) from ne_sources";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  
  $in{opshun} = ( ($dbh->fetch_row($sth))[0]) ? 'View': 'New';
 }

 #*---------------------------------------------------------------
 #*- Fill in the fields for an existing entry
 #*---------------------------------------------------------------
 sub fil_entry
 {
  &escape_q();
  $command   = "select nec_description, nec_match_condition, " .
               "nec_get_images from ne_sources where " . 
               "nec_url = $esq{nec_url}";
  ($sth, $db_msg) = $dbh->execute_stmt("$command");
  &quit("$command failed: $db_msg") if ($db_msg);
  my @fields = $dbh->fetch_row($sth);
  my @dfields = qw/nec_description nec_match_condition nec_get_images/;
  for my $i (0..$#fields) { $in{$dfields[$i]} = $fields[$i]; } 

 }

 #*---------------------------------------------------------------
 #*- Clear all fields for a new entry        
 #*---------------------------------------------------------------
 sub clr_entry
 { for (qw/nec_description nec_url nec_match_condition nec_get_images/)
    { $in{$_} = '';} 
   $stat_msg = "Fill in information for a news source";
 }

 #*---------------------------------------------------------------
 #*- Link to the clusters page and pass parameters
 #*---------------------------------------------------------------
 sub see_clusters
 { my $e_session = &url_encode($in{session});
   my $url = $CGI_DIR . "ne_browse.pl?session=$e_session";
   print "Location: $url", "\n\n"; exit(0); }


 #*---------------------------------------------------------------
 #*- dump the header html
 #*---------------------------------------------------------------
 sub head_html
 {
  my $news_image = "$ICON_DIR" . "news.jpg";
  my $e_session  = &url_encode($in{session});
  my $anchor = "$CGI_DIR/co_login.pl?session=$e_session";

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
     </center>
EOF

 }
                                                          

 #*---------------------------------------------------------------
 #*- show a list of people in a table
 #*---------------------------------------------------------------
 sub view_html
 {

  #*-- get the lists from the dlist table              
  my %descr = (); 
  $command = "select nec_description, nec_url from ne_sources order by 1";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  my @nec_descriptions = my @nec_urls = ();
  while ( (my $description, my $url) = $dbh->fetch_row($sth) )
     { push (@nec_descriptions, &trim_field($description, 40) ); 
       push (@nec_urls, $url); }

  #*-- build the html for the table
  my $body_html .= <<"EOF";
   <br> <center>
   <table cellspacing=0 cellpadding=0 border=0 bgcolor=white>
   <tr><td> 
   <table cellspacing=4 cellpadding=0 border=2 bgcolor=lightblue>
   <tr>
     <td bgcolor=lightyellow> <font color=darkred> No. </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> Description </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> URL </font> </td>
   </tr>
EOF
  for my $i (0..$#nec_descriptions)
   { 
    my $num = $i + 1;
    my $e_url     = &url_encode($nec_urls[$i]); 
    my $e_session = &url_encode($in{session}); 
    $body_html .= <<"EOF";
     <tr>
      <td bgcolor=white><font color=darkblue> $num.    </font> </td>
      <td bgcolor=white><font color=darkblue> $nec_descriptions[$i]</font> 
          </td>
      <td bgcolor=white><font color=darkred size=+1> 
        <a href=$FORM?nec_url=$e_url&opshun=Edit&session=$e_session> 
        $nec_urls[$i] </a> </font> </td>
     </tr>
EOF
    $i++;
   }

  #*-- add a button to add lists
  $body_html .= <<"EOF";
     </table> 
    </td> </tr> 
    <tr><td align=center> <br> 
      <input type=submit name=opshun value=New> &nbsp;
      <input type=submit name=opshun value=Browse>
    </td></tr> 
   </table> </center>
EOF
  return(\$body_html);

 }

 #*---------------------------------------------------------------
 #*- Show the screen to view details of each entry   
 #*---------------------------------------------------------------
 sub entry_html
 {

  #*-- build the html for the lists 
  &escape_q();
  my $y_check = my $n_check = '';
  if ($in{nec_get_images} && $in{nec_get_images} =~ /^y$/i) 
       { $y_check = 'CHECKED'; }
  else { $n_check = 'CHECKED'; }

  #*-- show the name, identity, e-mail, and notes fields
  my $body_html .= <<"EOF";
  <table cellspacing=2 cellpadding=0 border=0>
  <tr> <td colspan=2> <br> </td> </tr>
  <tr>
    <td> <font color=darkred size=+1> *Description: </font> </td>
    <td> <textarea name=nec_description cols=70 rows=1>$in{nec_description}</textarea></td>
  </tr>

  <tr>
    <td> <font color=darkred size=+1> *URL: </font> </td>
    <td> <textarea name=nec_url cols=70 rows=1>$in{nec_url}</textarea></td>
  </tr>  

  <tr>
    <td> <font color=darkred size=+1> Match Condition: </font> </td>
    <td> <textarea name=nec_match_condition cols=70 rows=1>$in{nec_match_condition}</textarea></td>
  </tr>  

  <tr>
    <td> <font color=darkred size=+1> Get Images: </font> </td>
    <td> <font color=darkblue size=+1> Yes </font>
         <input type=radio name=nec_get_images value='y' $y_check>
         <font color=darkblue size=+1> No </font>
         <input type=radio name=nec_get_images value='n' $n_check>
    </td>
  </tr>  

  <tr>
     <td colspan=2 align=center> 
        <table border=0 cellspacing=24 cellpadding=0>
         <tr>
           <td> <input type=submit name=opshun value='New'> </td>
           <td> <input type=submit name=opshun value='Save'> </td>
           <td> <input type=submit name=opshun value='Update'> </td>
           <td> <input type=submit name=opshun value='Delete'> </td>
           <td> <input type=submit name=opshun value='View'> </td>
         </tr>
        </table>
     </td>
  </tr>

  </table>
EOF

  return(\$body_html);
 }


 #*------------------------------------------------------
 #*-- escape strings with single quotes
 #*------------------------------------------------------
 sub escape_q
 {
  %esq = (); 
  $in{nec_description} =~ s/"/'/g if ($in{nec_description}); 
  foreach (qw/nec_description nec_url nec_get_images nec_match_condition/)
   { $in{$_} = '' unless ($in{$_}); 
     $in{$_} =~ s/^\s+//; $in{$_} =~ s/\s+$//;
     $esq{$_} = $dbh->quote($in{$_}); }
 }

 #*---------------------------------------------------------------
 #*- Exit with a message            
 #*---------------------------------------------------------------
 sub quit
 {
  &head_html(); &msg_html($_[0] . "<br>$stat_msg"); &tail_html(); exit(0);
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
