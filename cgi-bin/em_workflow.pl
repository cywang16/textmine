#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
 #*-----------------------------------------------------------------------
 #*- em_workflow.pl
 #*-  
 #*-   Summary: Display the list of tasks scheduled in order by date and
 #*-       their associated status. 
 #*----------------------------------------------------------------

 use strict; use warnings;
 use lib qw/../;
 use Time::Local;
 use TextMine::DbCall;
 use TextMine::Constants;
 use TextMine::Utils;
 use TextMine::WordUtil qw/gen_vector sim_val/;
 use TextMine::MailUtil qw/email_head email_vector/;

 #*-- set the constants
 use vars (
  '$dbh',		#*-- database handle
  '$sth',		#*-- statement handle
  '$stat_msg',		#*-- status message for the page
  '$db_msg',		#*-- database error message
  '$command',		#*-- var for SQL command
  '$ref_val',		#*-- reference value
  '$FORM',		#*-- name of the form
  '%in',		#*-- hash for form fields
  '%esq',		#*-- hash for escaped fields
  '$current_date',	#*-- current date field
  '$body_html',		#*-- HTML body of page
  '$cdate', '$cmonth', '$cyear', '$cday',	#*-- date fields
  '$ONE_DAY', '$ONE_WEEK', '$ONE_MONTH'		#*-- date constants
  );

 #*-- set some global variables
 &set_vars();

 #*-- handle the selection of a date
 &date_handler();

 #*-- handle the options
 &add_entry() if ($in{opshun} eq 'Save');
 &upd_entry() if ($in{opshun} eq 'Update');
 &del_entry() if ($in{opshun} eq 'Delete');
 &clr_entry() if ($in{opshun} eq 'New');
 
 #*-- set defaults
 ($sth, $db_msg) = $dbh->execute_stmt("select count(*) from em_worklist");
 &quit("$command failed: $db_msg") if ($db_msg);
 $in{opshun} = 'New'  unless ( ($dbh->fetch_row($sth))[0] );
 $in{opshun} = 'View' unless ($in{opshun});

 #*-- dump the header, body, status and tail html 
 print ${$ref_val = &email_head("E-flow", $FORM, $in{session})}; 
 $body_html = ${$ref_val = 
               ($in{opshun} =~ /^(?:View|Next|Prev|First|Last)/i) ? 
                &view_html(): &entry_html()};
 &msg_html($stat_msg) if ($stat_msg); 
 print ("$body_html\n");
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

  #*-- remove the forgetful parms
  my @parms = qw/opshun date_opshun select_date/;
  foreach (@parms, 'entry_date', 's_opshun', 'descr', 'type', 
    'address', 'period') { $in{$_} = '' unless ($in{$_}); }
  &mod_session($dbh, $in{session}, 'del', @parms);
  $in{entry_date} = time() unless ($in{entry_date});
  $in{s_opshun} = 'Show All Events' unless ($in{s_opshun});
  &mod_session($dbh, $in{session}, 'mod',
           'entry_date', "$in{entry_date}", 's_opshun', "$in{s_opshun}");
  $current_date = time();
  $ONE_DAY = 86400; $ONE_WEEK = 7 * $ONE_DAY; $ONE_MONTH = 30 * $ONE_DAY;
  ($cdate, $cmonth, $cyear, $cday) = (gmtime($current_date))[3..6];

  #*-- verify the id for the event
  if ($in{id})
   {
    $command = "select count(*) from em_worklist where emi_id = $in{id}";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit("$command failed: $db_msg") if ($db_msg);
    $in{id} = 0 unless (($dbh->fetch_row($sth))[0]);
   }

 }
 #*---------------------------------------------------------------
 #*- add an entry if possible and set the status message
 #*---------------------------------------------------------------
 sub add_entry
 {

  #*--- check for mandatory entries
  unless ($in{descr})  
   { $stat_msg .= " The Description field is mandatory,"; return(); }

  #*-- check for a duplicate
  &escape_q(); 
  $command = "select count(*) from em_worklist where " .
             " emi_date = $in{entry_date} and emc_period = '$in{period}' " .
             " and emc_descr = " . $dbh->quote($in{descr});
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  if (($dbh->fetch_row($sth))[0])
  { $stat_msg .= "-- Task " . $in{descr} . " exists in the worklist table,";
    $stat_msg .= " press Update<br> "; 
    return(); }  

  #*-- build the insert statement for the task
  $command  = <<"EOF";
   insert into em_worklist (emi_id, emi_date, emc_type, emc_period, 
          emc_address, emc_descr ) values (0, $in{entry_date}, $esq{type},
          $esq{period}, $esq{address}, $esq{descr})
EOF
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  $stat_msg .= "-- Task " . $in{descr} . " was added,<br>";
  $in{id} = $dbh->last_id();
  &mod_session($dbh, $in{session}, 'mod', 'id', $in{id} ); 
 }

 #*---------------------------------------------------------------
 #*- Update an existing entry 
 #*---------------------------------------------------------------
 sub upd_entry
 {

  #*--- check for mandatory entries
  return() unless($in{id});
  unless ($in{descr})  
   { $stat_msg .= "-- The Description field is mandatory,<br>"; return(); }

  #*-- check if the entry exists
  &escape_q(); 
  $command = "select count(*) from em_worklist where emi_id = $in{id}";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  unless (($dbh->fetch_row($sth))[0])
   { $stat_msg .= "-- Task " . $in{descr} . " does not exist in the " . 
                  " Table,<br>";
     return(); }

  #*-- build the update statement
  $command = <<"EOF";
   update em_worklist set emc_type = $esq{type}, emc_descr = $esq{descr},
          emc_address = $esq{address}, emc_period = $esq{period},
          emi_date = $in{entry_date} where emi_id = $in{id}
EOF
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  $stat_msg .= "-- Task " . $in{descr} . " was changed successfully,<br>";
 }

 #*---------------------------------------------------------------
 #*- Delete an existing entry 
 #*---------------------------------------------------------------
 sub del_entry
 {
  return() unless($in{id});

  #*-- delete the entry in the appropriate abook table
  &escape_q(); 
  $command = "delete from em_worklist where emi_id = $in{id}";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  $stat_msg .= "-- The Task " . $in{descr} . " was deleted,<br>";
  $in{opshun} = 'View'; #*-- return to the view window
 }

 #*---------------------------------------------------------------
 #*- Clear all fields for a new entry        
 #*---------------------------------------------------------------
 sub clr_entry
 {
  for (qw/descr address/) { $in{$_} = '';}
  $in{type} = 'Receive'; $in{period} = 'Once'; $in{id} = 0; 
  $in{entry_date} = $current_date;
 }

 #*---------------------------------------------------------------
 #*- show a list of people in a table
 #*---------------------------------------------------------------
 sub view_html
 {

  #*-- get the lists from the worklist table              
  my %emc_descr  = my %emi_date    = my %emc_type =
  my %emc_period = my %emc_address = my %emc_status =
  my %emi_sdate  = my %emi_edate   = ();
  $command = "select emi_id, emc_descr, emi_date, emc_type, " .
             "emc_period, emc_address from em_worklist";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  while ( (my $id, my $descr, my $date, my $type, my $period, my $address) 
          = $dbh->fetch_row($sth) )
     { $emc_descr{$id}   = $descr;     $emi_date{$id}   = $date; 
       $emc_type{$id}    = $type;      $emc_period{$id} = $period; 
       $emc_address{$id} = $address; }

  #*-- get the range of dates and set the date for the table
  foreach my $id (keys %emi_date)
   { ($emi_sdate{$id}, $emi_edate{$id}, $emi_date{$id}) = 
      &set_date($emi_date{$id}, $emc_period{$id}); }

  my ($body_html, @ids); 
  foreach my $id (sort keys %emi_date)
   { 
    #*-- check if the current date is in range
    if ( ($in{s_opshun} eq 'Show All Events') ||
         ( ($emi_sdate{$id} <= $current_date) &&
           ($current_date   <= $emi_edate{$id}) ) )
     { 

      #*-- check the status, there should be an e-mail with 
      #*-- the same address and in the date range with the same type
      push (@ids, $id);
      (my $e_address = $emc_address{$id}) =~ s/([_%])/\\$1/g;
      unless ($e_address) { $emc_status{$id} = '&nbsp;'; next; }
      $e_address = $dbh->quote('%' . $e_address . '%');
      $command  = "select emc_subject, emc_from, emc_to, emc_cc, emc_text " .
                  " from em_email where ";
      $command .= ($emc_type{$id} =~ /receive/i) ? 
           "emc_status LIKE '%receive%' and emc_from LIKE $e_address ":
           "emc_status LIKE '%sen%'    and emc_to   LIKE $e_address ";
      $command .= "and $emi_sdate{$id} <= emi_date ";
      $command .= "and emi_date <= $emi_edate{$id} ";
      ($sth, $db_msg) = $dbh->execute_stmt($command);
      &quit("$command failed: $db_msg") if ($db_msg);

      #*-- compare the text of the email with the event description
      #*-- if greater than a threshold, the task is complete
      $emc_status{$id} = '<font color=red> Incomplete </font>';
      while ( my ($from, $to, $cc, $subject, $text) = $dbh->fetch_row($sth))
       { my %email = 
           &email_vector($from, $to, $cc, $subject, $text, $dbh, 1000);
         my %descr = &gen_vector(\$emc_descr{$id}, 'idf', 'email', $dbh);
         if (&sim_val(\%email, \%descr) > 0.10) #*-- gt than a threshold
          { $emc_status{$id} = '<font color=green> Complete </font>'; last; }
       } #*-- end of while
 
     } #*-- end of if
    } #*-- end of for

  #*-- compute the current page number
  my $num_ids = @ids;
  my $ids_per_page = 12;
  my $num_pages = ($num_ids >= $ids_per_page) ?
               int($num_ids / $ids_per_page): 0;
  $num_pages++   if ( ($num_ids % $ids_per_page) != 0);

  $in{cpage}++            if ($in{opshun} eq 'Next');
  $in{cpage}--            if ($in{opshun} eq 'Prev');
  $in{cpage} = 1          if ($in{opshun} eq 'First');
  $in{cpage} = $num_pages if ($in{opshun} eq 'Last');

  #*-- make sure that current page is in range
  $in{cpage} = 1          unless ($in{cpage});
  $in{cpage} = $num_pages if ($in{cpage} > $num_pages);
  $in{cpage} = 1          if ($in{cpage} < 1);

  #*-- set the start file and save the current page number
  &mod_session($dbh, $in{session}, 'mod', 'cpage', $in{cpage});
  my $start_file = ($in{cpage} - 1) * $ids_per_page;

  my @page_ids = ();
  my $i = 0; my $j = 0; 
  foreach my $id ( sort {$emi_date{$b} <=> $emi_date{$a}} @ids)
   { 
    if (++$j >= $start_file)
      { $page_ids[$i] = $id; last if (++$i >= $ids_per_page); } }

      
  #*-- build the body of the table
  $i = $start_file + 1; 
  my $e_session = &url_encode($in{session}); 
  foreach my $id (@page_ids)
   {
    my $period = &ret_pval($emi_date{$id}, $emc_period{$id});
    $emc_address{$id} = '&nbsp;' unless ($emc_address{$id});
    $emc_period{$id} = '&nbsp;' unless ($emc_period{$id});
    $body_html .= <<"EOF";
     <tr>
       <td bgcolor=white> <font color=darkblue>$i.               </font></td>
       <td bgcolor=white>
         <a href=$FORM?session=$e_session&opshun=Edit&id=$id>
        <font color=darkblue> $emc_descr{$id} </font> </a> </td>
       <td bgcolor=white> <font color=darkblue>$period           </font></td>
       <td bgcolor=white> <font color=darkblue>$emc_type{$id}    </font></td>
       <td bgcolor=white> <font color=darkblue>$emc_period{$id}  </font></td>
       <td bgcolor=white> <font color=darkblue>$emc_address{$id} </font></td>
       <td bgcolor=white> $emc_status{$id} </td>
     </tr>
EOF
    $i++;
   } #*-- end of for

  #*-- prefix the header if there is some data to be shown
  my $show_opshun = ($in{s_opshun} eq 'Show All Events') ?
                    'Show Current Events': 'Show All Events';
  $body_html = <<"EOF" . $body_html if (@ids);
   <br>
   <table cellspacing=0 cellpadding=0 border=0 bgcolor=white>
    <tr><td align=center> <br> 
      <input type=submit name=opshun value=New> &nbsp;
      <font color=darkred> Page $in{cpage} of $num_pages </font>
                            &nbsp; &nbsp;
      <input type=submit name=opshun value=Next> &nbsp;
      <input type=submit name=opshun value=Prev> &nbsp;
      <input type=submit name=opshun value=First> &nbsp;
      <input type=submit name=opshun value=Last> &nbsp; 
      <input type=submit name=s_opshun value='$show_opshun'> &nbsp; 
      <br> <br>
    </td></tr> 
   <tr><td> 
   <table cellspacing=4 cellpadding=0 border=2 bgcolor=lightblue>
   <tr>
     <td bgcolor=lightyellow> <font color=darkred> No. </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> Description </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> Date </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> Type </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> Frequency </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> Address </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> Status </font> </td>
   </tr>
EOF
  #*-- append the end of table html
  $body_html .= <<"EOF" if (@ids);
     </table> 
    </td> </tr> 
   </table>
EOF

  return (my $ref_val = &entry_html()) unless($body_html);
  return(\$body_html);

 }

 #*---------------------------------------------------------------
 #*- Show the screen to view details of each entry   
 #*---------------------------------------------------------------
 sub entry_html
 {
  my ($emc_descr, $emc_type, $emc_address, $emi_date, $emc_period);
  my ($body_html);

  #*-- read from the DB and collect the data
  $body_html = "<br><table border=0 cellspacing=8 cellpadding=0>"; 
  if ( ($in{id}) && !($in{date_opshun} eq 'OK') )
   {
    $command = "select emc_descr, emc_type, emc_address, emi_date, ".
               " emc_period from em_worklist where emi_id = $in{id}";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit("$command failed: $db_msg") if ($db_msg);
    ($emc_descr, $emc_type, $emc_address, $emi_date, $emc_period)
            = $dbh->fetch_row($sth);
   }
  else
   { $emc_descr = $in{descr};     $emc_type = $in{type};
     $emc_address = $in{address}; $emc_period = $in{period}; 
     $emi_date = $in{entry_date};
     $stat_msg .= '-- Enter information for an e-mail event <br>';
   }

  my $send_check    = ($emc_type =~ /Send/i) ?      'checked': '';
  my $recv_check    = ($send_check) ?               '': 'checked';
  my $weekly_check  = ($emc_period =~ /Weekly/i) ?  'checked': '';
  my $monthly_check = ($emc_period =~ /Monthly/i) ? 'checked': '';
  my $annual_check  = ($emc_period =~ /Annual/i) ?  'checked': '';
  my $none_check    = ($weekly_check || $monthly_check ||
                       $annual_check) ?    '': 'checked';
  $emi_date = &f_date($emi_date, 1);

  $body_html .= <<"EOF";
   <tr>
    <td> <font color=darkred size=+1>Description: </font></td>
    <td align=left> 
       <textarea name=descr rows=1 cols=60>$emc_descr</textarea></td>
    </tr>

   <tr>
    <td> <font color=darkred size=+1>Address: </font></td>
    <td align=left> 
      <textarea name=address rows=1 cols=60>$emc_address</textarea></td>
   </tr>

   <tr>
    <td> <font color=darkred size=+1>Period: </font></td>
    <td align=left> 
      <input type=radio name=period value="Once" $none_check>
      <font color=darkblue size=+1> Once </font> &nbsp;
      <input type=radio name=period value="Weekly" $weekly_check>
      <font color=darkblue size=+1> Weekly </font> &nbsp;
      <input type=radio name=period value="Monthly" $monthly_check>
      <font color=darkblue size=+1> Monthly </font> &nbsp;
      <input type=radio name=period value="Annual" $annual_check>
      <font color=darkblue size=+1> Annual </font> &nbsp;
    </td>
   </tr>

   <tr>
    <td> <font color=darkred size=+1>Type: </font></td>
    <td align=left> 
      <input type=radio name=type value="Send"    $send_check>
      <font color=darkblue size=+1> Send </font> &nbsp;
      <input type=radio name=type value="Receive" $recv_check>
      <font color=darkblue size=+1> Receive </font> &nbsp;
    </td>
   </tr>

   <tr>
    <td> <font color=darkred size=+1>Date: </font></td>
    <td align=left> 
         <input type=submit name=select_date value='$emi_date'>
    </td>
   </tr>
EOF

 #*-- add the end of table html
 $body_html .= <<"EOF";
     <tr>
       <td> &nbsp; </td>
       <td align=left>
         <input type=submit name=opshun value='Save'> &nbsp;
         <input type=submit name=opshun value='Update'> &nbsp;
         <input type=submit name=opshun value='Delete'> &nbsp;
         <input type=submit name=opshun value='View'> &nbsp;
       </td>
     </tr>
    </table>
EOF

  return(\$body_html);
 }

 #*------------------------------------------------------
 #*-- Accept a date with a period and return a date range and
 #*-- a display date
 #*------------------------------------------------------
 sub set_date
 {
  my ($table_date, $period) = @_;
  my ($sdate, $edate, $show_date);

  $sdate = $edate = $show_date = 0;
  
  #*-- set the date range for a weekly period (+/- 1 day)
  if ($period =~ /Weekly/i)
   {
    (my $wday) = (gmtime($table_date))[6];
    my @days = ( ($wday + 6) % 7, $wday, ($wday + 1) % 7);
    my $i = 0;
    foreach (@days)
     { if ($cday == $_)
       { $show_date = timegm(0, 0, 0, $cdate, $cmonth, $cyear);
         $sdate = $show_date - ($i * $ONE_DAY);
         $edate = $sdate + (3 * $ONE_DAY);
         last; }
       $i++;
     } #*-- end of for
   } #*-- end of if weekly period
  
  #*-- set the date range for a monthly period (+/- 1 week)
  if ($period =~ /Monthly/i)
   {
    (my $tdate) = (gmtime($table_date))[3];
    $tdate = 28 if ( ($tdate > 28) && ($cmonth == 1) 
                     && !&leap_year($cyear) );
    $show_date = timegm(0, 0, 0, $tdate, $cmonth, $cyear);
    $sdate = $show_date - $ONE_WEEK;
    $edate = $show_date + $ONE_WEEK;
   }
  
  #*-- set the date range for an annual period (+/- 1 month)
  if ($period =~ /Annual/i)
   {
    $show_date = $table_date;
    $sdate = $show_date - $ONE_MONTH; $edate = $show_date + $ONE_MONTH;
   }
  
  #*-- set the date range for a one time event (+/- 1 month)
  if ($period =~ /Once/i)
   {
    $show_date = $table_date;
    $sdate = $show_date - $ONE_WEEK; $edate = $sdate + $ONE_MONTH;
   }
  
  return ($sdate, $edate, $show_date);

 }

 #*------------------------------------------------------
 #*-- Clean up the worklist table 
 #*------------------------------------------------------
 sub clean_up
 {

  #*-- remove one time entries which are over 3 months old
  $command = "delete from em_worklist where emc_period = 'Once' and " .
             " emi_date < ($current_date - (3 * $ONE_MONTH) )";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  #*-- fix the dates for annual events
  my ($id, $date, %dates);
  $command = "select emi_id, emi_date from em_worklist " .
             " where emc_period = 'Annual'";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  $dates{$id} = $date while (($id, $date) = $dbh->fetch_row($sth));

  foreach my $id (keys %dates)
   {
    (my $tdate, my $tmonth, my $tyear) = (gmtime($dates{$id}))[3..5];
    if ( ($tyear != $cyear) && 
         !&in_range($dates{$id} - $ONE_MONTH, $current_date,
                    $dates{$id} + $ONE_MONTH) )
     { $tdate = 28 if ( ($tdate > 28) && ($tmonth == 1) 
                     && !&leap_year($cyear) );
       my $new_date = timegm(0, 0, 0, $tdate, $tmonth, $cyear);
       $command = "update em_worklist set emi_date = $new_date " .
                  " where emi_id = $id";
       (undef, $db_msg) = $dbh->execute_stmt($command);
       &quit("$command failed: $db_msg") if ($db_msg);
     } #*-- end of if
   } #*-- end of foreach $id
 }

 #*------------------------------------------------------
 #*-- Accept an epoch value and period type and return
 #*-- the appropriate string
 #*------------------------------------------------------
 sub ret_pval
 {
  my ($epoch, $ptype) = @_;
  my $retval;

  if ($ptype =~ /Weekly/i)
   { ($retval = &f_date($epoch,1)) =~ s/^(\w+),.*/$1/; }
  if ($ptype =~ /Monthly/i)
   { ($retval = &f_date($epoch,0,1)) =~ s/^(\w+).*/$1/; }
  if ($ptype =~ /^(?:Annual|Once)/i)
   { $retval = &f_date($epoch); }
  return($retval);
 }

 #*---------------------------------------------------------------
 #*- Handle the selection of dates
 #*---------------------------------------------------------------
 sub date_handler
 {

  #*-- if choosing a date
  if ($in{date_opshun} =~ /selecting_date/)
   {
    &mini_head_html();
    my $body_html = ${$ref_val = &dateChooser
     ($FORM, $in{date_year}, $in{date_month}, $in{date_day},
                 "Select a Date", $in{session} )};
    print ("$body_html\n");
    &mini_tail_html();
    exit(0);
   }

  #*-- if a date has been chosen, then set the appropriate field
  if ($in{date_opshun} eq "OK")
   { $in{entry_date} = timegm(0, 0, 0, $in{date_day},
                              $in{date_month}, $in{date_year} - 1900);
     &mod_session($dbh, $in{session}, 'mod',
                              'entry_date', "$in{entry_date}");
     $in{opshun} = 'Edit';
    return(); }

  if ($in{select_date})
   {
    ($in{entry_day}, $in{entry_month}, $in{entry_year}) =
      (gmtime($in{entry_date}))[3..5];
    &mini_head_html();
    my $body_html = ${$ref_val = &dateChooser
     ($FORM, $in{entry_year}, $in{entry_month}, $in{entry_day},
                 "Select a Date", $in{session} )};
    print ("$body_html\n");
    &mini_tail_html();
    exit(0);
   }

 }

 #*------------------------------------------------------
 #*-- escape strings with single quotes
 #*------------------------------------------------------
 sub escape_q
 {
  %esq = (); 
  foreach (qw/descr address period type/)
   { $in{$_} =~ s/^\s+//; $in{$_} =~ s/\s+$//;
     $esq{$_} = $dbh->quote($in{$_}); }
 }

 #*---------------------------------------------------------------
 #*- Exit with a message            
 #*---------------------------------------------------------------
 sub quit
 {
  print ${my $ref_val = 
          &email_head("E-flow", $FORM, $in{session})};
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

 #*---------------------------------------------------------------
 #*- display a small header
 #*---------------------------------------------------------------
 sub mini_head_html
 {
  print "Content-type: text/html\n\n";
  print << "EOF";
   <html>
    <head>
     <title> Date Page for Tracking E-Mail events </title>
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
  $dbh->disconnect_db($sth);
  print << "EOF";
    </center>
     <input type=hidden name=session value=$in{session}>
   </form>
  </body>
  </html>
EOF
 }
