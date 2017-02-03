#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
#*----------------------------------------------------------------
#*- db_monitor.pl
#*-  
#*-   Summary: Manage tables in databases. Display the contents of 
#*-            tables and modify the contents. 
#*----------------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Utils;
 use TextMine::Constants;

 #*-- global variables
 use vars (
   '$body_html',	#*-- body of the page
   '$db_msg',		#*-- database error message
   '$stat_msg',		#*-- status message for the page
   '$ref_val',		#*-- a reference variable
   '$edit_row_incr',	#*-- the number of rows to show for edit on a page
   '$view_row_incr',	#*-- the number of rows to show for display on a page
   '$current_db',	#*-- the current selected database
   '$current_table',	#*-- the current selected table
   '@tables',		#*-- the list of tables for the database 
   '$dbh',		#*-- database handle 
   '$sth',		#*-- statement handle
   '%in',		#*-- hash for page fields
   '$command',		#*-- var for SQL commands
   '@cols',		#*-- columns in the table
   '@sel_cols',		#*-- selected columns in the page
   '%num_field',	#*-- a hash for numeric fields 
   '%blob_field',	#*-- a hash for blob fields
   '%text_field',	#*-- a hash for character fields
   '$FORM'		#*-- the name of the FORM
   );

 #*-- retrieve the passed parameters and set default values
 &set_vars();

 #*-- Build the html body based on the option
 &run_sql() if ($in{sql_command});
 if    ($in{opshun} eq 'New')  { &gen_main_html(); }
 elsif ($in{opshun} eq 'Edit') { &gen_edit_html(); } 
 elsif ($in{opshun} eq 'View') { &gen_view_html(); } 

 #*-- dump the html 
 &head_html(); 
 print ("$body_html\n"); 
 &msg_html($stat_msg) if ($stat_msg);
 &tail_html(); 

 exit(0);

 #*---------------------------------------------------------------
 #*- Set parameters and variables 
 #*---------------------------------------------------------------
 sub set_vars
 {

  #*-- set the form name and fetch the form fields
  $0 =~ s%.*[/\\]%%; $FORM = "$CGI_DIR" . "$0";
  %in = %{$ref_val = &parse_parms()};

  #*-- establish DB connection
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $in{userid}, 'Password' => $in{password},
       'Dbname' => $DB_NAME);
  &quit("Connect failure: $db_msg") if ($db_msg);

  #*-- initialize some fields to nulls
  my @dparms = qw/opshun p_opshun e_opshun view.x edit.x/;
  foreach (@dparms, 'current_row', 'sql_command', ) 
    { $in{$_} = '' unless ($in{$_}); }

  #*-- set the option
  $stat_msg = '';
  $in{opshun} = 'Edit' if ($in{'edit.x'});         
  $in{opshun} = 'View' if ( ($in{'view.x'}) || ($in{e_opshun} eq 'View') ); 
  $in{opshun} = 'New'  if ($in{p_opshun} eq 'Cancel');        
  $in{opshun} = ($in{opshun}  or 'New');
  $edit_row_incr = 1; $view_row_incr = 10;

  &mod_session($dbh, $in{session}, 'del', @dparms);
  &mod_session($dbh, $in{session}, 'mod', 'opshun', "$in{opshun}");
  $dbh->disconnect_db();
  
  #*-- set up the database, tables and columns lists
  #*-- the default database is the TextMine database or mysql                
  $current_db    = ($in{c_db} or "$DB_NAME" or 'mysql');
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $in{userid}, 'Password' => $in{password},
       'Dbname' => $current_db);
  &quit("Connect failure: $db_msg") if ($db_msg);
#*---------------------------------------------
#*- restrict access to the admin alone
#*---------------------------------------------
#  &quit("Retricted to the Admin") unless ($in{userid} =~ /admin/);

  #*-- select the current table and get the list of selected columns
  @tables = $dbh->show_tables();
  $current_table = ($in{c_table} or $tables[0]);
  @sel_cols = &get_columns($in{sql_command});

 }

 #*---------------------------------------------------------------
 #*- run a sql command depending on the option and set appropriate
 #*- messages 
 #*---------------------------------------------------------------
 sub run_sql
 {

  #*-- run the select command if paging and edit options are not reqd.
  #*-- return if there are any errors
  unless ( $in{p_opshun} || $in{e_opshun} )
   {
    ($sth, my $errmsg) = $dbh->execute_stmt("select " . $in{sql_command})
                         if ($in{sql_command});
    &quit("select $in{sql_command}", $errmsg) if ($errmsg);
    return();
   }
 
  #*-- for the edit option, handle inserts, deletes, & updates
  if ($in{opshun} eq 'Edit' && $in{e_opshun})
   {
    #*-- Run the insert command  
    &handle_insert() if ($in{e_opshun} eq 'Insert');

    #*-- Run the delete command    
    &handle_delete() if ($in{e_opshun} eq 'Delete');

    #*-- Run the update command    
    &handle_update() if ($in{e_opshun} eq 'Update');

   } #*-- end of in option eq edit

 }

 #*---------------------------------------------------------------
 #*- handle the insert command 
 #*---------------------------------------------------------------
 sub handle_insert
 {
  local $" = ', '; my %coldata = ();

  #*-- check if the numeric fields are valid
  foreach my $sel_col (@sel_cols) 
   {
    $in{$sel_col} =~ s/^\s+//; $in{$sel_col} =~ s/\s+$//;

    #*-- roughly check for a numeric format
    if ( $num_field{$sel_col} && ($in{$sel_col} =~ /[^0-9.+Ee-]/) )
     {
      $stat_msg .= "  -- The <font color=darkred> $sel_col </font> field ";
      $stat_msg .= " is a numeric field <br>.";
     }

    #*-- set the data field for the row
    $coldata{$sel_col} = $in{$sel_col} ? $in{$sel_col}:
                         ($num_field{$sel_col}) ? 0: "";
   } #*-- end of foreach sel_col 
  return() if ($stat_msg);

  #*-- build the values for the insert statement
  my $val_data = "";
  foreach (@cols)  
   { if ($coldata{$_} eq 'NULL') { $val_data .= "NULL, "; }
     else { $val_data .= ($num_field{$_}) ? "$coldata{$_}, ": 
                         $dbh->quote($coldata{$_}) .", "; }
   } #*-- end of foreach
  $val_data =~ s/,\s*$//;
  $command = "insert into $in{c_table} ( @cols ) values ( $val_data )";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  $in{current_row} = 1 unless($db_msg); #*-- reset the current row
  if ($db_msg)
   { $stat_msg .= '-- The <font color=darkred>' . $command . '</font> command ';
     $stat_msg .= " failed because $db_msg.<br>"; return(); }
  $stat_msg .= "-- The Insert command was successful...";

 } #*-- end of handle insert

 #*---------------------------------------------------------------
 #*- build the where clause for handle_update and handle_delete
 #*---------------------------------------------------------------
 sub build_where
 {
  #*-- get the data for the row, loop till the current row
  #*-- and populate the row_data hash
  ($command = $in{sql_command}) =~ s/^.*? from/ from/;
  local $" = ", ";
  ($sth, my $errmsg) = $dbh->execute_stmt("select @cols $command");
  &quit("select @cols $command", $errmsg) if ($errmsg);
  my $row_num = 1; my %row_data = my @coldata = ();
  while ( @coldata = $dbh->fetch_row($sth) ) 
   { last if (++$row_num > $in{current_row}); }
  for my $i (0..$#cols) 
   { $row_data{$cols[$i]} = defined($coldata[$i]) ? $coldata[$i]: 'NULL'; }

  #*-- build the where clause
  my $row = $in{current_row} - 1; 
  my $where_cl = " where ";

  #*-- use the primary key columns if possible, otherwise use
  #*-- all the columns 
  (my $ref_col) = $dbh->show_keys($current_table); 
  my @p_cols = @$ref_col; my $no_data = '';
  foreach my $col (@p_cols) { $no_data = 'Y' unless ($row_data{$col}); }
  my @t_cols = ($no_data eq 'Y') ? @p_cols: @cols;

  #*-- skip numeric fields in where clause
  foreach my $col (@t_cols)  
   { if ($row_data{$col} eq 'NULL') { $where_cl .= " $col is NULL and "; }
     else { $where_cl .= " $col = " . $dbh->quote($row_data{$col}) . ' and ' 
                         unless($num_field{$col}); }
   }
  $where_cl =~ s/\s*and\s*$//;
  return($where_cl);
 }

 #*---------------------------------------------------------------
 #*- handle the delete command 
 #*---------------------------------------------------------------
 sub handle_delete
 {
  my $where_cl = &build_where();
  $command = "delete from $in{c_table} $where_cl"; 
  (undef, $db_msg) = $dbh->execute_stmt($command);
  $in{current_row} = 1 unless($db_msg); #*-- reset the current row
  if ($db_msg)
   { $stat_msg  .= '-- The <font color=darkred> ' . $command . 
                   '</font> command ';
     $stat_msg .= " failed because $db_msg.<br>"; return(); }
  $stat_msg .= "-- The Delete command was successful...<br>";
  $in{e_opshun} = '';
 }

 #*---------------------------------------------------------------
 #*- handle the update command 
 #*---------------------------------------------------------------
 sub handle_update
 {
  #*-- check if the numeric fields are valid and build the set clause
  my $where_cl = &build_where();
  my $set_cl = " set "; $stat_msg = "";
  foreach my $sel_col (@sel_cols) 
   { 
    $in{$sel_col} =~ s/^\s+//; $in{$sel_col} =~ s/\s+$//;

    #*-- special case first
    if ( ($current_db =~ /mysql/i) && ($current_table =~ /user/i) &&
         ($sel_col eq 'Password') ) 
      { $set_cl .= " $sel_col = password('" . $in{Password} . "'),"; }

    #*-- handle numeric fields
    elsif ($num_field{$sel_col}) 
     {
      if ($in{$sel_col} =~ /[^0-9.+Ee-]/) 
       { $stat_msg .= "-- The <font color=darkred> $sel_col </font> field ";
         $stat_msg .= " is a numeric field.<br>"; }
      else
       { $in{$sel_col} = $in{$sel_col} ? $in{$sel_col}:
                         ($num_field{$sel_col}) ? 0: "";
         $set_cl .= " $sel_col = $in{$sel_col}, "; }
     }
    else
     {
      $set_cl .= ($in{$sel_col} eq 'NULL') ? " $sel_col = NULL, ":
                 " $sel_col = " . $dbh->quote($in{$sel_col}) . ", "; }
   } #*-- end of foreach
  return() if ($stat_msg);

  #*-- run the update command
  $set_cl =~ s/,\s*$//;
  $command = "update $in{c_table} $set_cl $where_cl";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  if ($db_msg)
   { $stat_msg .= '-- The <font color=darkred>' . $command . '</font> command ';
     $stat_msg .= " failed because $db_msg. <br>"; return(); }
  $stat_msg .= "-- The Update command was successful...";
  $in{e_opshun} = '';
 }

 #*---------------------------------------------------------------
 #*- generate the html for the table selection page
 #*---------------------------------------------------------------
 sub gen_main_html
 {
  my ($sql_field);

   #*-- Generate the sql command if there are no errors and not returning
   #*-- from view/edit window
   if ($in{p_opshun} eq 'Cancel') { foreach (@cols) { $in{$_} = ''; } }
   unless ( ($stat_msg) || ($in{p_opshun} eq 'Cancel') ) 
    {
     $in{sql_command} = "";
     foreach (@cols)  { $in{sql_command} .= " $_," if ($in{$_}); }
     $in{sql_command} .= " * " unless($in{sql_command} =~ s/,$//);
     $in{sql_command} .= " from $current_table";
    }

   #*-- get the list of databases and tables
   my $db_option = '';
   foreach ($dbh->show_dbs())
    { $db_option    .= ($_ eq $current_db) ? 
      "<option value='$_' selected> $_": "<option value='$_'> $_"; }
   my $table_option = '';
   $current_table = $tables[0] unless ($current_table);
   foreach (@tables)
    { $table_option .= ($_ eq $current_table) ? 
      "<option value='$_' selected> $_": "<option value='$_'> $_"; }

   #*-- set the list of columns when returning from view/edit window
   #if ($in{p_opshun} eq 'Cancel') { $in{$_}++ foreach (@sel_cols); }

   #*-- get the list of columns for the table
   my $col_option = '<td colspan=6> ';
   $col_option .= ' <table border=0 cellspacing=0 cellpadding = 0> <tr>'; 
   my $i = 0; my $colparm = '';
   foreach my $col (@cols)
    { 
      my $checked = ($in{$col}) ? "CHECKED": "";
      $col_option .=<<"EOF";
       <td> <input type=checkbox name='$col' 
             onClick="loadCol('$col');" $checked> 
            <font color=darkblue size=3> $col </font>
       </td>
       <td width=10> &nbsp; </td>
EOF
      $col_option .= "</tr><tr>" unless (++$i % 4);
      $colparm    .= ($in{$col}) ? "&$col=yes": ""; 
    }
   $col_option .= "</tr></table> </td>";

   #*-- build the html
   my $view_image = "$ICON_DIR" . "view_table.jpg";
   my $edit_image = "$ICON_DIR" . "edit_table.jpg";
   $body_html = <<"EOF";
     <tr>
      <td> <font color=darkred size=4> Choose a Database: </font> 
        <strong>
        <select name=c_db size=1 
                onChange="loadDB(this.options[this.selectedIndex].value);"> 
                $db_option </select>
           </strong> </td>
      <td width=15> &nbsp; </td> 
      <td> <font color=darkred size=4> Choose a Table: </font> 
        <strong>
        <select name=c_table size=1
                onChange="loadTab(this.options[this.selectedIndex].value);"> 
                $table_option </select>
           </strong> </td>
      <td width=15> &nbsp; </td>
      <td align=left colspan=2> 
         <input type=image src="$view_image" border=0
          name=view value="View Table"> </td>
     </tr>
     <tr>
      <td> <font color=darkred size=4> Select Columns: </font> </td>
     </tr>
     <tr> $col_option </tr>
     <tr>
      <td> <font color=darkred size=4> SQL Command: </font> </td>
     </tr>
     <tr>
      <td colspan=4> 
          <font color=darkblue size=4> Select </font>
          <textarea name=sql_command cols=80 rows=1>$in{sql_command}</textarea>
      </td>
      <td align=left colspan=2> 
         <input type=image src="$edit_image" border=0
          name=edit value="Edit Table"> </td>
     </tr>

EOF

  }  

 #*---------------------------------------------------------------
 #*- display the header html 
 #*---------------------------------------------------------------
 sub head_html
 {

  my $dbm_image  = "$ICON_DIR" . "dbm.jpg";
  my $e_session = &url_encode($in{session});
  my $anchor = "$CGI_DIR/co_login.pl?session=$e_session";
  my $arr_str = '';
  for my $i (0..$#cols) 
     { $arr_str .= ("if (document.dbform." . $cols[$i] . ".checked)" .
                   " { cmd += \"$cols[$i],\"; }\n\t "); } 

  #*-- javascript to call this script based
  #*-- on DB selected or table selected
  print "Content-type: text/html\n\n";
  print << "EOF";
   <html>
    <head>
     <title> Database Administration Page </title>
    </head>
  
    <body bgcolor=white>
     <form method=POST action="$FORM" name="dbform">
     <center>

      <script>

       function loadDB(dbparm)
        { location.href="$FORM?c_db=" + dbparm
              + "&sql_command=&c_table=&session=$e_session"; }

       function loadTab(tbparm)
        { location.href="$FORM?c_db=$current_db&session=$e_session" + 
                             "&c_table=" + tbparm; }

       function loadCol(colparm)
        {
         var cmd = "";
         $arr_str
         if (cmd.length == 0) { cmd = " * "; }
         else                 { cmd = cmd.substring(0, cmd.length - 1); }
         cmd += " from $current_table";
         document.dbform.sql_command.value = cmd;
        }

      </script>

      <table> <tr> <td> <a href=$anchor>
              <img src="$dbm_image" border=0> </a> </td> </tr> </table>

      <table width=80%>
EOF

 }

 #*--------------------------------------------
 #*- generate the html to view the table      
 #*--------------------------------------------
 sub gen_view_html
 {
  my (@coldata, %tab_data, $i);

  #*-- generate the header html and build the tab_data hash to
  #*-- the table's data in a 2D array
  &gen_head_html(); %tab_data = ();
  local $" = ", ";
  ($command = $in{sql_command}) =~ s/^.* from/ from/;

  #*-- run the select command and populate the tab_data hash
  #*-- with entries for each row
  ($sth, my $errmsg) = $dbh->execute_stmt("select @sel_cols $command");
  &quit("select @sel_cols $command", $errmsg) if ($errmsg);
  my $row_num = 0; my $field_len = int(200 / @sel_cols); 
  $field_len = 25 if ($field_len < 25);
  while ( ($row_num < ($in{current_row} + $view_row_incr - 1) ) && 
          (@coldata = $dbh->fetch_row($sth) ) )
   { unless ($row_num < ($in{current_row} - 1) )
      { for $i (0..$#coldata) 
        { unless ($num_field{$sel_cols[$i]})
           { $coldata[$i] = defined($coldata[$i]) ? 
                &trim_field($coldata[$i], $field_len): 'NULL'; }
          $tab_data{$row_num,$sel_cols[$i]} = ($coldata[$i] || 
                 ($coldata[$i] =~ /^0\s*/) ) ?  "$coldata[$i]": "&nbsp;" ; 
        }
      } #*-- end of unless
     $row_num++;
   } #*-- end of while

  #*-- show the table, if we have any data
  if (keys %tab_data)
   {
    #*-- print the header for the table 
    $body_html .= <<"EOF"; 
     <tr><td colspan=6>
     <table cellspacing=0 cellpadding=0 border=0 bgcolor=lightyellow>
     <tr><td>
     <table cellspacing=4 cellpadding=0 border=2 bgcolor=lightblue>
     <tr>
EOF

    #*-- print the column names for the table
    $body_html .= "<td bgcolor=lightyellow valign=top> "  .
     " <font color=darkred size=4> Row </font> </td>";
    foreach (@sel_cols)
     { $body_html .= "<td bgcolor=lightyellow valign=top> " .
                     "<font color=darkred size=4> $_ </font> </td>"; }
    $body_html .= "</tr>";

    #*-- print the row data till the end of the page or less
    my $e_session = &url_encode($in{session});
    for ($i = ($in{current_row} - 1); $i < $row_num; $i++)
     { 
      my $tval = $i + 1;
      $body_html .= <<"EOF";
       <tr> <td bgcolor=white valign=top> <font color=darkblue> 
            <a href=$FORM?session=$e_session&opshun=Edit&current_row=$tval>
            $tval </a></font></td>
EOF
      foreach (@sel_cols)
       { $body_html .= "<td bgcolor=white valign=top> <font color=darkblue> "
                    .  "$tab_data{$i,$_} </font> </td>"; }
      $body_html .= "</tr>";
     }

    $body_html .= "</table> </td> </tr> </table> </td> </tr>";
   } #*-- end of if keys tab data

 }

 #*--------------------------------------------
 #*- generate the html to edit the table      
 #*--------------------------------------------
 sub gen_edit_html
 {
  my (@coldata, %tab_data, $i);

  #*-- generate the header html and build the tab_data hash to
  #*-- the table's data in a 2D array
  &gen_head_html(); %tab_data = ();
  local $" = ", ";
  ($command = $in{sql_command}) =~ s/^.* from/ from/;
  ($sth, my $errmsg) = $dbh->execute_stmt("select @cols $command");
  &quit("select @cols $command", $errmsg) if ($errmsg);
  my $row_num = 0;
  while (@coldata = $dbh->fetch_row($sth) )
   { for $i (0..$#coldata) 
      { $coldata[$i] = defined($coldata[$i]) ? $coldata[$i]: 'NULL';
        $tab_data{$row_num,$cols[$i]} = 
        ($in{$cols[$i]} && $in{e_opshun}) ? $in{$cols[$i]}:
        ($coldata[$i] || ($coldata[$i] =~ /^0\s*/) ) ? "$coldata[$i]": 
                                                       "&nbsp;" ; 
      }
     last if (++$row_num == $in{current_row}); 
   }

  #*-- show the table, if we have any data or insert
  #*-- p_opshun is the paging option, insert is an p_opshun when the 
  #*-- table is empty. e_opshun is the option for modifying a row
  if ( (keys %tab_data) || ($in{p_opshun} eq 'Insert') || 
                           ($in{e_opshun} eq 'Insert') )
   {
    #*-- print the header for the table 
    $body_html .= <<"EOF";
      <tr><td colspan=6>                                               
      <table cellspacing=0 cellpadding=0 border=0 bgcolor=lightyellow>
      <tr><td>
      <table cellspacing=4 cellpadding=0 border=2 bgcolor=lightblue>
      <tr><td bgcolor=lightyellow>
          <font color=darkred size=4>Column</font></td>
          <td bgcolor=lightyellow>
          <font color=darkred size=4>Value</font></td>
      </tr>
EOF
    my $row = $in{current_row} - 1;
    foreach my $sel_col (@sel_cols)
     { my ($field_data); 
       my $nrows = ($text_field{$sel_col}) ? 2: 1;
       $field_data = "<textarea name='$sel_col' cols=75 rows=$nrows>";
       $field_data .= "$tab_data{$row,$sel_col}" 
         if ($tab_data{$row,$sel_col} || 
            ($tab_data{$row,$sel_col} =~ /^0\s*/) ); 
       $field_data .= "</textarea> "; 
         
       my ($n_fld) = ($num_field{$sel_col}) ? "(N)":""; 
       $body_html .= <<"EOF";
        <tr> 
          <td bgcolor=white> <font color=darkblue size=4> $sel_col$n_fld 
                             </font> </td>
          <td bgcolor=white> $field_data </td> 
        </tr>
EOF
     }

    $body_html .= <<"EOF";
     </table> 
     </td> </tr> 
     </table> 
     </td> </tr>

     <tr><td colspan=6>
     <table> <tr> 
     <td bgcolor=lightblue><input type=submit name=e_opshun value="Insert"></td>
     <td> &nbsp; </td>
     <td bgcolor=lightblue><input type=submit name=e_opshun value="Update"></td>
     <td> &nbsp; </td>
     <td bgcolor=lightblue><input type=submit name=e_opshun value="Delete"></td>
     <td> &nbsp; </td>
     <td bgcolor=lightblue><input type=submit name=e_opshun value="View"></td>
     </tr>
     </table>
     </td></tr>
EOF
   } #*-- end of if keys tab data

 }

 #*---------------------------------------------------------
 #*- generate the common header html to view/edit a table      
 #*---------------------------------------------------------
 sub gen_head_html
 {

  #*-- set the current row and count the number of rows
  (my $num_rows = 0); 
  $in{current_row} = 1 unless ($in{current_row});
  unless ($in{sql_command} =~ /(count\s*\(\s*\*\s*\).* from|group\s+by)/i)
   {
    ($command = "select $in{sql_command}") 
                 =~ s/^(.*?) from/count\(\*\) from/i;
    ($sth, my $errmsg) = $dbh->execute_stmt("select $command");
    &quit("select $command", $errmsg) if ($errmsg);
    ($num_rows) = $dbh->fetch_row($sth);
   }
  else
   {
    ($sth, my $errmsg) = $dbh->execute_stmt("select $in{sql_command}");
    &quit("select $in{sql_command}", $errmsg) if ($errmsg);
    while (my (@temp) = $dbh->fetch_row($sth)) { $num_rows++; }
   }

  #*-- handle the paging buttons
  my $row_incr  = ($in{opshun} eq 'Edit') ? $edit_row_incr: $view_row_incr;
  my $lrow_incr = ($in{opshun} eq 'Edit') ? 0: ($num_rows % ($row_incr + 1));
  $in{current_row} += $row_incr if ($in{p_opshun} eq 'Next');
  $in{current_row} -= $row_incr if ($in{p_opshun} eq 'Prev');
  $in{current_row}  = 1         if ($in{p_opshun} eq 'First');
  $in{current_row}  = $num_rows - $lrow_incr + 1 if ($in{p_opshun} eq 'Last');
  $in{current_row}  = $num_rows - $lrow_incr if ($in{current_row} > $num_rows);
  $in{current_row}  = 1 if ($in{current_row} < 1);
  my $end_row = $in{current_row} + $row_incr - 1; 
  $end_row = $num_rows if ($end_row > $num_rows);
  my $row_line = ($in{opshun} eq 'Edit') ?
    "Row $in{current_row} of $num_rows":
    "Row $in{current_row} - $end_row of $num_rows";

  #*-- generate an insert button, if needed
  my $insert_button = ($num_rows || ($in{opshun} eq 'View') || 
                                    ($in{p_opshun} eq 'Insert') ) ?
     "": "<td bgcolor=lightblue> " . 
     "<input type=submit name=p_opshun value='Insert'></td>";

  $body_html = <<"EOF";
   <tr><td colspan=6>  
        <font color=darkred size=4> Command: </font> 
        <font color=darkblue size=4> select $in{sql_command} </font>
   </td></tr>

   <tr><td colspan=6>
    <table> <tr> 
     <td> <font color=darkblue> $row_line </td>
     <td> &nbsp; </td>
     <td bgcolor=lightblue><input type=submit name=p_opshun value='Next'></td>
     <td> &nbsp; </td>
     <td bgcolor=lightblue><input type=submit name=p_opshun value='Prev'></td>
     <td> &nbsp; </td>
     <td bgcolor=lightblue><input type=submit name=p_opshun value='First'></td>
     <td> &nbsp; </td>
     <td bgcolor=lightblue><input type=submit name=p_opshun value='Last'></td>
     <td> &nbsp; </td>
     <td bgcolor=lightblue><input type=submit name=p_opshun value='Cancel'></td>
     <td> &nbsp; </td>
     $insert_button
    </tr>
    </table>
    <br> <br>
   </td></tr>
EOF

 }

 #*---------------------------------------------------------
 #*- get the array of columns        
 #*---------------------------------------------------------
 sub get_columns
 {
  my ($sql_command) = @_;
  my ($i, @fields); 
 
  return() unless (@tables);
  (my $ref_col, my $ref_type) = $dbh->show_columns($current_table);
  @cols = my @columns = @$ref_col;

  #*-- set the blob_field and numeric field arrays
  %num_field = %blob_field = %text_field = ();
  for $i(0..$#cols)
   { $blob_field{$cols[$i]}++  if (@$ref_type[$i] =~ /^\s*blob/i);
     $num_field{$cols[$i]}++   if (@$ref_type[$i] =~ /^\s*(?:int|float)/i); 
     $text_field{$cols[$i]}++  if (@$ref_type[$i] =~ /^\s*text/i); }

  #*-- fix @columns, do not handle binary fields
  for $i (0..$#cols)
   { splice(@columns, $i, 1) if ($blob_field{$cols[$i]}); }
  
  #*-- show all columns
  return(@columns) unless ($sql_command);

  $sql_command =~ s/^\s+//;
  (my $columns) = $sql_command =~ /^(.*) from/i;
  $columns = '*' unless ($columns);
  $columns =~ s/^\s+//; $columns =~ s/\s+$//; 
  return (@columns) if ($columns =~ /^\*$/);

  my @tcols = split/,/, $columns;
  for my $i(0..$#tcols)
   { 
     #*-- clean up the column and escape ( ) and * chars
     $tcols[$i] =~ s/^\s+//; $tcols[$i] =~ s/\s+$//; 
     $tcols[$i] =~ s/([()*])/\\$1/g; 

     #*-- fix upper/lower case problems and skip blob fields
     foreach my $col (@columns) 
      { $tcols[$i] =~ s/$tcols[$i]/$col/ if ($col =~ /$tcols[$i]/i); } 
     splice(@tcols, $i, 1) if ($blob_field{$tcols[$i]});  
   }
  return(@tcols);

 }

 #*---------------------------------------------------------------
 #*- Dump the end of the html page 
 #*---------------------------------------------------------------
 sub tail_html
 {
  $dbh->disconnect_db($sth);
  print << "EOF";
    </table>
    </center>
    <input type=hidden name=session value='$in{session}'>
    <input type=hidden name=current_row value='$in{current_row}'>
   </form>
  </body>
  </html>
EOF

 }

 #*---------------------------------------------------------------
 #*- Print the error message for SQL Commands and exit
 #*---------------------------------------------------------------
  sub quit
 {
  #*-- establish DB connection
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $in{userid}, 'Password' => $in{password},
       'Dbname' => $DB_NAME);
  &gen_main_html() unless ($db_msg);
  &head_html(); print ("$body_html"); 
    print << "EOF";
    <tr> <td colspan=6> <font color=darkred size=4> Message: </font> 
         <font color=darkblue size=4> Failed to execute: $_[0] </font> </td>
    </tr> 
    <tr> <td colspan=6> <font color=darkred size=4> Error: </font> 
         <font color=darkblue size=4> $_[1] </font> </td>
    </tr> 
EOF
    &tail_html(); exit(0); 
   }

 #*---------------------------------------------------------------
 #*- Print the error message for a form error 
 #*---------------------------------------------------------------
  sub msg_html
  {  
    print << "EOF";
    <tr> <td colspan=6> <font color=darkred size=4> Message: </font> 
         <font color=darkblue size=4> $_[0] </font> </td>
    </tr> 
EOF
   }
