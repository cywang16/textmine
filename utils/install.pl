
 use lib qw/../;

 #*-----------------------------------------------------------
 #*- install.pl
 #*-   Create files in directories              
 #*-----------------------------------------------------------
 use strict; use warnings;
 use File::Copy;
 use File::Path;
 use Cwd;
 use lib qw%..%;
 use TextMine::Constants qw/$ROOT_DIR $WEB_DIR $CGI_DIR $ICON_DIR
                            $UTILS_DIR $PACK_DIR $LSI_DIR/;

 #*-- copy the CGI perl scripts 
 my $CURR_DIR = getcwd(); $CURR_DIR .= '/' unless ($CURR_DIR =~ m%/$%);
 print "Copying the CGI perl scripts.....\n";
 &cfile($CURR_DIR . 'cgi-bin/', $WEB_DIR . $CGI_DIR, '*');

 #*-- copy the icons
 print "Copying the icons.....\n";
 &cfile($CURR_DIR . 'icons/tm/', $WEB_DIR . $ICON_DIR, 'jpg');

 #*-- check if the root dir and the current dir are different
 #*-- then copy files 
 print "Copying files to the root directory\n";
 if ($ROOT_DIR ne $CURR_DIR)
  {
   &cfile($CURR_DIR, $ROOT_DIR, '*');
   &cfile($CURR_DIR . 'utils',              $UTILS_DIR, '*');
   &cfile($CURR_DIR . 'utils/data',         $UTILS_DIR . 'data', '*');
   &cfile($CURR_DIR . 'lsi',                $LSI_DIR, '*');
   &cfile($CURR_DIR . 't',                  $ROOT_DIR . 't', '*');
   &cfile($CURR_DIR . 'tmp',                $ROOT_DIR . 'tmp', '*');
   &cfile($CURR_DIR . 'TextMine',           $PACK_DIR . 'TextMine', '*');
   &cfile($CURR_DIR . 'docs',               $ROOT_DIR . 'docs', '*');
   &cfile($CURR_DIR . 'docs/html',          $ROOT_DIR . 'docs/html', '*');
   &cfile($CURR_DIR . 'docs/html/images',   $ROOT_DIR . 'docs/html/images','*');
   &cfile($CURR_DIR . 'tools/pos',          $ROOT_DIR . 'tools/pos', '*');
   &cfile($CURR_DIR . 'tools/quanda',       $ROOT_DIR . 'tools/quanda', '*');
   &cfile($CURR_DIR . 'tools/reuters',      $ROOT_DIR . 'tools/reuters', '*');
   &cfile($CURR_DIR . 'tools/wordnet',      $ROOT_DIR . 'tools/wordnet', '*');
   &cfile($CURR_DIR . 'tools/wordnet/misc', $ROOT_DIR . 'tools/wordnet/misc', '*');
  }

 print "Finished copying files\n";

 exit(0);

 #*-----------------------------------------------------------
 #*- copy files from one directory to another
 #*- parameters: from directory, to directory, and file type
 #*-----------------------------------------------------------
 sub cfile
 {
  my ($from_dir, $to_dir, $ftype) = @_;

  #*-- from directory must exist
  return unless (-d $from_dir);
  $ftype = ($ftype eq '*') ? '.': '\\.' . $ftype . '$';

  #*-- create the to directory, if necessary
  mkpath ($to_dir, 0, 0755) unless (-d $to_dir);
  $to_dir   .= '/' if ($to_dir   !~ m%/$%);
  $from_dir .= '/' if ($from_dir !~ m%/$%);

  #*-- build a list of files to copy
  my @files = (); my $file;
  opendir (DIR, $from_dir) || return;
  while ($file = readdir DIR)
   {
     next if (-d $from_dir . $file);
     next if ( ($file =~ /^\./) || ($file !~/$ftype$/) );
     push (@files, $file); }
  closedir DIR;

  foreach my $file (@files)
   { my $f_file = $from_dir . $file; my $t_file = $to_dir   . $file;
     copy($f_file, $t_file);
     chmod 0755, $t_file if ($t_file =~ /\.(pl|pm)$/); }

 }
