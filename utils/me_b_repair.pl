#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------------------
 #*- me_b_repair.pl
 #*-  
 #*-   1. Read the me_list table and check if the corresponding
 #*-      files exists, if not, save the id and signature
 #*-   2. Look in alternate directories and make the list of files
 #*-      get the signatures of all files with a media suffix
 #*-   3. Check for matching signatures, if found update the index
 #*-
 #*- Options:
 #*-   h - Help
 #*-   c - cleanup, will delete dead links
 #*-   f - fix, will attempt to fix dead links
 #*-   d - debug, show the list of dead links
 #*----------------------------------------------------------------

 #*-- retrieve the parameters
 use strict; use warnings;
 use Digest::MD5 qw(md5_base64);
 use Getopt::Std;
 use File::Find;
 use TextMine::DbCall;
 use TextMine::Index qw(rem_index);
 use TextMine::Constants qw($DB_NAME @MFILE_TYPES 
               clean_filename fetch_dirname); 

 #*-- global variables
 our ($media_reg,	#*-- RE for media types
      $dbh,		#*-- database handle
      $sth,		#*-- statement handle
      $command,		#*-- variable for SQL command
      $stat_msg,	#*-- status message
      $db_msg,		#*-- database error message
      @DIRS,		#*-- list of dirs. to search for files 
      %files, 		#*-- hash of file names
      %mfile, 		#*-- hash of missing file names
      %msignature, 	#*-- hash of signatures for missing file names
      %opt		#*-- passed options
     );

 #*-- get a database connection
 ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
      'Userid' => 'tmadmin', 'Password' => 'tmpass',
      'Dbname' => $DB_NAME);
 &quit("Connect failure: $db_msg") if ($db_msg);

 #*-- build the list of missing files in the index
 &build_missing();

 #*-- get the file list for the specified directories in @DIRS
 &get_file_list();

 #*-- check for matching file names and fix the index
 &fix_index();

 $dbh->disconnect_db($sth);
 print "Status:\n$stat_msg\n";

 exit(0);

 #*----------------------------------------------------------
 #*- Build the list of missing files and assoc. signatures
 #*----------------------------------------------------------
 sub build_missing
 {
  local $" = '|'; $media_reg = qr/\.(?:@MFILE_TYPES)$/i; local $" = ' ';

  #*-- parse the arguments
  getopt('vchd', \%opt);    
  if ($opt{h})
   { print "Usage: me_b_repair.pl [-help -verbose -cleanup -debug -fix]\n"     .
     "\t The cleanup option will remove invalid entries from the index\n" . 
     "\t The verbose option will print statements to track index repair\n".
     "\t The fix option will attempt to repair the index \n".
     "\t The debug option show dead links but will not corrent the index\n";
     exit(0);
   }
  
  #*-- build the @DIRS array
  my $inline = '';
  while ($inline = <DATA>) { chomp($inline); push (@DIRS, $inline); } 
  $stat_msg = '';

  #*-- build the list of missing files and assoc. signatures
  %mfile = %msignature = ();
  my ($lii_id, $lic_file, $lic_signature);
  $command = "select lii_id, lic_file, lic_signature from me_list";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command $command failed: $db_msg") if ($db_msg);
  
  print ("Building list of missing files...\n") if ($opt{v});
  while (($lii_id, $lic_file, $lic_signature) = $dbh->fetch_row($sth) )
   { unless (-f $lic_file) 
      { $lic_file = (&fetch_dirname($lic_file))[1]; #*-- save filename alone 
        print ("Missing file: $lic_file...\n") if ($opt{v});
        $mfile{$lic_file} = $lii_id; 
        $msignature{$lic_file} = $lic_signature; }
   }

 }

 #*----------------------------------------------------------
 #*- Look in alternate directories and make the list of files
 #*----------------------------------------------------------
 sub get_file_list
 {
   #*-- get the files from the input directory
   my @t_files = (); my $i = 1;
   foreach my $DIR (@DIRS)
    { find sub { $t_files[$i++] = $File::Find::name
              if ($File::Find::name =~ m%$media_reg%i) }, "$DIR"; 
      print ("Looking for media files in $DIR\n") if ($opt{v}); }
   
   #*-- clean up t_files, use the filename to check if it has
   #*-- been moved to another directory
   %files = ();
   foreach my $path (@t_files)
    { next unless ($path); $path = &clean_filename($path); 
      my $filename = (&fetch_dirname($path))[1]; 
      $files{$filename} = $path; }
 }

 #*--------------------------------------------------
 #*- Check if the files match and update the index 
 #*- keys for mfiles and files arrays is the filename
 #*- alone without the directory
 #*--------------------------------------------------
 sub fix_index
 {

  #*-- remove dead links from the index to cleanup
  if ($opt{c})
   {
    foreach my $file (keys %mfile)
     {
      $command = "select lic_description from me_list where " .
                   "lii_id = $mfile{$file}";
      ($sth, $db_msg) = $dbh->execute_stmt($command);
      &quit("Command $command failed: $db_msg") if ($db_msg);
      (my $descr) = $dbh->fetch_row($sth);

      #*-- remove from the index and the table
      $stat_msg .= &rem_index($mfile{$file}, $descr, 'me', $dbh);
      $command = "delete from me_list where lii_id = $mfile{$file}";
      (undef, $db_msg) = $dbh->execute_stmt($command);
      &quit("Command $command failed: $db_msg") if ($db_msg);
      print ("Removed index entries for: $file\n") if ($opt{v});
     }
    return(0);
   }

  #*-- print the list of dead links from the index
  if ($opt{d})
   {
    foreach my $file (keys %mfile)
     {
      $command = "select lic_description, lic_file from me_list where " .
                   "lii_id = $mfile{$file}";
      ($sth, $db_msg) = $dbh->execute_stmt($command);
      &quit("Command $command failed: $db_msg") if ($db_msg);
      (my $descr, my $lic_file) = $dbh->fetch_row($sth);
      print ("$lic_file for $descr not found\n");
      print ("Found a matching file $file\n") if ($files{$file});
     }
    return(0);
   }

  #*-- try and resolve the dead link problem
  foreach my $file (keys %mfile)
   {
    #*-- if there is a matching file in the index
    if ($files{$file})
     {
      print ("Found a matching file: $file\n") if ($opt{v});
      $stat_msg .= "Match File: $file\t";

      #*-- get the signature of the file and check if it matches
      undef($/);
      unless (open (IN, "<", &clean_filename("$files{$file}")) )
       { $stat_msg .= "Could not open $files{$file} $!\n"; next; };
      binmode(IN); my $file_source = <IN>; close(IN);

      #*-- compute the signature and update the table for a match
      my $digest = md5_base64($file_source);
      if ($digest ne $msignature{$file})
        { $stat_msg .= "signatures did not match\n"; 
          print ("Did not fix index for: $files{$file}\n") if ($opt{v}); }
      else 
        { #*-- update the index for a matching file
          $command = "update me_list set lic_file = " . 
          $dbh->quote($files{$file}) . " where lii_id = $mfile{$file}"; 
          (undef, $db_msg) = $dbh->execute_stmt($command);
          $stat_msg .= ($db_msg) ?
             "Command: $command failed --> $db_msg\n":
             "Fixed index for: $file\n" ; }
     }
    else
     { print ("Did not find a matching file for: $file\n") if ($opt{v}); } 
    #*-- end of if

   } #*-- end of foreach

 }

 #*------------------------------
 #*- Exit if there is a problem  
 #*------------------------------
 sub quit
 {
  print ("Msg: $_[0]\n");
  print ("$stat_msg\n");
  exit(0);
 }

#*-- list of directories to search for files

__DATA__
D:\images
 Exit if there is a problem  
 #*------------------------------
 sub quit
 {
  print ("Msg: $_[0]\n");
  print ("$stat_msg\n");
  exit(0);
 }

#*-- list of directories to search for files

__DATA__
/tmp/images
