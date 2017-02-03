#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------------------
 #*- run_fetch_b.pl
 #*-  
 #*-   Summary: Start a process to fetch an URL
 #*-
 #*----------------------------------------------------------------
 use strict; use warnings;
 use TextMine::Constants qw/$UTILS_DIR $OSNAME $PERL_EXE $DELIM/;
 use TextMine::MyProc;

 print ("Started fetching URL\n");
 #our $url = 'http://newsrss.bbc.co.uk/rss/newsonline_world_edition/technology/rss.xml';
 our $url = 'http://rss.news.yahoo.com/rss/tech';
 our $timeout = 60; 
 our $filename = "/home/manuk/textmine-0.2/utils/news.xml";
 our $get_html = 1;
 our $get_images = 0;
 our $args = join('___', $url, $timeout, $filename, $get_html, $get_images);
 our @cmdline = ("$UTILS_DIR" . "fetch_b_url.pl ", $args);
 our $retval = &create_process(\@cmdline, 0, 'Perl.exe', "$PERL_EXE");
 print ("Finished fetching URL\n");
 exit(0);
