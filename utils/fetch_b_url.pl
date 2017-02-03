#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*-----------------------------------------------------------
 #*- fetch_b_url.pl
 #*-  
 #*-  Input: URL, timeout in seconds, filename to save the
 #*-         HTML, option to get images, option to get html
 #*-         a debug option
 #*-  
 #*-  Output: HTML or HTML in a file or HTML + Images in a dir
 #*-----------------------------------------------------------

 use strict; use warnings;
 use TextMine::MyURL     qw(get_URL get_base parse_HTML clean_link);
 use TextMine::Constants qw($DB_NAME clean_filename fetch_dirname);

 #*-- get the arguments
 our ($url,		#*-- URL 
      $timeout,		#*-- timeout before giving up on fetching URLs
      $filename,	#*-- full name of the file to save the HTML
      $get_html,	#*-- flag to get the HTML
      $get_images,	#*-- flag to get images
      $debug,		#*-- optional debug flag 
      $spi_id		#*-- optional ID of the spider requesting the URL
     );
 
 #*-- fetch the parameters
 ($url, $timeout, $filename, $get_html, $get_images, $debug, $spi_id) =
     split/___/, $ARGV[0];

 #*-- set some variables
 (my $tdir) = &fetch_dirname($filename); 
 my $dfile  = &clean_filename("$tdir/" . time() . "debug.txt");
 
 if ($debug)
  { open (DEBUG, ">", "$dfile") || exit; binmode DEBUG, ":raw"; }

 #*-- create an empty file
 open (OUT, ">", &clean_filename("$filename")) || 
                      &terminate("Unable to open $filename $!\n"); 
 close(OUT);


 #*-- establish a DB connection 
 use TextMine::DbCall;
 our ($dbh, $sth, $command, $db_msg);
 ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
      'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => $DB_NAME);

 #*-- get the HTML for the page
 my ($ref_html, $ref_base);
 if ($get_html)
  {
   my $start_time = time();
   print DEBUG "Fetching ", substr($url,0,50), "....\n" if ($debug);

   ($ref_html, $ref_base) = &get_URL($url, $timeout);

   #*-- check if the page will be refreshed
   #*-- get refreshed page just once
   if ($$ref_html =~ /meta.*?Refresh.*?URL=(.*?)">/i)
   { my $redirect_url = $1;
     unless ($redirect_url =~ /^http:/i) #*-- unless a complete URL
      { $redirect_url = &clean_link(&get_base($url) . '/' . $redirect_url); }
     ($ref_html, $ref_base) = &get_URL($redirect_url, $timeout);
     $url = $redirect_url;
   }

   my $time_elapsed = time() - $start_time;
   print DEBUG "Fetched (" . length($$ref_html) . 
             ") in $time_elapsed secs.\n" if ($debug);
   if ($time_elapsed <= $timeout)
    { open (OUT, ">", &clean_filename("$filename")) || 
                      &terminate("Unable to open $filename $!\n"); 
      #*-- add the rspider tag only for HTML files
      print OUT "<rspider_url src=$url></rspider_url>\n" 
                      if ($filename =~ /html?$/);
      print OUT "$$ref_html\n"; close(OUT); }
   print DEBUG "Saved html for $url. \n" if ($debug);
  }

 exit(0) unless ($get_images =~ /y/i);

 #*-- get the list of images and edit the html file
 #*-- to reflect the new locations of the image files
 our $base = ($ref_base) ? $$ref_base: &get_base($url);
 unless ($$ref_html)
  { open (IN, "<", &clean_filename("$filename")) || 
         &terminate("Unable to open $filename $!\n");
    undef($/); $$ref_html = <IN>; close(IN); }
 (my $ref_text, my $ref_links, my $ref_images) = 
                   &parse_HTML($$ref_html, $base);

 #*-- get each image and save 
 exit(0) unless($ref_images);

 print DEBUG "Extracting images\n" if ($debug);
 my %images = %$ref_images;
 foreach my $image (sort keys %images)
  {
   #*-- make an entry in the common images table 
   #*-- KEY: Remote URL      VALUE: Local URL 
   (my $ref_src, my $local_file) = &ret_image($image);
   if ( length($$ref_src) > 4 )
    { $images{$image} = 'file://localhost/' . $local_file; 
      print DEBUG "Set $image in Images array\n" if ($debug); }
   else
    { delete ($images{$image}); 
      print DEBUG "Deleted $image from Images array\n" if ($debug); }

  } #*-- end of foreach
 $dbh->disconnect_db($sth);

 my $html1 = my $html = $$ref_html; my $quotes = '["\']';
 my %cache_images = ();
 while ( ( $html  =~ m%<\s*img.*?src\s*=\s*        #*-- scan the image tag
                 ($quotes) (.*?) (?:\1) %xsgi) || #*-- for the src
         ( $html1 =~ m%<\s*img.*?src\s*=\s*    
                 ()(.*?) (?:\s|>) %xsgi) )
  { 
   my $oquote = $1 ? $1: ''; my $html_image = my $iname = $2;
   $iname = &clean_link($iname, $base);
   print DEBUG "Found Image: $iname with base $base\n" if ($debug);

   #*-- save the list of images to be replaced
   if ($images{$iname})
    { $cache_images{"$oquote" . "$html_image"     . "$oquote"} = 
                    "$oquote" . "$images{$iname}" . "$oquote";
      print DEBUG "Cached im.".  $cache_images{"$oquote$html_image$oquote"} .
           "\n will replace $oquote$html_image$oquote\n" if ($debug); }
  }

 if ( ( $html =~ m%<\s*body.*?background\s*=\s*   #*-- scan the body tag
                 ($quotes) (.*?) (?:\1) %xsi) || #*-- for the background
      ( $html =~ m%<\s*body.*?background\s*=\s*   #*-- image
                 ()(.*?) (?:\s|>) %xsi) )
  { 
   my $oquote = $1 ? $1: ''; my $html_image = my $iname = $2;
   $iname = &clean_link($iname, $base);
   print DEBUG "Found Image: $iname with base $base for background\n" 
         if ($debug);

   #*-- save the image to be replaced
   if ($images{$iname})
    { $cache_images{"$oquote" . "$html_image"     . "$oquote"} = 
                    "$oquote" . "$images{$iname}" . "$oquote";
      print DEBUG "Cached im.".  $cache_images{"$oquote$html_image$oquote"} .
           "\n will replace $oquote$html_image$oquote\n" if ($debug); }
  }

 #*-- replace the image names
 foreach my $cimage (sort keys %cache_images)
  { my $cache_image = $cache_images{$cimage}; 
    $cimage         = $cimage; 
    print DEBUG "Replacing $cimage with $cache_image\n" if ($debug);
    $html =~ s/$cimage/$cache_image/g; } 

 #*-- rewrite the html for the file
 print DEBUG "Re-writing HTML for the page\n" if ($debug);
 $filename = &clean_filename($filename);
 open (OUT, ">", "$filename") || &terminate("Unable to open $filename $!\n"); 
 print OUT "<rspider_url src=$url></rspider_url>\n";
 print OUT "$html\n";
 close(OUT); close(DEBUG) if ($debug);

 exit(0);

 #*-----------------------------------------------------------------------
 #*- return the image in $ref_src to caller
 #*-----------------------------------------------------------------------
 sub ret_image
 {
  (my $image) = @_;

  #*-- check if the image exists in the database, if so, then
  #*-- set the images array to the URL from the database
  my ($ref_src);
  $dbh->execute_stmt("lock tables sp_images read");
  $command = "select spc_local_file from sp_images where " .
             " spc_remote_url = " . $dbh->quote($image);
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &terminate("Command $command failed: $db_msg") if ($db_msg);
  (my $local_file) = $dbh->fetch_row($sth);
  $dbh->execute_stmt("unlock tables");

  if ($local_file && (-s $local_file) )
   { open (IN, "<", "$local_file") || 
          &terminate("Unable to open $local_file $!\n");
     undef($/); binmode(IN); my $src = <IN>; close(IN); $ref_src = \$src; }
  else
   {
    print DEBUG "Fetching image $image\n" if ($debug);
    ($ref_src) = &get_URL($image);
    print DEBUG "Fetched (" . length($$ref_src) . ") \n" if ($debug);
    (my $suffix) = $image =~ m%\.([^./\\]{2,6})$%;

    #*-- attempt to figure out the image suffix
    unless ($suffix)
     { my $header = substr($$ref_src, 0, 25);
       $suffix = ($header =~ /jfif/i) ? 'jpg':
                 ($header =~ /gif/i) ?  'gif':
                 ($header =~ /png/i) ?  'png': 'unk'; 
     } #*-- end of inner unless
    $local_file =  &clean_filename("$tdir/" . time() . int(rand(1000)) .
                                   ".$suffix");
    print DEBUG "Writing $local_file...\n" if ($debug);
    open (OUT, ">", "$local_file") ||
    &terminate("Unable to open $local_file $!\n"); 
    binmode OUT, ":raw"; print OUT ("$$ref_src\n");
    close(OUT);
    print DEBUG "Finished writing $local_file (" . length($$ref_src) . 
                                      ")...\n" if ($debug);
    #*-- if suffix is unknown or we could not fetch the file
    #*-- , do not make an entry in the images table
    if ( ($suffix !~ /unk/) && ($$ref_src !~ /Cannot fetch http:/i) )
     {
      $dbh->execute_stmt("lock tables sp_images write");
      $command = "replace into sp_images values ($spi_id, " .
        $dbh->quote($local_file) . ", " . $dbh->quote($image) . ") ";
      (undef, $db_msg) = $dbh->execute_stmt($command);
      &quit("Command: $command failed --> $db_msg") if ($db_msg);
      $dbh->execute_stmt("unlock tables");
     } #*-- end if suffix

   } #*-- end of if
  return($ref_src, $local_file);

 }

 #*-----------------------------------------------------------------------
 #*- In case of an error, return with a message if debug is on
 #*-----------------------------------------------------------------------
 sub terminate
 {
  my ($msg) = @_;
  print DEBUG "$msg\n" if ($debug);
  close (DEBUG) if ($debug);
  exit(0);
 } 
