
 use lib qw/../;

 #*----------------------------------------------------------------
 #*- load_mod.pl
 #*-  
 #*- Summary: load perl modules using ppm or CPAN
 #*- 
 #*- Module Dependencies: 
 #*-  1.  Crypt::Rot47 
 #*-  2.  DBI
 #*-  3.  DBD::mysql 
 #*-  4.  Digest::MD5
 #*-  5.  HTML::Parser 
 #*-  6.  GD
 #*-  7.  Win32 		included in Windows
 #*-  8.  Win32::Process	included in Windows
 #*-  9.  URI::URL 		maybe in site library
 #*-  10. URI::Escape           maybe in site library
 #*-  11. WWW:RobotRules        maybe in site library
 #*-  12. XML::RSS::Parser	Optional RSS Parser
 #*----------------------------------------------------------------
 use strict; use warnings; 
 use Config;
 use TextMine::Constants qw/$PPM_DIR $OSNAME $PERL_EXE clean_filename 
               fetch_dirname/;

 print ("Started load_mod.pl\n");
 print ("Installing the Perl dependent modules ...\n");
 &setup_modules();
 print ("Finished installing Perl dependent modules ....\n");
 print ("Finished load_mod.pl\n");
 exit(0);

 #*-------------------------------------------------------------------
 #*- install the dependent modules, if possible
 #*-------------------------------------------------------------------
 sub setup_modules
 {
  my @MOD_DEP = qw/
			Crypt::Rot47 
			DBI 
			DBD::mysql 
			Digest::MD5 
			HTML::Parser 
                        XML::RSS::Parser
			GD
		/;
  print "Are you running ActiveState Perl ? (Y/N): ";
  chomp(my $in = <STDIN>);
  if ($in =~ /^y/i) #*-- use the PPM package to install modules
   { (my $ppm) = &fetch_dirname($PERL_EXE);
     $ppm .= ($OSNAME =~ /win/i) ? 'ppm.bat': 'ppm';
     foreach my $module (@MOD_DEP)
      { 
        $module = "$PPM_DIR$module" . '.ppd'; $module =~ s/::/\-/; 
        $module = &clean_filename("$module");
        my $command = "$ppm install $module";
        print ("Install module $module (Y/N): ");
        next if ( ($in = <STDIN>) =~ /n/i);
        system("$command\n");
      }
   }
  else #*-- use the CPAN module to install Perl modules
   {
    print "Try to install modules using the CPAN module\n" .
          " which requires an Internet connection (Y/N) ? : ";
    my $inst_mod = <STDIN>; chomp($inst_mod);
    return() unless ($inst_mod =~ /y/i);
    foreach my $module (@MOD_DEP)
     { my $command = "$PERL_EXE -MCPAN -e \"install '$module'\"";
       print ("Install module $module (Y/N): ");
       next if ( ($in = <STDIN>) =~ /n/i);
       system ("$command\n"); }
   }
 }
