#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------------------
 #*- compile.pl
 #*-  
 #*- Summary: Compile scripts in the cgi-bin, TextMine, and util dirs
 #*----------------------------------------------------------------
 use strict; use warnings;
 use TextMine::Constants qw/$WEB_DIR $CGI_DIR $ROOT_DIR $PERL_EXE/;
 use TextMine::Utils;
 use Cwd;

 print ("Started compile.pl\n");

 #*-- get the collection of directories
 my @dirs = my @suffix = ();
 while (my $line = <DATA>)
  {
   my ($dir, $suffix) = $line =~ /^(.*?)\s(..)/;
   push (@dirs, "$ROOT_DIR$dir"); push (@suffix, $suffix); 
  }

 #*-- add the CGI directory
 push (@dirs, $WEB_DIR . '.' . $CGI_DIR); push (@suffix, 'pl');

 for my $i (0..$#dirs)
  {
   chdir $dirs[$i];
   opendir (DIR, $dirs[$i]) || die ("Could not open $dirs[$i] $!\n");
   while ( (my $file = readdir(DIR) ) )
    {
     next unless ($file =~ /\.$suffix[$i]$/);
     $file = "\"$dirs[$i]/$file\"";
     my $command = "$PERL_EXE -T -c $file";
     system ($command); 
    } #*-- end of while
  } #*-- end of for

 print ("Finished compile.pl\n");
 exit(0);

__DATA__
./utils pl
./t pl
./tools/pos pl
./tools/quanda pl
./tools/reuters pl
./tools/wordnet pl
./tools/wordnet/misc pl
./TextMine pm
