
 #*--------------------------------------------------------------------
 #*- configure.pl
 #*-   Configure the directory names in Constants.pm
 #*--------------------------------------------------------------------
 use strict; use warnings;
 use Config;

 #*-- build a hash with the directory names
 my %dnames = (); my $inline;

 print << "EOD";

  *-------------------------------------------------------*
  *- I N S T A L L A T I O N   O F   T E X T  M I N E     
  *-                                                     
  *- You will need the names of the
  *-                                                     
  *- a) the installation directory for Text Mine     
  *-
  *- b) the web root directory 
  *-
  *- The PPM packages is an optional directory. It is
  *- used by ActiveState Perl to find and load Perl modules.  
  *- If you don't use ActiveState Perl, you can ignore this
  *- directory and use the CPAN module to load modules.
  *- You may need to be root to install Perl modules.
  *-
  *- NOTE: USE THE BACKSLASH (/) for directory paths
  *-
  *-------------------------------------------------------*
EOD
 print ("Continue installation (Y/N): ");
 exit(0) if ( ($inline = <STDIN>) =~ /n/i);
 print "\n";

 #*-- get the root directory
 $dnames{'ROOT_DIR'} = ($ENV{'PWD'}) ? $ENV{'PWD'} : '.';
 print "This is the top level directory where Text Mine\n" .
       "will be installed\n\n";
 print "Full path of the root installation dir. ($dnames{'ROOT_DIR'}): ";
 $inline = <STDIN>; chomp($inline);
 $dnames{'ROOT_DIR'} = $inline if ($inline =~ /\S/);
 $dnames{'ROOT_DIR'} .= '/' if ($dnames{'ROOT_DIR'} !~ m%/$%);

 #*-- get the web directory
 print "\nThis is the top level directory for the web server\n" .
       "e.g. on Linux, the default would be /var/www\n" .
       " and on Windows, the default would be " .
       " C:/Program Files/Apache Group/Apache2 \n\n";
 $dnames{'WEB_DIR'} = ' ';
 print "Full path to the top level web server dir. ($dnames{'WEB_DIR'}): ";
 $inline = <STDIN>; chomp($inline);
 $dnames{'WEB_DIR'} = $inline if ($inline =~ /\S/);
 $dnames{'WEB_DIR'} .= '/' if ($dnames{'WEB_DIR'} !~ m%/$%);

 #*-- get the cgi directory
 print "\nThis is the cgi-bin directory for the Text Mine cgi scripts \n" .
       "It is a relative directory path that is appended \n" .
       "to the web server host name in an URL\n\n"; 
 $dnames{'CGI_DIR'} = '/cgi-bin/tm';
 print "URL path to the Text Mine CGI scripts dir. ($dnames{'CGI_DIR'}): ";
 $inline = <STDIN>; chomp($inline);
 $dnames{'CGI_DIR'} = $inline if ($inline =~ /\S/);
 $dnames{'CGI_DIR'} .= '/' if ($dnames{'CGI_DIR'} !~ m%/$%);

 #*-- get the icons directory
 print "\nThis is the icons directory for the Text Mine scripts \n" .
       "It is a relative directory path that is appended \n" .
       "to the web server host name in an URL\n\n"; 
 $dnames{'ICON_DIR'} = '/icons/tm';
 print "Relative path to the Text Mine icons dir. ($dnames{'ICON_DIR'}): ";
 $inline = <STDIN>; chomp($inline);
 $dnames{'ICON_DIR'} = $inline if ($inline =~ /\S/);
 $dnames{'ICON_DIR'} .= '/' if ($dnames{'ICON_DIR'} !~ m%/$%);

 #*-- set the package directory
 $dnames{'PACK_DIR'} = $dnames{'ROOT_DIR'};
 $dnames{'PACK_DIR'} .= '/' if ($dnames{'PACK_DIR'} !~ m%/$%);

 #*-- set the utilities directory
 $dnames{'UTILS_DIR'} = $dnames{'ROOT_DIR'} . 'utils/';
 $dnames{'UTILS_DIR'} .= '/' if ($dnames{'UTILS_DIR'} !~ m%/$%);

 #*-- set the lsi directory
 $dnames{'LSI_DIR'} = $dnames{'ROOT_DIR'} . 'lsi/';
 $dnames{'LSI_DIR'} .= '/' if ($dnames{'LSI_DIR'} !~ m%/$%);

 #*-- set the temporary directory
 $dnames{'TMP_DIR'} = $dnames{'ROOT_DIR'} . 'tmp/';
 $dnames{'TMP_DIR'} .= '/' if ($dnames{'TMP_DIR'} !~ m%/$%);

 #*-- get the PPM directory
 print "\nThis is an optional directory to the ActiveState Perl " .
        " PPM packages\n\n";
 $dnames{'PPM_DIR'} = '';
 print "Full path to the PPM Directory (for ActivePerl): ";
 $inline = <STDIN>; chomp($inline);
 $dnames{'PPM_DIR'} = $inline if ($inline =~ /\S/);
 $dnames{'PPM_DIR'} .= '/' if ($dnames{'PPM_DIR'} !~ m%/$%);
 
 #*-- update the original constants.pm
 print ("Update Constants.pm (Y/N): ");
 exit(0) if ( ($inline = <STDIN>) =~ /n/i);

 open (IN, "+<TextMine/Constants.pm") or 
       die ("Could not open Constants.pm $!\n");
 binmode(IN, ":raw");
 my @lines = <IN>;

 #*-- replace some of the lines
 for my $i (0..$#lines)
 {

 $lines[$i] = '   $ROOT_DIR  = \'' . "$dnames{'ROOT_DIR'}\';" .
              "\t#*-- top level dir.\n"
       if ($lines[$i] =~ /^\s+\$ROOT_DIR\s+=/);
 $lines[$i] = '   $WEB_DIR  = \'' . "$dnames{'WEB_DIR'}\';" .
              "\t#*-- web root dir.\n"
       if ($lines[$i] =~ /^\s+\$WEB_DIR\s+=/);
 $lines[$i] = '   $CGI_DIR  = \'' . "$dnames{'CGI_DIR'}\';" .
              "\t#*-- cgi scripts\n"
       if ($lines[$i] =~ /^\s+\$CGI_DIR\s+=/);
 $lines[$i] = '   $PACK_DIR  = \'' . "$dnames{'PACK_DIR'}\';" .
              "\t#*-- package dir.\n"
       if ($lines[$i] =~ /^\s+\$PACK_DIR\s+=/);
 $lines[$i] = '   $UTILS_DIR  = \'' . "$dnames{'UTILS_DIR'}\';" .
              "\t#*-- utilities dir.\n"
       if ($lines[$i] =~ /^\s+\$UTILS_DIR\s+=/);
 $lines[$i] = '   $LSI_DIR  = \'' . "$dnames{'LSI_DIR'}\';" .
              "\t#*-- lsi dir.\n"
       if ($lines[$i] =~ /^\s+\$LSI_DIR\s+=/);
 $lines[$i] = '   $TMP_DIR  = \'' . "$dnames{'TMP_DIR'}\';" .
              "\t#*-- temporary dir.\n"
       if ($lines[$i] =~ /^\s+\$TMP_DIR\s+=/);
 $lines[$i] = '   $ICON_DIR  = \'' . "$dnames{'ICON_DIR'}\';" .
              "\t#*-- icon dir.\n"
       if ($lines[$i] =~ /^\s+\$ICON_DIR\s+=/);
 $lines[$i] = '   $PPM_DIR  = \'' . "$dnames{'PPM_DIR'}\';" .
              "\t#*-- ppm dir.\n"
       if ($lines[$i] =~ /^\s+\$PPM_DIR\s+=/);

 }

 #*-- rewrite the constants.pm file
 seek (IN, 0, 0);
 print IN @lines;
 close(IN);

 print "Created an updated Constants.pm in Text Mine\n";

 print ("Fixing the first line of cgi perl scripts...\n");
 &fix_files();
 print ("Finished fixing the first line of cgi perl scripts...\n");

 exit(0);

 #*----------------------------------------------------
 #*- fix the interpreter for multiple directories 
 #*----------------------------------------------------
 sub fix_files
 {
  my @DIRS = qw% ./t ./cgi-bin ./utils ./utils/data ./tools/pos ./tools/quanda
              ./tools/reuters ./tools/wordnet ./tools/wordnet/misc %;
  foreach (@DIRS) { &fix_interpreter("mod", $_); }
 }

 #*----------------------------------------------------
 #*- add the interpreter line to the top of the file
 #*----------------------------------------------------
 sub fix_interpreter
 {
  my ($function, $dir) = @_;

  #*-- build the replacement line with the path for the Perl binary
  #*-- and the package directory
  my $rline = '#!' . $Config{'perlpath'} . 
              "\n use lib (\"$dnames{'PACK_DIR'}\");\n";

  #*-- get the list of perl scripts in the directory
  opendir DIR, $dir || die "Could not open $dir directory $!\n";
  my @pfiles = sort grep { /\.pl$/i } map {"$dir/$_"} readdir DIR;
  closedir DIR;

  foreach my $file (@pfiles)
  {

   next if ($file =~ /(configure.pl|setup.pl|load_mod.pl|install.pl)/);
   open (IN, "<", $file) || die ("Could not open file $file $!\n");
   my $inline = <IN>; close(IN);

   #*-- skip files which are OK
   next if ( ($function eq 'add') && ($inline =~ /^#!/) );
   next if ( ($function eq 'rem') && ($inline !~ /^#!/) );

   open (IN, "+<", $file) || die ("Could not open file $file $!\n");
   my @lines = <IN>;

   #*-- add the replacement line and print
   if ($function eq 'add')
    { unshift @lines, $rline; 
      seek(IN, 0, 0); print IN (@lines); truncate(IN, tell(IN)); }

   if ($function eq 'mod')
    { shift @lines if ($lines[0] =~ /^#!/);
      shift @lines if ($lines[0] =~ /^\s+use\s+lib/);
      unshift @lines, $rline; 
      seek(IN, 0, 0); print IN (@lines); truncate(IN, tell(IN)); }

   if ($function eq 'rem')
    { shift @lines if ($lines[0] =~ /^#!/);
      shift @lines if ($lines[0] =~ /^\s+use\s+lib/);
      seek(IN, 0, 0); print IN (@lines); truncate(IN, tell(IN)); }
   close(IN);
  }
 }
