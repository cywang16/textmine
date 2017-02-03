#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
 #*----------------------------------------------------------------
 #*- tx_entities.pl
 #*-  
 #*-   Summary: Extract entities tags 
 #*----------------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Utils qw(parse_parms mod_session url_encode log10);
 use TextMine::Constants qw($CGI_DIR $DB_NAME $TMP_DIR $ICON_DIR);
 use TextMine::Entity qw(entity_ex);
 use TextMine::Tokens qw(assemble_tokens);

 #*-- set the constants
 use vars (
  '$dbh',		#*-- database handle
  '$sth',		#*-- statement handle
  '$db_msg',		#*-- database error message
  '$command',		#*-- SQL command field
  '$ref_val',		#*-- reference variable
  '$FORM',		#*-- name of form
  '@tags',		#*-- list of tags for words in text box
  '@words',		#*-- list of words in text box
  '%in',		#*-- hash for form fields
  '$e_session',		#*-- URL encoded session field
  '$body_html',		#*-- HTML for body of page
  '$tbox',		#*-- text box variable for page
  '$stat_msg',		#*-- status message for page
  '$buttons'		#*-- buttons to show 
  );

 #*-- retrieve and set variables
 &set_vars();

 #*-- handle the options
 &handle_reset()  if ($in{opshun} eq 'Reset');
 &handle_new()    if ($in{opshun} eq 'New');
 &handle_ent()    if ($in{opshun} eq 'Extract Entities');
 &handle_update() if ($in{opshun} eq 'Update Rules');

 #*-- dump the header, body and tail html 
 &head_html(); &body_html(); &tail_html(); 

 exit(0);

 #*-----------------------------------------------------
 #*- Set some global vars            
 #*-----------------------------------------------------
 sub set_vars
 {
  #*-- retrieve the passed parameters
  $0 =~ s%.*[/\\]%%; $FORM = "$CGI_DIR" . "$0";
  %in    = %{$ref_val = &parse_parms};

  #*-- establish a DB connection
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $in{userid}, 'Password' => $in{password},
       'Dbname' => $DB_NAME);
  &quit("Could not establish DB connection: $db_msg") if ($db_msg);

  #*-- set the forgetful parms
  $in{opshun} = 'New' unless (defined($in{opshun}));
  $in{opshun} = 'New' if ($in{opshun} eq 'Return');
  $stat_msg = $tbox = $buttons = '';
  &mod_session($dbh, $in{session}, 'del', 'opshun' );
  $e_session = &url_encode($in{session});
 }

 #*---------------------------------------------------------------
 #*- Fill in fields for startup    
 #*---------------------------------------------------------------
 sub handle_new
 {
  $stat_msg = 'Paste text and select an option';
  $tbox = (defined($in{tbox})) ? $in{tbox}: '';
  $tbox = '<tr> <td colspan=2> <textarea name=tbox cols=70 rows=20>' .
          "$tbox" . '</textarea> </td></tr>'; 
  $buttons = "<td colspan=2 align=center><input type=submit name=opshun "
           . "value='Extract Entities'> &nbsp; &nbsp; <input type=submit "
           . " name=opshun value='Reset'></td>";
 }

 #*---------------------------------------------------------------
 #*- Reset the fields              
 #*---------------------------------------------------------------
 sub handle_reset
 {
  $stat_msg = 'Paste text and select an option';
  $tbox = '<tr> <td colspan=2> <textarea name=tbox cols=70 rows=20>' .
          "" . '</textarea> </td></tr>'; 
  $buttons = "<td colspan=2 align=center><input type=submit name=opshun "
           . "value='Extract Entities'> &nbsp; &nbsp; <input type=submit "
           . " name=opshun value='Reset'></td>";
 }

 #*---------------------------------------------------------------
 #*- Extract the Entities
 #*---------------------------------------------------------------
 sub handle_ent
 {
  my ($rw, undef, $rt) = &entity_ex(\$in{tbox}, $dbh);
  @words = @$rw; @tags = @$rt;
 
  #*-- save the tags and size in the session data
  &mod_session($dbh, $in{session}, 'mod', 
               map { 't_' . $_, $tags[$_] } (0..$#tags) );
  &mod_session($dbh, $in{session}, 'mod', 'num_tags', $#tags+1);
  &build_ent_table();
 }

 #*---------------------------------------------------------------
 #*- Update the Entity tables          
 #*---------------------------------------------------------------
 sub handle_update
 {

  #*-- cross reference of entity tables and entity types
  my %e_tables = ( 'a' => 'co_abbrev',
                   'c' => 'co_entity',
                   'd' => 'co_entity',
                   'h' => 'co_entity',
                   'l' => 'co_place',
                   'o' => 'co_org',
                   'p' => 'co_person',
                   't' => 'co_entity' );
  
  #*-- entity types table
  my %e_types  = ( 'a' => 'abbreviation',
                   'c' => 'currency',
                   'd' => 'dimension',
                   'h' => 'tech',
                   'l' => 'place',
                   'o' => 'org',
                   'p' => 'person',
                   't' => 'time' );

  #*-- build the @words and @tags arrays
  (my $rt, undef) = &assemble_tokens(\$in{tbox}, $dbh); @words = @$rt;
  @tags = map {$in{"w_$_"}} (0..($in{num_tags}-1));

  #*-- save the tags in the session data as t_1, t_2, ...
  &mod_session($dbh, $in{session}, 'mod',
               map { 't_' . $_, $in{"w_$_"} } (0..($in{num_tags}-1)) );
  #*-- check if any of the tags were changed
  for my $i (0..($in{num_tags}-1))
   {
    #*-- skip miscellaneous tags
    next if ($tags[$i] eq 'm');
    #*-- skip unchanged tags
    next if ($in{"w_$i"} eq $in{"t_$i"});

    if (my $table = $e_tables{$in{"w_$i"}})
     {
      foreach (split/\s+/, $words[$i])
       { my $etype = ($in{"w_$i"} =~ /[lo]/) ? 
            'part_' . $e_types{$in{"w_$i"}}: $e_types{$in{"w_$i"}};
         my $word = $dbh->quote(lc($_));
         $command = "replace into $table values ($word, '$etype', '')"; 
         $dbh->execute_stmt($command);
         &quit("$command failed: $db_msg") if ($db_msg);
       }
      if ( (my $word = $dbh->quote(lc($words[$i]))) =~ s/\s+/_/g )
       {
        $command = <<"EOF";
       replace into $table values ($word, '$e_types{$in{"w_$i"}}','') 
EOF
        $dbh->execute_stmt($command);
        &quit("$command failed: $db_msg") if ($db_msg);
       }
     } #*-- end of if

   } #*-- end of for
  $stat_msg .= "<font color=darkred size=+1> Updated the rule " .
               "table </font>";
  &build_ent_table();
 }

 #*---------------------------------------------------------------
 #*- build the entity table html
 #*---------------------------------------------------------------
 sub build_ent_table
 {

  #*-- tags and associated description
  my %tagd = qw/a abb c cur d dim h tec l pla m mis n num o org p per
                r pro t tim x x/;
  $tbox = <<"EOF";
  <tr><td colspan=2>
   <table border=0 cellspacing=2 cellpadding=0>
   <tr>
       <td> <font color=darkred> Legend </font> </td>
EOF
  foreach (sort keys %tagd)
   { $tbox .= "<td> <font color=darkred> $_ - $tagd{$_} </font> </td>"; }
  
  $tbox .= <<"EOF";
   </tr>
   </table> 
  </td></tr>

  <tr><td colspan=2>
   <table border=0 cellspacing=2 cellpadding=0>
    <tr> <td> <font size=+1 color=darkred> Token </font> </td>
         <td align=center><font size=+1 color=darkred> Entity Type 
         </font></td></tr>
EOF
  my @tag_l = sort keys %tagd;
  foreach my $i (0..$#words)
   {
    next unless ($tags[$i]);
    $tbox .= "<tr> <td> <font color=darkblue> " .
             "$words[$i] </font> </td>";
    $tbox .= "<td> <table cellspacing=0 cellpadding=0 border=0> <tr>";
    my $checked = my $color = '';
    for my $j (0..$#tag_l)
     {
      if ($tags[$i] =~ /^$tagd{$tag_l[$j]}/)
       { $checked = 'CHECKED'; $color = 'color=red'; }
      else
       { $checked = '';        $color = 'color=darkblue'; }
      $tbox .= "<td> <font $color> $tag_l[$j] </font> " .
               " <input type=radio name=w_$i " .
               " value=$tag_l[$j] $checked> &nbsp; &nbsp; </td> "; }
    $tbox .= "</tr> </table> </td> </tr>\n";
    
   } #*-- end of for i

  #*-- add the buttons
  $buttons = "<td colspan=2 align=center><input type=submit name=opshun "
           . "value='Update Rules'> &nbsp; &nbsp; <input type=submit "
           . " name=opshun value='Return'></td>";

 }

 #*---------------------------------------------------------------
 #*- dump some header html
 #*---------------------------------------------------------------
 sub head_html
 {
  my $te_image   = "$ICON_DIR" . "ent.jpg";
  my $anchor = "$CGI_DIR/co_login.pl?session=$e_session";

  print "Content-type: text/html\n\n";
  print << "EOF";
   <html>
    <head> <title> Extract Entities Page </title> </head>

    <body bgcolor=white>

     <form method=POST action="$FORM">

     <center>
      <table> <tr> <td> <a href=$anchor>
              <img src="$te_image" border=0> </a> </td> </tr> </table>
EOF
 }

 #*---------------------------------------------------------------
 #*- Show the body of the html page
 #*---------------------------------------------------------------
 sub body_html
 {
  print <<"EOF";

    <table cellspacing=2 cellpadding=0 border=0>
    <tr> <td> <br> </td> </tr>
    <tr> <td colspan=2 align=center> <font color=darkblue size=+1> 
          $stat_msg </font> 
         </td> </tr>

    $tbox  
    <tr> <td colspan=2> &nbsp; </td> </tr>

    <tr align=center> $buttons </tr>

    </table>
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
 #*- Exit with a message
 #*---------------------------------------------------------------
 sub quit
 { &head_html(); &msg_html($_[0] . "<br>$stat_msg"); &tail_html(); exit(0); }

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
