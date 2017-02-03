#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
#*----------------------------------------------------------------
#*- em_lists.pl
#*-  
#*-   Summary: The default function is to view lists. Other functions
#*-       include add list, update list, and delete list. If no lists
#*-       are available in view list, them show the add list screen.
#*----------------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Constants;
 use TextMine::Utils;
 use TextMine::MailUtil;

 #*-- set the constants
 use vars (
  '$dbh',	#*-- database handle
  '$sth',	#*-- statement handle
  '$stat_msg',	#*-- status message for the page
  '$db_msg',	#*-- database error message
  '$command',	#*-- variable for the SQL command
  '$ref_val',	#*-- reference variable
  '%esq',	#*-- hash for escaped fields in the form
  '$FORM',	#*-- name of the form
  '%in',	#*-- hash for form fields
  '@mlist'	#*-- a list of members
  );

 #*-- set some global variables
 &set_vars();

 #*-- handle the options
 &add_entry() if ($in{opshun} eq 'Save');
 &upd_entry() if ($in{opshun} eq 'Update');
 &del_entry() if ($in{opshun} eq 'Delete');
 &fil_entry() if ($in{opshun} eq 'Browse');
 &sen_entry() if ($in{opshun} eq 'Compose');
 &clr_entry() if ($in{opshun} eq 'New');
 
 #*-- set defaults
 ($sth, $db_msg) = $dbh->execute_stmt("select count(*) from em_dlist");
 &quit("$command failed: $db_msg") if ($db_msg);
 $in{opshun} = 'New' unless ( ($dbh->fetch_row($sth))[0] );
 $in{opshun} = 'View' unless ($in{opshun});

 #*-- dump the header, body, status and tail html 
 print ${$ref_val = &email_head("Lists", $FORM, $in{session})}; 
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

  #*-- build the collection of members in an array
  @mlist = (); my ($m_id);
  foreach (qw/em_abook em_abook_home/)
   {
    ($sth,$db_msg) = $dbh->execute_stmt("select abc_identity from $_");
    &quit("$command failed: $db_msg") if ($db_msg);
    push(@mlist, $m_id) while ( ($m_id) = $dbh->fetch_row($sth) );
   }
  &mod_session($dbh, $in{session}, 'del', @mlist, 'opshun');
  foreach (@mlist, 'opshun') { $in{$_} = '' unless ($in{$_}); }

 }
 #*---------------------------------------------------------------
 #*- add an entry if possible and set the status message
 #*---------------------------------------------------------------
 sub add_entry
 {

  #*--- check for mandatory entries
  unless ($in{dlc_name})  
   { $stat_msg .= " The Name field is mandatory,"; return(); }

  #*-- check for a duplicate
  &escape_q(); 
  $command = "select count(*) from em_dlist where dlc_name = $esq{dlc_name}";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  if (($dbh->fetch_row($sth))[0])
   { $stat_msg .= "-- List " . $in{dlc_name} . " exists in the list table,"; 
     $stat_msg .= " press Update<br> "; 
     return(); }  

  #*-- build the insert statement
  $command  = "insert into em_dlist (dlc_name, dlc_description) values";
  $command .= "($esq{dlc_name}, $esq{dlc_description})";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  #*-- add the entries in the dlist_abook table
  $command = "delete from em_dlist_abook where dlc_name = $esq{dlc_name}";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  foreach my $identity (@mlist)
   { if ($in{$identity})
      {
       my $e_identity = $dbh->quote($identity); 
        $command  = "insert into em_dlist_abook (dlc_name, dlc_identity) ";
        $command .= "values ($esq{dlc_name}, $e_identity)";
        (undef, $db_msg) = $dbh->execute_stmt($command);
        &quit("$command failed: $db_msg") if ($db_msg);
      } 
   }
  $stat_msg .= "-- List " . $in{dlc_name} . " was added,<br>";

 }

 #*---------------------------------------------------------------
 #*- Update an existing entry 
 #*---------------------------------------------------------------
 sub upd_entry
 {

  #*--- check for mandatory entries
  unless ($in{dlc_name})  
   { $stat_msg .= "-- The Name field is mandatory,<br>"; return(); }

  #*-- check if the entry exists
  &escape_q(); 
  $command = "select count(*) from em_dlist where dlc_name = $esq{dlc_name}";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  unless (($dbh->fetch_row($sth))[0])
   { $stat_msg .= "-- List " . $in{dlc_name} . 
                  " does not exist in the Table,<br>";
     return(); }

  #*-- build the update statement
  my $set_arr = join (",", map {"$_ = $esq{$_}"} 
                qw/dlc_name dlc_description/);
  $command = "update em_dlist set $set_arr ";
  $command .= " where dlc_name = $esq{dlc_name}";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  #*-- delete and add entries in the abook_dlist table
  $command = "delete from em_dlist_abook where dlc_name = $esq{dlc_name}";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  foreach my $identity (@mlist)
   { if ($in{$identity})
      { my $e_identity = $dbh->quote($identity); 
        $command  = "insert into em_dlist_abook (dlc_name, dlc_identity) ";
        $command .= "values ($esq{dlc_name}, $e_identity)";
        ($sth, $db_msg) = $dbh->execute_stmt($command);
        &quit("$command failed: $db_msg") if ($db_msg);
      } 
   }
  $stat_msg .= "-- List $in{dlc_name} was changed successfully,<br>";
 }

 #*---------------------------------------------------------------
 #*- Delete an existing entry 
 #*---------------------------------------------------------------
 sub del_entry
 {
  #*--- check for mandatory entries
  unless ($in{dlc_name}) 
   { $stat_msg .= "-- The List field is mandatory,<br>"; return(); }
  &escape_q(); 

  #*-- delete the entry in the appropriate abook table
  $command = "delete from em_dlist where dlc_name = $esq{dlc_name}";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  #*-- delete entries in the abook_dlist table
  $command = "delete from em_dlist_abook where dlc_name = $esq{dlc_name}";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  $stat_msg .= "-- The List " . $in{dlc_name} . " entry was deleted,<br>";
  $in{opshun} = 'View'; #*-- return to the view window
 }

 #*---------------------------------------------------------------
 #*- Fill in the fields for an existing entry
 #*---------------------------------------------------------------
 sub fil_entry
 {
  &escape_q();
  $command   = "select dlc_name, dlc_description from em_dlist ";
  $command  .= "where dlc_name = $esq{dlc_name}";
  ($sth, $db_msg) = $dbh->execute_stmt("$command");
  &quit("$command failed: $db_msg") if ($db_msg);
  my @fields = $dbh->fetch_row($sth);
  my @dfields = qw/dlc_name dlc_description/;
  for my $i (0..$#fields) { $in{$dfields[$i]} = $fields[$i]; } 

  $command   = "select dlc_identity from em_dlist_abook ";
  $command  .= "where dlc_name = $esq{dlc_name}";
  ($sth, $db_msg) = $dbh->execute_stmt("$command");
  &quit("$command failed: $db_msg") if ($db_msg);
  while ( (my $identity) = $dbh->fetch_row($sth) ) { $in{$identity}++; }

 }

 #*---------------------------------------------------------------
 #*- Build the distr. lists to send and link to compose
 #*---------------------------------------------------------------
 sub sen_entry
 {
  #*-- get the names and e-mail ids from both tables
  my $dlists = ''; my (@dlists);
  $command   = "select dlc_name from em_dlist ";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  while ( (my $dlc_name) = $dbh->fetch_row($sth) )
     { push (@dlists, $dlc_name);
       $dlists .= &url_encode($dlc_name) . ","
                  if ($in{"se_$dlc_name"}); }
  &mod_session($dbh, $in{session}, 'del', 
                        map {'se_' . $_} @dlists);

  #*-- redirect to compose
  $dlists =~ s/,$//;
  my $e_session = &url_encode($in{session});
  my $url = $CGI_DIR . 
     "em_compose.pl?session=$e_session&dlists=$dlists&emails=&from=&to=" .
     "&cc=&subject=&text=";
  print "Location: $url", "\n\n"; exit(0);
 }

 #*---------------------------------------------------------------
 #*- Clear all fields for a new entry        
 #*---------------------------------------------------------------
 sub clr_entry
 { for (qw/dlc_name dlc_description/, @mlist) { $in{$_} = '';} }

 #*---------------------------------------------------------------
 #*- show a list of people in a table
 #*---------------------------------------------------------------
 sub view_html
 {

  #*-- get the lists from the dlist table              
  my %descr = (); 
  $command = "select dlc_name, dlc_description from em_dlist";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  while ( (my $name, my $description) = $dbh->fetch_row($sth) )
     { $descr{$name} = $description; }
  &mod_session($dbh, $in{session}, 'del', 
               map {'se_' . $_} keys %descr);

  #*-- build the html for the table
  my $body_html .= <<"EOF";
   <br>
   <table cellspacing=0 cellpadding=0 border=0 bgcolor=white>
   <tr><td> 
   <table cellspacing=4 cellpadding=0 border=2 bgcolor=lightblue>
   <tr>
     <td bgcolor=lightyellow> <font color=darkred> No. </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> Description </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> Name </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> Select </font> </td>
   </tr>
EOF

  my $i = 1; 
  foreach my $name (sort keys %descr)
   { 
    my $key = "se_$name";
    my $checked = ($in{$key}) ? "CHECKED": "";
    my $e_name    = &url_encode($name); 
    my $e_session = &url_encode($in{session}); 
    $body_html .= <<"EOF";
     <tr>
      <td bgcolor=white><font color=darkblue> $i    </font> </td>
      <td bgcolor=white><font color=darkblue> $descr{$name} </font> </td>
      <td bgcolor=white><font color=darkred size=+1> 
        <a href=$FORM?dlc_name=$e_name&opshun=Browse&session=$e_session> 
        $name </a> </font> </td>
      <td bgcolor=white> <input type=checkbox name="$key" $checked>   </td>
     </tr>
EOF
    $i++;
   }

  #*-- add a button to add lists
  $body_html .= <<"EOF";
     </table> 
    </td> </tr> 
    <tr><td colspan=4 align=center> <br> 
      <input type=submit name=opshun value=New> &nbsp;
      <input type=submit name=opshun value=Compose>
      <input type=hidden name=myself value=No>
    </td></tr> 
   </table>
EOF
  return(\$body_html);

 }

 #*---------------------------------------------------------------
 #*- Show the screen to view details of each entry   
 #*---------------------------------------------------------------
 sub entry_html
 {

  #*-- build the html for the lists 
  &escape_q(); my $i = 0; 
  my $mlist_html = "<table border=0 cellspacing=4 cellpadding=0> <tr>";
  foreach my $mlist (sort @mlist)
   { $mlist =~ s/"/\\"/g;
     my $mname = ($in{$mlist}) ? "<font color=red>$mlist</font>": $mlist; 
     $mlist_html .= "<td align=right>$mname</td><td><input ";
     $mlist_html .= " type=checkbox name=\"$mlist\" ";
     $mlist_html .= ($in{$mlist}) ? "CHECKED>": ">";
     $mlist_html .= "</td>";
     $mlist_html .= "</tr><tr>" if ((++$i % 6) == 0);
   }
  $mlist_html .= "</tr></table>";
  
  if ($in{opshun} eq 'New')
   { $in{dlc_name} = $in{dlc_description} = ''; 
     &msg_html("Enter a list name and description <br>"); }

  #*-- show the name, identity, e-mail, and notes fields
  my $body_html .= <<"EOF";
  <table cellspacing=2 cellpadding=0 border=0>
  <tr> <td colspan=2> <br> </td> </tr>
  <tr>
    <td> <font color=darkred size=+1> *Name: </font> </td>
    <td> <textarea name=dlc_name cols=70 rows=1>$in{dlc_name}</textarea></td>
  </tr>

  <tr>
    <td> <font color=darkred size=+1> Description: </font> </td>
    <td> 
   <textarea name=dlc_description cols=70 rows=1>$in{dlc_description}</textarea>
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

  <tr>
    <td valign=top> <font color=darkred size=+1> Members: </font> </td>
    <td> $mlist_html </td>
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
  $in{dlc_name} =~ s/"/'/g; #*-- cannot handle " in list name
  foreach (qw/dlc_name dlc_description/)
   { $in{$_} = '' unless ($in{$_}); 
     $in{$_} =~ s/^\s+//; $in{$_} =~ s/\s+$//;
     $esq{$_} = $dbh->quote($in{$_}); }
 }

 #*---------------------------------------------------------------
 #*- Exit with a message            
 #*---------------------------------------------------------------
 sub quit
 {
  print ${my $ref_val = &email_head("Lists", $FORM, $in{session})};
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
