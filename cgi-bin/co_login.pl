#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
 #*------------------------------------------------------------------------
 #*- co_login.pl
 #*-  
 #*- Summary: If no parameters have been entered, show the login screen
 #*-          If userid and password is present, then check       
 #*-          If a session is passed, use it and then check       
 #*-	      Otherwise, show the login screen
 #*----------------------------------------------------------------

 use strict; use warnings;
 use Digest::MD5 qw(md5_base64);
 use TextMine::DbCall;
 use TextMine::Utils     qw(parse_parms encode url_encode);
 use TextMine::Constants qw($CGI_DIR $ICON_DIR $DB_NAME $EQUAL $SDELIM);

 #*-- global variables
 use vars (
        '$FORM',	#*-- name of the form
        '$body_html',	#*-- var for the body of the page
        '$stat_msg',	#*-- a status message for the page
        '%in',		#*-- a hash for the fields on the page
        '$dbh',		#*-- database handle
        '$sth',		#*-- DB statement handle
        '$secret'	#*-- text chunk for creating MD5 session ID
          );

 #*-- set the initial variables
 &set_vars();

 #*-- verify the password if entered
 &check_password() if ($in{userid});
 &build_body()     if ($in{session});

 #*-- dump the html 
 &head_html(); &msg_html($stat_msg) if ($stat_msg); 
 &body_html(); &tail_html(); 

 exit(0);

 #*---------------------------------------------------------------
 #*- Set some default values 
 #*---------------------------------------------------------------
 sub set_vars
 {
  #*-- set the constants
  $0 =~ s%.*[/\\]%%; $FORM = "$CGI_DIR" . "$0";

  #*-- retrieve the passed parameters
  %in    = %{my $ref_val = &parse_parms("$0")};

  #*-- set %in parms
  foreach (qw/userid password session/) { $in{$_} = '' unless ($in{$_}); } 

  $secret = 'Change this secret to your secret';

 };

 #*---------------------------------------------------------------
 #*- Check if the password is valid
 #*---------------------------------------------------------------
 sub check_password
 {
  my ($command, $db_msg);

 #*-- establish a connection to the mysql database
 ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
   'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => 'mysql');

 #*-- check if the userid and password are valid in the mysql database
 $command  = "select count(*) from user where user = '$in{userid}' ";
 $command .= "and password = PASSWORD('$in{password}')";
 ($sth, $db_msg) = $dbh->execute_stmt($command);
 &quit("Command: $command failed --> $db_msg") if ($db_msg);

 #*-- show the table of contents for a good password
 #*-- and generate a session id
 if (($dbh->fetch_row($sth))[0])
  {

   #*-- clean up expired sessions for the userid
   $dbh->disconnect_db($sth);
   ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '', 
        'Userid' => $in{userid}, 'Password' => $in{password},
        'Dbname' => $DB_NAME);

   #*-- sessions expire after a day
   my $ltime = time(); my $expiry = $ltime + 86400;
   $command  = "delete from co_session where sec_userid = '$in{userid}' " .
               " and sei_expiry < $ltime";
   (undef, $db_msg) = $dbh->execute_stmt($command);
   &quit("Command: $command failed --> $db_msg") if ($db_msg);

   #*-- generate a new session for the userid using the secret, time + userid
   $in{session}  = md5_base64($secret .
                   md5_base64($secret . "$ltime" . $in{userid}) );

   #*-- encode the session data and save in the table
   my $e_session = $dbh->quote($in{session});
   my $sec_data  = $dbh->quote(&encode
      ("userid"   . $EQUAL . $in{userid}   . $SDELIM     . 
       "password" . $EQUAL . $in{password} . $SDELIM));
   $command  = "insert into co_session set sec_session = $e_session, ";
   $command .= "sec_userid = '$in{userid}', sei_expiry = $expiry, ";
   $command .= "sec_data = $sec_data "; 
   (undef, $db_msg) = $dbh->execute_stmt($command);
   &quit("Command: $command failed --> $db_msg") if ($db_msg);
  }
 else
  { $stat_msg = "The userid and password do not match in the table"; }

 $dbh->disconnect_db($sth);

 }

 #*---------------------------------------------------------------
 #*- Build the body html     
 #*---------------------------------------------------------------
 sub build_body
 {
  my ($command, $db_msg);

  #*-- check if the session is valid
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
   'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => $DB_NAME);
  my $e_session = $dbh->quote($in{session});
  $command  = "select count(*) from co_session where ";
  $command .= "sec_session = $e_session";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  (my $count) = $dbh->fetch_row($sth);
  $dbh->disconnect_db($sth);
  return() unless($count);

  #*-- if session id is valid, then generate a table of contents
  $e_session = &url_encode($in{session});
  my $me_index    = $CGI_DIR . "me_index.pl?session=$e_session";
  my $me_search   = $CGI_DIR . "me_search.pl?session=$e_session";
  my $sp_search   = $CGI_DIR . "sp_search.pl?session=$e_session&opshun=View";
  my $db_monitor  = $CGI_DIR . "db_monitor.pl?session=$e_session";
  my $db_save     = $CGI_DIR . "db_save.pl?session=$e_session";
  my $em_search   = $CGI_DIR . "em_search.pl?session=$e_session&opshun=View";
  my $ne_browse   = $CGI_DIR . "ne_browse.pl?session=$e_session";
  my $qu_browse   = $CGI_DIR . "qu_browse.pl?session=$e_session";
  my $tx_stats    = $CGI_DIR . "tx_stats.pl?session=$e_session";
  my $tx_entities = $CGI_DIR . "tx_entities.pl?session=$e_session";
  my $tx_pos      = $CGI_DIR . "tx_pos.pl?session=$e_session";
  my $wn_dict     = $CGI_DIR . "wn_dict.pl?session=$e_session";
  $body_html = <<"EOF";

    <table cellspacing=8 cellpadding=0 border=0>

     <tr>
      <td> <a href=$tx_stats> <img src="$ICON_DIR/tex.jpg" border=0> 
           </a> </td>
      <td width=20> &nbsp; </td>
      <td> <a href=$tx_entities> <img src="$ICON_DIR/ent.jpg" border=0> 
           </a> </td>
      <td width=20> &nbsp; </td>
      <td> <a href=$tx_pos>  <img src="$ICON_DIR/pos.jpg" border=0> 
           </a> </td>
     </tr>

     <tr>
      <td> <a href=$me_search> <img src="$ICON_DIR/se.jpg" border=0>   
           </a> </td>
      <td width=20> &nbsp; </td>
      <td> <a href=$me_index> <img src="$ICON_DIR/index.jpg" border=0> 
           </a> </td>
      <td width=20> &nbsp; </td>
      <td> <a href=$ne_browse> <img src="$ICON_DIR/news.jpg" border=0> 
           </a> </td>
     </tr>

     <tr>
      <td> <a href=$qu_browse> <img src="$ICON_DIR/query.jpg" border=0> 
           </a> </td>
      <td width=20> &nbsp; </td>
      <td> <a href=$sp_search> <img src="$ICON_DIR/searchw.jpg" border=0> 
           </a> </td>
      <td width=20> &nbsp; </td>
      <td> <a href=$em_search> <img src="$ICON_DIR/emm.jpg" border=0> 
           </a> </td>
     </tr>

     <tr>
      <td> <a href=$db_monitor> <img src="$ICON_DIR/dbm.jpg" border=0> 
           </a> </td>
      <td width=20> &nbsp; </td>
      <td> <a href=$db_save> <img src="$ICON_DIR/dbb.jpg" border=0> 
           </a> </td>
      <td width=20> &nbsp; </td>
      <td> <a href=$wn_dict> <img src="$ICON_DIR/wnet.jpg" border=0> 
           </a> </td>
     </tr>

    </table>

EOF

 }


 #*---------------------------------------------------------------
 #*- display the header html 
 #*---------------------------------------------------------------
 sub head_html
 {
  my $logo_image    = "$ICON_DIR" . "tm_logo.jpg";
  print "Content-type: text/html\n\n";
  print << "EOF";
   <html>
    <head>
     <title> Login Page for Text Mining </title>
    </head>
  
    <body bgcolor=white>

     <form method=POST action="$FORM" name=dbform>

     <center>
      <table> <tr> <td> <img src="$logo_image"> </td> </tr> </table>

EOF

 }

 #*---------------------------------------------------------------
 #*- display the body html if any was generated, otherwise
 #*- show the login screen 
 #*---------------------------------------------------------------
 sub body_html
 {
  if ($body_html) { print "$body_html\n"; }
  else
   {
    print << "EOF";
    <table border=0 cellspacing=10 cellpadding=10>
     <tr> 
       <td> <font color=darkred size=+1> Userid: </font> </td>
       <td> <input type=text name=userid size=26 value='$in{userid}'></td>
     </tr>
     <tr> 
       <td> <font color=darkred size=+1> Password: </font> </td>
       <td> <input type=password name=password size=26 
            value='$in{password}'></td>
     </tr>
     <tr> 
       <td> &nbsp; </td>
       <td> <input type=submit name=submit size=20 value="Submit"></td>
     </tr>
    </table>
EOF
   }
 }

 #*---------------------------------------------------------------
 #*- Exit with a message
 #*---------------------------------------------------------------
 sub quit
 {
  &head_html(); &msg_html($_[0] . "<br>$stat_msg"); 
  &body_html(); &tail_html();
  exit(0);
 }

 #*---------------------------------------------------------------
 #*- Dump an error message           
 #*---------------------------------------------------------------
 sub msg_html
 { print << "EOF";
    <table> <tr> <td bgcolor=lightyellow>
                 <font color=darkred size=4> $_[0] </font> </td>
    </tr> </table>
EOF
 }
 

 #*---------------------------------------------------------------
 #*- Dump the end of the html page 
 #*---------------------------------------------------------------
 sub tail_html
 {
  print << "EOF";
    </center>
   </form>
  </body>
  </html>
EOF
 }
