#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
 #*----------------------------------------------------------------
 #*- tx_stats.pl
 #*-  
 #*-   Summary: Show a text box and capture statistics for the
 #*-            entered text. Build plots and compare with the
 #*-            Reuters 21578 collection   
 #*----------------------------------------------------------------

 use strict; use warnings;
 use GD;		#*-- for building plots
 use TextMine::DbCall;
 use TextMine::Index     qw(content_words);
 use TextMine::Utils     qw(parse_parms mod_session url_encode log10);
 use TextMine::Constants qw($CGI_DIR $DB_NAME $TMP_DIR $ICON_DIR 
                         clean_filename);

 #*-- Global variables 
 use vars  ('$dbh',	#*-- database handle
            '$sth',	#*-- statement handle
            '$db_msg',	#*-- database error message
            '$FORM', 	#*-- name of this form
            '%in',	#*-- hash containing form fields
            '$e_session',	#*-- url encoded session  
            '$body_html',	#*-- text string for HTML of body
            '$tbox',		#*-- text box
            '$stat_msg',	#*-- status message for page
            '$buttons'		#*-- buttons at the bottom of the page
     );

 #*-- retrieve and set variables
 &set_vars();

 #*-- handle the buttons
 &dump_stats()  if ($in{opshun} eq 'Statistics');
 &reset_form()  if ($in{opshun} eq 'Reset');
 &ent_form()    if ($in{opshun} eq 'New');

 #*-- dump the header, body and tail html 
 &head_html(); &body_html(); &tail_html(); 

 exit(0);

 #*-----------------------------------------------------
 #*- Set some global vars            
 #*-----------------------------------------------------
 sub set_vars
 {
  #*-- set the form name
  $0 =~ s%.*[/\\]%%; $FORM = "$CGI_DIR" . "$0";

  #*-- retrieve the passed parameters and establish DB Connection
  %in    = %{my $ref_val = &parse_parms};
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $in{userid}, 'Password' => $in{password},
       'Dbname' => $DB_NAME);

  #*-- set the opshun parm and delete from session
  $in{opshun} = 'New' unless (defined($in{opshun}));
  $in{opshun} = 'New' if ($in{opshun} =~ /^(?:Return)$/);
  &mod_session($dbh, $in{session}, 'del', 'opshun' );
  $stat_msg = $tbox = $buttons = '';
  $e_session = &url_encode($in{session});
 }

 #*---------------------------------------------------------------
 #*- Dump the statistics 
 #*---------------------------------------------------------------
 sub dump_stats
 {
  $stat_msg = "Statistics of Text compared to Reuters Corpus";
  
  #*-- first get the words including stopwords
  my @words   = @{&content_words(\$in{tbox}, '', $dbh, '1' )};
  my $c_words = @words;                #*-- count the number of words
  return() unless ($c_words);

  #*-- count the number of word types
  my %wcount; $wcount{$_}++ foreach (@words);
  my $c_wtypes = keys %wcount;

  #*-- compute average word length and frequencies of word lengths
  my $len = 0; my @word_len = (0) x 30;
  foreach (@words) 
   { my $temp = length($_); $len += $temp; $word_len[$temp]++; }
  $len = ($len / $c_words); $len =~ s/(\...).*$/$1/;

  #*-- compute the frequency of letters
  my %letters;
  foreach (@words)
   { my @letters = split//, $_;
     foreach (@letters) { if ($_ =~ /[A-Za-z]/) { $letters{lc($_)}++; } }
   }

  #*-- compute the frequency of word types
  my %lw_count; 
  foreach (keys %wcount) { $lw_count{$wcount{$_}}++; }
  
  #*-- compute the frequencies for ranks
  my $rank = 0; my $mod; my %rcount;
  foreach (sort {$wcount{$b} <=> $wcount{$a}} keys %wcount)
   { $rank++; $rcount{$_} = $rank; }

  #*-- build the rank vs. freq. plot
  my @xdata1 = my @xdata2 = my @ydata1 = my @ydata2 = ();
  @xdata1 = qw/1 2 3 4 5 6 7 8 9 10 20 30 40 50 60 70 80 90 100 200 300 
               400 500 600 700 800 900 1000 2000 3000 4000 5000 6000 7000 
               8000 9000 10000 20000 30000 40000 50000/;

  @ydata1 = qw/120021 72225 68685 53462 52890 49984 48440 25578 25535 24278 
               14647 9520 7093 5365 4547 3561 3269 2904 2677 1489 1065 828 
               678 567 485 421 355 316 134 80 52 37 27 21 17 14 11 3 2 1 1/;

  foreach ( sort { $rcount{$a} <=> $rcount{$b} } keys %rcount)
   { push (@xdata2, $rcount{$_}); push (@ydata2, $wcount{$_}); }

  my $filename = "$TMP_DIR" . "rank.png";
  my $prefix = 'file://localhost';
  $prefix .= '/' unless ($filename =~ m%^/%);
  my $url1 = $prefix . $filename;
  
  &plot('Rank vs. Frequency', 'Rank', 'Frequency', 'Log', 
         \@xdata1, \@ydata1, \@xdata2, \@ydata2, $filename);

  #*-- build the letter vs. freq. plot
  @xdata1 = (1..26);
  @ydata1 = qw/ 1390004 1061818 1011703 904178 894859 874373 873753 835207 
                535318 524329 446069 428164 322927 316462 300582 269024 
                219063 191897 177133 165147 127583 84935 38707 23827 
                17592 10500/;
  @xdata2 = (1..26); @ydata2 = ();
  foreach ( sort {$letters{$b} <=> $letters{$a} } keys %letters)
   { push (@ydata2, $letters{$_}); }

  $filename = "$TMP_DIR" . "letter.png";
  my $url2 = $prefix . $filename;
  &plot('Letter vs. Frequency', 'Letter', 'Frequency', '', 
         \@xdata1, \@ydata1, \@xdata2, \@ydata2, $filename);

  #*-- build the word length vs. frequency plot
  #*-- anomaly word of 345 occurrences with length 18 is telecommunications
  @xdata1 = (1..28);
  @ydata1 = qw/ 103935 384003 478902 405460 266770 211299 219979 166147 
                113545 72742 36190 21809 11833 3915 978 297 114 345 17 
                30 2 1 1 2 0 0 0 0/;
  @xdata2 = (1..28); @ydata2 = @word_len;
  
  $filename = "$TMP_DIR" . "wlength.png";
  my $url3 = $prefix . $filename;
  &plot('Word Length vs. Frequency', 'Word Length', 'Frequency', '', 
         \@xdata1, \@ydata1, \@xdata2, \@ydata2, $filename);

  #*-- build the word frequency vs. frequency plot
  #*-- a few occurrences of long words distort the lower end of the curve
  @xdata1 = qw/1 2 3 4 5 6 7 8 9 10 10 20 30 40 50 60 70 80 90 100
              100 200 300 500 600 800 896 1003 2008 3029 4005 5006
              6248 7023 8061 9038 10259 20298 25578 48440 49984 68685
              72225 120021/;

  @ydata1 = qw/17026 6962 3764 2498 1789 1361 1045 872 692 649 649
              183 121 83 53 39 23 25 20 20 20 1 3 1 2 1 1 3 2 1 1
              1 1 1 1 1 1 1 1 1 1 1 1 1/;

  @xdata2 = (); @ydata2 = ();
  foreach (sort { ${a} <=> ${b} } keys %lw_count)  
    { push (@xdata2, $_); push (@ydata2, $lw_count{$_}); }

  $filename = "$TMP_DIR" . "wfreq.png";
  my $url4 = $prefix . $filename;
  &plot('Word Frequency vs. Frequency', 'Word Frequency', 'Frequency', 
        'Log', \@xdata1, \@ydata1, \@xdata2, \@ydata2, $filename);
  
  $tbox = <<"EOF";

  <tr> <td align=center> 
     <table cellspacing=0 cellpadding=0 border=0 bgcolor=lightyellow>
     <tr><td>
     <table cellspacing=4 cellpadding=0 border=2 bgcolor=lightblue>

     <tr>
        <td bgcolor=lightyellow valign=top> 
            <font color=darkred size=4> Statistic </font> </td>
        <td bgcolor=lightyellow valign=top>
            <font color=darkred size=4> Text </font> </td>
        <td bgcolor=lightyellow valign=top>
            <font color=darkred size=4> Reuters </font> </td>
     </tr>

     <tr>
        <td bgcolor=white valign=top> 
            <font color=darkblue size=4> No. of content Words </font> </td>
        <td bgcolor=white valign=top>
            <font color=darkblue size=4> $c_words </font> </td>
        <td bgcolor=white valign=top>
            <font color=darkblue size=4>  2,416,645 </font> </td>
     </tr>

     <tr>
        <td bgcolor=white valign=top> 
            <font color=darkblue size=4> No. of Word Types </font> </td>
        <td bgcolor=white valign=top>
            <font color=darkblue size=4> $c_wtypes </font> </td>
        <td bgcolor=white valign=top>
            <font color=darkblue size=4>  52,637 </font> </td>
     </tr>

     <tr>
        <td bgcolor=white valign=top> 
            <font color=darkblue size=4> Average Word length </font> </td>
        <td bgcolor=white valign=top>
            <font color=darkblue size=4> $len </font> </td>
        <td bgcolor=white valign=top>
            <font color=darkblue size=4>  4.93 </font> </td>
     </tr>

     </table>
     </td></tr>
     </table>

 </td></tr>

 <tr><td> &nbsp; </td></tr>
 <tr><td align=center> 
    <table border=8 cellspacing=0 cellpadding=0>
    <tr> <td> <img src=$url1> </td> </tr> </table>
 </td></tr>

 <tr><td> &nbsp; </td></tr>
 <tr><td align=center> 
    <table border=8 cellspacing=0 cellpadding=0>
    <tr> <td> <img src=$url2> </td> </tr> </table>
 </td></tr>

 <tr><td> &nbsp; </td></tr>
 <tr><td align=center> 
    <table border=8 cellspacing=0 cellpadding=0>
    <tr> <td> <img src=$url3> </td> </tr> </table>
 </td></tr>

 <tr><td> &nbsp; </td></tr>
 <tr><td align=center> 
    <table border=8 cellspacing=0 cellpadding=0>
    <tr> <td> <img src=$url4> </td> </tr> </table>
 </td></tr>

EOF

  $buttons = '<td align=center> <input type=submit name=opshun value=Return> </td>';
 }

 #*---------------------------------------------------------------
 #*- Fill in fields for startup    
 #*---------------------------------------------------------------
 sub ent_form
 {
  $stat_msg = 'Paste text and select an option';
  $tbox = (defined($in{tbox})) ? $in{tbox}: '';
  $tbox = '<tr> <td colspan=2> <textarea name=tbox cols=70 rows=20>' .
          "$tbox" . '</textarea> </td></tr>'; 
  $buttons = <<"EOF"
    <td align=center><input type=submit name=opshun value='Statistics'></td>
    <td align=center><input type=submit name=opshun value='Reset'></td>
EOF
 }

 #*---------------------------------------------------------------
 #*- Reset the fields              
 #*---------------------------------------------------------------
 sub reset_form
 {
  $stat_msg = 'Paste text and select an option';
  $tbox = '<tr> <td colspan=2> <textarea name=tbox cols=70 rows=20>' .
          "" . '</textarea> </td></tr>'; 
  $buttons = <<"EOF"
   <td align=center><input type=submit name=opshun value='Statistics'></td>
   <td align=center><input type=submit name=opshun value='Reset'></td>
EOF
 }

 #*---------------------------------------------------------------
 #*- dump some header html
 #*---------------------------------------------------------------
 sub head_html
 {
  my $te_image   = "$ICON_DIR" . "tex.jpg";
  my $anchor = "$CGI_DIR/co_login.pl?session=$e_session";

  print "Content-type: text/html\n\n";
  print << "EOF";
   <html>
    <head> <title> Exploring Text Page </title> </head>

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

    <tr> $buttons </tr>

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

 #*------------------------------------------------------------
 #*- build a plot using the data passed
 #*- @xdata1 and @ydata1 are fixed data from the Reuters Corpus
 #*- @xdata2 and @ydata2 are variable data
 #*- No. of partitions of y axis will vary depending on max. of @ydata1
 #*- No. of partitions of x axis is fixed at 5
 #*- y axis is always log scale
 #*- x axis is either linear or log scale
 #*------------------------------------------------------------
 sub plot
 {
  my ($title, $xtitle, $ytitle, $xtype, $xdata1, $ydata1, 
      $xdata2, $ydata2, $filename) = @_;

  my $width   = 400;  #*-- width of image
  my $height  = 400;  #*-- height of image
  my $xdisp = 50;     #*-- x displacement from upper left corner 
  my $ydisp = 30;     #*-- y displacement from upper left corner
  my $p_width = 300;  #*-- width of plot
  my $p_height = 300; #*-- height of plot

  #*-- create a new image and read the data
  my $image = new GD::Image($width, $height);
  my @xdata1 = @$xdata1; my @ydata1 = @$ydata1;
  my @xdata2 = @$xdata2; my @ydata2 = @$ydata2;

  #*-- smooth @ydata2
  my @temp = @ydata2;
  for my $i (1..($#temp - 1))
   { $ydata2[$i] = ($temp[$i-1] + $temp[$i] + $temp[$i+1]) / 3; }

  #*-- smooth @ydata1
  @temp = @ydata1;
  for my $i (1..($#temp - 1))
   { $ydata1[$i] = ($temp[$i-1] + $temp[$i] + $temp[$i+1]) / 3; }
  
  #*-- find the max. y and adjust with width of the plot
  my $maxy = 0; foreach (@ydata1) { $maxy = $_ if ($maxy < $_); }
  my $yparts = 4;
  $yparts = 7 if ( ($maxy < 10_000_000) && ($maxy > 1_000_000) );
  $yparts = 6 if ( ($maxy < 1_000_000)  && ($maxy > 100_000) );
  $yparts = 5 if ( ($maxy < 100_000)    && ($maxy > 10_000) );
 
  #*-- allocate some colors
  my $white     = $image->colorAllocate(255, 255, 255);
  my $lightgray = $image->colorAllocate(230, 230, 210);
  my $black     = $image->colorAllocate(0, 0, 0);
  my $red       = $image->colorAllocate(255, 0, 0);
  my $blue      = $image->colorAllocate(0, 0, 255);

  #*-- draw the title in the center
  $image->fill(1, 1, $white);
  my $char_width = gdLargeFont->width;
  my $xloc = $xdisp + int ( ($p_width - (length($title) * $char_width) ) 
             / 2.0);
  my $yloc = 10;
  $image->string(gdLargeFont, $xloc, $yloc, $title, $black);

  #*-- draw the y axis title
  $yloc = $ydisp + $p_height - int ( ($p_height - (length($ytitle) * 
             $char_width) ) / 2.0);
  $xloc = 2;
  $image->stringUp(gdLargeFont, $xloc, $yloc, $ytitle, $black);

  #*-- draw the x axis title
  $yloc = $ydisp + $p_height + $ydisp;
  $xloc = $xdisp + int ( ($p_width - (length($xtitle) * $char_width) ) / 2.0);
  $image->string(gdLargeFont, $xloc, $yloc, $xtitle, $black);

  #*-- draw the 1 at the corner
  $image->string(gdSmallFont, $xdisp - 5, $ydisp + $p_height + 5,
                 "1", $black);

  #*-- draw the y ticks and the label
  my $ysep = $p_height / $yparts; 
  for my $i (1..$yparts)
   {
    $yloc = $ydisp + $p_height - ($i * $ysep);
    $image->string(gdSmallFont, $xdisp - 20, $yloc, "10", $black);
    $image->string(gdTinyFont, $xdisp - 7, $yloc-5, "$i", $black);
    $image->line($xdisp - 2, $yloc, $xdisp + 2 + $p_width, $yloc, $lightgray);
   }

  #*-- draw the x ticks and the label
  my $xsep = $p_width / 5;
  for my $i (1..5)
   {
    $xloc = $xdisp + ($i * $xsep);
    if ($xtype eq 'Log')
     {
      $image->string(gdSmallFont, $xloc - 10, $ydisp + $p_height + 5, 
                     "10", $black);
      $image->string(gdTinyFont, $xloc + 4, $ydisp + $p_height + 2, 
                     "$i", $black);
     }
    else
     { my $val = 6 * $i;
      $image->string(gdSmallFont, $xloc - 5, $ydisp + $p_height + 5, 
                     "$val", $black);
     }
    $image->line($xloc, $ydisp + $p_height - 2, $xloc, $ydisp + 2, $lightgray);
   }

  my $xlog_sep = $p_width / 5;
  my $ylog_sep = $p_height / $yparts;
  my $x_sep    = $p_width / 29;


  #*-- draw the line for the xdata1 and ydata1
  my @xpos = my @ypos = ();
  for my $i (0..$#xdata1)
   { $ypos[$i] = $ydisp + $p_height - (&log10($ydata1[$i]) 
                                       * $ylog_sep);
     $ypos[$i] = $ydisp + $p_height if ($ypos[$i] > ($ydisp + $p_height) );
     if ($xtype eq 'Log')
      { $xpos[$i] = $xdisp + (&log10($xdata1[$i]) * $xlog_sep); }
     else
      { $xpos[$i] = $xdisp + $i * $x_sep; }
   }
  
  for my $i (1..$#xpos)
   { $image->line($xpos[$i-1], $ypos[$i-1], $xpos[$i], $ypos[$i], $blue); }

  #*-- draw the line for the xdata2 and ydata2
  @xpos = @ypos = ();
  for my $i (0..$#xdata2)
   { $ypos[$i] = $ydisp + $p_height - (&log10($ydata2[$i]) 
                                       * $ylog_sep);
     $ypos[$i] = $ydisp + $p_height if ($ypos[$i] > ($ydisp + $p_height) );
     if ($xtype eq 'Log')
      { $xpos[$i] = $xdisp + (&log10($xdata2[$i]) * $xlog_sep); }
     else
      { $xpos[$i] = $xdisp + $i * $x_sep; }
   }
  
  for my $i (1..$#xpos)
   { $image->line($xpos[$i-1], $ypos[$i-1], $xpos[$i], $ypos[$i], $red); }

  #*-- draw the box
  $image->line($xdisp, $ydisp, $xdisp, $ydisp + $p_height, $black);
  $image->line($xdisp, $ydisp, $xdisp + $p_width, $ydisp, $black);
  $image->line($xdisp, $ydisp + $p_height, $xdisp + $p_width, 
               $ydisp + $p_height, $black);
  $image->line($xdisp + $p_width, $ydisp, $xdisp + $p_width, 
               $ydisp + $p_height, $black);

  #*-- draw the legend
  $image->line($xdisp + $p_width - 80, $ydisp + 10, 
               $xdisp + $p_width - 70, $ydisp + 10, $blue);
  $image->string(gdSmallFont, $xdisp + $p_width - 60, 
                 $ydisp + 3, "Reuters", $blue);
  $image->line($xdisp + $p_width - 80, $ydisp + 30, 
               $xdisp + $p_width - 70, $ydisp + 30, $red);
  $image->string(gdSmallFont, $xdisp + $p_width - 60, 
                 $ydisp + 23, "Text", $red);

  if (defined($filename))
   { open (OUT, ">", &clean_filename("$filename") ) ||
      quit ("Unable to open $filename $!\n");
     binmode(OUT);
     print OUT $image->png;
     close(OUT); }

  return(0);

 }
