#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
#*----------------------------------------------------------------
#*- db_save.pl
#*-  
#*-   Summary: Backup and Restore tables/database from files       
#*-            Select a database and tables to backup or restore.
#*----------------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::MyProc;
 use TextMine::Utils qw/parse_parms url_encode mod_session dirChooser/;
 use TextMine::Constants qw/$CGI_DIR $ICON_DIR $DB_NAME $ISEP
               $UTILS_DIR $EQUAL   $OSNAME   $PERL_EXE clean_filename/;

 use vars (
   '%in',		#*-- hash for form fields
   '$current_db',	#*-- selected database
   '$dbh',		#*-- database handle for tables
   '$l_dbh',		#*-- database handle for tm
   '$sth',		#*-- statement handle
   '$command',		#*-- SQL Command
   '@tables',		#*-- list of tables to be backed up or restored
   '$body_html',	#*-- body of the page
   '$db_msg',		#*-- database error message
   '$stat_msg',		#*-- status message
   '$ref_val',		#*-- reference value
   '$FORM',		#*-- name of form
   '$prc_status',	#*-- status of the backup/restore process
   '$prc_sub_tid',	#*-- tid of the backup/restore process
   '$prc_logdata',	#*-- log data to be shown in the table
   '$in_progress'	#*-- message for the page
   );

 #*-- set the initial global vars
 &set_vars();

 #*-- handle the selection of a file
 &file_handler();
 
 #*-- handle the functions
 &handle_functions();

 #*-- dump the html 
 &head_html(); 
 &gen_main_html();
 &msg_html($stat_msg) if ($stat_msg);
 print ("$body_html\n"); 
 &tail_html(); 

 #*-------------------------------------------------------
 #*- Set some global vars
 #*-------------------------------------------------------
 sub set_vars
 {
  #*-- set the form name and retrieve the passed fields     
  %in = %{$ref_val = &parse_parms()};
  $0 =~ s%.*[/\\]%%; $FORM = "$CGI_DIR" . "$0";
  $stat_msg = ''; my $start_time = time();

  #*-- set up the database, tables and columns                
  $current_db    = ($in{c_db} or "$DB_NAME");
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $in{userid}, 'Password' => $in{password},
       'Dbname' => $current_db);
  @tables  = $dbh->show_tables();

  #*-- get a second database handle for the tm database
  ($l_dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $in{userid}, 'Password' => $in{password},
       'Dbname' => $DB_NAME);

  #*-- handle the checkboxes separately
  unless ($in{dir_opshun})
   {
    #*-- modify the session data to reflect selected tables
    #*-- clean out the tables session data
    &mod_session($l_dbh, $in{session}, 'del', @tables);

    #*-- build a new hash for the tables
    my %s_tables = (); $s_tables{$_}++ foreach CGI::param("tables");
    my @sess_data = ();
    foreach my $table (@tables)
     { push (@sess_data, $table); 
       push (@sess_data, ($s_tables{$table}) ? 1: 0); }

    #*-- update the session data with new tables selected
    &mod_session($l_dbh, $in{session}, 'mod', @sess_data);

    #*-- fetch the page fields in the 'in' hash again
    %in = %{$ref_val = &mod_session($l_dbh, $in{session}, 'all')};
   }

  &refresh_fields();

  #*-- clean up the session data
  my @dparms = qw/dir_opshun opshun/;
  &mod_session($l_dbh, $in{session}, 'del', @dparms); 
  
  #*-- set defaults
  foreach (qw/dir_opshun opshun tid c_file/)
    { $in{$_} = '' unless ($in{$_}); }
 }

 #*-------------------------------------------------------
 #*- Select a file to backup to or restore from
 #*-------------------------------------------------------
 sub file_handler
 {

  #*-- if choosing a file
  if ($in{dir_opshun} eq 'selecting_dir')
   { $in{dir_opshun} = '';
     &mini_head_html();
     $body_html = ${$ref_val = &dirChooser( $FORM, 
       $in{dir_cdrive}, 'Select a File', 1, $in{session}) };
     print ("$body_html\n");
     &mini_tail_html(); }

  #*-- if we have chosen a directory, then set the current drive field
  if ($in{dir_opshun} eq "OK")
   { $in{c_file} = $in{dir_cdrive}; 
     $in{dir_opshun} = ''; 
     $stat_msg .= " -- <font color=red> Warning: </font> " . 
               "$in{c_file} is not a file or does not exist ...<br>"  
                unless(-f $in{c_file});
     return; }

  #*-- if option is to choose a file, display the select screen
  if ($in{opshun} eq "Select File")
   { &mini_head_html();
     $body_html = ${$ref_val = &dirChooser( $FORM, 
       $in{c_file}, 'Select a File', 1, $in{session})};
     print ("$body_html\n");
     &mini_tail_html(); }

 }

 
 #*--------------------------------------------------
 #*- Handle the options backup and restore options 
 #*--------------------------------------------------
 sub handle_functions
 {
  #*-- like a new start
  if ($in{opshun} =~ /^(?:Restart)/i)
   { $prc_status = $prc_sub_tid = $prc_logdata = ''; 
     my @dparms = qw/tid c_file opshun dir_opshun/; 
     push(@dparms, @tables);
     &mod_session($l_dbh, $in{session}, 'del', @dparms);
     %in = %{$ref_val = &mod_session($l_dbh, $in{session}, 'all')};
     $in{c_file} = $in_progress = ''; }

  #*-- a file name and at least one table must be provided
  my $table_ok = 0; foreach (@tables) { $table_ok = 1 if ($in{$_}); }
  unless ($table_ok)   { $stat_msg .= "-- Select 1 or more tables"; return; }
  unless ($in{c_file}) { $stat_msg .= "-- Enter a filename"; return; }

  #*-- the file must be opened for output
  if (!$in_progress && $in{opshun} =~ /^Backup/)
   { unless ( open (IN, ">>", &clean_filename("$in{c_file}")) )
     { $stat_msg .= "-- Could not append to <font color=darkred>" . 
                 " $in{c_file} </font> because $! <br>"; return; }
     close(IN);
     &create_entry();&start_process();&refresh_fields(); $in_progress = 1; }

  #*-- the file must be opened for input
  if (!$in_progress && $in{opshun} =~ /^Restore/)
   { unless ( open (IN, "<", &clean_filename("$in{c_file}")) )
     { $stat_msg .= "-- Could not read <font color=darkred>" . 
       " $in{c_file} </font> because $! <br>"; return; }
     close(IN);
     unless(-T $in{c_file})
     { $stat_msg .= "-- <font color=darkred> $in{c_file} " .
       " is not a text file </font> because $!. <br>"; return; } 
     &create_entry();&start_process();&refresh_fields(); $in_progress = 1; }

  #*-- Change the status for other functions
  if ($in_progress && $in{opshun} =~ /^(?:Stop|Restart)/i)
   { $command = "update co_proctab set prc_status = " .
                " 'Task stopped ...' where pri_tid = $in{tid}"; 
     (undef, $db_msg) = $l_dbh->execute_stmt($command);
     &quit("$command failed because $db_msg") if ($db_msg); }

 }
 
 #*--------------------------------------------------------
 #*- create a new entry in the proctab 
 #*--------------------------------------------------------
 sub create_entry
 {
  $in{tid} = time(); local $" = ' ';
  my @s_tables = ();
  foreach (@tables) { push (@s_tables, $_) if ($in{$_}); }
  my $task_info = $l_dbh->quote(join ($ISEP, $in{opshun}, "@s_tables", 
                        $in{c_db}, $in{c_file}));
  $command = "insert into co_proctab values ($in{tid}, 0, " .
             " '$in{opshun} in progress...', '', $task_info)";
  (undef, $db_msg) = $l_dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  &mod_session($l_dbh, $in{session}, 'mod', 'tid', "$in{tid}");
 }
 
 #*--------------------------------------------------------
 #*- Refresh fields to show current tid data
 #*--------------------------------------------------------
 sub refresh_fields
 {
  #*-- check if the tid exists in the proctab table
  $l_dbh->execute_stmt("lock tables co_proctab WRITE");
  if ($in{tid})
   { $command = "select prc_status, prc_sub_tid, prc_logdata from " .
               "co_proctab where pri_tid = $in{tid}";
     ($sth, $db_msg) = $l_dbh->execute_stmt($command);
     &quit("$command failed because $db_msg") if ($db_msg);
     ($prc_status, $prc_sub_tid, $prc_logdata) = $l_dbh->fetch_row($sth);}
  $l_dbh->execute_stmt("unlock tables"); 

  #*-- initialize the process fields
  unless ($prc_status)
   { $prc_status = $prc_sub_tid = $prc_logdata = ''; }
  else
   { $in_progress = ($prc_status =~ /progress/i) ? 1: 0; } 
 }
 
 #*--------------------------------------------------------------
 #*- Start an independent process to backup or restore tables 
 #*--------------------------------------------------------------
 sub start_process
 {
  (my $file = $in{c_file}) =~ s%\\%/%g;
  my @cmdline = ("$UTILS_DIR" . "db_proc.pl " ,
   join $ISEP, $in{tid}, $in{userid}, $in{password});
  $stat_msg .= "-- $in{opshun} in progress.... <br>";
  my $retval = &create_process(\@cmdline, 1, 'Perl.exe -T', "$PERL_EXE");
  return(0);
 }

 #*---------------------------------------------------------------
 #*- generate the html for the table selection page
 #*---------------------------------------------------------------
 sub gen_main_html
 {
  my ($sql_field);

  #*-- get the list of databases 
  my $db_option = '';
  foreach ($dbh->show_dbs())
   { $db_option    .= ($_ eq $current_db) ? 
      "<option value='$_' selected> $_": "<option value='$_'> $_"; }

  #*-- get the list of tables for the current database and handle
  #*-- the checkboxes
  my $tab_option = '<table border=0 cellspacing=0 cellpadding = 0> <tr>';
  my $i = 0; 
  foreach my $table (@tables)
   { my $checked = ($in{$table}) ? "CHECKED": '';
     $tab_option .=<<"EOF";
      <td> <input type=checkbox name=tables value='$table' $checked>
           <font color=darkblue size=3> $table </font> </td>
      <td width=10> &nbsp; </td>
EOF
     $tab_option .= "</tr><tr>" unless (++$i % 3);
   }
  $tab_option .= "</tr></table> </td>";

  #*-- parse the log data and display
  my @ldata = split/$EQUAL/, $prc_logdata;
  my $log_html = '<table border=0 cellspacing=0 cellpadding=0>';
  my @task_d = split/$ISEP/, $ldata[0] if ($ldata[0]);
  if (@task_d)
   { 
     my $part1 = ($task_d[0] =~ /Backup/i) ? "from": "to";
     my $part2 = ($task_d[0] =~ /Backup/i) ? "to"  : "from";
     $log_html .= <<"EOF";
      <tr> <td> <font color=darkblue> Task: <font color=darkred>
      $task_d[0] </font> $task_d[1] <font color=darkred> $part1
      Database: </font> $task_d[2] <font color=darkred> $part2 File: </font>
EOF
     $log_html .= $task_d[3] . " </font> </td></tr>";
   }
  foreach (@ldata[1..$#ldata])
   { $log_html .= "<tr><td> <font color=darkblue> $_ </font> </td></tr>"; }
  $log_html .= "</table>";

  my $buttons_html = '<table border=0 cellspacing=0 cellpadding=0>';
  unless ($in_progress)
   { $buttons_html .= <<"EOF";
      <tr>
       <td> <input type=submit name=opshun value=Backup> </td>
       <td width=10> &nbsp; </td>
       <td> <input type=submit name=opshun value=Restore> </td>
       <td width=10> &nbsp; </td>
       <td> <input type=submit name=opshun value=Restart> </td>
      </tr>
EOF
   }
  else
   { $buttons_html .= <<"EOF";
      <tr>
       <td> <input type=submit name=opshun value=Stop> </td>
       <td width=10> &nbsp; </td>
       <td> <input type=submit name=opshun value=Refresh> </td>
       <td width=10> &nbsp; </td>
       <td> <input type=submit name=opshun value=Restart> </td>
      </tr>
EOF
   }
  $buttons_html .= "</table>";

  #*-- build the html
  $body_html = <<"EOF";
   <tr>
    <td> <font color=darkred size=4> Choose a Database:*</font> </td>
    <td> 
      <strong>
      <select name=c_db size=1 
              onChange="loadDB(this.options[this.selectedIndex].value);"> 
              $db_option </select>
      </strong> </td>
   </tr>

   <tr>
    <td valign=top><font color=darkred size=4> Choose Table(s):*</font></td> 
    <td> $tab_option </td>
   </tr>

   <tr>
    <td colspan=2> 
      <table border=0 cellspacing=0 cellpadding=4>
       <tr>
         <td><font color=darkred size=4> File:* </font></td> 
         <td> <strong>
              <textarea name=c_file rows=1 cols=75>$in{c_file}</textarea>
              </strong> </td>
         <td> <strong><input type=submit name=opshun value="Select File">
              </strong> </td>
       </tr>
       </table> 
      </td>
   </tr>

   <tr> <td align=center colspan=2> $buttons_html </td> </tr>

   <tr> <td colspan=2><br> <hr size=3> </td> </tr>

   <tr>
     <td colspan=2> <font color=darkred size=4> Log: </font> $log_html </td>
   </tr>

EOF
  }  
  
 #*---------------------------------------------------------------
 #*- display the header html 
 #*---------------------------------------------------------------
 sub head_html
 {

  my $e_file      = ($in{c_file}) ? &url_encode($in{c_file}): '';
  my $e_session   = &url_encode($in{session});
  my $dbb_image   = "$ICON_DIR" . "dbb.jpg";
  my $anchor = "$CGI_DIR/co_login.pl?session=$e_session";
  print "Content-type: text/html\n\n";
  print << "EOF";
   <html>
    <head>
     <title> Database Backup/Restore Page </title>
    </head>
  
    <body bgcolor=white>
     <form method=POST action="$FORM" name="dbform">
     <center>

      <script>
       function loadDB(dbparm)
        { location.href="$FORM?c_db=" + dbparm +
             "&c_table=&c_file=$e_file&session=$e_session"; }
      </script>

      <table> <tr> <td> <a href=$anchor>
              <img src="$dbb_image" border=0> </a> </td> </tr> </table>
      <br>
      <table width=80%>
EOF

 }

 #*---------------------------------------------------------------
 #*- Dump the end of the html page 
 #*---------------------------------------------------------------
 sub tail_html
 {
  $dbh->disconnect_db()       if ($dbh);
  $l_dbh->disconnect_db($sth) if ($l_dbh);
  print << "EOF";
    </table>
    </center>
     <input type=hidden name=session value='$in{session}'>
   </form>
  </body>
  </html>
EOF
  exit(0);

 }

 #*---------------------------------------------------------------
 #*- Print the error message for SQL Commands and exit
 #*---------------------------------------------------------------
  sub quit
  { &gen_main_html();   &head_html();
    &msg_html("$_[0]"); print ("$body_html");
    &tail_html();
   }

 #*---------------------------------------------------------------
 #*- Print the error message for a form error and exit
 #*---------------------------------------------------------------
  sub msg_html
  {  
    print << "EOF";
    <tr> <td colspan=6> <font color=darkred size=4> Message: </font> 
         <font color=darkblue size=4> $_[0] </font> </td>
    </tr> 
EOF
   }
   
 #*---------------------------------------------------------------
 #*- display a small header 
 #*---------------------------------------------------------------
 sub mini_head_html
 {
  print "Content-type: text/html\n\n";
  print << "EOF";
   <html>
    <head>
     <title> Database Save Page </title>
    </head>
  
    <body bgcolor=white>
     <form method=POST action="$FORM">
     <center>
EOF
 }

 #*---------------------------------------------------------------
 #*- Dump a smaller end of the html page 
 #*---------------------------------------------------------------
 sub mini_tail_html
 {
  $dbh->disconnect_db() if ($dbh);
  $l_dbh->disconnect_db($sth)   if ($l_dbh);
  print << "EOF";
    </center>
    <input type=hidden name=tid value='$in{tid}'>
    <input type=hidden name=session value='$in{session}'>
   </form>
  </body>
  </html>
EOF
  exit(0);

 }
