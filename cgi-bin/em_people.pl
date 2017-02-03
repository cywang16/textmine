#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
#*----------------------------------------------------------------
#*- em_people.pl
#*-  
#*-   Summary: The default function is to view a list of people. 
#*-       Other functions include add, update, and delete. If no people
#*-       are available in view, them show the add screen.
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
  '$command',	#*-- SQL Command
  '$ref_val',	#*-- reference value
  '%esq',	#*-- hash for escaped values
  '$FORM',	#*-- name of this form
  '%in',	#*-- hash for form fields
  '@dlists',	#*-- list of distribution lists
  '$e_session',	#*-- URL Encoded session
  '$rows_per_pg'	#*-- number of rows per page 
  );

 #*-- retrieve and set variables
 &set_vars();

 #*-- handle the options
 &vis_entry() if ($in{opshun} eq 'Visualize');
 &add_entry() if ($in{opshun} eq 'Save');
 &upd_entry() if ($in{opshun} eq 'Update');
 &del_entry() if ($in{opshun} eq 'Delete');
 &fil_entry() if ($in{opshun} eq 'Browse');
 &sen_entry() if ($in{opshun} eq 'Compose');
 &clr_entry() if ($in{opshun} eq 'New');

 #*-- set default values
 $in{opshun} = 'View' unless ($in{opshun});
 unless (&count_entries()) { $in{myself} = 'Yes'; $in{opshun} = 'New'; }

 #*-- dump the header, status, body and tail html 
 print ${$ref_val = &email_head("People", $FORM, $in{session})}; 
 &msg_html($stat_msg) if ($stat_msg); 
 print ${$ref_val = ($in{opshun} eq 'View') ? &view_html(): &entry_html()};
 &tail_html(); 

 exit(0);


 #*-----------------------------------------------------
 #*- Set some global vars            
 #*-----------------------------------------------------
 sub set_vars
 {
  #*-- retrieve the passed parameters and set the form name
  $0 =~ s%.*[/\\]%%; $FORM = "$CGI_DIR" . "$0";
  %in    = %{$ref_val = &parse_parms};
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $in{userid}, 'Password' => $in{password},
       'Dbname' => $DB_NAME);

  #*-- build the collection of distribution lists in an array
  @dlists = (); my $dlist; 
  $command = "select dlc_name from em_dlist";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  push(@dlists, $dlist) while ( ($dlist) = $dbh->fetch_row($sth) );

  #*-- handle the checkboxes separately, checkboxes maybe on
  #*-- multiple pages, checked/unchecked info is saved in the session
  if ($in{people_cbox})
   {
    my @se_people = split/\s+/, $in{people_cbox};
    &mod_session($dbh, $in{session}, 'del', @se_people);
    my %s_people = (); $s_people{$_}++ foreach CGI::param("people");
    my @sess_data = ();
    foreach my $person (@se_people)
     { push (@sess_data, $person);
       push (@sess_data, ($s_people{$person}) ? 1: 0); }
    &mod_session($dbh, $in{session}, 'mod', @sess_data);
    %in = %{$ref_val = &mod_session($dbh, $in{session}, 'all')};
   }
  
  #*-- set the forgetful parms
  my @dparms;
  push (@dparms, @dlists, 'opshun', 'p_opshun', 'letter'); 
  foreach (@dparms) { $in{$_} = '' unless ($in{$_}); }
  &mod_session($dbh, $in{session}, 'del', @dparms);
  $e_session = &url_encode($in{session});
  $rows_per_pg = 12;
 }

 #*---------------------------------------------------------------
 #*- add an entry if possible and set the status message
 #*---------------------------------------------------------------
 sub add_entry
 {

  #*--- check for mandatory entries
  unless ($in{abc_name})  
    { $stat_msg .= "-- The Name field is mandatory,<br>"; }
  unless ($in{abc_identity})  
    { $stat_msg .= "-- The Identity field is mandatory,<br>"; }
  unless ($in{abc_email}) 
    { $stat_msg .= "-- The E-Mail field is mandatory,<br>"; }
  return() unless ($in{abc_name} && $in{abc_identity} && $in{abc_email});

  #*-- identity should not contain spaces
  if ($in{abc_identity} =~ /\S\s\S/) 
   { $in{abc_identity} =~ s/\s/_/g; return(); }

  #*-- check for a duplicate entry
  &escape_q(); 
  foreach my $table (qw/em_abook em_abook_home/)
   {
    $command  = "select count(*) from $table where ";
    $command .= " abc_identity = $esq{abc_identity}";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit("$command failed: $db_msg") if ($db_msg);
    if ( ($dbh->fetch_row($sth))[0] > 0)
     { my $msg = ($table eq 'em_abook_home') ? "Private": "Public"; 
       $stat_msg .= $in{abc_identity} . " exists in the $msg Address Book,"; 
       $stat_msg .= " Press Update "; 
       return(); }
   } #*-- end of for

  #*-- build the insert statement, separate insert statements
  #*-- for self e-mail address and other e-mail addresses
  my ($table, $c_command, $v_command);
  if ($in{myself} eq 'Yes')
   { $table = "em_abook_home"; 
     $c_command = ", abc_signature, abc_private_key, abc_keywords";
     $v_command = ", $esq{abc_signature}, $esq{abc_private_key}, 
                     $esq{abc_keywords}"; }
  else
   { $table = "em_abook"; $c_command = $v_command = ''; }
  $command = <<"EOF";
     insert into $table (abc_identity, abc_name, abc_email, abc_public_key, 
                         abc_notes $c_command ) 
            values ($esq{abc_identity}, $esq{abc_name}, $esq{abc_email}, 
                    $esq{abc_public_key}, $esq{abc_notes} $v_command)
EOF
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  #*-- delete and add entries in the abook_dlist table
  $command  = "delete from em_dlist_abook where ";
  $command .= " dlc_identity = $esq{abc_identity}";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  foreach my $dlist (@dlists)
   { if ($in{$dlist})
      { my $e_dlist = $dbh->quote($dlist); 
        $command  = "insert into em_dlist_abook (dlc_name, dlc_identity) ";
        $command .= "values ($e_dlist, $esq{abc_identity})";
        (undef, $db_msg) = $dbh->execute_stmt($command);
        &quit("$command failed: $db_msg") if ($db_msg);
      } 
   }
  $stat_msg .= $in{abc_identity} . " was added,<br>";

 }

 #*---------------------------------------------------------------
 #*- Update an existing entry 
 #*---------------------------------------------------------------
 sub upd_entry
 {

  #*--- check for mandatory entries
  unless ($in{abc_name}) 
   { $stat_msg .= "-- The Name field is mandatory,<br>"; }
  unless ($in{abc_identity})  
   { $stat_msg .= "-- The Identity field is mandatory,<br>"; }
  unless ($in{abc_email}) 
   { $stat_msg .= "-- The E-Mail field is mandatory,<br>"; }
  return() unless ($in{abc_name} && $in{abc_identity} && $in{abc_email});

  #*-- check if the entry exists
  &escape_q(); 
  my $table = ($in{myself} eq 'Yes') ? "em_abook_home": "em_abook";
  $command  = "select count(*) from $table where ";
  $command .= "abc_identity = $esq{abc_identity}";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  if ( ($dbh->fetch_row($sth))[0] == 0)
   { my $msg = ($in{myself} eq 'Yes') ? "Private": "Public"; 
     $stat_msg .= $in{abc_identity} . 
                  " does not exist in the $msg Address Book,"; 
     return(); }

  #*-- build the update statement
  $command = "update $table set ";
  foreach (qw/abc_name abc_identity abc_email abc_notes abc_public_key/)
   { $command .= " $_ = $esq{$_},"; }
  if ($in{myself} eq 'Yes')
   { foreach (qw/abc_private_key abc_signature abc_keywords/)
      { $command .= " $_ = $esq{$_},"; }
   }
  $command =~ s/,$//;  
  $command .= " where abc_identity = $esq{abc_identity}";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  #*-- delete and add entries in the abook_dlist table
  $command  = "delete from em_dlist_abook where ";
  $command .= " dlc_identity = $esq{abc_identity}";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  foreach my $dlist (@dlists)
   { if ($in{$dlist})
      { my $e_dlist = $dbh->quote($dlist); 
        $command  = "insert into em_dlist_abook (dlc_name, dlc_identity) ";
        $command .= "values ($e_dlist, $esq{abc_identity})";
        (undef, $db_msg) = $dbh->execute_stmt($command);
        &quit("$command failed: $db_msg") if ($db_msg);
      } 
   }
  $stat_msg .= $in{abc_identity} . " was changed successfully,<br>";
 }

 #*---------------------------------------------------------------
 #*- Visualize an existing entry's network using Pajek
 #*---------------------------------------------------------------
 sub vis_entry
 {
  $in{opshun} = 'Browse';

  #*-- create a .net file in the temp directory with the vertice 
  #*-- and edges information
  my $tfile = $TMP_DIR . "email.net";
  open (OUT, ">", &clean_filename("$tfile")) || 
       &quit ("Unable to open $tfile $!\n");
#  binmode OUT, ":raw";
  &escape_q(); 

  #*-- build the from/to emails of the network
  my %vertices = my %arcs = ();
  $command  = "select nec_from, nec_to, nei_count from em_network";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  my $i = 1;
  while ( (my $from, my $to, my $count) = $dbh->fetch_row($sth) )
   { 
    #next if ($count <= 10);
    $from = lc($from); $to = lc($to); 
    $vertices{$from} = $i++ unless($vertices{$from}); 
    $vertices{$to}   = $i++ unless($vertices{$to}); 
    $arcs{"$from,$to"} = $count; 
   }

  #*-- first dump the vertices
  print OUT "*Vertices ", scalar keys %vertices, "\n";
  foreach my $key (sort {$vertices{$a} <=> $vertices{$b}} keys %vertices)
   { 
     my $loc = ($esq{abc_email} =~ /$key/i) ? "0.5 0.5 0.5": '';
     (my $tkey = $key) =~ s/@.*$//;
     print OUT "$vertices{$key} \"$tkey\" $loc\n"; } 

  #*-- next dump the arcs
  print OUT "*Arcs\n";
  foreach my $key (sort keys %arcs)
   {
    (my $from, my $to) = $key =~ /(.*),(.*)/;
    print OUT "$vertices{$from} $vertices{$to} $arcs{\"$from,$to\"}\n";
   }
  close(OUT);

  $stat_msg .= "-- A email.net file was created in $TMP_DIR --";

  return();

 }

 #*---------------------------------------------------------------
 #*- Delete an existing entry 
 #*---------------------------------------------------------------
 sub del_entry
 {
  #*--- check for mandatory entries
  unless ($in{abc_identity}) 
   { $stat_msg .= "-- The Identity field is mandatory,<br>"; return(); }
  &escape_q(); 

  #*-- delete the entry in the appropriate abook table
  my $table = ($in{myself} eq 'Yes') ? "em_abook_home": "em_abook";
  $command = "delete from $table where abc_identity = $esq{abc_identity}";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  #*-- delete entries in the abook_dlist table
  $command  = "delete from em_dlist_abook where ";
  $command .= " dlc_identity = $esq{abc_identity}";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  $stat_msg .= "-- The " . $in{abc_identity} . " entry was deleted,<br>";
  $in{opshun} = 'View'; 

 }

 #*---------------------------------------------------------------
 #*- Fill in the fields for an existing entry
 #*---------------------------------------------------------------
 sub fil_entry
 {
  #*-- try retrieval from public and the private address book
  &escape_q();
  $command   = "select abc_identity, abc_name, abc_public_key, " .
               " abc_notes, abc_email ";
  my $s_command = "from em_abook where abc_identity = $esq{abc_identity}";
  ($sth, $db_msg) = $dbh->execute_stmt("$command $s_command");
  &quit("$command failed: $db_msg") if ($db_msg);
  my @fields = $dbh->fetch_row($sth);
  unless ($fields[0])
   {
    $command .= ", abc_signature, abc_private_key, abc_keywords"; 
    $s_command = "from em_abook_home where abc_identity =$esq{abc_identity}";
    ($sth, $db_msg) = $dbh->execute_stmt("$command $s_command");
    &quit("$command failed: $db_msg") if ($db_msg);
    @fields = $dbh->fetch_row($sth);
   }
  
  my @dfields = qw/abc_identity abc_name abc_public_key abc_notes abc_email
                   abc_signature abc_private_key abc_keywords/;
  for my $i (0..$#fields) { $in{$dfields[$i]} = $fields[$i]; } 

  #*-- fill in the lists where the person is a member
  $command   = "select dlc_name from em_dlist_abook ";
  $command  .= "where dlc_identity = $esq{abc_identity}";
  ($sth, $db_msg) = $dbh->execute_stmt("$command");
  &quit("$command failed: $db_msg") if ($db_msg);
  while ( (my $name) = $dbh->fetch_row($sth) ) { $in{$name}++; }

 }

 #*---------------------------------------------------------------
 #*- Build the e-mail list to send and link to compose
 #*---------------------------------------------------------------
 sub sen_entry
 {
  #*-- get the names and e-mail ids from both tables
  my $emails = '';
  foreach (qw/em_abook_home em_abook/)
   {
    $command = "select abc_identity from $_";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit("$command failed: $db_msg") if ($db_msg);
    while ( (my $identity) = $dbh->fetch_row($sth) )
     { $emails .= "$identity," if ($in{"se_$identity"}); }
   }

  #*-- save the current page number
  &mod_session($dbh, $in{session}, 'mod', 'cpage', $in{cpage});

  #*-- redirect to compose
  $emails =~ s/,$//;
  my $url = $CGI_DIR . 
   "em_compose.pl?session=$e_session&emails=$emails&dlists=&from=&to=" .
   "&subject=&cc=&text=";
  print "Location: $url", "\n\n"; exit(0); 

 }

 #*---------------------------------------------------------------
 #*- Clear all fields for a new entry        
 #*---------------------------------------------------------------
 sub clr_entry
 {
  for (qw/abc_identity abc_name abc_public_key abc_notes abc_email
   abc_signature abc_private_key abc_keywords/, @dlists) { $in{$_} = '';}
  $in{myself} = 'Yes';
  $stat_msg .= "-- Enter a person's information";
 }

 #*---------------------------------------------------------------
 #*- count the number of entries in the address books
 #*---------------------------------------------------------------
 sub count_entries
 {
  #*-- count the number of entries in the abook and abook_home tables
  my $pcount = 0;
  for (qw/em_abook em_abook_home/)
   {
    ($sth, $db_msg) = $dbh->execute_stmt("select count(*) from $_");
    &quit("$command failed: $db_msg") if ($db_msg);
    ($pcount) += ($dbh->fetch_row($sth))[0];
   }
  return($pcount);
 }

 #*---------------------------------------------------------------
 #*- show a list of people in a table
 #*---------------------------------------------------------------
 sub view_html
 {

  #*-- get the names and e-mail ids from both tables
  my %name = my %email = my %myself = ();
  foreach (qw/em_abook_home em_abook/)
   {
    $command = "select abc_email, abc_identity, abc_name from $_";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit("$command failed: $db_msg") if ($db_msg);
    while ( (my $email, my $identity, my $name) = $dbh->fetch_row($sth) )
     { $name{$identity} = $name; $email{$identity} = $email; 
       $myself{$identity} = ($_ eq 'em_abook_home') ? 'Yes':'No'; }
   }

  #*-- compute the current page number
  my $num_ids = keys %name;
  my $num_pages = ($num_ids >= $rows_per_pg) ?
               int($num_ids / $rows_per_pg): 0;
  $num_pages++   if ( ($num_ids % $rows_per_pg) != 0);

  $in{cpage}++            if ($in{p_opshun} eq 'Next');
  $in{cpage}--            if ($in{p_opshun} eq 'Prev');
  $in{cpage} = 1          if ($in{p_opshun} eq 'First');
  $in{cpage} = $num_pages if ($in{p_opshun} eq 'Last');

  #*-- set the start file depending on page number or letter
  my $i = 0;
  if ($in{letter})
   { $in{cpage} = 0;
     foreach ( sort keys %name) 
      { last if ($in{letter} lt ucfirst(substr($_, 0, 1)) ); 
        $in{cpage}++ unless ($i++ % $rows_per_pg); }
   }

  #*-- make sure that current page is in range
  $in{cpage} = 1          unless($in{cpage});
  $in{cpage} = $num_pages if ($in{cpage} > $num_pages);
  $in{cpage} = 1          if ($in{cpage} < 1);

  #*-- save the current page number
  &mod_session($dbh, $in{session}, 'mod', 'cpage', $in{cpage});
  my $start_file = ($in{cpage} - 1) * $rows_per_pg;

  #*-- sort the ids by alphabet
  my @sort_files = (); $i = 0;
  foreach ( sort keys %name) { $sort_files[$i++] = $_; }

  my @files = ();
  for ($i = 0; $i < $rows_per_pg; $i++)
   { $files[$i] = $sort_files[$start_file + $i]
                  if ($sort_files[$start_file + $i]); }

  #*-- build the html for the table
  my $body_html .= <<"EOF";
   <br>
   <table cellspacing=0 cellpadding=0 border=0 bgcolor=white>
   <tr><td align=center> <br> 
      <input type=submit name=opshun value=New> &nbsp;
      <font color=darkred> Page $in{cpage} of $num_pages </font> 
                           &nbsp; &nbsp;
      <input type=submit name=p_opshun value=Next> &nbsp;
      <input type=submit name=p_opshun value=Prev> &nbsp;
      <input type=submit name=p_opshun value=First> &nbsp;
      <input type=submit name=p_opshun value=Last> &nbsp;
      <input type=submit name=opshun value=Compose>
      <input type=hidden name=myself value=No>
    </td></tr> 
   <tr><td align=center> <br>
   <table cellspacing=4 cellpadding=0 border=2 bgcolor=lightblue>
   <tr>
     <td bgcolor=lightyellow> <font color=darkred> No. </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> Identity </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> Name </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> E-Mail </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> Select </font> </td>
   </tr>
EOF
  my @se_people = map { 'se_' . $_} @files; local $" = ' ';
  &mod_session($dbh, $in{session}, 'mod', 'people_cbox', "@se_people");

  $i = $start_file + 1; 
  foreach my $identity (@files)
   { 
    my $key = "se_$identity";
    my $checked = ($in{$key}) ? "CHECKED": "";
    my $e_identity = &url_encode($identity); 
    $body_html .= <<"EOF";
     <tr>
     <td bgcolor=white><font color=darkblue> $i </font> </td>
     <td bgcolor=white><font color=darkred size=+1> 
         <a href=$FORM?abc_identity=$e_identity&opshun=Browse&myself=$myself{$identity}&session=$e_session> 
         $identity </a> </font> </td>
     <td bgcolor=white><font color=darkblue> $name{$identity}  </font> </td>
     <td bgcolor=white><font color=darkblue> $email{$identity} </font> </td>
     <td bgcolor=white> <input type=checkbox name=people 
         value="$key" $checked> </td>
     </tr>
EOF
    $i++;
   }

  #*-- add a button to add people
  my $let_html = '<tr>';
  for my $letter ('A'..'Z')
   { $let_html .= "<td><input type=submit name=letter value=\"$letter \"> " .
                  "</td>"; 
     $let_html .= "</tr><tr>" if ($letter eq 'M');
   }
  $let_html .= '</tr>';
  
  $body_html .= <<"EOF";
     </table> 
    <tr><td align=center> <br> 
      <table cellspacing=8 cellpadding=0 border=0>
        $let_html 
      </table>
    </td> </tr>
    </td> </tr> 
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
  my $dlist_html = "<table border=0 cellspacing=0 cellpadding=0> <tr>";
  foreach my $dlist (@dlists)
   { $dlist =~ s/"/\\"/g;
     $dlist_html .= "<td> $dlist <input type=checkbox name=\"$dlist\" ";
     $dlist_html .= ($in{$dlist}) ? "CHECKED>": ">";
     $dlist_html .= "</td>";
     $dlist_html .= "</tr><tr>" if ((++$i % 3) == 0);
   }
  $dlist_html .= "</tr></table>";

  #*-- show the name, identity, e-mail, and notes fields
  my $body_html .= <<"EOF";
  <table cellspacing=2 cellpadding=0 border=0>
  <tr> <td colspan=2> <br> </td> </tr>
  <tr>
    <td> <font color=darkred size=+1> *Name: </font> </td>
    <td> <textarea name=abc_name cols=70 rows=1>$in{abc_name}</textarea></td>
  </tr>

  <tr>
    <td> <font color=darkred size=+1> *Identity: </font> </td>
    <td> <textarea name=abc_identity cols=70 rows=1>$in{abc_identity}</textarea>
        </td>
  </tr>  

  <tr>
    <td> <font color=darkred size=+1> *E-Mail: </font> </td>
    <td> <textarea name=abc_email cols=70 rows=1>$in{abc_email}</textarea>
    </td>
  </tr>  

  <tr>
    <td> <font color=darkred size=+1> Notes: </font> </td>
    <td> <textarea name=abc_notes cols=70 rows=2>$in{abc_notes}</textarea> 
    </td>
  </tr>  

  <tr>
    <td> <font color=darkred size=+1> Public Key: </font> </td>
    <td> 
    <textarea name=abc_public_key cols=70 rows=2>$in{abc_public_key}</textarea> 
    </td>
  </tr>  

  <tr>
    <td valign=top> <font color=darkred size=+1> Member of: </font> </td>
    <td> $dlist_html </td>
  </tr>  
EOF

  if ($in{myself} eq 'Yes')
   {
    my ($no_check, $yes_check);
    if ($in{opshun} eq 'New') { $no_check = 'CHECKED'; $yes_check = ''; }
    else                      { $no_check = ''; $yes_check = 'CHECKED'; }
    $body_html .= <<"EOF";
     <tr>
      <td> <font color=darkred size=+1> Private Key: </font> </td>
      <td> 
   <textarea name=abc_private_key cols=70 rows=2>$in{abc_private_key}</textarea>
      </td>
     </tr>  

     <tr>
      <td> <font color=darkred size=+1> Signature: </font> </td>
      <td> 
   <textarea name=abc_signature cols=70 rows=2>$in{abc_signature}</textarea> 
      </td>
     </tr>  

     <tr>
      <td> <font color=darkred size=+1> Keywords: </font> </td>
      <td> 
   <textarea name=abc_keywords cols=70 rows=2>$in{abc_keywords}</textarea> 
      </td>
     </tr>  

     <tr>
      <td> <font color=darkred size=+1> Myself: </font> </td>
      <td> No  <input type=radio name=myself value='No'  $no_check>
           Yes <input type=radio name=myself value='Yes' $yes_check> </td>
     </tr>  
EOF
   } #*-- end of unless

 #*-- generate some statistics, if an e-mail is available
 if ($in{abc_email})
  {
   #*-- get the most frequent e-mails received
   my ($i, @from, @to, $sent, $received);
   $command = "select nec_from, nei_count from em_network where " .
      "nec_to LIKE " . $dbh->quote('%' . $in{abc_email} . '%') . 
      " order by 2 desc";
   ($sth, $db_msg) = $dbh->execute_stmt("$command");
   &quit("$command failed: $db_msg") if ($db_msg);
   $i = 0; @from = (); 
   while (@_ = $dbh->fetch_row($sth))
    { push(@from, "$_[0] ($_[1])"); last if (++$i == 3); }  
   my $most_freq_r = join ",", @from;

   #*-- get the number of e-mails sent last week
   my $start_date = time() - 604800; my $end_date = time();
   $command = "select count(*) from em_email where " .
     "emc_from LIKE " . $dbh->quote('%' . $in{abc_email} . '%') . " and " .
     "$start_date <= emi_date and emi_date <= $end_date";
   ($sth, $db_msg) = $dbh->execute_stmt("$command");
   &quit("$command failed: $db_msg") if ($db_msg);
   ($sent) = $dbh->fetch_row($sth);

   #*-- get the number of e-mails received last week
   $command = "select count(*) from em_email where " .
     "emc_to LIKE " . $dbh->quote('%' . $in{abc_email} . '%') . " and " .
     "$start_date <= emi_date and emi_date <= $end_date";
   ($sth, $db_msg) = $dbh->execute_stmt("$command");
   &quit("$command failed: $db_msg") if ($db_msg);
   ($received) = $dbh->fetch_row($sth);
   
   $body_html .= <<"EOF";
     <tr> <td colspan=2> <br> </td> </tr>
     <tr> <td colspan=2> 
        <font size=+1 color=darkred> E-mails from: </font>
        <font color=darkblue> $most_freq_r </font> </td> </tr>
     <tr> <td colspan=2> 
        <font size=+1 color=darkred> Sent </font>
        <font color=darkblue> $sent e-mails last week </font> </td> </tr>
     <tr> <td colspan=2> 
        <font size=+1 color=darkred> Received </font>
        <font color=darkblue> $received e-mails last week </font> </td> </tr>
EOF

  }

 #*-- dump the buttons
 $body_html .= <<"EOF";
     <tr> <td colspan=2> <br> </td> </tr>

     <tr>
      <td colspan=2 align=center> 
         <table border=0 cellspacing=24 cellpadding=0>
          <tr>
            <td> <input type=submit name=opshun value='New'> </td>
            <td> <input type=submit name=opshun value='Save'> </td>
            <td> <input type=submit name=opshun value='Update'> </td>
            <td> <input type=submit name=opshun value='Delete'> </td>
            <td> <input type=submit name=opshun value='View'> </td>
            <td> <input type=submit name=opshun value='Visualize'> </td>
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
  $in{abc_identity} =~ s/"/'/g; #*-- cannot handle "
  foreach (qw/abc_identity abc_name abc_notes abc_email 
              abc_public_key abc_private_key abc_signature abc_keywords/)
   { $in{$_} = '' unless ($in{$_}); 
     $in{$_} =~ s/^\s+//; $in{$_} =~ s/\s+$//;
     $esq{$_} = $dbh->quote($in{$_}); }
 }

 #*---------------------------------------------------------------
 #*- Exit with a message            
 #*---------------------------------------------------------------
 sub quit
 {
  print ${my $ref_val = &email_head("People", $FORM, $in{session})};
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
