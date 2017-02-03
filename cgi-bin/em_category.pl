#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
#*----------------------------------------------------------------
#*- em_category.pl
#*-  
#*-   Summary: View and create categories for emails    
#*----------------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Constants;
 use TextMine::Utils;
 use TextMine::MailUtil qw/email_head compute_centroid get_children
                           vec_to_string string_to_vec string_to_array/;

 #*-- global variables 
 use vars (
    '$dbh',		#*-- database handle
    '$sth',		#*-- statement handle
    '$stat_msg',	#*-- status message for the page
    '$db_msg',		#*-- database status message
    '$command',		#*-- SQL Command
    '$ref_val',		#*-- reference var
    '%esq',		#*-- escaped form fields
    '$FORM',		#*-- Name of form
    '%in',		#*-- hash for saving form fields
    '@PARMS',		#*-- list of form names
    '$e_session',	#*-- URL encoded session id
    '$emi_misc_catid',	#*-- category for misc. category
    '$num_cols',	#*-- number of levels for the category
    '@red',		#*-- red value for color table
    '@blue',		#*-- blue value for color table
    '@green'		#*-- green value for color table
    );

 #*-- retrieve and set variables
 &set_vars();

 #*-- handle the e_opshuns 
 &add_category()  if ($in{e_opshun} eq 'Save');
 &upd_category()  if ($in{e_opshun} eq 'Update');
 &res_category()  if ($in{e_opshun} eq 'Reset');
 &del_category()  if ($in{e_opshun} eq 'Delete');
 &updk_category() if ($in{e_opshun} eq 'Update Keyword Weight');
 &ema_category()  if ($in{e_opshun} eq 'E-Mails');
 &trn_category()  if ( ($in{e_opshun} eq 'Stop Training') ||
                       ($in{e_opshun} eq 'Continue Training') );

 #*-- dump the header, status, body and tail html 
 print ${$ref_val = &email_head("Category", $FORM, $in{session})};
 my $body_html = 
    ${$ref_val = ($in{opshun} eq 'View') ? &view_html(): &entry_html()};
 &msg_html($stat_msg) if ($stat_msg); 
 print ("$body_html\n");
 &tail_html(); 

 exit(0);

 #*-----------------------------------------------------
 #*- Set some global vars            
 #*-----------------------------------------------------
 sub set_vars
 {
  #*-- Set the form name and fetch the passed parameters
  $0 =~ s%.*[/\\]%%; $FORM = "$CGI_DIR" . "$0";
  %in    = %{$ref_val = &parse_parms};
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $in{userid}, 'Password' => $in{password},
       'Dbname' => $DB_NAME);

  #*-- check and make sure that there is at least one category
  ($sth,$db_msg) = $dbh->execute_stmt( "select count(*) from em_category");
  &quit("$command failed: $db_msg") if ($db_msg);
  (my $count) = $dbh->fetch_row($sth);

  #*-- there should always be at least one category
  unless ($count)
   { $command = "insert into em_category values ( 0, 0, 0, 0, 
                        'Miscellaneous', 'Miscellaneous Category', '')";
     (undef,$db_msg) = $dbh->execute_stmt("$command");
     &quit("$command failed: $db_msg") if ($db_msg); }

  #*-- initialize the category values
  if ($in{emi_catid})
   { $command = "select emc_catname, emc_descr, emi_parent from " .
                "em_category where emi_catid = $in{emi_catid}";
     ($sth, $db_msg) = $dbh->execute_stmt("$command");
     &quit("$command failed: $db_msg") if ($db_msg);
     ($in{emc_catname}, $in{emc_descr}, $in{emi_parent}) = 
         $dbh->fetch_row($sth); 

     #*-- get the parent's category name
     $command = "select emc_catname from em_category where " .
                " emi_catid = $in{emi_parent}";
     ($sth, $db_msg) = $dbh->execute_stmt("$command");
     &quit("$command failed: $db_msg") if ($db_msg);
     ($in{emc_parent}) = $dbh->fetch_row($sth); 
   } #*-- end of if

  unless ($in{opshun})
   { $in{opshun} = 'New'  if ($count == 1); 
     $in{opshun} = 'View' if ($count > 1); }

  @PARMS = qw/emc_descr emc_catname weight term e_opshun opshun/;
  foreach (@PARMS) { $in{$_} = '' unless ($in{$_}); }

  #*-- get the category id for the miscellaneous category
  $command = "select emi_catid from em_category ".
             "where emc_catname = 'Miscellaneous' ";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  ($emi_misc_catid) = $dbh->fetch_row($sth);

  #*-- build the color table for the keywords
  for my $i (0..255)
   { $red[$i] = 0; $green[$i] = $i; $blue[$i] = 255 - $i; }
  for my $i (0..255)
   { $red[$i+256] = $i; $green[$i+256] = 255 - $i; $blue[$i+256] = 0; }

  #*-- set the forgetful parms
  &mod_session($dbh, $in{session}, 'del', 
                     'opshun', 'e_opshun', 'emi_catid');
  $e_session = &url_encode($in{session}); $stat_msg = '';
 }

 #*---------------------------------------------------------------
 #*- add the category, if possible and set the status message
 #*---------------------------------------------------------------
 sub add_category
 {

  #*-- check for any errors in entering data
  return() if ( (my $fh = &edit_fields()) eq 'Error');

  #*-- category name must be unique
  if ( ($dbh->fetch_row($sth))[0])
   { $stat_msg .= "<font color=darkblue>" . $in{emc_catname} . 
                  "</font> exists in the table, Press Update<br>"; 
     $in{opshun} = 'Edit'; return(); }

  #*-- disallow children of the miscellaneous category
  if ($in{emc_parent} =~ /miscellaneous/i)
   { $stat_msg .= "Cannot make a child of the miscellanous category<br>";
     return(); }

  #*-- get the parent level and parent for the selected category
  (my $emi_level, my $emi_parent) = &get_catinfo(); $emi_level++;

  #*-- build the insert statement
  my $q_parent  = $dbh->quote($emi_parent);
  my $q_catname = $dbh->quote($in{emc_catname});
  my $q_descr   = $dbh->quote($in{emc_descr});
  $command = <<"EOF";
    insert into em_category set emi_catid = 0, emi_parent = $q_parent,
      emi_level = $emi_level, emi_text_size = 0, emc_end_train = ' ',
      emc_catname = $q_catname, emc_descr = $q_descr, emc_centroid = ''
EOF
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
                               
  $stat_msg .= "-- The <font color=darkblue> " . $in{emc_catname} . 
               "</font> category was added,<br>";

 }

 #*---------------------------------------------------------------
 #*- Update an existing category 
 #*---------------------------------------------------------------
 sub upd_category
 {
  $in{opshun} = 'Edit';
  #*-- check for any errors in entering data
  return() if ( (my $fh = &edit_fields()) eq 'Error');

  #*-- a category by the same name must exist
  unless ( ($dbh->fetch_row($sth))[0])
   { $stat_msg .= "<font color=darkblue>" . $in{emc_catname} . 
                  "</font> does not exist in the table, Press Save,<br>"; 
     return(); }

  #*-- disallow children of the miscellaneous category
  if ($in{emc_parent} =~ /miscellaneous/i)
   { $stat_msg .= "Cannot make a child of the miscellanous category<br>";
     return(); }

  #*-- disallow changes to the miscellaneous category
  if ($in{emc_catname} =~ /miscellaneous/i)
   { $stat_msg .= "Cannot change the miscellanous category<br>";
     return(); }

  #*-- get the parent level and parent for the selected category
  (my $emi_level, my $emi_parent) = &get_catinfo(); $emi_level++;

  #*-- disallow cyclic parent child relationships
  if (&get_catid() == $emi_parent)
   { $stat_msg .= "Category cannot be a parent of itself<br>";
     return(); }

  #*-- build the replace statement
  $command = "update em_category set emi_parent = $emi_parent, " . 
             "emi_level = $emi_level, " . 
             "emc_descr = "   . $dbh->quote($in{emc_descr}) .
             " where emc_catname = " . $dbh->quote($in{emc_catname});
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  $stat_msg .= "<font color=darkblue>" . $in{emc_catname} . 
               "</font> was changed successfully,<br>";
 }

 #*---------------------------------------------------------------
 #*- Reset an existing entry 
 #*---------------------------------------------------------------
 sub res_category
 {
  #*-- check for any errors in entering data
  $in{opshun} = 'Edit';
  return() if ( (my $fh = &edit_fields()) eq 'Error');

  unless ( ($dbh->fetch_row($sth))[0])
   { $stat_msg .= "<font color=darkblue>" . $in{emc_catname} . 
                  "</font> does not exist in the table, Press Save,<br>"; 
     return(); }
 
  #*-- rebuild a centroid for the category, get the text for all
  #*-- emails in the category and build the normalized vector
  
  my $emi_catid = &get_catid();
  my $s_vector = &compute_centroid($emi_catid, $dbh);

  #*-- build the replace statement
  $command = "update em_category " .
             "set emc_centroid = " .  $dbh->quote($s_vector) .
             " where emi_catid = $emi_catid ";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  $stat_msg .= "<font color=darkblue>" . $in{emc_catname} . 
               "</font> was reset successfully,<br>";
 }

 #*---------------------------------------------------------------
 #*- Delete an existing category and its children
 #*---------------------------------------------------------------
 sub del_category
 {
  #*-- check for any errors in entering data
  return() if ( (my $fh = &edit_fields()) eq 'Error');

  #*-- a category with the same name must exist
  unless ( ($dbh->fetch_row($sth))[0])
   { $stat_msg .= "<font color=darkblue>" . $in{emc_catname} . 
                  "</font> does not exist in the table<br>"; 
     return(); }

  #*-- Cannot delete the miscellaneous category
  if  ($in{emc_catname} =~ /Miscellaneous/i)
   { $stat_msg .= "<font color=darkblue>" . $in{emc_catname} . 
                  "</font> category cannot be deleted<br>"; 
     $in{opshun} = 'Edit';
     return(); }

  #*-- get the list of all categories below this category
  my $emi_catid = &get_catid();
  my @catids = &get_children($emi_catid, $dbh);

  #*-- update all the emails for all categories to misc
  foreach my $catid (@catids)
   {
    $command = "update em_email set emi_catid = $emi_misc_catid " .
               " where emi_catid = $catid"; 
    (undef, $db_msg) = $dbh->execute_stmt($command);
    &quit("$command failed: $db_msg") if ($db_msg);
   }

  #*-- delete all categories and sub-categories 
  foreach my $catid (@catids)
   {
    $command = "delete from em_category where emi_catid = $catid"; 
    (undef, $db_msg) = $dbh->execute_stmt($command);
    &quit("$command failed: $db_msg") if ($db_msg);
   }

  $stat_msg .= "-- The <font color=darkblue>" . $in{emc_catname} . 
               "</font> search was deleted,<br>";
  $in{opshun} = 'View'; 
  foreach (@PARMS) { $in{$_} = ' ' if ($_ =~ /^emc/); }

 }

 #*---------------------------------------------------------------
 #*- Change the training status of a category (stop or continue)
 #*---------------------------------------------------------------
 sub trn_category
 {
  $in{opshun} = 'Edit';
  my $emc_end_train = ($in{e_opshun} eq 'Stop Training') ? 'Y': ' ';
  my $emi_catid = &get_catid();

  #*-- build the replace statement
  $command = "update em_category " .
    "set emc_end_train = '$emc_end_train' where emi_catid = $emi_catid";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  $stat_msg .= "<font color=darkblue>" . $in{emc_catname} . 
               "</font> was changed successfully,<br>";
 }

 #*---------------------------------------------------------------
 #*- Get the category's parent information
 #*---------------------------------------------------------------
 sub get_catinfo
 {
  my ($emi_level, $emi_parent);
  if ($in{emc_parent} =~ /root/i)
   { $emi_level = -1; $emi_parent = 0; }
  else
   { $command = "select emi_level, emi_catid from em_category ".
                "where emc_catname = " . $dbh->quote($in{emc_parent});
     ($sth, $db_msg) = $dbh->execute_stmt($command);
     &quit("$command failed: $db_msg") if ($db_msg);
     ($emi_level, $emi_parent) = $dbh->fetch_row($sth); }
  return($emi_level, $emi_parent);
 }

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
 #*- Edit the fields  
 #*---------------------------------------------------------------
 sub edit_fields
 {
  #*--- check for mandatory entries
  unless ($in{emc_descr})  
    { $stat_msg .= "-- The Description field is mandatory,<br>"; }
  unless ($in{emc_catname})  
    { $stat_msg .= "-- The Category Name field is mandatory,<br>"; }
  return('Error') unless ( $in{emc_descr} && $in{emc_catname} );

  #*-- check for a duplicate
  &escape_q(); 
  $command  = "select count(*) from em_category where ";
  $command .= "emc_catname = $esq{emc_catname}";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  return('');
 }

 #*---------------------------------------------------------------
 #*- Update the key weights for the category
 #*---------------------------------------------------------------
 sub updk_category
 { 
  $in{opshun} = 'Edit';
  #*-- check for any errors in entering data
  return() if ( (my $fh = &edit_fields()) eq 'Error');

  unless ( ($dbh->fetch_row($sth))[0])
   { $stat_msg .= "<font color=darkblue>" . $in{emc_catname} . 
                  "</font> does not exist in the table<br>"; 
     return(); }

  #*-- get the selected keyword
  my $emi_catid = &get_catid();
  $command = "select emc_centroid from em_category where " .
             "emi_catid = $emi_catid";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  (my $emc_centroid) = $dbh->fetch_row($sth);

  if ( ($in{emc_catname} =~ /^Miscellaneous/i) || !$emc_centroid )
   { $stat_msg .= "<font color=darkblue> No keywords for this category" . 
                  "</font>"; return(); }

  #*-- set the new term weight and the sum of the new term weights
  my %terms = &string_to_vec($emc_centroid);
  $terms{$in{term}} = $in{weight}; my $sum_wts = 1.0 - $in{weight};
 
  #*-- get the sum of the old term weights 
  my $sum_old_wt = 0;
  foreach my $term (keys %terms)
   { $sum_old_wt += $terms{$term} unless ($term eq $in{term}); }

  #*-- set the new term weights
  foreach my $term (keys %terms)
   { $terms{$term} = $terms{$term} * $sum_wts / $sum_old_wt 
                     unless ($term eq $in{term}); }
  
  #*-- build the new centroid
  my $centroid = $dbh->quote(&vec_to_string(%terms));
  $command = "update em_category set emc_centroid = $centroid " .
             "where emi_catid = $emi_catid";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  
 }

 #*----------------------------------------------------------------
 #*- transfer to em_search.pl and pass the category id 
 #*----------------------------------------------------------------
 sub ema_category 
 { my $emi_catid = &get_catid();
   my $url = $CGI_DIR . 
     "em_search.pl?session=$e_session&description=&emi_catid=$emi_catid";
   print "Location: $url", "\n\n"; exit(0); }

 #*---------------------------------------------------------------
 #*- show a list of categories in a table
 #*---------------------------------------------------------------
 sub view_html
 {
  my $body_html;

  #*-- get the category ids for level 0
  my @l0_ids = (); my $emi_catid;
  $command = "select emi_catid from em_category where emi_level = 0 " .
             " order by emc_catname asc";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  while ( ($emi_catid) = $dbh->fetch_row($sth) )
   { push (@l0_ids, $emi_catid); }

  #*-- get the number of columns for the categories
  $command = "select max(emi_level) from em_category";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  ($num_cols) = ($dbh->fetch_row($sth))[0] + 1;

  $body_html = <<"EOF";
   <br>
   <table border=0 cellspacing=0 cellpadding=0 bgcolor=whitesmoke>
    <tr><td colspan=$num_cols>
          <font size=4 color=darkred> List of Categories </font> </td> </tr>
EOF
 
  foreach my $catid (@l0_ids)
   { $body_html .= (&get_child_html($catid))[0]; }

  $body_html .= <<"EOF";
   <tr><td bgcolor=white colspan=$num_cols align=center> <br>
       <input type=submit name=opshun value=New></td></tr>
   </table>
EOF

  return(\$body_html);
 }

 #*---------------------------------------------------------------
 #*- Build the html for the categories  
 #*---------------------------------------------------------------
 sub get_child_html
 {
  (my $catid) = @_;

  #*-- get the category name and level 
  my $command = "select emc_catname, emc_descr, emi_level from " .
                " em_category where emi_catid = $catid";
  (my $sth, my $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  (my $emc_catname, my $emc_descr, my $emi_level) = $dbh->fetch_row($sth);

  #*-- check if it is a parent
  my $folder_i = $ICON_DIR . "folder.jpg";
  my $blank_i  = $ICON_DIR . "blank.jpg";
  $command = "select count(*) from em_category where emi_parent = $catid";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  (my $pcount) = $dbh->fetch_row($sth);
  my $itag = ($pcount) ? "<img src=$folder_i border=0>" : '';

  #*-- count the number of e-mails in this category
  $command = "select count(*) from em_email where emi_catid = $catid";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  (my $e_count) = $dbh->fetch_row($sth);

  my $blank_cols = $emi_level; 
  my $non_blank_cols = $num_cols - $blank_cols; 
  my $s_url = $CGI_DIR . 
              "em_search.pl?session=$e_session&description=&emi_catid=$catid";
  my $c_url = $CGI_DIR . "em_category.pl?session=$e_session" . 
              "&emi_catid=$catid&opshun=Edit";
  my $e_cell = "<td align=left><img src=$blank_i width=40 height=0 border=0> " .
               "</td>";
  my $color_val = ($emi_level %2) ? "cornsilk": "beige";

  my $child_html = '';
  if ($pcount)
   { $command = "select emi_catid from em_category where emi_parent = $catid";
     ($sth, $db_msg) = $dbh->execute_stmt($command);
     &quit("$command failed: $db_msg") if ($db_msg);
     my @ids = ();
     while ( (my $c_catid) = $dbh->fetch_row($sth) ) { push (@ids, $c_catid); }
     foreach my $c_catid (@ids)
      { (my $c_html, my $c_count) = &get_child_html($c_catid); 
        $child_html .= $c_html; $e_count += $c_count; }
   }
  my $body_html = "<tr>";
  if ($blank_cols) 
   { foreach my $i (1..$blank_cols) { $body_html .= $e_cell; } }
  $body_html .= <<"EOF";
    <td colspan=$non_blank_cols align=left> 
    <table border=0 cellspacing=2 cellpadding=2>
    <tr>
     <td bgcolor=$color_val> <a href=$s_url> $itag 
         <font size=3> $emc_catname ($e_count) </font> </a> </td>
     <td> &nbsp; </td>
     <td bgcolor=$color_val> <a href=$c_url> $emc_descr </a> </td>
    </tr>
    </table>
    </td> </tr>
    $child_html
EOF
  return($body_html, $e_count);
  
 }

 #*---------------------------------------------------------------
 #*- Show the screen to view details of each entry   
 #*---------------------------------------------------------------
 sub entry_html
 {

  #*-- create the html for the keywords, get all the keys for the centroid
  #*-- build the color table
  my $emi_catid = ($in{emi_catid}) ? $in{emi_catid}: &get_catid(); 
  my $emc_centroid; my $emc_end_train = ' ';
  if ($emi_catid)
   { $command = "select emc_centroid, emc_end_train from em_category where" .
                " emi_catid = $emi_catid";
     ($sth, $db_msg) = $dbh->execute_stmt($command);
     &quit("$command failed: $db_msg") if ($db_msg);
     ($emc_centroid, $emc_end_train) = $dbh->fetch_row($sth); 
   }
  else { $emc_centroid = ''; }
  $emc_end_train = ($emc_end_train eq 'Y') ? 'Continue Training':
                                             'Stop Training';

  my $term_option = '';
  my @terms = ($emc_centroid) ? &string_to_array($emc_centroid): ();
  $#terms = 29 if (@terms > 30); #*-- truncate the terms array

  #*-- if there are keywords
  if (@terms)
   {
    my $tsize = 512;
    (my $max_wt) = $terms[0]       =~ /$ISEP(.*?)$/;
    (my $min_wt) = $terms[$#terms] =~ /$ISEP(.*?)$/;

    $term_option = '<table border=0 cellspacing=0 cellpadding = 0> <tr>';
    my $i = 0;
    foreach (@terms)
     { (my $term, my $wt) = $_ =~ /^(.*)$ISEP(.*)$/; 
       my $cval = uc(&color_hval($wt, $max_wt, $min_wt, $tsize));
       my $checked = ($term eq $in{term}) ? "CHECKED": "";
       $wt =~ s/(\...).*/$1/;
       $term_option .=<<"EOF";
         <td> <input type=radio name=term value='$term' $checked>
              <font color=#$cval> $term:$wt </font> </td>
         <td width=10> &nbsp; </td>
EOF
       $term_option .= "</tr><tr>" unless (++$i % 3);
      }
    $term_option .= "</tr></table>"; }
  else { $term_option = 'Empty'; }

  #*--- create the HTML for the parent
  my @parents = ('Root');
  $command = "select emc_catname from em_category order by 1 asc";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  while ( (my $emc_catname) = $dbh->fetch_row($sth) )
   { push (@parents, $emc_catname); }

  #*-- build the HTML for the selection
  my $parent_option = '';
  foreach (@parents)
   { $parent_option .= ($in{emc_parent} && ($_ eq $in{emc_parent}) ) ?
      "<option value='$_' selected> $_": "<option value='$_'> $_"; }

  #*-- build the HTML for the key weights
  my $weight_option = '';
  foreach (qw% 0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 % )
   { $weight_option .= ($in{weight} && ($_ eq $in{weight}) ) ?
      "<option value='$_' selected> $_": "<option value='$_'> $_"; }

  my $body_html .= <<"EOF";
   <br> <center>
   <table border=0 cellspacing=4 cellpadding=0>

   <tr>
    <td> <font color=darkblue> Name*: </font> </td>
    <td colspan=2> 
      <textarea name=emc_catname rows=1 cols=80>$in{emc_catname}</textarea>
    </td>
   </tr>

   <tr>
    <td> <font color=darkblue> Description*: </font> </td>
    <td colspan=2> 
     <textarea name=emc_descr rows=1 cols=80>$in{emc_descr}</textarea> </td>
   </tr>

   <tr>
    <td> <font color=darkblue> Parent*: </font> </td>
    <td colspan=2> 
         <strong> <select name=emc_parent size=1> $parent_option </select>
    </strong> </td>
   </tr>

   <tr>
    <td> <font color=darkblue> Keywords: </font> </td>
    <td colspan=2> $term_option </td>
   </tr>

   <tr>
    <td> <font color=darkblue> Weight: </font> </td>
    <td> <strong> <select name=weight size=1> $weight_option </select> </td>
    <td> <input type=submit name=e_opshun value='Update Keyword Weight'></td>
   </tr>
   

   <tr>
     <td colspan=3 align=center> <br>
      <input type=submit name=e_opshun value='Save'> &nbsp;
      <input type=submit name=e_opshun value='Update'> &nbsp;
      <input type=submit name=e_opshun value='Delete'> &nbsp;
      <input type=submit name=e_opshun value='Reset'> &nbsp;
      <input type=submit name=opshun value='View'> &nbsp;
      <input type=submit name=e_opshun value='$emc_end_train'> &nbsp;
      <input type=submit name=e_opshun value='E-Mails'> &nbsp;
     </td>
   </tr>

  </table>
  </center>

EOF
  $stat_msg .= 'Enter parameters for a new category' 
               if ($in{opshun} eq 'New');
  return(\$body_html);
 }

 #*-----------------------------------------------------------------
 #*- return a hexval for the colors based on the value and range
 #*-----------------------------------------------------------------
 sub color_hval
 {
  my ($value, $maxval, $minval, $tsize) = @_;
  my ($pos, $rval, $gval, $bval);
  
  if ($value < $minval)    { $pos = 0; }
  elsif ($value > $maxval) { $pos = $tsize - 1; }
  else
   { my $range = $maxval - $minval + 1.0E-10;
     my $scale = $tsize / $range;
     $pos = int ( ($value - $minval) * $scale); }
  $rval = &hexval($red[$pos]);   $rval = "0$rval" if (length($rval) == 1);
  $gval = &hexval($green[$pos]); $gval = "0$gval" if (length($gval) == 1);
  $bval = &hexval($blue[$pos]);  $bval = "0$bval" if (length($bval) == 1);
  return ($rval . $gval . $bval);
 }

 #*------------------------------------------------------
 #*-- escape strings with single quotes
 #*------------------------------------------------------
 sub escape_q
 {
  %esq = ();
  foreach (@PARMS)
   { if ($in{$_}) { $in{$_} =~ s/^\s+//; $in{$_} =~ s/\s+$//; }
     $esq{$_} = ($_ =~ /^emc_/) ? $dbh->quote($in{$_}): 
                ($in{$_}) ? $in{$_}: 0; }
 }

 #*---------------------------------------------------------------
 #*- Exit with a message            
 #*---------------------------------------------------------------
 sub quit
 { print ${$ref_val = &email_head("Category", $FORM, $in{session})};
   &msg_html($_[0] . "<br>$stat_msg"); &tail_html(); exit(0); }

 #*---------------------------------------------------------------
 #*- Dump an error message           
 #*---------------------------------------------------------------
 sub msg_html
 {
  my ($msg) = @_;
  $msg =~ s/,\s*<br>$/<br>/;
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
    <input type=hidden name=session value=$in{session}>
   </form>
   </center>
  </body>
  </html>
EOF
 }
