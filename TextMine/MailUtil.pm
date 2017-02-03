
 #*--------------------------------------------------------------------------
 #*- MailUtil.pm						
 #*-
 #*- A group of functions for managing an e-mail archive
 #*--------------------------------------------------------------------------

 package TextMine::MailUtil;

 use strict; use warnings;
 use lib qw/../;
 use Config;
 use Time::Local;
 use Digest::MD5 qw(md5_base64);
 use TextMine::Constants qw($ICON_DIR $CGI_DIR MONTH_NUMBER $SDELIM $ISEP);
 use TextMine::Utils     qw(url_encode);
 use TextMine::Index     qw(add_index rem_index);
 use TextMine::WordUtil  qw(normalize gen_vector sim_val);
 use TextMine::DbCall;
 require Exporter;
 our @ISA = qw(Exporter);
 our @EXPORT = qw(email_head save_email);
 our @EXPORT_OK = qw(compute_centroid get_children mod_centroid
  delete_email email_vector vec_to_string string_to_vec string_to_array);

 #*------------------------------------------------------------------
 #*- email_head
 #*- Description: Dump the header HTML for the email function     
 #*------------------------------------------------------------------
 sub email_head
 {
  my ($function,	#*-- name of the email function
      $FORM,		#*-- the name of email script calling this function
      $session		#*-- the session for this invocation
     ) = @_;
  
  #*-- save the url encoded version of the session id
  my $e_session = '?opshun=&session=' . &url_encode($session);
  my $emm_image = "$ICON_DIR" . "emm.jpg";

  my $se_html  = ($function eq "Search") ?
    "<font color=darkred size=+1>Search</font>":
    "<a href=$CGI_DIR" . "em_search.pl$e_session> 
        <font size=+1> Search </font> </a>";

  my $co_html  = ($function eq "Compose") ?
    "<font color=darkred size=+1>Compose</font>":
    "<a href=$CGI_DIR" . "em_compose.pl$e_session> 
     <font size=+1> Compose </font> </a> ";

  my $li_html  = ($function eq "Lists") ?
    "<font color=darkred size=+1>Lists</font>":
    "<a href=$CGI_DIR" . "em_lists.pl$e_session> 
    <font size=+1> Lists </font> </a>";

  my $pe_html  = ($function eq "People") ?
    "<font color=darkred size=+1>People</font>":
    "<a href=$CGI_DIR" . "em_people.pl$e_session> 
    <font size=+1> People </font> </a>";

  my $ca_html  = ($function eq "Category") ?
    "<font color=darkred size=+1>Category</font>":
    "<a href=$CGI_DIR" . "em_category.pl$e_session> 
    <font size=+1> Category </font> </a> ";

  my $wf_html  = ($function eq "E-flow") ?
    "<font color=darkred size=+1>E-flow</font>":
    "<a href=$CGI_DIR" . "em_workflow.pl$e_session> 
    <font size=+1> E-flow </font> </a> ";

  my $anchor = "$CGI_DIR/co_login.pl$e_session";
  my $body_html = "Content-type: text/html\n\n";
  $body_html .= <<"EOF";
   <html>
    <head>
     <title> E-Mail Administration Page </title>
    </head>

    <body bgcolor=white>
     <center>
      <form method=POST action="$FORM" name="dbform">
      <table> <tr> <td> <a href=$anchor>
              <img src="$emm_image" border=0> </td> </tr> </table>

      <table border=0 cellspacing=0 cellpadding=0>
       <tr>
        <td bgcolor=#efefef align=center width=120 nowrap> $ca_html </td>
        <td width=15>&nbsp;</td>
        <td bgcolor=#efefef align=center width=120 nowrap> $co_html </td>
        <td width=15>&nbsp;</td>
        <td bgcolor=#efefef align=center width=120 nowrap> $li_html </td>
        <td width=15>&nbsp;</td>
        <td bgcolor=#efefef align=center width=120 nowrap> $pe_html </td>
        <td width=15>&nbsp;</td>
        <td bgcolor=#efefef align=center width=120 nowrap> $se_html </td>
        <td width=15>&nbsp;</td>
        <td bgcolor=#efefef align=center width=120 nowrap> $wf_html </td>
       </tr>
       <tr>
        <td colspan=11 bgcolor=#ffcc33><img width=1 height=1 alt=""></td> 
       </tr>
      </table>

EOF
  return(\$body_html);

 }

 #*---------------------------------------------------------------
 #*- Compute a centroid for an e-mail category                
 #*- Get all the data for the category and build a vector
 #*- return the string representation of the vector
 #*---------------------------------------------------------------
 sub compute_centroid
 {
  my ($emi_catid,	#*-- the category id
      $dbh		#*-- database handle
  ) = @_;

  #*-- return if we are trying to compute the centroid for the misc. category
  #*-- misc. category has an empty centroid
  return('') if ($emi_catid == &get_misc_id($dbh) );

  my $command = "select emc_from, emc_to, emc_cc, emc_subject, emc_text " .
                "from em_email where emi_catid = $emi_catid";
  (my $sth, my $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  my $from = my $to = my $cc = my $subject = my $text = '';
  while ( my ($emc_from, $emc_to, $emc_cc, $emc_subject, $emc_text) =
          $dbh->fetch_row($sth) )
   { $from    .= " $emc_from";    $to   .= " $emc_to"; $cc .= " $emc_cc"; 
     $subject .= " $emc_subject"; $text .= " $emc_text"; }

  #*-- generate a vector from the email attributes
  my %vector = &email_vector($from, $to, $cc, $subject, $text, $dbh);
  return( &vec_to_string(%vector) );
 }

 #*------------------------------------------------------------------
 #*- Create a vector from e-mail fields 
 #*------------------------------------------------------------------
 sub email_vector
 {
  my ($from,	#*-- from e-mail addresses
      $to, 	#*-- to e-mail addresses 
      $cc,	#*-- cc e-mail addresses
      $subject, #*-- subject field
      $text, 	#*-- text of the emails
      $dbh,	#*-- database handle
      $len	#*-- max. length of the email vector
    ) = @_;

  $len = 100 unless ($len); #*-- limit length of vector to 100
  my @docs = (); my $str = $text; 

  #*-- assign a higher weight to subject and from fields by repeating
  #*-- it 5 times
  $str .= " $subject " x 5; $str .= "$from " x 5; 
  $str .= "$to "       x 1; $str .= "$cc "   x 1 if ($cc); 

  #*-- generate the vector using the frequency
  my %vector = &gen_vector(\$str, 'fre', 'email', $dbh, $len);
  return(%vector);
 }

 #*------------------------------------------------------------------
 #*- Add/remove a vector to/from the centroid and recompute the centroid
 #*- Accept a vector and its length and the optional delta value
 #*------------------------------------------------------------------
 sub mod_centroid
 {
  my ($dbh,	#*-- database handle
      $catid,	#*-- category id
      $vector,	#*-- vector to modify the centroid for the category
      $func, 	#*-- function to add or remove the vector from the centroid
      $delta	#*-- vector weight for centroid addition/removal 
     ) = @_;

  return('') unless($dbh && $catid);
  $delta = 0.0 unless($delta); #*-- set a default value

  #*-- get centroid information
  my $command = "select emc_catname, emc_centroid, emi_text_size, " .
     "emc_end_train from em_category where emi_catid = $catid";
  (my $sth, my $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  my ($emc_catname, $emc_centroid, $emi_text_size, $emc_end_train) = 
       $dbh->fetch_row($sth);

  #*-- the centroid for the misc. category is not modified
  #*-- if the training for this category is ended, do not modify
  return('') if ( ($emc_catname =~ /^Miscellaneous/i) ||
                  ($emc_end_train eq 'Y') );

  #*-- compute the weight for the message being added/removed
  #*-- a higher weight for a longer message
  my $msg_wt = my $cen_wt = 0; my $vlen = length($vector);
  if ($func =~ /add/i)
   { $msg_wt = ($vlen * (1.0 + $delta) ) / ($emi_text_size + $vlen); }
  elsif ($func =~ /rem/i)
   { if ($emi_text_size > $vlen)
      { $msg_wt = ($vlen * (1.0 + $delta) ) / ($emi_text_size - $vlen) }
     else { $msg_wt = 1.0; }
   }
  $cen_wt = 1.0 - $msg_wt;

  #*-- sum the vector and the centroid with the appropriate weights
  my %vec_c = &string_to_vec($emc_centroid);
  my %vec_v = &string_to_vec($vector);
  my %vec = &combine_v(\%vec_c, $cen_wt, \%vec_v, $msg_wt, $func);
  &normalize(\%vec);

  #*-- update the em_category table with the new centroid and length
  my $centroid = $dbh->quote(&vec_to_string(%vec));
  my $tlen = ($func =~ /^add/i) ? $emi_text_size + $vlen:
                                  $emi_text_size - $vlen;
  $tlen = 0 if ($tlen < 0);
  $command = "update em_category set emc_centroid = $centroid, " .
             "emi_text_size = $tlen where emi_catid = $catid"; 
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
 }

 #*--------------------------------------------------------------------
 #*- combine two vectors to form a common vector based on the function
 #*-   %vec = %v1 +/- %v2
 #*--------------------------------------------------------------------
 sub combine_v
 {
  my ($v1, 	#*-- vector 1
      $w1,	#*-- weight for vector 1
      $v2,	#*-- vector 2
      $w2, 	#*-- weight for vector 2
      $func,	#*-- add or remove
      $len	#*-- max. length for combined vector
     ) = @_;
  
  $len = 100 unless($len);
  my %vec = (); my %v1 = %$v1; my %v2 = %$v2;
  $w1 = 0 unless($w1); $w2 = 0 unless($w2); 
  foreach (keys %v1) { $vec{$_}  = $v1{$_} * $w1; }
  if ($func =~ /add/i)
   { foreach (keys %v2) 
      { if ($vec{$_})   { $vec{$_} += $v2{$_} * $w2; }
        else            { $vec{$_}  = $v2{$_} * $w2; } }
   }
  elsif ($func =~ /rem/i)
   { foreach (keys %v2) 
      { if ($vec{$_})   { $vec{$_} -= $v2{$_} * $w2; } }
   }

  #*-- remove words from the vector which have a very low weight
  foreach (keys %vec) { delete($vec{$_}) if ($vec{$_} < 0.001); }

  #*-- limit the length of the new vector
  my %new_vec = (); my $i = 0;
  for my $term (sort {$vec{$b} <=> $vec{$a}} keys %vec )
   { $new_vec{$term} = $vec{$term}; 
     last if (++$i == $len); }

  return(%new_vec);

 }

 #*----------------------------------------------
 #*- recursively get all children categories
 #*----------------------------------------------
 sub get_children
 {
  my ($catid, $dbh) = @_;

  my @ids = ($catid);
  my $command = "select emi_catid from em_category where " .
                " emi_parent = $catid";
  (my $sth, my $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  while ( (my $emi_catid) = $dbh->fetch_row($sth) )
   { push (@ids, &get_children($emi_catid, $dbh) ); }
  return(@ids);
 }

 #*---------------------------------------------------------------
 #*- create a string for the vector with appropriate delimiters
 #*---------------------------------------------------------------
 sub vec_to_string
 { (my %vector) = @_;
   return ( join ($SDELIM, map {"$_#$vector{$_}"}
            sort {$vector{$b} <=> $vector{$a}} keys %vector) );
 }

 #*---------------------------------------------------------------
 #*- create a vector from the string with appropriate delimiters
 #*---------------------------------------------------------------
 sub string_to_vec
 { (my $string) = @_;
   return ( map { my($term, $wt) = split/#/, $_; $term => $wt}
            split/$SDELIM/, $string);
 }

 #*---------------------------------------------------------------
 #*- create an array from the string with appropriate delimiters
 #*---------------------------------------------------------------
 sub string_to_array
 { (my $string) = @_;
   return ( map { my($term, $wt) = split/#/, $_; $term . $ISEP . $wt}
            split/$SDELIM/, $string);
 }

 #*---------------------------------------------------------------
 #*- Delete the e-mail from the table and the index
 #*---------------------------------------------------------------
 sub delete_email
 {
  my ($dbh, $emi_id) = @_;
  my ($sth, $command, $db_msg, $stat_msg);

  #*-- delete from the index
  $command  = "select emc_from, emc_to, emc_subject, emi_catid, ";
  $command .= " emc_cc, emc_text from em_email where emi_id = $emi_id";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  my ($emc_from, $emc_to, $emc_subject, $emi_catid, $emc_cc, $emc_text) =
                                        $dbh->fetch_row($sth);
  #*-- delete the id from the index
  $emc_cc = '' unless ($emc_cc); $emc_subject = '' unless ($emc_subject);
  my $descr = "$emc_from $emc_to $emc_subject $emc_cc $emc_text";
  $stat_msg .= &rem_index($emi_id, "$descr", 'em', $dbh, 'email');

  #*-- delete the id from the email table
  $command  = "delete from em_email where emi_id = $emi_id";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
 }


 #*---------------------------------------------------------------
 #*- Save the e-mail text in the database and parse the text
 #*- Mail text is in the form
 #*- 
 #*- Date: 
 #*- From:
 #*- To:
 #*- Subject:
 #*- ....... Body ......
 #*- ......Repeated for each email message....
 #*---------------------------------------------------------------
 sub save_email
 {
  my ($dbh,	   #*-- database handle
      $email_text, #*-- a text string containing from,to, date, and text 
      $sep	   #*-- separator characters for messages
     ) = @_;
  my ($sth, $command, $db_msg, $stat_msg);

  #*-- save the header regex to extract mail headers
  $sep = '<br>' unless($sep);
  my @header_tags = qw/from to cc date sent subject/;
  local $"='|'; my $h_regex = qr/^\s*(@header_tags)\s*:(.*)$/i; local $"=' ';

  #*-- save the email information in an array using the tags
  #*-- Use a 2D hash ($email) to save multiple e-mails
  $stat_msg = '';
  my $id = 0;		#*-- message id counter 
  my $m_text = '';	#*-- message text
  my %email = (); #*-- array for msg text and headers

  my ($line, $line_key); my $i = 0;

  #*-- break the e-mail messages
  my @lines = split/\n/, $email_text;
  LOOP: while ($i <= $#lines)
  {
   #*-- check for a potential message header field
   if ( (my $line_key, $line) = $lines[$i] =~ m#$h_regex#)
    {
     $line_key = lc($line_key);
  
     #*-- skip if the tag has been seen for this message id
     #*-- add the tag and also check for a tag which maybe
     #*-- on 2 lines
     unless ($email{"$id,$line_key"})
      { 
        $email{"$id,$line_key"} = 
          ($line =~ /\S/) ? $line:
          ( ($lines[$i+1] =~ m#$h_regex#) ) ? $line: $lines[++$i]; 
      }
     else
      { $email{"$id,text"} .= $lines[$i] . "\n"; }
 
     $i++; next LOOP;
    } #*-- end of if

   #*-- check for end of message line
   if ($lines[$i] =~ /[-]+end of message[-]+/i)
    { $id++; $i++; next LOOP;
    } #*-- end of if

   $email{"$id,text"} .= $lines[$i++] . "\n"; 

  } #*-- end of while lines

  #*-- reset the mail id counter for the last email
  $id-- unless ($email{"$id,text"});

  #*-- clean up the mail tags - set the date and e-mail addresses
  for my $m_id (0..$id)
   { for my $tag (@header_tags)
      { 
       next unless ($email{"$m_id,$tag"});

       #*-- strip leading and trailing spaces
       $email{"$m_id,$tag"} =~ s/^\s+//; $email{"$m_id,$tag"} =~ s/\s+$//; 

       #*-- remove the angle brackets from the emails
       if ( ($tag =~ /^(from|to|cc)$/) && $email{"$m_id,$1"} )
        { $email{"$m_id,$tag"} =~ s/<([^>]+)>/$1/g; }

       #*-- convert the date to an epoch time, try 2 formats
       if ( ($tag =~ /^(date|sent)$/) && $email{"$m_id,$1"} )
        {
         my ($sec, $min, $hour, $date, $month, $year, $am);
         my $loc_time = time(); 
         if ( ( ($date, $month, $year, $hour, $min, $sec)
                 = $email{"$m_id,$tag"} =~ 
                /(\d+)\s+(\w+)\s+(\d+)\s+  #*-- date, month, and year
                 (\d+):(\d+):(\d+)/x) ||   #*-- hour, minute, and second
              ( ($month, $date, $year, $hour, $min, $am)
                 = $email{"$m_id,$tag"} =~
                /(\w+)\s+(\d+),\s+(\d+)\s+ #*-- month, date, and year
                 (\d+):(\d+)\s+((?i)a|pm)/x) )
          {
           #*-- set the month and year
           $month = lc(substr($month,0,3)); $month = MONTH_NUMBER->{$month};
           if ($year < 1900) { $year += ($year < 50) ? 2000: 1900; }
           $year -= 1900;
           #*-- set the hour and the seconds
           if ($am)
            { $sec = 0;
              $hour += 12 if ( ($am =~ /pm/i) && ($hour < 12) );
              $hour = 0   if ( ($am =~ /am/i) && ($hour == 12) ); }
 
           #*-- verify ranges before making the timegm call
           $loc_time = timegm($sec, $min, $hour, $date, $month, $year) 
           if ( (0 <= $sec)   && ($sec <=  59)   &&  #*-- seconds
                (0 <= $min)   && ($min <=  59)   &&  #*-- minutes
                (0 <= $hour)  && ($hour <=  23)  &&  #*-- hours
                (1 <= $year)  && ($year <= 138)  &&  #*-- year
                (0 <= $month) && ($month <=  11) &&  #*-- month
                (1 <= $date)  && ($date <=  31)  );  #*-- day
          } #*-- end of if my @date

          $email{"$m_id,date"} = $loc_time;
         }
        #*-- end of if $tag...

      } #*-- end of inner for
   } #*-- end of outer for

  #*-- check for the mandatory tags in the email message
  my $err_msg = 0;
  for my $m_id (0..$id)
   { 
    unless ($email{"$m_id,from"} && $email{"$m_id,to"} &&
            $email{"$m_id,date"})
     { print "Error in message $m_id \n"; 
       print "From: $email{\"$m_id,from\"}\n";
       print "To: $email{\"$m_id,to\"}\n";
       print "Date: $email{\"$m_id,date\"}\n";
       print "Subject: $email{\"$m_id,subject\"}\n";
       $err_msg++; }
   }
  exit(0) if ($err_msg);

  #*-- save the email and headers in the database
  for my $m_id (0..$id)
   { 
    #*-- set default values for cc and subject fields
    $email{"$m_id,cc"}      = '' unless ($email{"$m_id,cc"});
    $email{"$m_id,subject"} = '' unless ($email{"$m_id,subject"});

    #*-- check if a duplicate email exists, same message at the same
    #*-- time from same person
    my $digest  = $dbh->quote(md5_base64($email{"$m_id,text"}));
    my $from    = $dbh->quote($email{"$m_id,from"});
    $command = <<"EOF";
      select count(*) from em_email where emc_from = $from and 
             emi_date = $email{"$m_id,date"} and emc_digest = $digest
EOF
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit ("Command: $command failed --> $db_msg") if ($db_msg);
    if ( ($dbh->fetch_row($sth))[0] > 0)
     { $stat_msg .= "-- A duplicate message from " . $email{"$m_id,from"} .
                    " exists in the database$sep"; next; }
     
    my $subject = $dbh->quote($email{"$m_id,subject"}); 
    my $to      = $dbh->quote($email{"$m_id,to"}); 
    my $cc      = $dbh->quote($email{"$m_id,cc"}); 
    my $text    = $dbh->quote($email{"$m_id,text"}); 

    #*-- create an email vector from the email
    my %e_vec = &email_vector( $email{"$m_id,from"}, $email{"$m_id,to"}, 
    $email{"$m_id,cc"}, $email{"$m_id,subject"}, $email{"$m_id,text"}, $dbh);
    $command = "select emi_catid, emc_centroid from em_category";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit ("Command: $command failed --> $db_msg") if ($db_msg);
    
    #*-- find the centroid which best matches the vector
    my $max_sim = 0.0; my $max_catid = 0;
    while ( my ($emi_catid, $emc_centroid) = $dbh->fetch_row($sth) )
     { next unless($emc_centroid =~ /\w/);
       my %c_vec = &string_to_vec($emc_centroid);
       my $sim   = &sim_val(\%e_vec, \%c_vec);
       if ($sim > $max_sim)
        { $max_sim = $sim; $max_catid = $emi_catid; } 
     }

    #*-- if the max. sim is > than the threshold, set the category
    if ($max_sim >= 0.2)
     { my $vlen = length( $email{"$m_id,from"} . $email{"$m_id,to"} .
       $email{"$m_id,cc"} . $email{"$m_id,subject"} . $email{"$m_id,text"} );
       #*-- add the new email to the centroid
       &mod_centroid($dbh, $max_catid, &vec_to_string(%e_vec), $vlen,
                     'add', 0); }
    else #*-- put in the misc. category
     { $max_catid = &get_misc_id($dbh); }

    $command = <<"EOF";
    insert into em_email set emi_id = 0, emi_date = $email{"$m_id,date"},
     emi_catid = $max_catid, emc_status = 'Received', emc_subject = $subject,
     emc_digest = $digest, emc_from = $from,        emc_to = $to, 
     emc_cc = $cc,         emc_text = $text
EOF
    (undef, $db_msg) = $dbh->execute_stmt($command);
    &quit ("Command: $command failed --> $db_msg") if ($db_msg);
    $stat_msg .= "-- Message from " .  $email{"$m_id,from"} . " saved$sep";

    #*--- retrieve the id of the latest message and update the index
    $email{"$m_id,id"} = $dbh->last_id();
    
    my $tvar = $email{"$m_id,from"} . " " . $email{"$m_id,to"};
    $tvar   .= " " . $email{"$m_id,cc"}      if ($email{"$m_id,cc"});
    $tvar   .= " " . $email{"$m_id,subject"} if ($email{"$m_id,subject"});
    $stat_msg .= &add_index($email{"$m_id,id"}, $tvar, 'em', $dbh, 'email');
    $stat_msg .= &add_index($email{"$m_id,id"}, $email{"$m_id,text"},'em',$dbh);

   } #*-- end of for $m_id

  #*-- process the 'from' and 'to' tags to build the network
  my @patterns = ();
  my $e_spec = '<?([\w._-]+@[\w._-]+)>?'; my $n_quote = '"([^"]+)"';
  my $n_chars = '(.*?)';
  push(@patterns, "$n_quote\\s*$e_spec|$e_spec\\s*$n_quote");
  push(@patterns, "$n_chars\\s*$e_spec|$e_spec\\s*$n_chars");
  my @e_regexes = map { qr/$_/ } @patterns;

  #*-- create the e-mail network
  my ($from_email, $from_name);
  for my $m_id (0..$id)
   { 
    TAG: for my $tag (qw/from to cc/)
     { 

      #*-- split on commas and then combine as needed
      my @s_emails = split/,/, $email{"$m_id,$tag"} 
                     if ($email{"$m_id,$tag"});
      my $i = 0;
      while ($i <= $#s_emails)
       {
        my $s_email = $s_emails[$i];
        if ($s_email =~ /"/)      #*-- fix problems with commas in quotes
         { while ($s_email !~ /".*"/)
            { $s_email .= ",$s_emails[++$i]"; last if ($i == $#s_emails); }
         } #*-- end of if

        $s_email =~ s/^\s+//; $s_email =~ s/\s+$//;
        REGEX: foreach my $e_regex (@e_regexes)
         {
          #*-- set the e-mail and name, if possible
          my ($email, $name);
          if ($s_email =~ /$e_regex/)
           {
            #*-- save the from and to in the database
            ($email, $name) = ($1 || $2) ? ($2, $1): ($4, $3);
            ($email, $name) = ($name, $email) if ($email !~ /$e_spec/);
            $email = $dbh->quote($email); $name = $dbh->quote($name);
            if ($tag eq 'from')
             { ($from_email, $from_name) = ($email, $name); }
            else
             {
              $command  = "select nei_count from em_network where";
              $command .= " nec_from = $from_email and nec_to = $email";
              ($sth, $db_msg) = $dbh->execute_stmt($command);
              &quit ("Command: $command failed --> $db_msg") if ($db_msg);
              my $count = ($dbh->fetch_row($sth))[0];
              $count = ($count) ? ($count + 1): 1;
              $command = <<"EOF";
               replace into em_network
               (nec_from, nec_from_name, nec_to, nec_to_name, nei_count)
               values ( $from_email,$from_name, $email, $name, $count)
EOF
              (undef, $db_msg) = $dbh->execute_stmt($command);
             } #-- end of inner if
            last REGEX;
           } #*-- end of outer if
         } #*-- end of foreach e_regex
        $i++;
       } #*-- end of while
     } #*-- end of inner for
   } #*-- end of outer for
 
  return($stat_msg);

 } #*-- end of save_email

 #*------------------------------------------------------
 #*- get the category id for the miscellaneous category
 #*------------------------------------------------------
 sub get_misc_id
 { my ($dbh) = @_;
   my $command = "select emi_catid from em_category where " .
                  "emc_catname = 'Miscellaneous'";
   my ($sth, $db_msg) = $dbh->execute_stmt($command);
   &quit ("Command: $command failed --> $db_msg") if ($db_msg);
   return( ($dbh->fetch_row($sth))[0] );
 }


 #*---------------------------------------------------
 #*- return with an error message
 #*---------------------------------------------------
 sub quit
 {
  my ($msg) = @_;
  print STDERR "$msg\n";
  return; 
 }

1; #return true 
=head1 NAME

TextMine - MailUtil (Utilities for handling e-mail)

=head1 SYNOPSIS

use TextMine::MailUtil;

=head1 DESCRIPTION

=head2 email_head

  Generate the HTML for an e-mail header based on the current
  function.

=head2 save_email

  A long function to parse the passed text and save the e-mail.
  The tags for the e-mail are saved in a hash. The text and
  mail tags are indexed and saved in a database index. The text
  and metadata for the e-mail are saved in another e-mail table.
  The e-mail network is updated based on the from and to addresses
  in the e-mail.

=head2 compute_centroid

  Every category has zero or more associated e-mails. The text and
  e-mail metadata is used to build a centroid for the category. 
  The centroid is a vector consisting of 100 terms with weights
  that describe the category.

=head2 mod_centroid

  A centroid can be modified based on the manual categorization
  of an incoming e-mail. The weight of the new e-mail in modifying
  the category description is taken into account. A long e-mail
  will have more weight than a short e-mail. An e-mail can be
  added or removed from a category. The centroid is appropriately
  adjusted to reflect the addition or removal of the e-mail.

=head2 delete_email

  Emails are deleted in batch. When an e-mail is deleted on the
  web interface, it is marked for deletion. The actual deletion
  takes place when a batch script is executed. The index for the
  e-mail is build and removed. Then, the text for the e-mail and
  associated metadata is removed from the e-mail table. The
  e-mail network is not updated.

=head1 AUTHOR

Manu Konchady <mkonchady@yahoo.com>
