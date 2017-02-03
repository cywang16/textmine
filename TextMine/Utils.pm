
 #*--------------------------------------------------------------------------
 #*- Utils.pm						
 #*-  A collection of general utility functions
 #*-
 #*-  Functions:
 #*-  1. parse_parms	Parse CGI parms and save session data
 #*-  2. url_encode 	Encode parms for an URL
 #*-  3. url_decode 	Decode parms from an URL
 #*-  4. dirChooser 	Generate HTML to choose dirs or files
 #*-  5. f_date     	Format a date for printing           
 #*-  6. dateChooser	Generate HTML to select a date from a calendar
 #*-  7. days_in_month	Return the number of days in month for yr.
 #*-  8. leap_year	Return a boolean, if a leap year or not
 #*-  9. days_in_year	Return the number of days in the year  
 #*-  10. mod_session	Handle fields for session data           
 #*-  11. trim_field	Shorten the length of a field            
 #*-  12. clean_array	Return an array with dups removed        
 #*-  13. sum_array	Return the sum of elements of an array
 #*-  14. log2		Return log2 of the parameter             
 #*-  15. log10		Return log10 of the parameter             
 #*-  16. hexval	Return hexadecimal value of the number   
 #*-  17. factorial	Return factorial of the parameter  
 #*-  18. combo		Return the nCr combination value
 #*--------------------------------------------------------------------------

 package TextMine::Utils;

 use strict; use warnings;
 use lib qw/../;
 use Config;
 use Crypt::Rot13;
 use TextMine::DbCall;
 use TextMine::MyProc    qw/get_drives/;
 use TextMine::Constants qw/FMONTH_NAME MONTH_NAME WEEK_DAYS MONTH_DAYS
     $DB_NAME MAXDATA $CGI_DIR $SDELIM $EQUAL $OSNAME $ICON_DIR 
     &clean_filename/;
 require Exporter;
 our @ISA = qw(Exporter);
 our @EXPORT    = qw(parse_parms url_encode mod_session trim_field f_date
                  dateChooser dirChooser leap_year hexval sum_array);
 our @EXPORT_OK = qw(url_decode min_max days_in_month days_in_year
                  encode decode clean_array log2 log10 factorial combo);

 #*-- global variables
 our (%in); 

 #*------------------------------------------------------------------
 #*- parse_parms
 #*- Reads in GET or POST data using the CGI module
 #*- Return a hash of the fields and associated data
 #*------------------------------------------------------------------

 sub parse_parms 
 {
  my ($script) = @_;	#*-- optional caller's script

  #*-- check if passed data exceeds the limit
  my $len  = $ENV{'CONTENT_LENGTH'};
  if (defined($len) && ($len > MAXDATA) )  
   { die("parse_parms: Attempting to receive too much data: $len bytes\n"); }

  #*-- set the passed parameters
  use CGI qw/param/; %in = ();
  $in{$_} = param($_) foreach (param());

  #*-- return, if the login.pl script is being executed
  return (\%in) if (defined($script) && ($script =~ /co_login.pl$/i)); 

  #*-- redirect to login.pl, if no session id is provided
  unless ($in{session})
   { print "Location: $CGI_DIR" . "co_login.pl", "\n\n"; exit(0); } 
  
  #*-- get the session data 
  (my $dbh) = TextMine::DbCall->new ( 'Host' => '',
   'Userid' => 'tmuser', 'Password' => 'tmpass', 'Dbname' => $DB_NAME);
  my $command = "select sec_data from co_session where " .
              " sec_session = " . $dbh->quote($in{session});
  (my $sth) = $dbh->execute_stmt($command);
  (my $sec_data) = $dbh->fetch_row($sth);

  #*-- redirect to login.pl, unless some session data is provided
  unless ($sec_data)
   { print "Location: $CGI_DIR" . "co_login.pl", "\n\n"; exit(0); } 
  
  #*-- update the session data
  $sec_data = &decode($sec_data);
  my @tdata = split m%$SDELIM%, $sec_data;
  foreach my $parm (@tdata)
   { (my $key, my $val) = split m%$EQUAL%, $parm; 
     next if exists $in{$key}; #*-- use the new parameter value
     $in{$key} = $val;	       #*-- restore the old parameter value 
   }

  #*-- update the table with the new session data
  $sec_data = join ($SDELIM, map { $_ . $EQUAL . $in{$_} } keys %in);
  $sec_data = &encode($sec_data);

  $command = "update co_session set sec_data = " . $dbh->quote($sec_data);
  $command .= " where sec_session = " . $dbh->quote($in{session});
  $dbh->execute_stmt($command);
  
  $dbh->disconnect_db($sth);
  return(\%in); 
  
 }

 #*-----------------------------------------------------------------
 #*- mod_session:
 #*-  Modify the session data based on the option and passed data
 #*-  for add and mod options, sdata contains parameters and values
 #*-  for del, sdata contains parameters to be removed
 #*- 
 #*- Format of session data:
 #*- Field_name1###Field_data1___Field_name2###Field_data2......
 #*-----------------------------------------------------------------
 sub mod_session
 {
  (my $dbh,	#*-- database handle
   my $session,	#*-- session id
   my $opshun,	#*-- function - mod, del, cln, all, ret
   my @sdata	#*-- session data
  ) = @_;

  #*-- fetch the database session data for the passed session
  my $command = "select sec_data from co_session ";
  $command   .= " where sec_session = " . $dbh->quote($session);
  (my $sth, my $db_msg) = $dbh->execute_stmt($command);  
  return() if ($db_msg);
  (my $sec_data) = $dbh->fetch_row($sth);
  $sec_data = &decode($sec_data);
  return() unless($sec_data);
  
  #*-- handle the various functions
  FUNCTION: {

   #*-- modify existing parameters in the session data,
   #*-- add, if the parameter does not exist
   if ($opshun eq 'mod')
    { 
     for (my $i = 0; $i < @sdata; $i+= 2)
      { 
        $sdata[$i+1] = substr($sdata[$i+1], 0, 4096); #*-- field len. limit 4K
        $sec_data .= $SDELIM . $sdata[$i] . $EQUAL . $sdata[$i+1]
        unless ($sec_data =~ 
      s{(^|$SDELIM)($sdata[$i]$EQUAL)(.*?)($SDELIM|$)}{$1$2$sdata[$i+1]$4}s); 
      }
     last FUNCTION; }

   #*-- delete parameters from the session data
   if ($opshun eq 'del')
    { 
     for (my $i = 0; $i < @sdata; $i+= 1)
      { $sec_data =~ s{(^|$SDELIM)($sdata[$i]$EQUAL)(.*?)($SDELIM|$)}{$1}; }
     last FUNCTION; }

   #*-- erase all parameters except session no. from the session data
   if ($opshun eq 'cln')
    { $sec_data = "session" . $EQUAL . $session;
      last FUNCTION; }

   #*-- Return the session data for a set of parameters
   if ($opshun eq 'ret')
    { my (@res); 
      for (my $i = 0; $i < @sdata; $i+= 1)
       { my $val = ($sec_data =~ 
              /(^|$SDELIM)($sdata[$i]$EQUAL)(.*?)($SDELIM|$)/) ? $3: '';
         push(@res, $val);
       }
      return(\@res); }

   #*-- Return all the session data 
   if ($opshun eq 'all')
    { my (%res); 
      foreach (split/$SDELIM/, $sec_data)
       { (my $key, my $val) = $_ =~ /(.*)$EQUAL(.*)/;
          $res{$key} = $val; } 
      return(\%res); }

  } #*-- end of FUNCTION

  #*-- update the session data
  $sec_data =~ s/$SDELIM$//; $sec_data = &encode($sec_data);
  $command  = "update co_session set sec_data = " . $dbh->quote($sec_data) .
              " where sec_session = " . $dbh->quote($session);
  (undef, $db_msg) = $dbh->execute_stmt($command);  
  return(1);
 }

 #*------------------------------------------------------------------
 #*- dirChooser
 #*-  Return the HTML for selecting a directory or file
 #*------------------------------------------------------------------
 sub dirChooser
 {
  my ($FORM,		#*-- calling form name
      $cdrive,		#*-- optional drive name
      $title, 		#*-- title shown on web page
      $show_files, 	#*-- flag for file selection
      $session		#*-- session id
     ) = @_;

  #*-- get the drives
  my ($e_cdrive, @all_files, $file, $full_file, $atime, $fsize);
  use File::stat qw(:FIELDS);
  my @roots = &get_drives(); 

  #*-- set the drive depending on the OS
  if (!($cdrive)) { $cdrive = ($OSNAME eq "win") ? "C:/": "/"; }
  $cdrive =~ s%\\%/%g; $cdrive =~ s/"/\\"/g;
  $cdrive =~ s%/$%% unless ($OSNAME eq 'nix'); 	#*-- remove trailing slash
  $cdrive =~ s%/[^/]*?/\.\.$%% if ($cdrive =~ m%\.\.$%); #*-- handle parents
  $session = &url_encode("$session"); 

  #*-- generate header HTML 
  my $html = << "EOF";

  <center>
  <table> 
   <tr> <td colspan=4 align=center>
        <font size=4 color=darkblue> $title </font> <br><br> </td> </tr>
   <tr> <td align=left> 
            <font color=darkred> Current Directory: </font> </td> 
        <td colspan=2>
        <textarea name=dir_cdrive rows=1 cols=60>$cdrive</textarea> </td>
        <td> <input type=submit name=dir_opshun value="OK"> </td>
   </tr>
  </table> 
  <table> 
   <tr> <td colspan=4> &nbsp; </td> </tr>
   <tr> <td bgcolor=lightyellow> 
            <font color=darkblue size=+1>Name</font> </td>
        <td bgcolor=lightyellow> 
            <font color=darkblue size=+1>Type</font> </td>
        <td bgcolor=lightyellow> 
            <font color=darkblue size=+1>Date</font> </td>
        <td bgcolor=lightyellow> 
            <font color=darkblue size=+1>Size(KB)</font></td>
   </tr>
EOF

 #*-- dump the drives
 $title =~ s/"/\\"/g; my $drive_i = $ICON_DIR . "drive.jpg";
 foreach my $root (sort @roots)
  {
   $root =~ s%\\%/%g;
   $e_cdrive = &url_encode("$root"); 
   $html .= << "EOF";
    <tr> <td> <a href='$FORM?dir_cdrive=$e_cdrive&session=$session&dir_opshun=selecting_dir&file_opshun=$show_files'> 
           <img src=$drive_i align=top border=0> 
           <font color=darkblue> $root</font> </a></td>
         <td> <font color=black> Drive </font> </td>
         <td> <font color=black> &nbsp; </font> </td>
         <td> <font color=black> &nbsp; </font> </td>
    </tr>
EOF
  } 

 
 #*-- if the current drive is a directory
 if (-d $cdrive)
  {
   $cdrive =~ s%$%/% unless ($cdrive =~ m%/$%);  #*-- add trailing slash 
   opendir DIR, $cdrive;
   @all_files = readdir DIR;
   closedir DIR; my $folder_i = $ICON_DIR . "folder.jpg";
   foreach $file (sort @all_files)
    { 
     next if ($file =~ /^\.$/);
     $full_file = "$cdrive" . "$file";
     if (my $st = stat($full_file) )
      { $atime = gmtime ( $st->atime ); $fsize = ' '; }
     $e_cdrive = &url_encode("$full_file"); $e_cdrive =~ s%"%\\"%;
     if (-d $full_file)
      {
       $file = "Up one level.." if ($file =~ /^\.\.$/);
       $html .= << "EOF";
        <tr> <td> 
         <a href='$FORM?dir_cdrive=$e_cdrive&session=$session&dir_opshun=selecting_dir&file_opshun=$show_files'> 
         <img src=$folder_i border=0><font color=darkblue> $file</font> </a></td>
         <td> <font color=black> Directory </font> </td>
         <td> <font color=black> $atime </font> </td>
         <td> <font color=black> $fsize K </font> </td>
        </tr>
EOF
      }
     elsif (-f $full_file)
      {
       my $file_i = $ICON_DIR . "file.jpg";
       if ($show_files)
        {
         $html .= << "EOF";
        <tr> <td> 
         <a href='$FORM?dir_cdrive=$e_cdrive&session=$session&dir_opshun=selecting_dir&file_opshun=$show_files'> 
         <img src=$file_i border=0><font color=darkblue> $file </font> </a></td>
         <td> <font color=black> File </font> </td>
         <td> <font color=black> $atime </font> </td>
         <td> <font color=black> $fsize K </font> </td>
        </tr>
EOF
        }
       else
        {
         $html .= << "EOF";
          <tr> <td>
           <img src=$file_i border=0 border=0><font color=darkblue> $file </font></td>
          <td> <font color=black> File </font> </td>
          <td> <font color=black> $atime </font> </td>
          <td> <font color=black> $fsize K </font> </td>
         </tr>
EOF
        } #*-- end of if show files
      } #*-- if the file is a directory
    } #*-- end of for each
  }

 #*-- HTML for selecting a file
 else
  {
   my $folder_i = $ICON_DIR . "folder.jpg";
   my $file_i   = $ICON_DIR . "file.jpg";
   $atime = $fsize = 0;
   if (my $st = stat($cdrive) )
    { $atime = gmtime ( $st->atime ); 
      $fsize = $st->blocks; $fsize = 0 unless ($fsize =~ /^\d/); 
      $fsize /= 1000; $fsize =~ s/(\..).*$/$1/; }
   $e_cdrive = &url_encode("$cdrive/.."); $e_cdrive =~ s%"%\\"%;
   (my $file = $cdrive) =~ s%^.*/([^/]*?)$%$1%;
   $html .= << "EOF";
     <tr> <td> 
         <a href='$FORM?dir_cdrive=$e_cdrive&session=$session&dir_opshun=selecting_dir&file_opshun=$show_files'> 
         <img src=$folder_i border=0><font color=darkblue> 'Up one level..' </font> </td>
         <td> <font color=black> Directory </font> </td>
         <td> <font color=black> &nbsp; </font> </td>
         <td> <font color=black> &nbsp; </font> </td>
     </tr>
     <tr> <td> 
         <img src=$file_i border=0><font color=darkblue> $file</font> </td>
         <td> <font color=black> File </font> </td>
         <td> <font color=black> $atime </font> </td>
         <td> <font color=black> $fsize K </font> </td>
     </tr>
EOF

  } #*-- end of if cdrive is a directory 

 $html .= << "EOF";
  <input type=hidden name=file_opshun value='$show_files'>
 </table>
 </center>
EOF
 return(\$html);

 }

 #*------------------------------------------------------------------
 #*- dateChooser
 #*- Generates HTML to select a date
 #*------------------------------------------------------------------
 sub dateChooser
 {
  use Time::Local;
  my ($FORM,	#*-- caller script name
      $year,	#*-- number of year
      $month,	#*-- month number (between 0 and 11)
      $day,	#*-- day number
      $title,	#*-- title to show on web page 
      $session	#*-- session id
     ) = @_;

  #*-- check for validity of data
  $session = &url_encode($session);
  $year += 1900 if ($year < 1900);
  return ("Year is out of range, 1970 - 2037\n") if ( ($year < 1970) ||
                                                      ($year > 2037) );
  return ("Month is out of range, 0 - 11\n")     if ( ($month < 0)   ||
                                                      ($month > 11) );
  my $mdays = &days_in_month($month, $year);
  return ("Date is out of range, 1 - $mdays\n")  if ( ($day < 1) ||
                                                      ($day > $mdays) );

  my $eseconds = timegm(0, 0, 0, $day, $month, $year - 1900);
  my $date_line = f_date($eseconds);
  $eseconds  = timegm(0, 0, 0, 1, $month, $year - 1900);
  my $wday   = (gmtime($eseconds))[6];
  $eseconds  = $eseconds - ($wday * 86400);
  my $month_name = ucfirst(FMONTH_NAME->{$month});
  
  #*-- build the header HTML
  $title = "Select a Date" unless($title);
  my $html = <<"EOF";

  <center><br><font size=+1 color=darkred>$title</font> <br> </center>
  <center><br><font size=+1 color=darkblue>$month_name $year</font> </center>
  <table cellspacing=8 cellpadding=0 border=0> 
   <tr> 
     <td bgcolor=lightyellow align=right><font color=darkred>Sun</font></td>
     <td bgcolor=lightyellow align=right><font color=darkred>Mon</font></td>
     <td bgcolor=lightyellow align=right><font color=darkred>Tue</font></td>
     <td bgcolor=lightyellow align=right><font color=darkred>Wed</font></td>
     <td bgcolor=lightyellow align=right><font color=darkred>Thu</font></td>
     <td bgcolor=lightyellow align=right><font color=darkred>Fri</font></td>
     <td bgcolor=lightyellow align=right><font color=darkred>Sat</font></td>
   </tr>
   <tr>
EOF

  #*-- calculate the number of week rows in the calendar
  my $num_rows = int($mdays / 7);
  $num_rows++ if ( ($mdays % 7) || ($month eq 1) );
  $num_rows++ if ( ($mdays + $wday) > 35);
  my $num_cells = 7 * $num_rows;
  my $cells = 0; my $toggle = ($wday) ? 1:0; my $row = 1;

  #*-- special case for the 1st day on a Sunday
  $toggle = !$toggle if ( ($row == 1) && ((gmtime($eseconds))[3] == 1) );
  while ($cells < $num_cells)
   {

    (my $mday, my $mmonth, my $myear) = (gmtime($eseconds))[3..5];
    if ($myear > 137) { $cells++; next; }
    $toggle = !$toggle if ( ($row == 1) && ($mday == 1) );
    my $dcolor = ($toggle) ? "darkblue":"darkred"; 
    $dcolor = "red" if ( ($day == $mday) && ($month == $mmonth) );
    $html .= <<"EOF";

      <td align=right> 
         <a href='$FORM?date_opshun=selecting_date&session=$session&date_year=$myear&date_month=$mmonth&date_day=$mday'> 
         <font size=+1 color=$dcolor> $mday </font> </a>
      </td>
EOF
    $toggle = !$toggle if ( ($row == $num_rows) && ($mday == $mdays) );
    $cells++; $eseconds += 86400;
    unless($cells % 7)
      { $row++; $html .= "</tr><tr>"; }

   } #*-- end of while

  $html .= <<"EOF";
    </tr>
   </table>
    <center> <input type=submit name=date_opshun value=OK> </center>

   <table cellspacing=4 cellpadding=0 border=0>

    <tr> 
      <td> <font color=darkred size=+1> Date: </font> </td>
      <td colspan=12> <font color=red size=+1> $date_line </font> </td>
    </tr>

    <tr> 
      <td> <font color=darkred size=+1> Month: </font> </td>
EOF

  for my $i (0..11)
   {
    $html .= "<td> <a href='$FORM?date_opshun=selecting_date&session=$session&date_year=$year&date_month=$i&date_day=1'>" . ucfirst(MONTH_NAME->{$i}) . "</a></td>";
   }

  $html .= <<"EOF";
     </tr>
     <tr>
       <td> <font color=darkred size=+1> Year: </font> </td>
EOF

  my $s_year = ($year > 1974) ? ($year - 5): 1970;
  my $e_year = ($year < 2032) ? ($year + 6): 2037;
  $e_year = 1981 if ($s_year == 1970);
  $s_year = 2027 if ($e_year == 2037);
  foreach ($s_year..$e_year)
   {
    $html .= "<td> <a href='$FORM?date_opshun=selecting_date&session=$session&date_year=$_&date_month=$month&date_day=$day'> $_ </a> </td> ";

   }

  $html .= << "EOF";
     </tr> </table>
     <input type=hidden name=date_year value='$year'>
     <input type=hidden name=date_month value='$month'>
     <input type=hidden name=date_day value='$day'>
     <input type=hidden name=date_opshun value='OK'>
EOF
  return(\$html);

 }

 #*------------------------------------------------------------------
 #*- f_date
 #*- Description: Format the date and return the string
 #*------------------------------------------------------------------
 sub f_date
 {
  my ($epoch, $show_wday, $show_month, $show_time) = @_;

  (my $day, my $month, my $year, my $wday) = (gmtime($epoch))[3..6];
  my $month_name = ($show_month) ? ucfirst(FMONTH_NAME->{$month}):
                                   ucfirst(MONTH_NAME->{$month});
  my $suffix = 'st' if ($day =~ /1$/); 
  $suffix = 'nd' if ($day =~ /2$/); 
  $suffix = 'rd' if ($day =~ /3$/); 
  $suffix = 'th' if ( ( (4  <= $day) && ($day <= 20) ) ||
                      ( (24 <= $day) && ($day <= 30) ) );
  my $dateline = "$month_name $day$suffix, " . (1900 + $year);
  $dateline = WEEK_DAYS->{$wday} . ", $dateline" if ($show_wday);
  if ($show_time)
   { (my $secs, my $mins, my $hrs) = (gmtime($epoch))[0..2];
     $mins = "0" . $mins unless ($mins > 9);
     $secs = "0" . $secs unless ($secs > 9);
     $dateline .= " $hrs:$mins:$secs GMT"; }
  return ($dateline);

 }

 #*----------------------------------------------------------
 #*- accept an array and remove unwanted elements and dups
 #*- build array elements with quotes
 #*----------------------------------------------------------
 sub clean_array
 {
  (my @iarr) = @_;
  my $in_quotes = 0; my $word = ''; my @new_arr; my %dups;
  foreach (@iarr)
   {
    next unless /[\d\w]/;
    $in_quotes++ if s/^['"]//;
    if ($in_quotes)
      { if (s/["']$//)
          { $in_quotes--;
            push (@new_arr, "$word$_") unless ($dups{"$word$_"});
            $dups{"$word$_"}++; $word = ''; }
        else { $word .= "$_ "; }
      }
    else { push (@new_arr, $_) unless($dups{$_}); $dups{$_}++; }
   }
  return (@new_arr);
 }

 #*---------------------------------------------
 #*- Trim the field based on the field length
 #*----------------------------------------------
 sub trim_field
 {
  my ($field, $field_len) = @_;

  if (!defined($field)) { $field = "&nbsp"; return($field); }
  $field = "&nbsp;" unless($field || $field =~ /^0\s*$/);
  $field_len = 10 unless($field_len);
  my $col_len = length($field);
  $field = substr($field, 0, $field_len - 1) .  "...." .
           ($col_len - $field_len) . " chars..." if ($col_len > $field_len);
  return($field);
 }

 #*------------------------------------------------------------------
 #*- days_in_month
 #*- Description: Return the number of days in a month 
 #*------------------------------------------------------------------
 sub days_in_month
 {
  my ($month, $year) = @_;
  
  #*-- if month is between 0 and 11, assume a numeric interpretation
  $month = MONTH_NAME->{$month} if ( (0 <= $month) && ($month < 12) );
  $month = lc($month);
  my $ndays = MONTH_DAYS->{$month};
  $ndays++ if ( ($month eq "feb") && (&leap_year($year)) );
  return($ndays);
 }

 #*------------------------------------------------------------------
 #*- leap_year
 #*- Description: Return true if the year is a leap year
 #*------------------------------------------------------------------
 sub leap_year
 {
  my ($year) = @_;
  return(0) if ($year % 4);	#*-- if not divisible by 4
  return(1) if ($year % 100); 	#*-- if not divisible by 100
  return(0) if ($year % 400);   #*-- if not divisible by 400
  return($year);
 }

 #*------------------------------------------------------------------
 #*- min_max
 #*- Description: Return the min and max of elements of an array
 #*------------------------------------------------------------------
 sub min_max
 { my $min = 1.0E+40; my $max = 0.0; my $min_ind = my $max_ind = my $i = 0;
   foreach (@{$_[0]}) 
     { if ($min > $_) { $min = $_; $min_ind = $i; }
       if ($max < $_) { $max = $_; $max_ind = $i; }
       $i++; }
   return($min, $max, $min_ind, $max_ind); }

 #*------------------------------------------------------------------
 #*- sum_array
 #*- Description: Return sum of elements of an array
 #*------------------------------------------------------------------
 sub sum_array
 { my $total = 0; $total += $_ foreach (@{$_[0]}); return($total); }

 #*------------------------------------------------------------------
 #*- hexval
 #*- Description: Return the hexadecimal value of the number
 #*------------------------------------------------------------------
 sub hexval
 { (my $decval) = @_; 
   $decval =~ s/(\d+)/sprintf("%x", $1)/ge; return($decval); }

 #*------------------------------------------------------------------
 #*- days_in_year
 #*- Description: Return the number of days in the year 
 #*------------------------------------------------------------------
 sub days_in_year
  { return(365) if (!(&leap_year($_[0]))); return(366); }

 #*------------------------------------------------------------------
 #*- combo
 #*- Description: Return the nCr, number of ways r objects
 #*-              can be selected from a set of n objects
 #*------------------------------------------------------------------
 sub combo
 {
  my ($n, $r) = @_;

  my $nfact = &factorial($n); my $nrfact = &factorial($n - $r);
  my $rfact = &factorial($r);
  return ( $nfact / ($nrfact * $rfact) );
 }

 #*------------------------------------------------------------------
 #*- factorial
 #*- Description: Return factorial of the passed parameter     
 #*------------------------------------------------------------------
 sub factorial
 { my $fact = 1; $fact *= $_ for (2..$_[0]); return ($fact); }

 #*------------------------------------------------------------------
 #*- log2
 #*- Description: Return log base 2 of the passed parameter     
 #*------------------------------------------------------------------
 sub log2
 { return(0) unless($_[0]); return ( log($_[0]) / log(2) ); }

 #*------------------------------------------------------------------
 #*- log10
 #*- Description: Return log base 10 of the passed parameter     
 #*------------------------------------------------------------------
 sub log10
 { return(0) unless($_[0]); return ( log($_[0]) / log(10) ); }

 #*------------------------------------------------------------------
 #*- url_encode
 #*- Description: Encode the passed parameter and return  
 #*------------------------------------------------------------------
 sub url_encode
 { (my $eval = $_[0]) 
             =~ s/([^0-9a-zA-Z*._-])/"%" . sprintf("%lx", (ord($1)))/eg; 
   return($eval); }

 #*------------------------------------------------------------------
 #*- url_decode
 #*- Description: Decode the passed parameter and return  
 #*------------------------------------------------------------------
 sub url_decode
 { (my $dval = $_[0]) =~ s/\%(..)/pack("c",hex($1))/eg; return($dval); }

 #*------------------------------------------------------------------
 #*- encode
 #*- Description: Return an encoded version of the session data
 #*------------------------------------------------------------------
 sub encode
 {
  (my $text) = @_; return ($text); #*-- to skip encrypt
  my $crypto = new Crypt::Rot13; $crypto->charge("$text");
  my @enc_text = $crypto->rot13(10); return("@enc_text");
 }

 #*------------------------------------------------------------------
 #*- decode
 #*- Description: Return a decoded version of the session data
 #*------------------------------------------------------------------
 sub decode
 {
  (my $text) = @_; return ($text); #*-- to skip decrypt
  my $crypto = new Crypt::Rot13; $crypto->charge("$text");
  my @dec_text = $crypto->rot13(16); return("@dec_text");
 }

1; #return true 
=head1 NAME

Utils - TextMine General Utilities

=head1 SYNOPSIS

use TextMine::Utilities;

=head1 DESCRIPTION

=head2 parse_parms	

  Read in CGI parameters and check for the session id. If none
  is present or it is invalid, then return to the login screen

=head2 url_encode

  Encode the parameters in an URL so they will be transmitted
  without modifications

=head2 url_decode
  
  Decode the parameters in an URL

=head2 dirChooser

  Create HTML for a form that provides a field to select a
  directory or file. The list of directories and files are
  shown.

=head2 f_date

  Create a string that displays a nicely formatted date

=head2 dateChooser

  Create HTML for a form that provides a field to select a date

=head2 days_in_month, days_in_year, leap_year
 
  Return the number of days in the month for a particular year
  Return the number of days in a year for a particular year
  A flag indicating a leap year

=head2	mod_session

  Modify the session data. Add, modify or delete session parameters

=head2 trim_field

  Truncate a field and show the number of characters remaining in 
  the field

=head1 AUTHOR

Manu Konchady <mkonchady@yahoo.com>
