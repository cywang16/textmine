#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------------------
 #*- me_b_index.pl
 #*-  
 #*-   Summary: Index the files in directories in batch
 #*-
 #*-   1. Read the input parameters                
 #*-   2. Recursively collect all files from the input directory
 #*-      and save the list.
 #*-   3. Process the files one at a time 
 #*-   4. Print a status message at the bottom of the page
 #*-
 #*----------------------------------------------------------------

 #*-- retrieve the parameters
 use strict; use warnings;
 use Digest::MD5 qw(md5_base64);
 use File::Find;
 use Pod::Text;
 use Time::Local;
 use TextMine::DbCall;
 use TextMine::MyURL qw(parse_HTML);
 use TextMine::Index qw(add_index parse_file);
 use TextMine::Constants qw($DB_NAME $POD2TEXT @MFILE_TYPES @AUDIO_TYPES 
     @IMAGE_TYPES @VIDEO_TYPES @DOC_TYPES $OSNAME
     clean_filename fetch_dirname); 

 #*-- global variables
 our ($sth,		#*-- statement handle
      $dbh,		#*-- database handle
      $db_msg,		#*-- database error message
      $stat_msg, 	#*-- status message 
			#*-- REs for media files
      $media_reg, $image_reg, $audio_reg, $doc_reg, $video_reg
     );

 #*-- retrieve passed parameters and set variables
 &set_vars();

 #*-- locate the file based on options
 &file_locater();

 &quit('');

 exit(0);

 #*-------------------------------------------------------
 #*- Set some global vars 
 #*-------------------------------------------------------
 sub set_vars
 {
  print "Started Batch index\n";
  $stat_msg = '';

  #*-- build REs for the media types
  local $" = '|';
  $media_reg = qr/\.(?:@MFILE_TYPES)$/i;
  $doc_reg   = qr/\.(?:@DOC_TYPES)$/i;
  $image_reg = qr/\.(?:@IMAGE_TYPES)$/i;
  $audio_reg = qr/\.(?:@AUDIO_TYPES)$/i;
  $video_reg = qr/\.(?:@VIDEO_TYPES)$/i;
  local $" = ' ';

  #*-- establish a DB connection
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
     'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => $DB_NAME);
  &quit("Connect failure: $db_msg") if ($db_msg);

 }

 #*---------------------------------------------------------------
 #*- Build a list of files that have not been indexed and add
 #*- them to the index
 #*---------------------------------------------------------------
 sub file_locater
 {
   my ($descr, $ret_val);

   my @t_files = ();
   while (my $idir = <DATA>) 
    { #*-- get the files from the input directories
      chomp($idir); 
      print "Started processing $idir\n";
      find sub { push (@t_files, $File::Find::name)  
              if ($File::Find::name =~ m%$media_reg%i) }, $idir;
    }

   #*-- keep files that have not been indexed in the @files array
   my @files = (); 
   foreach my $file (@t_files)
    { 
     #*-- fetch files which have not been indexed
     next unless($file);
     $file = &clean_filename($file); my $q_file = $dbh->quote($file);
     my $command = "select lii_id from me_list where lic_file = $q_file"; 
     ($sth, $db_msg) = $dbh->execute_stmt($command);
     &quit("Command: $command failed --> $db_msg") if ($db_msg);
     push (@files, $file) unless ( ($dbh->fetch_row($sth))[0] );
    }

   #*-- quit, if no files were found in the directory
   &quit("No new files were found in directories") unless (@files);

   #*-- process each file 
   undef($/); 
   foreach my $file (@files)
    {
     print "Started processing $file....\n";
     open(IN, "<", &clean_filename("$file")) or 
         &quit("Unable to open file $file -- $!\n");
     binmode(IN); my $file_source = <IN>; 
     close(IN);
     my $digest = md5_base64($file_source);
 
     #*-- check if a copy of the file has been indexed in the DB
     #*-- i.e., a file with the same signature
     my $command  = "select count(*) from me_list where lic_signature = ";
     $command .= $dbh->quote($digest);
     ($sth, $db_msg) = $dbh->execute_stmt($command);
     &quit("Command: $command failed --> $db_msg") if ($db_msg);
     next if ( ($dbh->fetch_row($sth))[0] );

     #*-- check if we have a filter for the file types
     (my $suffix) = $file =~ /\.(.*)$/;

     #*-- accepted file types 
     my @FTYPES   = qw/htm html txt pl pm jpg jpeg gif png/; 
     local $" = '|'; my $doc_reg = qr/(?:@FTYPES)$/i; local $" = ' ';
     next unless ($suffix =~ /$doc_reg/);
     
     #*-- convert html to text
     if ($suffix =~ /htm/i)
      { ($ret_val) = &parse_HTML($file_source, ''); 
         $descr = $$ret_val; } 

     #*-- no conversion necessary for txt files
     elsif ($suffix =~ /txt/i)
      { $descr = $file_source; }
     
     #*-- convert pod to text
     elsif ($suffix =~ /^(?:pl|pm)/i)
      {
       my $parser = Pod::Text->new (sentence => 0, width => 80);
       open IN, "-|", "$POD2TEXT $file" or die "Unable to open pipe $!\n";
       my @data = <IN>; close(IN); $descr = "@data";
      }

     #*-- otherwise, assign a default description
     else
      { $descr = &parse_file($file); }

     #*-- build the insert statement
     my $mdate =  (stat $file)[9];

     #*-- insert in the files table
     $command  = "insert into me_list values (0, " . (stat $file)[9] . ", "
       . $dbh->quote($file)   . ", " . $dbh->quote($descr) . ", " 
       . $dbh->quote($digest) . ")";
     ($sth, $db_msg) = $dbh->execute_stmt($command);
     &quit("Command: $command failed --> $db_msg") if ($db_msg);
     my $id = $dbh->last_id();
     $stat_msg .= &add_index($id, $descr, 'me', $dbh);
     print "Finished processing $file....\n";

    } #*-- end of for

 }

 #*---------------------------------------------------------------
 #*- Exit with a message            
 #*---------------------------------------------------------------
 sub quit
 {
  $dbh->disconnect_db($sth);
  print ("$_[0]" . "\n$stat_msg"); 
  print "Ended Batch index\n";
  exit(0);
 }

#*-- specify the name of the directory to scan below, omit trailing slash
__DATA__
/tmp/images
