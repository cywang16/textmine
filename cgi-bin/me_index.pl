#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
 #*----------------------------------------------------------------
 #*- me_index.pl
 #*-   Summary: 
 #*-   1. Read the input parameters                
 #*-   2. Recursively collect all files from the input directory
 #*-      and save the list.
 #*-   3. Process the files one at a time and allow the user
 #*-      to page back and forth.
 #*-   4. Display a status message at the bottom of the page
 #*----------------------------------------------------------------

 use strict; use warnings;
 use Digest::MD5 qw(md5_base64);
 use File::Find;
 use Time::Local;
 use TextMine::DbCall;
 use TextMine::Index qw/add_index rem_index/;
 use TextMine::Utils qw(parse_parms mod_session dirChooser dateChooser
                        trim_field f_date url_encode);
 use TextMine::Constants qw( $CGI_DIR $ICON_DIR $DB_NAME $OSNAME 
     @MFILE_TYPES @AUDIO_TYPES @IMAGE_TYPES @VIDEO_TYPES @DOC_TYPES 
     clean_filename fetch_dirname);

 #*-- global variables
 use vars (
  '%in',		#*-- hash for form fields
  '$FORM',		#*-- name of form
  '@files',		#*--
  '$command',		#*-- var for SQL command
  '$sth',		#*-- statement handle
  '$dbh',		#*-- database handle
  '$db_msg',		#*-- database error message
  '$stat_msg',		#*-- status message for a page
  '$icount',		#*-- flag for previously indexed file 
  '$digest',		#*-- MD5 digest of a file
  '$ref_val',		#*-- reference var
  '$num_files',		#*-- number of files to be indexed
  '$media_reg', '$image_reg', '$audio_reg', '$doc_reg', '$video_reg'
  );			#*-- REs for media types

 #*-- retrieve passed parameters and set variables
 &set_vars();

 #*-- handle the selection of a direcory
 &dir_handler(); 

 #*-- handle the selection of a date
 &date_handler(); 

 #*-- locate the file based on options
 &file_locater();

 #*-- process the selected function
 &function_handler();

 #*-- dump the html 
 &head_html(); 
 &msg_html($stat_msg) if ($stat_msg); 
 &body_html() if (@files); 
 &tail_html(); 

 exit(0);

 #*-------------------------------------------------------
 #*- Set some global vars 
 #*-------------------------------------------------------
 sub set_vars
 {
  #*-- set the form name and REs for the media types
  #*-- fetch the form fields
  $stat_msg = '';
  local $" = '|';
  $media_reg = qr/\.(?:@MFILE_TYPES)$/i;
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
  $in{opshun} = 'Save' if ($in{'index.x'});
  $in{opshun} = 'Fetch' unless ($in{opshun});

  #*-- delete the forgetful parms
  my @dparms = qw/index.x opshun date_opshun select_date dir_opshun infile/;
  &mod_session($dbh, $in{session}, 'del', @dparms);

  foreach (qw/dir_opshun date_opshun opshun view_files indx @dparms/)
   { $in{$_} = '' unless ($in{$_}); }
 }

 #*---------------------------------------------------------------
 #*- Handle the selection of the directory
 #*---------------------------------------------------------------
 sub dir_handler
 {

  #*-- if choosing a directory
  if ($in{dir_opshun} eq 'selecting_dir')
   {
    &mini_head_html();
    my $body_html = ${$ref_val = 
    &dirChooser($FORM,$in{dir_cdrive},
              'Select Source Directory',0,$in{session})};
    print ("$body_html\n");
    &mini_tail_html();
    exit(0);
   }

  #*-- if we have chosen a directory, then set the current drive field
  if ($in{dir_opshun} eq "OK") 
   { $in{idir} = $in{dir_cdrive}; return(); } 

  #*-- if option is to choose a dir, display the select screen 
  if ($in{opshun} eq "Select Source Directory") 
   {
    &mini_head_html(); 
    my $body_html = ${$ref_val = 
     &dirChooser($FORM,$in{idir},$in{opshun},0,$in{session})}; 
    print ("$body_html\n");
    &mini_tail_html();
    exit(0); 
   }

  #*-- set the idir parm, if called from search.pl
  if ($in{infile})
   { ($in{idir}) = &fetch_dirname($in{infile}); $in{view_files} = 'All'; 
     &mod_session($dbh, $in{session}, 'mod',
                            'view_files', "$in{view_files}"); } 

  #*-- if the directory entry is blank, then display the opening html
  &quit("A Source directory must be entered") unless ($in{idir});

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
   { $in{index_date} = timegm(0, 0, 0, $in{date_day}, 
                              $in{date_month}, $in{date_year} - 1900);
     &mod_session($dbh, $in{session}, 'mod',
                              'index_date', "$in{index_date}");
     $in{opshun} = 'New_date';
    return(); }

  if ($in{select_date})
   { 
    &mini_head_html();
    my $body_html = ${$ref_val = &dateChooser
     ($FORM, $in{index_year}, $in{index_month}, $in{index_day}, 
                 "Select a Date", $in{session} )};
    print ("$body_html\n");
    &mini_tail_html();
    exit(0);
   }

 }

 #*---------------------------------------------------------------
 #*- Choose the file using selected options
 #*---------------------------------------------------------------
 sub file_locater
 {
   #*-- recursively get the files from the input directory
   my %ifiles = ();
   my @t_files = (); my $i = 1;
   find sub { $t_files[$i++] = $File::Find::name  
              if ($File::Find::name =~ m%$media_reg%i) }, "$in{idir}";

   #*-- keep indexed files in the @files array
   if ( defined($in{ifiles}) &&
        ( ($in{opshun} ne 'Fetch') || ($in{opshun} eq 'New_date') ) ) 
    { map {$ifiles{$_}++} split/,/,$in{ifiles}; } 
   @files = (); 
   foreach my $file (@t_files)
    { 
      #*-- fetch files which have not been indexed
      $file = &clean_filename($file); my $q_file = $dbh->quote($file);
      if ($in{view_files} eq 'New')
       { $command = "select lii_id from me_list where lic_file = $q_file"; 
         ($sth, $db_msg) = $dbh->execute_stmt($command);
         &quit("Command: $command failed --> $db_msg") if ($db_msg);
         (my $lii_id) = $dbh->fetch_row($sth);
         if ($lii_id) #*-- simulate a transaction like environment
                      #*-- while indexing is ongoing
          { push (@files, $file) if ($ifiles{$lii_id}); next; }
       }  
      push (@files, $file);                                       
    }

   #*-- quit, if no files were found in the directory
   $num_files = @files - 1;
   &quit("No files were found in directory: '$in{idir}'") unless ($num_files);

   #*-- process the navigation options
   $in{indx} = 1 unless ($in{indx});
   $in{indx}++            if ($in{opshun} eq 'Next');
   $in{indx}--            if ($in{opshun} eq 'Prev');
   $in{indx} = 1          if ($in{opshun} eq 'First');
   $in{indx} = $num_files if ($in{opshun} eq 'Last');

   #*-- make sure indx is in range
   $in{indx} = $num_files if ($in{indx} > $num_files);
   $in{indx} = 1 if ($in{indx} < 1);

   #*-- handle the selection of a file if called from search script
   #*-- set the indx parm based on the location of the file in @files
   if ($in{infile})
    { for my $i (0..$#files)
       { $in{indx} = $i if ($in{infile} eq $files[$i]); }  
    }

   #*-- save the indx parameter in the session data
   &mod_session($dbh, $in{session}, 'mod', 'indx', $in{indx});

   #*-- check if the file has been indexed in the DB
   undef($/); 
   open(IN, "<", &clean_filename("$files[$in{indx}]")) || 
        &quit("Unable to open file '$files[$in{indx}]' -- $!\n");
   binmode(IN); 
   my $file_source = <IN>; 
   close(IN);
   $digest = md5_base64($file_source);
 
   $command  = "select count(*), lii_date, lic_description ";
   $command .= " from me_list where lic_signature = ";
   $command .= $dbh->quote($digest) . " group by lii_id";
   ($sth, $db_msg) = $dbh->execute_stmt($command);
   &quit("Command: $command failed --> $db_msg") if ($db_msg);
   ($icount, my $lii_date, my $lic_description) = $dbh->fetch_row($sth);

   #*-- set the description and date fields
   if ($in{opshun} =~ /^(?:Next|Prev|First|Last|Delete|Fetch)/)
    { $in{descr} = ''; $in{index_date} = time(); } 

   if ( ($icount) && ($in{opshun} ne 'Re-Index') )
    { $in{index_date} = $lii_date unless ($in{opshun} eq 'New_date'); 
      $in{descr} = &trim_field($lic_description, 70); }
   else
    { $in{descr} = '' unless($in{descr}); }

 }

 #*---------------------------------------------------------------
 #*- Process the function 
 #*---------------------------------------------------------------
 sub function_handler
 {

  #*-- handle the various functions
  FUNCTION: {
    
  #*-- save the file if it has not been indexed and has a description
  if ($in{opshun} =~ /^Save/)  
   { &quit("The current file has been indexed -- Press Re-Index") 
           if ($icount);
     &quit("Please enter a description for $files[$in{indx}]")
           unless ($in{descr});
     &cre_file(); $stat_msg = "-- Current file has been indexed<br>";
     last FUNCTION; }

  #*-- re-create the index for an existing file
  if ($in{opshun} =~ /^Re-Index/)
   { &quit("Please enter a description for $files[$in{indx}]")
          unless ($in{descr});
     &del_file if ($icount);
     &cre_file(); $stat_msg = "-- Current file has been re-indexed<br>";
     last FUNCTION; }

  #*-- delete the file and clean up the index  
  if ($in{opshun} =~ /^Delete/)
   { &quit("The current file is not indexed") unless ($icount);
     &del_file;
     $stat_msg = "-- The file has been removed from the index<br>"; 
     $in{descr} = ''; last FUNCTION; }

  #*-- when a new date has been chosen, restore the old descr.
  if ($in{opshun} eq 'New_date')
   { $in{descr} = (@{my $ret = &mod_session($dbh, $in{session}, 
                        'ret', 'descr')})[0]; 
     last FUNCTION; }

  #*-- default
  if ($in{opshun} =~ /^Fetch/)
   { &quit("No files available in this directory") unless (@files);
     &mod_session($dbh, $in{session}, 'del', 'ifiles');
     last FUNCTION; }

  } #*-- end of FUNCTION

 }


 #*---------------------------------------------------------------
 #*- Delete the entry from the index and main table
 #*---------------------------------------------------------------
 sub del_file
 {
  #*-- get and parse the description for the file
  my $q_digest = $dbh->quote($digest);
  $command  = "select lic_description, lii_id from me_list ";
  $command .= "where lic_signature = $q_digest ";
  ($sth, $db_msg) = $dbh->execute_stmt($command);  
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  (my $lic_description, my $lii_id) = $dbh->fetch_row($sth);

  #*-- delete the id from the index
  $stat_msg .= &rem_index($lii_id, $lic_description, 'me', $dbh);   

  #*-- delete from the main table
  $command = "delete from me_list where lic_signature = $q_digest";
  (my $retval, $db_msg) = $dbh->execute_stmt($command);  
  &quit("Command: $command failed --> $db_msg") if ($db_msg);

 }

 #*---------------------------------------------------------------
 #*- Create an entry in the main table and the index
 #*---------------------------------------------------------------
 sub cre_file
 {
  #*-- insert in the files table
  $command = "insert into me_list values (0, "; 
  $command .= "$in{index_date}, " . $dbh->quote($files[$in{indx}])  . ", ";
  $command .= $dbh->quote($in{descr})                               . ", ";
  $command .= $dbh->quote($digest) . ")";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  my $id = $dbh->last_id();
  $stat_msg .= &add_index($id, $in{descr}, 'me', $dbh);

  #*-- set a session parameter for the indexed file
  my $ifiles = ($in{ifiles}) ? "$in{ifiles},$id": "$id";
  &mod_session($dbh, $in{session}, 'mod', 'ifiles', "$ifiles");

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
     <title> Index Page for Multimedia Retrieval Engine </title>
    </head>
  
    <body bgcolor=white>

     <form method=POST action="$FORM">
     <center>
EOF
 }

 #*---------------------------------------------------------------
 #*- display the header html 
 #*---------------------------------------------------------------
 sub head_html
 {
  #*-- set defaults for index date
  $in{index_date} = time() unless($in{index_date});
  ($in{index_day}, $in{index_month}, $in{index_year}) =
                   (gmtime($in{index_date}))[3..5];
  &mod_session($dbh, $in{session}, 'mod', 
    'index_date',  $in{index_date}, 'index_day',  $in{index_day},
    'index_month', $in{index_month},'index_year', $in{index_year});
  $in{descr} = '' unless($in{descr});
  my $index_date   = &f_date($in{index_date});
  my $ind_image    = "$ICON_DIR" . "index.jpg";
  my $index_image  = "$ICON_DIR" . "index_it.jpg";
  my $search_image = "$ICON_DIR" . "search_it.jpg";
  my $e_session = &url_encode($in{session});
  my $anchor = "$CGI_DIR" . "co_login.pl?session=$e_session";
  my $search_cgi = "$CGI_DIR" . "me_search.pl?session=$e_session";
  my $new_check = ($in{view_files} eq 'New') ? 
                  'CHECKED' : ' onClick = "loadForm()"';
  my $all_check = ($new_check eq 'CHECKED' ) ? 
                  'onClick = "loadForm()"' : 'CHECKED';

  print "Content-type: text/html\n\n";
  print << "EOF";
   <html>
    <head>
     <title> Load Page for Multimedia Retrieval Engine </title>
    </head>
  
    <body bgcolor=white>

     <form method=POST action="$FORM" name=dbform>

      <script>
       function loadForm() 
        { document.dbform.indx.value = 1; 
          document.dbform.submit(); }

      </script>

     <center>
      <table> <tr> <td> <a href=$anchor>
              <img src="$ind_image" border=0> </a> </td> </tr> </table>

      <table>
       <tr> 
         <td> <font color=darkred> Source Directory: </font> </td>
         <td> <textarea name=idir rows=1 cols=70>$in{idir}</textarea></td>
         <td> <input type=submit name=opshun 
                                 value="Select Source Directory"> </td>
       </tr>

       <tr> 
         <td> <font color=darkred> Description: </font> </td>
         <td> <textarea name=descr rows=1 cols=70>$in{descr}</textarea></td>
         <td> <input type=submit name=opshun value="Fetch"> </td>
       </tr>

       <tr> 
        <td colspan=3>
        <table>
          <tr>
           <td> <font color=darkred> Date: </font>
             <input type=submit name=select_date value="$index_date"> 
           </td>
           <td> &nbsp; </td>
           <td> <font color=darkred> Files: </font> </td>
           <td> All <input type=radio name=view_files value='All' $all_check>
                New <input type=radio name=view_files value='New' $new_check>
           </td>
           <td> &nbsp; </td>
           <td> 
             <input type=image src=$index_image border=0 name=index>
           </td>
           <td> &nbsp; </td>
           <td>
            <a href=$search_cgi> <img src=$search_image border=0> </a>
           </td>
          </tr>
        </table>
       </td> </tr>
     </table>
EOF

 }

 #*---------------------------------------------------------------
 #*- Display the file based on the file index 
 #*---------------------------------------------------------------
 sub body_html
 {
  my $file = "$files[$in{indx}]"; 
  $file = "file://localhost/" . $file;
  my $file_html = 
  ($file =~ /$image_reg/) ?  "<img src=\"$file\">":
  ($file =~ /$doc_reg/) ?  
    "<font color=darkblue size=+1> Document <a href='$file'>$file</font></a>": 
  ($file =~ /$audio_reg/) ?  
    "<font color=darkblue size=+1> Audio <a href='$file'> $file </font> </a>": 
  ($file =~ /$video_reg/) ?  
    "<font color=darkblue size=+1> Video <a href='$file'> $file </font> </a>": 
    "<font color=darkblue size=+1> Other <a href='$file'> $file </font> </a>"; 
  print << "EOF";

    <table> <tr> 
     <td> <font color=darkred> $in{indx} of $num_files files </font> </td>
     <td> &nbsp; </td>
     <td> &nbsp; </td>
     <td bgcolor=lightblue><input type=submit name=opshun value="Next"></td>
     <td> &nbsp; </td>
     <td bgcolor=lightblue><input type=submit name=opshun value="Prev"></td>
     <td> &nbsp; </td>
     <td bgcolor=lightblue><input type=submit name=opshun value="First"></td>
     <td> &nbsp; </td>
     <td bgcolor=lightblue> <input type=submit name=opshun value="Last"></td>
     <td> &nbsp; </td>
     <td bgcolor=lightblue> <input type=submit name=opshun value="Re-Index"></td>
     <td> &nbsp; </td>
     <td bgcolor=lightblue> <input type=submit name=opshun value="Delete"></td>
     <td> &nbsp; </td>
    </tr>
    </table>
    <br> <br>
    <table> <tr> <td bgcolor=lightyellow>
    $file_html
    </td> </tr> </table>
EOF

 }

 #*---------------------------------------------------------------
 #*- Exit with a message            
 #*---------------------------------------------------------------
 sub quit
 {
  &head_html(); &msg_html($_[0] . "<br>$stat_msg"); 
  &body_html() if ($num_files); 
  &tail_html(); 
  exit(0);
 }

 #*---------------------------------------------------------------
 #*- Dump an error message           
 #*---------------------------------------------------------------
 sub msg_html
 {
  print << "EOF";
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
  $dbh->disconnect_db($sth);
  print << "EOF";
    </center>
    <input type=hidden name=indx value=$in{indx}>
    <input type=hidden name=session value=$in{session}>
   </form>
  </body>
  </html>
EOF
 }
    #<input type=hidden name=dir_opshun value=$in{dir_opshun}>

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
