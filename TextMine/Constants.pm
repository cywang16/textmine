
 #*--------------------------------------------------------------------------
 #*- Constants.pm						
 #*-
 #*- A list of constants used in the TextMine modules. This file
 #*- is modified by configure.pl.
 #*--------------------------------------------------------------------------

 package TextMine::Constants;

 use strict; use warnings;
 use lib qw/../;
 use Config;
 use File::Spec::Functions;
 require Exporter;
 our @ISA = qw(Exporter);
 our @EXPORT = qw(
     $OSNAME    $ROOT_DIR $CGI_DIR  $ICON_DIR $TMP_DIR
     $UTILS_DIR $DB_HOST $DB_NAME  $PERL_EXE $DELIM $SDELIM    $ISEP     $EQUAL   MAXDATA
     &clean_filename &fetch_dirname);

 our @EXPORT_OK = qw(
     MONTH_NUMBER MONTH_NAME   FMONTH_NAME  $PACK_DIR    $PROXY       
     $PAJEK_EXE   $POD2TEXT    $PPM_DIR     $LSI_DIR     $WEB_DIR  
     @MFILE_TYPES @AUDIO_TYPES @IMAGE_TYPES @VIDEO_TYPES @DOC_TYPES 
     @QWORDS      @ETYPES      @QTYPES      @SCHEMES     PI_CONSTANT  
     E_CONSTANT   WEEK_DAYS    MONTH_DAYS);

 #*-- TextMine global vars
 our ($OSNAME, 		#*-- operating system 'nix' or 'win'
      $PERL_EXE,	#*-- path to Perl executable
      $PAJEK_EXE,	#*-- optional path to Pajek executable 
      $ROOT_DIR,	#*-- full path to root directory for TextMine
      $WEB_DIR,		#*-- full path to web root directory
      $TMP_DIR, 	#*-- full path to a temp. directory for TextMine
      $UTILS_DIR,	#*-- full path to the batch utilities scripts
      $CGI_DIR,		#*-- web path to CGI scripts
      $PACK_DIR,	#*-- full path to top level dir. for TextMine packages
      $PPM_DIR,		#*-- optional path to the PPM dir. of Active Perl
      $ICON_DIR,	#*-- web path to icons dir. for TextMine
      $LSI_DIR,		#*-- full path to the LSI dir. 
      $DB_HOST,		#*-- name of the database host(mysql)
      $DB_NAME,		#*-- name of the TextMine database (tm)
      $PROXY,		#*-- optional proxy server name 
      @MFILE_TYPES,	#*-- all media file types
      @AUDIO_TYPES,	#*-- audio file types
      @IMAGE_TYPES,	#*-- image file types
      @VIDEO_TYPES,	#*-- video file types
      @DOC_TYPES,	#*-- formatted document file types
      @QTYPES,		#*-- types of questions
      @QWORDS,		#*-- types of question words 
      @ETYPES,		#*-- types of entities 
      @SCHEMES,		#*-- list of scheme names for URLs
      $DELIM,		#*-- delimiter for general data
      $SDELIM,		#*-- delimiter for session data
      $ISEP,		#*-- a separator for keys and values
      $EQUAL,		#*-- a separator for session keys and values
      $POD2TEXT,	#*-- full path to the pod2text converter 
      );

 #*-- set the constants     
 BEGIN 
  { 

   die ("A version of Perl 5 or later  is necessary to run the script\n")
               if ( ($] =~ /^(\d+)\./) && ($1 < 5) );

   #*-- enter dir. names, add a trailing / for directories
   $OSNAME   = ($Config{'osname'} =~ /win/i) ? "win": "nix";
   $ROOT_DIR  = '/mnt/shares/';	#*-- top level dir.
   $WEB_DIR  = '/usr/src/myapp/web/';	#*-- web root dir.
   $CGI_DIR  = '/cgi-bin/tm/';	#*-- cgi scripts
   $PACK_DIR  = '/mnt/shares/';	#*-- package dir.
   $UTILS_DIR  = '/mnt/shares/utils/';	#*-- utilities dir.
   $LSI_DIR  = '/mnt/shares/lsi/';	#*-- lsi dir.
   $TMP_DIR  = '/mnt/shares/tmp/';	#*-- temporary dir.
   $ICON_DIR  = '/icons/tm/';	#*-- icon dir.

   #*-- optional fields that maybe changed
   $DB_HOST  = 'mysql';                    #*-- database host name
   $DB_NAME  = 'tm';                    #*-- database name
   $PROXY    = '';		        #*-- URL for proxy server 
   $PPM_DIR  = '/';	#*-- ppm dir.
   $PAJEK_EXE =  'D:/Program Files/Pajek/Pajek.exe';

   $PERL_EXE   = $Config{'perlpath'};     #*-- path for perl executable
   ($POD2TEXT  = $Config{'bin'}) .= ($OSNAME eq 'win') ? '\\pod2text.bat':
                                                        '/pod2text';

   #*-- delimiters
   $DELIM  = "___"; #*-- delimiter for general data
   $SDELIM = "_!_"; #*-- delimiter for session data
   $ISEP   = "!!!"; #*-- separator for data
   $EQUAL  = '###'; #*-- key and value separator for session data

   #*-- media type constants
   @IMAGE_TYPES = qw/jpg jpeg gif png/;
   @AUDIO_TYPES = qw/au ra mp3 wav midi mid/;
   @VIDEO_TYPES = qw/ram/;
   @DOC_TYPES   = qw/pdf ps doc xls ppt htm html pl pm/;
   @MFILE_TYPES = (@IMAGE_TYPES, @AUDIO_TYPES, @VIDEO_TYPES, @DOC_TYPES);
   @SCHEMES = qw/data file gopher http ldap mailto news nntp pop
                 rlogin rtsp rtspu rsync snews telnet ssh urn/;

   #*-- exported constants and vars
   use constant MAXDATA    => 131072; # maximum bytes to accept via POST
   use constant E_CONSTANT => 2.7182818284; #*-- the constant e
   use constant PI_CONSTANT => 3.1415926535; #*-- the pi constant

   #*-- question and entity types
   @QWORDS = qw/Name How What When Where Which Who Why/;
   @ETYPES = qw/currency dimension miscellaneous number 
                org person place time tech/;
   @QTYPES = qw/currency dimension miscellaneous
                org person place time/;

   #*-- calendar related constants

   #*-- xref table for month name to number
   use constant MONTH_NUMBER => { 'jan'=> '0', 'feb'=> '1', 'mar'=> '2', 
    'apr'=> '3', 'may'=> '4', 'jun'=> '5', 'jul'=> '6', 'aug'=> '7', 
    'sep'=> '8', 'oct'=> '9', 'nov'=> '10', 'dec'=> '11' };

   #*-- xref table for month number to name
   use constant MONTH_NAME => {'0' => 'jan', '1' => 'feb', '2' => 'mar', 
    '3'  => 'apr', '4' => 'may', '5' => 'jun', '6' => 'jul', '7'  => 'aug',
    '8' => 'sep', '9' => 'oct', '10' => 'nov', '11' => 'dec'};

   #*-- xref table for month number to full name
   use constant FMONTH_NAME => {'0' => 'january', '1' => 'february', 
    '2' => 'march', '3'  => 'april', '4' => 'may', '5' => 'june', 
    '6' => 'july', '7'  => 'august', '8' => 'september', 
    '9' => 'october', '10' => 'november', '11' => 'december'};

   #*-- xref table for days in a month, leap year handled in code
   use constant MONTH_DAYS => { 'jan'=> '31', 'feb'=> '28', 'mar'=> '31',
    'apr'=> '30', 'may'=> '31', 'jun'=> '30', 'jul'=> '31', 'aug'=> '31', 
    'sep'=> '30', 'oct'=> '31', 'nov'=> '30', 'dec'=> '31' };

   #*-- xref table for number to week day
   use constant WEEK_DAYS  => {'0'=> 'Sunday', '1'=> 'Monday', '2'=> 'Tuesday',
    '3'=> 'Wednesday','4'=> 'Thursday','5'=> 'Friday', '6'=> 'Saturday' };

  }


 #*------------------------------------------------------------------
 #*- clean_filename
 #*- Description: Return a path and filename for the platform
 #*------------------------------------------------------------------
 sub clean_filename
 { (my $infile) = @_;
   (my $volume, my $dirs, my $filename) = File::Spec->splitpath($infile);
   return ($dirs) ? File::Spec->catfile($volume, $dirs, $filename): 
                    $filename;
 }

 #*------------------------------------------------------------------
 #*- fetch_dirname
 #*- Description: Return the directory for a filename
 #*------------------------------------------------------------------
 sub fetch_dirname
 { (my $infile) = @_;
   (my $volume, my $dirs, my $filename) = File::Spec->splitpath($infile);
   return ($dirs)? (File::Spec->catfile($volume, $dirs, ''), $filename):
                   ('', $filename);
 }

1;

=head1 NAME

Constants - TextMine Constants

=head1 SYNOPSIS

use TextMine::Constants;

=head1 DESCRIPTION

  Contains a list of constants used by various TextMine modules
  including directory names, media types, delimiters, and date constants

=head1 AUTHOR

Manu Konchady <mkonchady@yahoo.com>
 and date constants

=head1 AUTHOR

Manu Konchady <mkonchady@yahoo.com>
