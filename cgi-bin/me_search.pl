#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
 #*----------------------------------------------------------------
 #*- me_search.pl
 #*-
 #*-   Summary: Accept the input parameters for the files and search
 #*-            the database. Display the matching files.
 #*----------------------------------------------------------------

 use strict; use warnings;
 use Time::Local;
 use File::Find;
 use TextMine::DbCall;
 use TextMine::Utils qw(parse_parms mod_session dateChooser f_date
     url_encode trim_field);
 use TextMine::Constants qw($CGI_DIR $ICON_DIR $DB_NAME $ISEP 
     @MFILE_TYPES @AUDIO_TYPES @IMAGE_TYPES @VIDEO_TYPES @DOC_TYPES );
 use TextMine::Index    qw(tab_word content_words text_match);

 #*-- global variables
 use vars (
  '%in',		#*-- hash for form fields
  '$FORM',		#*-- name of form
  '$command',		#*-- field for SQL command
  '$sth',		#*-- statement handle
  '$dbh',		#*-- database handle
  '$db_msg',		#*-- database error message
  '$ref_val',		#*-- reference variable
			#*-- REs for media types
  '$image_reg', '$audio_reg', '$doc_reg', '$video_reg',
  '%show',		#*-- hash for type of media selected
  '$stat_msg',		#*-- status message for page
  '@files',		#*-- list of files in the page
  '$num_pages',		#*-- total number of pages
  '$results_per_page',	#*-- number of results shown per page 
  );

 &set_vars();

 &date_handler();

 #*-- fetch the matching files, if possible
 &fetch_data() if ( defined($in{opshun}) && 
                    ($in{opshun} =~ /^(?:Next|Prev|First|Last)/i) );

 #*-- dump the html
 &head_html();
 &msg_html("Start Date is later than End Date")
           if ($in{start_date} > $in{end_date});
 &body_html();
 &tail_html();

 exit(0);

 #*---------------------------------------------------------------
 #*- Set the initial parameters 
 #*---------------------------------------------------------------
 sub set_vars
 {

  #*-- build the REs and form name and fetch the form fields
  $stat_msg = '';
  local $" = '|';
  $doc_reg   = qr/\.(?:@DOC_TYPES)$/i;
  $image_reg = qr/\.(?:@IMAGE_TYPES)$/i;
  $audio_reg = qr/\.(?:@AUDIO_TYPES)$/i;
  $video_reg = qr/\.(?:@VIDEO_TYPES)$/i;
  local $" = ' ';
  $0 =~ s%.*[/\\]%%; $FORM = "$CGI_DIR" . "$0";
  %in = %{$ref_val = &parse_parms($FORM)};

  #*-- establish a DB connection
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $in{userid}, 'Password' => $in{password},
       'Dbname' => $DB_NAME);
  &quit("Connect failure: $db_msg") if ($db_msg);

  $results_per_page = 10; 
  %show = ();
  for (qw/audio video image doc/) { $show{$_} = ($in{$_}) ? "CHECKED": ""; }
  $show{all}++ unless ( $show{audio} || $show{video} || $show{image} || 
                        $show{doc} );

  #*-- set the option
  $in{opshun} = 'First' if ($in{'opshun.x'});   

  #*-- clean up the session data
  my @dparms = qw/opshun date_opshun opshun.x s_date e_date/;
  push (@dparms, qw/doc image audio video fuzzy/) 
       unless($in{d_opshun} || $in{s_date} || $in{e_date});
  &mod_session($dbh, $in{session}, 'del', @dparms);

  #*-- set defaults for start and end dates 
  $in{start_date} = 946684800 unless($in{start_date}); 
  $in{end_date}   = time() + 86400 unless($in{end_date}); 
  foreach (qw/description audio video image doc fuzzy date_opshun cpage/) 
    { $in{$_} = '' unless ($in{$_}); }

 }

 #*---------------------------------------------------------------
 #*- Handle the selection of dates
 #*---------------------------------------------------------------
 sub date_handler
 {

  #*-- if choosing a date
  if ($in{date_opshun} eq 'selecting_date')
   {
    &mini_head_html();
    my $body_html = ${$ref_val = &dateChooser ($FORM, 
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
    &mod_session($dbh, $in{session}, 'del', 'd_opshun'); 
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
    my $body_html = ${$ref_val = &dateChooser ($FORM, 
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
    my $body_html = ${$ref_val = &dateChooser ($FORM, 
       $in{end_year}, $in{end_month}, $in{end_day}, 
       'Select a end date', $in{session})};
    print ("$body_html\n");
    &mini_tail_html();
    exit(0);
   }

 }

 #*----------------------------------------------------------------------
 #*- fetch the matching links based on the query and options selected
 #*-----------------------------------------------------------------------
 sub fetch_data
 {
  my ($lii_id, $lii_date, $lic_description, $lic_file, $i);

  #*-- get the ids of the files which contain the words in the 
  #*-- description and fall within the time range
  my @tables = qw/me_index/;
  my %files = ();

  #*-- cannot handle NOT here
  my @words = @{&content_words(\$in{description}, '', $dbh, undef, undef, 1)};
  if ( (@words) && ($in{description} !~ /\bNOT\b/i) )
   {
    foreach my $word (@words)
     { 
      my $table = 'me' . &tab_word($word);
      my $where_c;  #*-- build the where clause
      if ($in{fuzzy} || ($word =~ /[*]/) )
       {
        (my $e_word = $word) =~ s/([._%])/\\$1/g;
        $e_word =~ s/[*]/\%/g; $e_word = '%'."$e_word".'%' if ($in{fuzzy});
        $e_word = $dbh->quote($e_word);
        $where_c = "LIKE $e_word"; 
       }
      else
       { $where_c =  "= " . $dbh->quote($word); }

      $command = "select inc_ids from $table where inc_word $where_c";
      ($sth, $db_msg) = $dbh->execute_stmt($command);
      &quit("Command: $command failed --> $db_msg") if ($db_msg);
      while ( ($lii_id) = $dbh->fetch_row($sth) ) { $files{$lii_id}++; }
     } #*-- end of for each word

    #*--- split the concatenated ids in files into individual ids
    my @id_strings = keys %files; %files = ();
    foreach my $id_string (@id_strings)
     { 
      foreach my $id (split/,/, $id_string)  
       {
        #*-- extract the optional weight
        ($lii_id, my $null, my $wt) = $id =~ /(\d+)($ISEP(\d+))?/;
        $files{$lii_id}+= (defined($wt)) ? $wt: 1; 
       } #*-- end of inner for
     } #*-- end of outer for
   }
   #*-- for a blank description, retrieve every file
  else
   {
    $command = "select lii_id from me_list";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    while ( ($lii_id) = $dbh->fetch_row($sth) ) { $files{$lii_id}++; }
   } #*-- end of if @words

  #*-- check if the start and end dates are within the file's time
  my %filter_files = my %time_files = ();
  my $sort_by_wt = 1;
  foreach $lii_id (keys %files)
   {
    $command  = "select lii_date, lic_file, lic_description from ";
    $command .= "me_list where lii_id = $lii_id and $in{start_date} ";
    $command .= "< lii_date and lii_date < $in{end_date}";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    while ( ($lii_date, $lic_file, $lic_description) = 
             $dbh->fetch_row($sth) ) 
     {
      #*-- check if the description for the file matches the query
      #*-- $in{description} query matches the  file description
      next unless 
       (&text_match(\$lic_description,$in{description},$in{fuzzy}));
      my $valid_file = ''; 
      if ($show{image}) { $valid_file = 1 if ($lic_file =~ /$image_reg/); } 
      if ($show{audio}) { $valid_file = 1 if ($lic_file =~ /$audio_reg/); } 
      if ($show{video}) { $valid_file = 1 if ($lic_file =~ /$video_reg/); } 
      if ($show{doc})   { $valid_file = 1 if ($lic_file =~ /$doc_reg/); } 
      next unless ($valid_file || $show{all});
    
      #*-- use the weight or time to rank files
      $filter_files{$lii_id}++; 
      $time_files{$lii_id} = ($sort_by_wt) ? $files{$lii_id}: $lii_date; 
     }

   } #*-- end of for each keys %files

  #*-- sort the file list by time or weight
  my @sort_files = (); $i = 0;
  foreach $lii_id ( sort { $time_files{$b} <=> $time_files{$a} }
                    keys %time_files)
   { $sort_files[$i++] = $lii_id; }

  #*-- compute the current page number
  my $num_files = keys %filter_files;
  $num_pages = ($num_files >= $results_per_page) ?
               int($num_files / $results_per_page): 0;
  $num_pages++   if ( ($num_files % $results_per_page) != 0);

  #*-- set the current page number
  $in{cpage}++            if ($in{opshun} eq 'Next');
  $in{cpage}--            if ($in{opshun} eq 'Prev');
  $in{cpage} = 1          if ($in{opshun} eq 'First');
  $in{cpage} = $num_pages if ($in{opshun} eq 'Last');

  #*-- make sure that cpage is in range
  $in{cpage} = 1          unless($in{cpage});
  $in{cpage} = $num_pages if ($in{cpage} > $num_pages);
  $in{cpage} = 1          if ($in{cpage} < 1);

  #*-- save the current page number
  &mod_session($dbh, $in{session}, 'mod', 'cpage', $in{cpage});
         
  my $start_file = ($in{cpage} - 1) * $results_per_page;
  @files = ();
  for ($i = 0; $i < $results_per_page; $i++)
   { $files[$i] = $sort_files[$start_file + $i] 
                   if ($sort_files[$start_file + $i]); }

  unless (@files)
   { &head_html(); &msg_html("No matching files were found ");
     &tail_html(); exit(0); }

 }

 #*---------------------------------------------------------------
 #*- fetch the small files based on page number and display
 #*---------------------------------------------------------------
 sub head_html
 {
  my $se_image     = "$ICON_DIR" . "se.jpg";
  my $getit_image   = "$ICON_DIR" . "get_it.jpg";
  my $fuzzy = ($in{fuzzy}) ? "CHECKED": "";
  ($in{start_day}, $in{start_month}, $in{start_year}) = 
                   (gmtime($in{start_date}))[3..5]; 
  ($in{end_day}, $in{end_month}, $in{end_year}) = 
                   (gmtime($in{end_date}))[3..5]; 
                                     
  my $start_date = &f_date($in{start_date});
  my $end_date   = &f_date($in{end_date});
  my $e_session  = &url_encode($in{session});
  my $anchor = "$CGI_DIR/co_login.pl?session=$e_session";

  print "Content-type: text/html\n\n";
  print <<"EOF";
   <html>
    <head>
     <title> Search Page for Multimedia Retrieval Engine </title>
    </head>
  
    <body bgcolor=white>

     <form method=POST action="$FORM">

     <center>
      <table> <tr> <td> <a href=$anchor> 
                   <img src="$se_image" border=0> </a> </td> </tr> </table>
     </center>

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
             <td valign=bottom> <font size=+1 color=darkred> Type: </font> </td>
             <td valign=bottom> <font color=darkblue> Docs </font> 
                  <input type=checkbox name='doc' $show{doc}> </td>
             <td> &nbsp; </td>
             <td valign=bottom> <font color=darkblue> Image </font> 
                  <input type=checkbox name='image' $show{image}> </td>
             <td> &nbsp; </td>
             <td valign=bottom> <font color=darkblue> Audio </font> 
                  <input type=checkbox name='audio' $show{audio}> </td>
             <td> &nbsp; </td>
             <td valign=bottom> <font color=darkblue> Video </font> 
                  <input type=checkbox name='video' $show{video}> </td>
             <td width=5> &nbsp; </td>
             <td valign=bottom> <font color=darkred size=+1> Fuzzy: </font> </td>
             <td valign=bottom> <input type=checkbox name='fuzzy' $fuzzy> </td>
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
   &head_html(); &body_html(); 
   &msg_html("$_[0]" . "<br>$stat_msg"); &tail_html();
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
     <title> Search Page for Multimedia Retrieval Engine </title>
    </head>
  
    <body bgcolor=white>

     <form method=POST action="$FORM">
     <center>
EOF
 }


 #*---------------------------------------------------------------
 #*- show the files and in a table                          
 #*---------------------------------------------------------------
 sub body_html
 {
  my ($lic_description, $lic_file);

  if (@files)
   {
    print <<"EOF";

    <center>
    <table> <tr> 
     <td> <font color=darkred> Page $in{cpage} of $num_pages </font> </td>
     <td> &nbsp; </td>
     <td> &nbsp; </td>
     <td> <input type=submit name=opshun value="Next"> </td>
     <td> &nbsp; </td>
     <td> <input type=submit name=opshun value="Prev"> </td>
     <td> &nbsp; </td>
     <td> <input type=submit name=opshun value="First"> </td>
     <td> &nbsp; </td>
     <td> <input type=submit name=opshun value="Last"> </td>
     <td> &nbsp; </td>
    </tr>
    </table>
    </center>
     <hr size=3 noshade> 
   <font size=+1 color=darkred> Results: </font><br>
   <table cellspacing=4 cellpadding=0 border=0 width=100%>
EOF
    } #*-- end of if @files

  for (my $i = 0, my $j = 1; $i <= $results_per_page; $i++)
   {
    if ($files[$i])
     {
      $command = "select lic_description, lic_file from me_list where ";
      $command .= "lii_id = $files[$i]";
      ($sth, $db_msg) = $dbh->execute_stmt($command);
      &quit("Command: $command failed --> $db_msg") if ($db_msg);
      ($lic_description, $lic_file) = $dbh->fetch_row($sth);

      #*-- determine the media type of the file
      my $file_type = ($lic_file =~ /$doc_reg/)   ?  "Document:":
                      ($lic_file =~ /$image_reg/) ?  "Image:":
                      ($lic_file =~ /$audio_reg/) ?  "Audio:":
                      ($lic_file =~ /$video_reg/) ?  "Video:": '';

      #*-- build the html for the media file
      my $index_script = "$CGI_DIR" . "me_index.pl";
      my $s_descr   = &trim_field($lic_description, 60);
      my $file_parm = &url_encode($lic_file);
      my $e_session = &url_encode($in{session});
      my $file_html = (-f $lic_file) ? 
       "<a href=\"file://localhost/$lic_file\"> "                      .
       "<font size=+1 color=darkblue> $s_descr </font></a>"            .
       "<font size=-1 color=darkred> $file_type        </font> "       .
       "<font size=-1 color=darkblue> $lic_file "                      .
       "<a href='$index_script?infile=$file_parm&session=$e_session'>" .
       " Edit </font> </a> ": 
       "<font color=darkred> A file could not be located at $lic_file "  .
       "</font>";

      my $file_no = ($in{cpage} - 1) * $results_per_page + $j; $j++;
      $file_html = "<font color=darkred> $file_no. </font> $file_html ";
      print << "EOF";
       <tr> 
         <td bgcolor=lightyellow valign=top> $file_html </td>
       </tr>
EOF
     }

   } #*-- end of for i

  print ("</tr></table>");

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
    #<input type=hidden name=cpage value=$in{cpage}>

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
