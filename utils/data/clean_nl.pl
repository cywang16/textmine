#!D:\Perl\bin\perl.exe
 use lib qw %D:/cygwin/home/konchady/cgi-bin/tm/%;

 #*-----------------------------------------------------
 #*- clean_nl.pl
 #*- 
 #*- remove the ^M characters from the end of the line
 #*-----------------------------------------------------
 opendir (DIR, ".");
 while ($in = readdir(DIR))
  { push (@files, $in) if ($in =~ /\.(?:txt|pl|pm)$/i); }
 closedir(DIR);

 @files = ();
 while ($inline = <DATA>)
  { chomp($inline); push (@files, $inline); }

 foreach (@files)
  { open (IN, "+<$_");
    binmode(IN, ":raw"); undef($/);
    $inline = <IN>; $inline =~ s/\x0D\x0A/\x0A/g;
    seek(IN, 0, 0);
    print IN $inline;
    close(IN);
  }
 exit(0);

__DATA__
co_abbrev.dat
co_org.dat
co_person.dat
wn_synsets.dat
