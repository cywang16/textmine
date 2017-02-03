#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
 #*----------------------------------------------------------------
 #*- em_search.pl
 #*-
 #*-   Summary: Accept the input parameters for the emails and search
 #*-            the database. Display the matching emails.
 #*----------------------------------------------------------------

 use strict; use warnings;
 use Time::Local;
 use TextMine::DbCall;
 use TextMine::Constants;
 use TextMine::Utils;
 use TextMine::Index    qw/rem_index content_words text_match tab_word/;
 use TextMine::WordUtil qw/sim_val/;
 use TextMine::MailUtil qw/get_children email_head compute_centroid 
            string_to_vec vec_to_string email_vector mod_centroid/;

 #*-- global variables
 use vars (
  '%in',	#*-- hash for form fields
  '$FORM',	#*-- name of form
  '$command',	#*-- SQL Command
  '$sth',	#*-- statement handle
  '$dbh',	#*-- database handle
  '$db_msg',	#*-- database error message
  '$ref_val',	#*-- reference value
  '$body_html',	#*-- html for body of page
  '%tipe',	#*-- hash for the type of e-mails (composed, recvd, or sent)
  '%catname',	#*-- hash of category ids and category names
  '@catids',	#*-- category ids of child categories
  '$stat_msg',	#*-- status message for the page
  '@words'	#*-- content words of the query
   );

 #*-- retrieve passed parameters and set variables
 &set_vars();

 #*-- handle the start and end dates
 &date_handler();

 #*-- process any option buttons
 &del_email()   if ( ($in{e_opshun} =~ /Delete/i) || 
                     ($in{p_opshun} =~ /Delete/i) );
 &fetch_page()  if ($in{p_opshun} =~ /^(?:Fetch|Next|Prev|First|Last)/i);
 &fetch_email() if ($in{e_opshun} =~ 
 /^(?:Fetch|Next|Prev|First|Last|Sent|Edit|Reply|Reply All|Later|Categorize)/i);

 #*-- dump the html
 &head_html();
 &msg_html($stat_msg) if ($stat_msg);
 print ("$body_html\n");
 &tail_html();

 exit(0);

 #*---------------------------------------------------------------
 #*- Set the initial parameters 
 #*---------------------------------------------------------------
 sub set_vars
 {
  #*-- get the form name and the form fields
  $stat_msg = '';
  $0 =~ s%.*[/\\]%%; $FORM = "$CGI_DIR" . "$0";
  %in = %{$ref_val = &parse_parms($FORM)};

  #*-- set the DB connection
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
      'Userid' => $in{userid}, 'Password' => $in{password},
      'Dbname' => $DB_NAME);
  &quit("Connect failure: $db_msg") if ($db_msg);

  #*-- initialize fields
  %tipe = (); $body_html = '';
  my @dparms = qw/opshun date_opshun p_opshun e_opshun opshun.x/;
  foreach (@dparms, 'sent', 'received', 'composed', 'description', 'fuzzy')
   { $in{$_} = '' unless ($in{$_}); }
  foreach (qw/sent received composed/) 
    { $tipe{$_} = ($in{$_} eq 'on') ? "CHECKED": ""; }
  $tipe{all}++ unless ( $tipe{sent} || $tipe{received} || $tipe{composed} );

  #*-- set the paging option
  if ($in{'opshun.x'}) 
   { $in{p_opshun} = 'First'; 
     &mod_session($dbh, $in{session}, 'del', 'emi_catid'); 
     $in{emi_catid} = ''; }

  #*-- if we are searching by category, then fetch all category
  #*-- ids under this category
  @catids = ();
  if ($in{emi_catid}) 
   { @catids = &get_children($in{emi_catid}, $dbh); 
     $in{p_opshun} = 'Fetch' unless($in{p_opshun}); }
  $in{p_opshun} = 'Fetch' if ($in{e_opshun} eq 'Return');

  #*-- set the array of category names associated with ids
  %catname = ();
  $command = "select emc_catname, emi_catid from em_category " .
             "where emc_centroid != '' order by 1 asc";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  while ( (my $emc_catname, my $emi_catid) = $dbh->fetch_row($sth) )
   { $catname{$emi_catid} = $emc_catname; }

  #*-- keep the session data updated
  push (@dparms, qw/sent received composed fuzzy/) 
    unless ($in{s_date} || $in{e_date});
  &mod_session($dbh, $in{session}, 'del', @dparms);

  #*-- set defaults for start and end dates 
  $in{start_date} = 946684800      unless($in{start_date}); 
  $in{end_date}   = time() + 86400 unless($in{end_date}); 
  $in{description} =~ s/^\s+//; $in{description} =~ s/\s+$//; 

 }

 #*---------------------------------------------------------------
 #*- Handle the selection of dates
 #*---------------------------------------------------------------
 sub date_handler
 {

  #*-- if choosing a date
  if ($in{'date_opshun'} eq 'selecting_date')
   {
    &mini_head_html();
    $body_html = ${$ref_val = &dateChooser ($FORM, 
     $in{date_year}, $in{date_month}, $in{date_day}, 'Select a date', 
     $in{session})};
    print ("$body_html\n");
    &mini_tail_html();
    exit(0);
   }

  #*-- if a date has been chosen, then set the appropriate field
  if ($in{date_opshun} eq "OK")
   {
    my $eseconds = timegm(59, 59, 23, $in{date_day}, $in{date_month}, 
                                   $in{date_year} - 1900);
    $in{start_date} = $eseconds if ($in{d_opshun} =~ /start/);
    $in{end_date}   = $eseconds if ($in{d_opshun} =~ /end/);
    &mod_session($dbh, $in{session}, 'del', 
                          'd_opshun', 's_date', 'e_date'); 
    &mod_session($dbh, $in{session}, 'mod', 
       'start_date', "$in{start_date}", 'end_date', "$in{end_date}"); 
    return();
   }

  #*-- if the start date must be changed
  if ($in{s_date})
   {
    ($in{start_day}, $in{start_month}, $in{start_year}) = 
                     (gmtime($in{start_date}))[3..5]; 
    &mod_session($dbh, $in{session}, 'mod', 'd_opshun', 'start'); 
    &mini_head_html();
    $body_html = ${$ref_val = &dateChooser ($FORM, 
       $in{start_year}, $in{start_month}, $in{start_day}, 
       'Select a start date', $in{session})};
    print ("$body_html\n");
    &mini_tail_html();
    exit(0);
   }

  #*-- if the end date must be changed
  if ($in{e_date})
   {
    ($in{end_day}, $in{end_month}, $in{end_year}) = 
                   (gmtime($in{end_date}))[3..5]; 
    &mod_session($dbh, $in{session}, 'mod', 'd_opshun', 'end'); 
    &mini_head_html();
    $body_html = ${$ref_val = &dateChooser ($FORM, 
       $in{end_year}, $in{end_month}, $in{end_day}, 
       'Select a end date', $in{session})};
    print ("$body_html\n");
    &mini_tail_html();
    exit(0);
   }

 }

 #*---------------------------------------------------------------
 #*- delete the e-mail(s). E-mails are actually deleted in
 #*- a separate process. The e-mail is marked for deletion here.
 #*---------------------------------------------------------------
 sub del_email
 {
  my ($emi_id, $emc_status, $emi_date, $emc_from, $emc_to, 
      $emi_catid, $emc_subject, $emc_cc, $emc_text);

  #*-- delete the e-mail when delete was pressed in the individual 
  #*-- e-mail screen
  if ($in{e_opshun})
   {
    my @sort_files = @{$ref_val = &fetch_data()};
    unless (@sort_files)
     { $stat_msg .= "-- No matching files were found<br> "; return(); }
    $emi_id = $sort_files[$in{ceid} - 1];
    $command = "update em_email set emc_dflag = 'D' where emi_id = $emi_id";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    &mod_session($dbh, $in{session}, 'del', 'e_opshun');
    $in{e_opshun} = 'Fetch';
    return();
   }

  #*-- delete the selected e-mails
  $command = "select MAX(emi_id) from em_email";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  my ($max_email) = $dbh->fetch_row($sth);
  for my $i (1..$max_email)
   { next unless($in{"d_$i"});
    $command = "update em_email set emc_dflag = 'D' where emi_id = $i";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    &mod_session($dbh, $in{session}, 'del', "d_$i");
   }
  $in{p_opshun} = 'Fetch';
  
 }

 #*---------------------------------------------------------------
 #*- fetch the email and display
 #*---------------------------------------------------------------
 sub fetch_email
 {
  my ($emi_id, %em);

  #*-- get the list of matching emails 
  %em = ();
  my @sort_files = @{$ref_val = &fetch_data()};
  unless (@sort_files)
   { $stat_msg .= "-- No matching files were found<br> "; return(); }

  #*-- compute the current email number
  my $num_files = @sort_files;
  $in{ceid}++            if ($in{e_opshun} eq 'Next');
  $in{ceid}--            if ($in{e_opshun} eq 'Prev');
  $in{ceid} = 1          if ($in{e_opshun} eq 'First');
  $in{ceid} = $num_files if ($in{e_opshun} eq 'Last');

  #*-- make sure that ceid is in range
  $in{ceid} = $num_files if ($in{ceid} > $num_files);
  $in{ceid} = 1          if ($in{ceid} < 1);
  $emi_id = $sort_files[$in{ceid} - 1];

  #*-- save the current email number
  &mod_session($dbh, $in{session}, 'mod', 'ceid', $in{ceid});

  #*-- handle the sent button
  if ($in{e_opshun} eq 'Sent')
   {
    $command  = "update em_email set emc_status = 'Sent', " .
                "emi_date = " . time() . " where emi_id = $emi_id";
    (undef, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
   } 

  $command = <<"EOF";
   select emi_date, emc_status, emc_from, emc_to, emc_subject, 
          emc_cc, emc_text, emi_catid from em_email where emi_id = $emi_id  
EOF
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  ($em{emi_date},    $em{emc_status}, $em{emc_from}, $em{emc_to}, 
   $em{emc_subject}, $em{emc_cc},     $em{emc_text}, $em{emi_catid}) = 
                     $dbh->fetch_row($sth);

  my $sent_button = ($em{emc_status} eq 'Composed') ? 
      '<td> <input type=submit name=e_opshun value="Edit"> </td> ' .
      '<td> <input type=submit name=e_opshun value="Sent"> </td> ' .
      '<td> &nbsp; </td>': '';

  #*-- enclose e-mail addresses, if necessary
  my $e_char = '\\w._-'; my $e_spec = "[$e_char]+\@[$e_char]+";
  my @en_emails = ();
  push (@en_emails, $1) while ($em{emc_to} =~ /($e_spec)([^>$e_char]|$)/g);
  foreach (@en_emails) { $em{emc_to} =~ s/$_/<$_>/; }

  foreach (qw/emc_text emc_from emc_to emc_cc emc_subject/)
    { next unless($em{$_}); $em{$_} =~ s/</ &lt;/g; $em{$_} =~ s/>/&gt; /g; }

  #*-- handle the edit button
  if ($in{e_opshun} eq 'Edit')
   { #*-- save the to, subject, and text in the session data and
     #*-- call em_compose.pl
     &mod_session($dbh, $in{session}, 'mod', 'from', $em{emc_from},
       'subject', $em{emc_subject}, 'e_text', $em{emc_text}, 
       'to', $em{emc_to}, 'cc', $em{emc_cc} );
     my $e_session  = &url_encode($in{session});
     my $url = $CGI_DIR . 
        "em_compose.pl?session=$e_session&emi_id=$emi_id&e_opshun=" .
        "Del&dlists=&emails=";
     print "Location: $url", "\n\n"; exit(0);
   } 

  #*-- Compose a reply with the attached text of the message to sender
  if ($in{e_opshun} eq 'Reply')
   { #*-- save the to, subject, and text in the session data and
     #*-- call em_compose.pl
     $em{emc_text} =~ s/\n/\n&gt; /g; $em{emc_text} =~ s/^/&gt; /g;
     &mod_session($dbh, $in{session}, 'mod', 'to', $em{emc_from},
       'subject', "Re: $em{emc_subject}", 'e_text', $em{emc_text} );
     my $e_session  = &url_encode($in{session});
     my $url = $CGI_DIR . "em_compose.pl?session=$e_session&dlists=&emails=";
     print "Location: $url", "\n\n"; exit(0);
   }

  #*-- Compose a reply with the attached text of the message to all
  if ($in{e_opshun} eq 'Reply All')
   { #*-- save the to, cc, subject, and text in the session data and
     #*-- call em_compose.pl
     $em{emc_text} =~ s/\n/\n&gt; /g; $em{emc_text} =~ s/^/&gt; /g;
     &mod_session($dbh, $in{session}, 'mod', 'to', 
      join(',', $em{emc_from}, $em{emc_to}), 'cc', $em{emc_cc}, 
      'subject', "Re: $em{emc_subject}", 'e_text', $em{emc_text} );
     my $e_session  = &url_encode($in{session});
     my $url = $CGI_DIR . "em_compose.pl?session=$e_session&dlists=&emails=";
     print "Location: $url", "\n\n"; exit(0);
   }

  #*-- Categorize the e-mail if a new category was chosen
  my $emi_catid = &get_catid();
  if ( ($in{e_opshun} eq 'Categorize') && ($emi_catid != $em{emi_catid}) )
   {
    my $old_catname = &get_catname($em{emi_catid});
    my %email_v = &email_vector($em{emc_from}, $em{emc_to}, $em{emc_cc},
                  $em{emc_subject}, $em{emc_text}, $dbh);
    my $delta = 0; #*-- if moving from or to misc. category, delta is 0
    unless ( ( $old_catname     =~ /^Miscellaneous/i) ||
             ( $in{emc_catname} =~ /^Miscellaneous/i) )
     { my $cent1 = &get_centroid($old_catname);
       my $cent2 = &get_centroid($in{emc_catname});
       my %cent_v1 = &string_to_vec($cent1);
       my %cent_v2 = &string_to_vec($cent2);
       my $sim1 = &sim_val(\%cent_v1, \%email_v);
       my $sim2 = &sim_val(\%cent_v2, \%email_v);
       $delta = abs($sim1 - $sim2); }
    my $elen = length("$em{emc_from} $em{emc_to} $em{emc_cc} " .
                      "$em{emc_subject} $em{emc_text}");
    my $email_str = &vec_to_string(%email_v);

    #*-- add to the new category and remove from the old category
    #*-- use the delta to weight the category changes
    &mod_centroid($dbh, $emi_catid,   $email_str, 'add', $delta); 
    &mod_centroid($dbh, $em{emi_catid}, $email_str, 'rem', $delta); 

    $command = "update em_email set emi_catid = $emi_catid " .
               " where emi_id = $emi_id";
    (undef, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    $em{emi_catid} = $emi_catid;
   }

  #*-- Add an entry in the worklist table for the current message
  #*-- to process later
  if ($in{e_opshun} eq 'Later')
   { 
    #*-- check for a duplicate event
    my $emc_type = 'Send';
    my $emc_period = 'Once';
    $em{emc_from} =~ /<?([\w._-]+@[\w._-]+)>?/;
    my $emc_address = $dbh->quote($1);
    my $emc_descr = $dbh->quote("Reply to $em{emc_subject}");
    my $emi_date = timegm(0, 0, 0, (gmtime(time()))[3..5]);
    $command = "select count(*) from em_worklist where " .
               "emc_address = $emc_address and " . 
               "emc_descr   = $emc_descr   and " . 
               "emi_date    = $emi_date";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    if (($dbh->fetch_row($sth))[0])
     { $stat_msg .= "-- Duplicate event in the worklist table <br>";
       return(); }
    $command = <<"EOF";
     insert into em_worklist values (0, $emi_date, '$emc_type', 
            '$emc_period', $emc_address, $emc_descr)
EOF
    (undef, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    $stat_msg .= "-- Added task to reply later to $emc_address <br>";
   }

  #*-- highlight the search words in the e-mail text
  if (@words)
   { foreach my $word (@words) 
      { 
       $word =~ s/[*]/\\w\*/g;
       foreach (qw/emc_text emc_from emc_to emc_cc emc_subject/)
        { $em{$_} =~ s%($word)%<font color=red>$1</font>%gi if ($em{$_}); }
      } 
   }

  $body_html = <<"EOF";
    <center>
    <table> <tr> 
     <td> <font color=darkred> Email $in{ceid} of $num_files </font> </td>
     <td> &nbsp; </td>
     <td> <input type=submit name=e_opshun value="Next"> </td>
     <td> &nbsp; </td>
     <td> <input type=submit name=e_opshun value="Prev"> </td>
     <td> &nbsp; </td>
     <td> <input type=submit name=e_opshun value="First"> </td>
     <td> &nbsp; </td>
     <td> <input type=submit name=e_opshun value="Last"> </td>
     <td> &nbsp; </td>
    </tr><tr>
     <td> &nbsp; </td>
     <td> &nbsp; </td>
     <td> <input type=submit name=e_opshun value="Reply"> </td>
     <td> &nbsp; </td>
     <td> <input type=submit name=e_opshun value="Reply All"> </td>
     <td> &nbsp; </td>
     <td> <input type=submit name=e_opshun value="Later"> </td>
     <td> &nbsp; </td>
     <td> <input type=submit name=e_opshun value="Return"> </td>
     <td> &nbsp; </td>
     <td> <input type=submit name=e_opshun value="Delete"> </td>
     <td> &nbsp; </td>
     $sent_button
    </tr> </table>
    </center>
    <br> <hr size=3 noshade> 
EOF
    my $e_date = &f_date($em{emi_date});
    my $cc_html = ($em{emc_cc}) ? <<"EOF"
     <tr> <td valign=top align=left width=20%> 
          <font color=darkred size=+1> Cc: </font> </td>
          <td bgcolor=#eae99a align=left width=80%> 
          <font color=darkblue> $em{emc_cc} </font> </td> </tr>
EOF
    : '';

    $em{emc_text} =~ s/\n/<br>/g;
    my $category_option = '';
    foreach ( sort {$catname{$a} cmp $catname{$b}} keys %catname )
     { $category_option .= ($_ == $em{emi_catid}) ?
      "<option value='$catname{$_}' selected> $catname{$_}": 
      "<option value='$catname{$_}'> $catname{$_}"; }

    $body_html .= <<"EOF";
    <table cellspacing=4 cellpadding=0 border=0 width=100%>
     <tr> <td valign=top align=left width=20%> 
          <font color=darkred size=+1> From: </font> </td>
          <td bgcolor=#eae99a align=left width=80%> 
          <font color=darkblue> $em{emc_from} </font> </td> </tr>
     <tr> <td valign=top align=left width=20%> 
          <font color=darkred size=+1> Date: </font> </td>
          <td align=left bgcolor=#eae99a width=80%> <font color=darkblue> 
          $em{emc_status} on $e_date </font> </td> </tr>
     <tr> <td valign=top align=left width=20%> 
          <font color=darkred size=+1> To: </font> </td>
          <td bgcolor=#eae99a align=left width=80%> 
          <font color=darkblue> $em{emc_to} </font> </td> </tr>
     <tr> <td valign=top align=left width=20%> 
          <font color=darkred size=+1> Subject: </font> </td>
          <td bgcolor=#eae99a align=left width=80%> 
          <font color=darkblue> $em{emc_subject} </font> </td> </tr>
      $cc_html
     </table>
    <table cellspacing=4 cellpadding=0 border=0 width=100%>
     <tr> <td bgcolor=#eae99a width=400> <font color=darkblue> 
          $em{emc_text} </font></td></tr>
    </table>

    <table cellspacing=4 cellpadding=0 border=0>
     <tr> <td> <input type=submit name=e_opshun value=Categorize> </td>
          <td> <strong> <select name=emc_catname size=1> 
               $category_option </select> </strong> </td>
          </td></tr>
    </table>
EOF

 }

 #*---------------------------------------------------------------
 #*- Show a page of e-mails with header information
 #*---------------------------------------------------------------
 sub fetch_page
 {
  my ($emi_id, $emc_status, $emi_date, $emc_from, $emc_to, 
      $emc_subject, $emc_cc, $emc_text, $emi_catid);

  #*-- get the list of matching emails 
  my @sort_files = @{$ref_val = &fetch_data()};
  unless (@sort_files)
   { $stat_msg .= "-- No matching files were found<br> "; return(); }

  #*-- compute the current page number
  my $results_per_page = 10; 
  my $num_files = @sort_files;
  my $num_pages = ($num_files >= $results_per_page) ?
               int($num_files / $results_per_page): 0;
  $num_pages++   if ( ($num_files % $results_per_page) != 0);

  #*-- set the current page number
  $in{cpage}++            if ($in{p_opshun} eq 'Next');
  $in{cpage}--            if ($in{p_opshun} eq 'Prev');
  $in{cpage} = 1          if ($in{p_opshun} eq 'First');
  $in{cpage} = $num_pages if ($in{p_opshun} eq 'Last');

  #*-- make sure that cpage is in range
  $in{cpage} = 1          unless($in{cpage});
  $in{cpage} = $num_pages if ($in{cpage} > $num_pages);
  $in{cpage} = 1          if ($in{cpage} < 1);

  #*-- save the current page number
  &mod_session($dbh, $in{session}, 'mod', 'cpage', $in{cpage});
         
  my $start_file = ($in{cpage} - 1) * $results_per_page;
  my @eids = ();
  for (my $i = 0; $i < $results_per_page; $i++)
   { $eids[$i] = $sort_files[$start_file + $i] 
                   if ($sort_files[$start_file + $i]); }

  $body_html = <<"EOF";
    <center>
    <table> <tr> 
     <td> <font color=darkred> Page $in{cpage} of $num_pages </font> </td>
     <td> &nbsp; </td>
     <td> &nbsp; </td>
     <td> <input type=submit name=p_opshun value="Next"> </td>
     <td> &nbsp; </td>
     <td> <input type=submit name=p_opshun value="Prev"> </td>
     <td> &nbsp; </td>
     <td> <input type=submit name=p_opshun value="First"> </td>
     <td> &nbsp; </td>
     <td> <input type=submit name=p_opshun value="Last"> </td>
     <td> &nbsp; </td>
    </tr>
    </table>
    </center>
    <br> <hr size=3 noshade> 
    <table cellspacing=4 cellpadding=0 border=0 width=100%>
    <tr> <td align=left colspan=4>
    <font size=+1 color=darkred> Matching E-Mails: </font><br>
    </td> </tr>
    <tr>
      <td> <font color=darkred> No. </td>
      <td> <font color=darkred> Date </td>
      <td> <font color=darkred> Subject </td>
      <td> <font color=darkred> Name </font> </td>
      <td> <font color=darkred> Category </font> </td>
    </tr>
EOF
  my $i = 1;
  foreach my $eid (@eids)
   {
    $command = "select emi_date, emc_from, emc_to, emc_subject, " .
             " emc_status, emi_catid from em_email where emi_id = $eid";  
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    ($emi_date, $emc_from, $emc_to, $emc_subject, $emc_status, $emi_catid) = 
                $dbh->fetch_row($sth);
    my $e_date = &f_date($emi_date);
    $emc_subject    = &trim_field($emc_subject, 20);
    $emc_from       = &trim_field($emc_from, 20);
    $emc_to         = &trim_field($emc_to, 20);
    my $emc_catname = &trim_field($catname{$emi_catid}, 20);

    my $header = ($emc_status =~ /received/i) ? 'R: ':
                 ($emc_status =~ /sent/i) ? 'S: ': 'C: ';
    my $h_text = ($emc_status =~ /received/i) ? $emc_from: $emc_to;
    $h_text =~ s/</&lt;/g; $h_text =~ s/>/&gt;/g;
    my $pnum = $i + $start_file;
    my $link_email = "$FORM?e_opshun=Fetch&ceid=$pnum"                 . 
                     "&received=$in{received}&composed=$in{composed}"  .
                     "&sent=$in{sent}&fuzzy=$in{fuzzy}"                .
                     "&session=" .  &url_encode($in{session});
    $body_html .= <<"EOF";
     <tr>
      <td> <strong> $pnum. <input type=checkbox name=d_$eid> </strong> </td>
      <td bgcolor=#eae99a> <font color=darkblue> 
                           <a href=$link_email>  $e_date   </font> </a> </td>
      <td bgcolor=#eae99a> <font color=darkblue> $emc_subject </font> </td>
      <td bgcolor=#eae99a> <font color=darkred>  $header </font>
                           <font color=darkblue> $h_text </font> </td>
      <td bgcolor=#eae99a> <font color=darkblue> $emc_catname </font> </td>
     </tr>
EOF
    $i++;
   } #*-- end of for eid

  $body_html .= <<"EOF";
    <tr> <td colspan=6 align=center> 
           <input type=submit name=p_opshun value="Delete"> 
    </td> </tr> 
    </table>
EOF

 }

 #*---------------------------------------------------------------
 #*- fetch the list of files for the query, if any 
 #*---------------------------------------------------------------
 sub fetch_data
 {
  my ($emi_id, $emc_status, $emi_date, $emc_from, $emc_to, 
      $emc_subject, $emc_cc, $emc_text, $emc_dflag, $emi_catid) = '' x 9;

  #*-- get the ids of the files which contain the words in the 
  #*-- description and fall within the time range
  my %files = ();

  #*-- cannot handle NOT here
  @words = @{&content_words(\$in{description}, 'email', $dbh, undef, undef, 1)};
  if ( (@words) && ($in{description} !~ /\bNOT\b/i) )
   {
    foreach my $word (@words)
     { 
      my $table = 'em' . &tab_word($word);
      my $where_c = ' where inc_word ';  #*-- build the where clause
      if ($in{fuzzy} || ($word =~ /[*]/) )
       {
        (my $e_word = $word) =~ s/([._%])/\\$1/g;
        $e_word =~ s/[*]/\%/g; $e_word = '%'."$e_word".'%' if ($in{fuzzy});
        $e_word = $dbh->quote($e_word);
        $where_c .= "LIKE $e_word"; 
       }
      else
       { $where_c .=  "= " . $dbh->quote($word); }

      $command = "select inc_ids from $table $where_c";
      ($sth, $db_msg) = $dbh->execute_stmt($command);
      &quit("Command: $command failed --> $db_msg") if ($db_msg);
      while ( ($emi_id) = $dbh->fetch_row($sth) ) { $files{$emi_id}++; }
     } #*-- end of for each word

    #*--- split the concatenated ids in files into individual ids
    my @id_strings = keys %files; %files = ();
    foreach my $id_string (@id_strings)
     {  
      foreach my $id (split/,/, $id_string)
       {
        #*-- extract the weight
        ($emi_id, my $null, my $wt) = $id =~ /(\d+)($ISEP(\d+))?/;
        $files{$emi_id}+= (defined($wt)) ? $wt: 1;
       } #*-- end of inner for
     } #*-- end of outer for
   }
   #*-- for a blank description, retrieve every file
  else
   {
    $command = "select emi_id from em_email";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    while ( ($emi_id) = $dbh->fetch_row($sth) ) { $files{$emi_id}++; }
    #*-- create the @words array if it does not exist
    @words = split/[, ]/, $in{description} unless(@words); 
   } #*-- end of if @words

  #*-- check if the start and end dates are within the file's time
  my %filter_files = my %time_files = ();
  my $sort_by_wt = 0;
  foreach $emi_id (keys %files)
   {
    $command = <<"EOF";
      select emi_date, emc_status, emc_from, emc_to, emc_subject, emc_dflag, 
       emc_cc, emc_text, emi_catid from em_email where emi_id = $emi_id and 
       $in{start_date} < emi_date and emi_date < $in{end_date}
EOF
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    while ( ($emi_date, $emc_status, $emc_from, $emc_to, $emc_subject,
     $emc_dflag, $emc_cc, $emc_text, $emi_catid) = $dbh->fetch_row($sth) ) 
     {
      #*-- check if the description for the file matches the query
      #*-- $in{description} query matches the  file description
      next if ($emc_dflag && ($emc_dflag eq 'D'));
      $emc_cc = '' unless ($emc_cc);
      next if (@catids && &not_in_catids($emi_catid) );
      next unless 
       (&text_match(\"$emc_from $emc_to $emc_subject $emc_cc $emc_text",
                    $in{description}, $in{fuzzy}));
      my $valid_file = ''; 
      if ($tipe{composed}) 
         { $valid_file = 1 if ($emc_status =~ /composed/i);}
      if ($tipe{sent})      
         { $valid_file = 1 if ($emc_status =~ /sent/i); } 
      if ($tipe{received}) 
         { $valid_file = 1 if ($emc_status =~ /received/i);}
      next unless ($valid_file || $tipe{all});
    
      $filter_files{$emi_id}++; 
      $time_files{$emi_id} = ($sort_by_wt) ? $files{$emi_id}: $emi_date;
     }

   } #*-- end of for each keys %files

  #*-- sort the file list by time
  my @sort_files = (); my $i = 0;
  foreach $emi_id ( sort { $time_files{$b} <=> $time_files{$a} }
                    keys %time_files)
   { $sort_files[$i++] = $emi_id; }

  return(\@sort_files);
 }

 #*---------------------------------------------------------------
 #*- check if the category id is in the catids array        
 #*---------------------------------------------------------------
 sub not_in_catids
 { (my $emi_catid) = @_;
   foreach (@catids) { return(0) if ($emi_catid == $_); }
   return(1); }

 #*---------------------------------------------------------------
 #*- Get the category id
 #*---------------------------------------------------------------
 sub get_catid
 {
  my $catname = ($in{emc_catname}) ? $dbh->quote($in{emc_catname}):
                                     "'Miscellaneous'";
  $command = "select emi_catid from em_category where " .
             " emc_catname = $catname";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  return (($dbh->fetch_row($sth))[0]);
 }

 #*---------------------------------------------------------------
 #*- Get the category name for the category id
 #*---------------------------------------------------------------
 sub get_catname
 {
  my ($catid) = @_;
  return('') unless($catid);
  $command = "select emc_catname from em_category where emi_catid = $catid";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  return (($dbh->fetch_row($sth))[0]);
 }

 #*---------------------------------------------------------------
 #*- Get the centroid for the category
 #*---------------------------------------------------------------
 sub get_centroid
 {
  my ($catname) = @_;
  $catname = $dbh->quote($catname);
  $command = "select emc_centroid from em_category where " .
             "emc_catname = $catname";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  return( ($dbh->fetch_row($sth))[0] );
 }


 #*---------------------------------------------------------------
 #*- fetch the files based on page number and display
 #*---------------------------------------------------------------
 sub head_html
 {
  my $getit_image   = "$ICON_DIR" . "get_it.jpg";
  my $fuzzy = ($in{fuzzy}) ? "CHECKED": "";
  ($in{start_day}, $in{start_month}, $in{start_year}) = 
                   (gmtime($in{start_date}))[3..5]; 
  ($in{end_day}, $in{end_month}, $in{end_year}) = 
                   (gmtime($in{end_date}))[3..5]; 
  $stat_msg .= "-- Start Date is later than End Date<br>" 
               if ($in{start_date} > $in{end_date});
                                     
  my $start_date = &f_date($in{start_date});
  my $end_date   = &f_date($in{end_date});
  my $e_session  = &url_encode($in{session});

  print ${$ref_val = &email_head("Search", $FORM, $in{session})};
  print <<"EOF";
     <center>
      <table>

       <tr> <td colspan=9> <br> </td> </tr>
       <tr>
         <td> <font size=+1 color=darkred> Query: </font> </td>
         <td colspan=8> <strong> 
          <textarea name=description cols=80 rows=1>$in{description}
          </textarea> </strong> </td>
       </tr>

       <tr>
         <td valign=bottom> <font size=+1 color=darkred> Period: </font></td>
         <td colspan=8 valign=bottom>
           <table border=0 cellspacing=0 cellpadding=0>
            <tr> 
             <td valign=bottom> <font color=darkred> Start: </font> 
              <input type=submit name=s_date value="$start_date">
             </td>
             <td> &nbsp; </td>
             <td valign=bottom> <font color=darkred> End: </font> 
              <input type=submit name=e_date value="$end_date">
             </td>
             <td width=5> &nbsp; </td>
             <td valign=bottom> <font size=+1 color=darkred> Type: 
                                </font> </td>
             <td valign=bottom> <font color=darkblue> Sent </font> 
                  <input type=checkbox name=sent $tipe{sent}> </td>
             <td> &nbsp; </td>
             <td valign=bottom> <font color=darkblue> Received </font> 
                  <input type=checkbox name=received $tipe{received}> </td>
             <td> &nbsp; </td>
             <td valign=bottom> <font color=darkblue> Composed </font> 
                  <input type=checkbox name=composed $tipe{composed}> </td>
             <td width=5> &nbsp; </td>
             <td valign=bottom> <font color=darkred size=+1> Fuzzy: </font> </td>
             <td valign=bottom> <input type=checkbox name=fuzzy $fuzzy> </td>
            </tr>
           </table>
         </td>
        </tr>

        <tr>
          <td colspan=9 align=center> 
           <input type=image src="$getit_image" border=0
                  name=opshun value="Getit"> 
          </td> 
        </tr>

       </table>
     </center>

EOF

 }

 #*-------------------------------
 #*- quit with a message                                     
 #*-------------------------------
 sub quit
 {
   &head_html();
   &msg_html("$_[0]" . "<br>$stat_msg"); 
   &tail_html();
   exit(0);
 }

 #*---------------------------------------------------------------
 #*- display a small header 
 #*---------------------------------------------------------------
 sub mini_head_html
 {
  print "Content-type: text/html\n\n";
  print <<"EOF";
   <html>
    <head>
     <title> Search Page for E-Mail Retrieval Engine </title>
    </head>
  
    <body bgcolor=white>

     <form method=POST action="$FORM">
     <center>
EOF
 }


 #*---------------------------------------------------------------
 #*- Dump an error message           
 #*---------------------------------------------------------------
 sub msg_html
 {
  print << "EOF";
    <center>
    <table> <tr> <td bgcolor=lightyellow>
                 <font color=darkred size=4> $_[0] </font> </td>
    </tr> </table>
    </center>
EOF
 }
 

 #*---------------------------------------------------------------
 #*- Dump the end of the html page 
 #*---------------------------------------------------------------
 sub tail_html
 {
  $dbh->disconnect_db($sth);
  print <<"EOF";
    </center>
    <input type=hidden name=session value=$in{session}>
   </form>
  </body>
  </html>
EOF
 }

 #*---------------------------------------------------------------
 #*- Dump a smaller end of the html page 
 #*---------------------------------------------------------------
 sub mini_tail_html
 {
  $dbh->disconnect_db($sth);
  print <<"EOF";
    </center>
    <input type=hidden name=session value=$in{session}>
   </form>
  </body>
  </html>
EOF
 }
