#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
#*----------------------------------------------------------------
#*- em_compose.pl
#*-  
#*-   Summary: Save the composed e-mail in the table. Index the 
#*-            text and update send/receive stats
#*----------------------------------------------------------------

 use strict; use warnings;
 use Digest::MD5 qw(md5_base64);
 use TextMine::DbCall;
 use TextMine::Constants;
 use TextMine::Utils;
 use TextMine::MailUtil;
 use TextMine::Index qw(add_index rem_index);
 
 #*-- global variables 
 use vars (
  '$dbh',	#*-- database handle
  '$sth',	#*-- statement handle
  '$stat_msg',	#*-- status message for the page
  '$db_msg',	#*-- database message
  '$command',	#*-- SQL Command variable
  '$ref_val',	#*-- reference variable
  '%in',	#*-- hash for form fields
  '@PARMS',	#*-- field names in the form
  '$FORM',	#*-- name of form
   );

 #*-- set the global vars
 &set_vars();

 #*-- handle the options
 if ($in{opshun}   eq 'Save')  { &store_email(); }
 if ($in{e_opshun} eq 'Del')   { &del_email(); }
 if ($in{opshun}   eq 'Reset') { $in{$_} = '' foreach (@PARMS); } 

 #*-- dump the header, body, status and tail html 
 print ${$ref_val = &email_head("Compose", $FORM, $in{session})}; 
 &msg_html($stat_msg) if ($stat_msg); 
 &body_html(); 
 &tail_html(); 

 exit(0);

 #*---------------------------------------------------------------
 #*- Set the variables       
 #*---------------------------------------------------------------
 sub set_vars
 {
  #*-- retrieve the passed parameters and set the form name
  $0 =~ s%.*[/\\]%%; $FORM = "$CGI_DIR" . "$0";
  %in    = %{$ref_val = &parse_parms};

  $in{e_text} =~ s/\cM//g if ($in{e_text}); #*-- strip out control Ms

  #*-- establish a DB connection
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $in{userid}, 'Password' => $in{password},
       'Dbname' => $DB_NAME);

  #*-- initialize the form field names
  @PARMS = qw/from to cc subject e_text encrypt/;
  foreach ('dlists', 'emails', 'opshun', 'e_opshun', 'emi_id', @PARMS)
   { $in{$_} = '' unless ($in{$_}); }

  #*-- build the to variable using passed emails
  if ($in{emails})
   { foreach (split/,/, $in{emails}) 
       { $in{to} .= &get_details($_) . ','; } }

  #*-- build the to variable using the passed lists
  if ($in{dlists})
   {
    my (%ids, $identity); %ids = ();
    foreach (split/,/, $in{dlists})
     {
      #*-- for each list get the associated members
      next unless($_);
      $command  = "select dlc_identity from em_dlist_abook ";
      $command .= " where dlc_name = " . $dbh->quote($_);
      ($sth, $db_msg) = $dbh->execute_stmt($command);
      &quit("Command: $command failed --> $db_msg") if ($db_msg);
      $ids{$identity}++ while ( ($identity) = $dbh->fetch_row($sth) );
     }

    #*-- for each id get the name and add to the to variable
    foreach (sort keys %ids) { $in{to} .= &get_details($_) . ','; } 
   } #*-- end of if in dlists

  &mod_session($dbh, $in{session}, 'del', 'dlists', 'emails', 
                        'e_opshun', 'emi_id', @PARMS);
  $in{to} =~ s/,$//;
 }

 #*---------------------------------------------------------------
 #*- Return the name and e-mail for an identity      
 #*---------------------------------------------------------------
 sub get_details
 {
  (my $identity) = @_;
  my ($abc_name, $abc_email);
 
  foreach (qw/em_abook em_abook_home/)
   {
    $command = "select abc_name, abc_email from $_"; 
    $command .= " where abc_identity = " . $dbh->quote($identity);
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    ($abc_name, $abc_email) = $dbh->fetch_row($sth);
    last if ($abc_name);
   } #*-- end of inner for
  $abc_name =~ s/"/'/g if ($abc_name); #*-- cannot handle "
  $abc_email = '<' . $abc_email . '>'  if ($abc_email);
  return ( $abc_email ? "\"$abc_name\" $abc_email": $identity);

 }
 
 #*---------------------------------------------------------------
 #*- Build the screen to receive the email text      
 #*---------------------------------------------------------------
 sub body_html
 {
  my ($email, $identity, @ids);

  #*-- get the list of private e-mails and identity
  $command = "select abc_identity from em_abook_home"; 
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  push(@ids, "$identity") while ( ($identity) = $dbh->fetch_row($sth) );
  my $from_option = '';
  foreach (@ids)
   { $from_option .= ($_ eq $in{from}) ? "<option selected> $_":
                                         "<option> $_"; }
  my $yes_check = ($in{encrypt} eq 'Yes') ? 'CHECKED':'';
  my $no_check  = ($yes_check) ?            '':'CHECKED';

  #*-- show the name, identity, e-mail, and notes fields
  print <<"EOF";
  <br>
  <table cellspacing=2 cellpadding=0 border=0>

  <tr>
    <td> <font color=darkred size=+1> From: </font> </td>  
    <td> <select name=from size=1> $from_option </select> </td>  
  </tr>

  <tr>
    <td> <font color=darkred size=+1> To: </font> </td>  
    <td> <textarea name=to cols=80 rows=1>$in{to}</textarea> </td>  
  </tr>

  <tr>
    <td> <font color=darkred size=+1> Cc: </font> </td>  
    <td> <textarea name=cc cols=80 rows=1>$in{cc}</textarea> </td>  
  </tr>

  <tr>
    <td> <font color=darkred size=+1> Subject: </font> </td>  
    <td> <textarea name=subject cols=80 rows=1>$in{subject}</textarea> </td>  
  </tr>

  <tr>
    <td> <font color=darkred size=+1> Text: </font> </td>  
    <td> <textarea name=e_text cols=80 rows=10>$in{e_text}</textarea> </td>
  </tr>  

  <tr>
    <td> <font color=darkred size=+1> Encrypt: </font> </td>  
    <td> Yes <input type=radio name=encrypt value='Yes' $yes_check>
         No  <input type=radio name=encrypt value='No' $no_check> </td>
  </tr>

  <tr>
    <td> &nbsp; </td>  
    <td>  
        <table border=0 cellspacing=10 cellpadding=0>
        <tr> <td> <input type=submit name=opshun value="Save">  </td>
             <td> <input type=submit name=opshun value="Reset"> </td>
        </tr>
        </table>
    </td>
  </tr>  

  </table>
EOF

 }

 #*---------------------------------------------------------------
 #*- save the e-mail in the table
 #*---------------------------------------------------------------
 sub store_email
 {
  #*-- quote the parameters
  my $from    = $dbh->quote('"'. &get_name($in{from}) . '"' . "<" . 
                                 &get_email($in{from})     . ">");
  return (0) unless ($in{to});

  #*-- check if to/cc address is a nickname or a dist. list
  foreach my $to_cc (qw/to cc/)
   {
    my @addrs = (); my $details;
    &fix_comma(\$in{$to_cc});
    foreach my $addr (split/$ISEP/, $in{$to_cc})
     {
      #*-- 0. Clean up the address
      $addr =~ s/^\s+//; $addr =~ s/\s+$//;

      #*-- 1. if it looks like an e-mail address, add to list
      if ($addr =~ /@/) { push (@addrs, $addr); }

      #*-- 2. if is a nickname, get the address
      elsif ( ($details = &get_details($addr) ) &&
              ($details =~ /</) ) { push (@addrs, $details); }

      #*-- 3. if it is a list, get the addresses
      else
       {
        $command = "select dlc_identity from em_dlist_abook where " .
                   "dlc_name = " . $dbh->quote($addr);
        my ($sth, $db_msg) = $dbh->execute_stmt($command);
        &quit("Command: $command failed --> $db_msg") if ($db_msg);
        while ( my ($dlc_identity) = $dbh->fetch_row($sth) )
         { push (@addrs, &get_details($dlc_identity) ); }
       }
     } #*-- end of inner for

    #*-- build the new list of addresses
    $in{$to_cc} = join(',', @addrs) if (@addrs); $in{$to_cc} =~ s/,$//;
   } #*-- end of outer for

  my $to      = $dbh->quote($in{to});
  my $cc      = $dbh->quote($in{cc});
  my $subject = $dbh->quote($in{subject});
  my $e_text  = $dbh->quote($in{e_text});
  
  #*-- encrypt the text, if necessary using a public key
  if ($in{encrypt} eq 'Yes') { }
  
  #*-- check if a duplicate email exists, same to address and
  #*-- the same text
  my $digest  = $dbh->quote(md5_base64($in{e_text}));
  $command  = "select count(*) from em_email where ";
  $command .= "emc_to = $to and emc_digest = $digest";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  if (($dbh->fetch_row($sth))[0])
   { $stat_msg .= "-- A duplicate message to $in{to}";
     $stat_msg .= " exists in the database<br>"; return; }

  #*-- if not, then save the e-mail 
  my $ltime = time();
  $command = <<"EOF";
  insert into em_email (emi_id, emi_date, emi_catid, emc_status, 
    emc_subject, emc_digest, emc_from, emc_to, emc_cc, emc_text)
  values (0, $ltime, 1, 'Composed', $subject, $digest, $from, $to, 
                 $cc, $e_text)
EOF
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  $stat_msg .= "-- The message to $in{to} was saved<br> ";

  #*-- build the index for the email headers and text
  my $id = $dbh->last_id();
  $stat_msg .= &add_index($id, 
      "$in{from} $in{to} $in{cc} $in{subject}", 'em', $dbh, 'email');
  $stat_msg .= &add_index($id, "$in{e_text}", 'em', $dbh);

  #*-- process the 'from' and 'to' tags to build the email network
  my @patterns = ();
  my $e_spec = '<?([\w._-]+@[\w._-]+)>?'; my $n_quote = '"([^"]+)"';
  my $n_chars = '(.*?)';
  push(@patterns, "$n_quote\\s*$e_spec|$e_spec\\s*$n_quote");
  push(@patterns, "$n_chars\\s*$e_spec|$e_spec\\s*$n_chars");
  my @e_regexes = map { qr/$_/ } @patterns;

  my ($from_name, $from_email);
  $from_name  = $dbh->quote(&get_name($in{from}));
  $from_email = $dbh->quote(&get_email($in{from}));

  for my $tag (qw/to cc/)
   {
    #*-- split on commas and then combine as needed
    my @s_emails = split/,/, $in{$tag}; my $i = 0;
    while ($i <= $#s_emails)
     {
      my $s_email = $s_emails[$i];
      if ($s_email =~ /"/)      #*-- fix problems with commas in quotes
       { while ($s_email !~ /".*"/)
          { $s_email .= ",$s_emails[++$i]"; last if ($i == $#s_emails); }
       } #*-- end of if

      $s_email =~ s/^\s+//; $s_email =~ s/\s+$//;
      foreach my $e_regex (@e_regexes)
       {
        #*-- set the e-mail and name, if possible
        my ($email, $name);
        if ($s_email =~ /$e_regex/)
         { 
           #*-- save the from and to in the database
           ($email, $name) = ($1 || $2) ? ($2, $1): ($4, $3);
           ($email, $name) = ($name, $email) if ($email !~ /$e_spec/);
           $email = $dbh->quote($email); $name = $dbh->quote($name);
           $command  = "select nei_count from em_network where";
           $command .= " nec_from = $from_email and nec_to = $email";
           ($sth, $db_msg) = $dbh->execute_stmt($command);
           &quit("Command: $command failed --> $db_msg") if ($db_msg);
           my $count = ($dbh->fetch_row($sth))[0];
           $count = ($count) ? $count + 1: 1;
           $command = <<"EOF";
            replace into em_network
            (nec_from, nec_from_name, nec_to, nec_to_name, nei_count)
            values ( $from_email,$from_name, $email, $name, $count)
EOF
           (undef, $db_msg) = $dbh->execute_stmt($command);
          last;
         } #*-- end of if

       } #*-- end of foreach e_regex
      $i++;
     } #*-- end of while
   } #*-- end of for tag

 } #*-- end of store_email

 #*---------------------------------------------------------------
 #*- Delete the current e-mail      
 #*---------------------------------------------------------------
 sub del_email
 {
  #*-- delete the id from the index
  my $descr = '';
  for (qw/from to cc subject e_text/) { $descr .= " $in{$_}"; }
  $stat_msg .= &rem_index($in{emi_id}, "$descr", 'em', $dbh, 'email');

  #*-- delete the id from the email table
  $command  = "delete from em_email where emi_id = $in{emi_id}";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);

 }

 #*---------------------------------------------------------------
 #*- get the e-mail address for the identity
 #*---------------------------------------------------------------
 sub get_email
 {
  (my $identity) = @_;
  $command = "select abc_email from em_abook_home ";
  $command .= " where abc_identity = " . $dbh->quote($identity);
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  (my $email) = $dbh->fetch_row($sth);
  return ("$email");
 }

 #*---------------------------------------------------------------
 #*- get the name for the identity   
 #*---------------------------------------------------------------
 sub get_name
 {
  (my $identity) = @_;
  $command = "select abc_name from em_abook_home ";
  $command .= " where abc_identity = " . $dbh->quote($identity);
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  return ( ($dbh->fetch_row($sth))[0]);
 }

 #*-----------------------------------------------------------------------
 #*- Replace the comma separator in mailing list with a sep. character
 #*-----------------------------------------------------------------------
 sub fix_comma
  {
   my ($ref) = @_;

   return unless ($$ref);
   my $mail_list = ''; my $d_quotes = my $s_quotes = 0;
   foreach (split//, $$ref)
    {
     $d_quotes++ if /"/; $s_quotes++ if /'/;
     if ( ($d_quotes % 2) || ($s_quotes % 2) )
      { $mail_list .= $_; }
     elsif ($_ !~ /,/)
      { $mail_list .= $_; }
     else
      { $mail_list .= $ISEP; }
    }
   $$ref = $mail_list;
  }

 #*---------------------------------------------------------------
 #*- Exit with a message            
 #*---------------------------------------------------------------
 sub quit
 {
  $dbh->disconnect_db($sth);
  print ${my $ref_val = &email_head("Compose")};
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
