
 #*----------------------------------------------------------------------
 #*- MyURL.pm						
 #*- Description: A set of Perl functions for retrieving, parsing, and
 #*- modifying web pages.    
 #*-----------------------------------------------------------------------

 package TextMine::MyURL;

 use strict; use warnings;
 use HTML::Parser 3.0 ();
 use URI::URL;
 use lib qw/../;
 use TextMine::Constants qw($UTILS_DIR $OSNAME $PERL_EXE @SCHEMES);
 use TextMine::MyProc;

 require Exporter;
 our @ISA    = qw(Exporter);
 our @EXPORT_OK = qw(parse_HTML get_URL get_site get_base 
                     sub_HTML  fetch_URL clean_link);

 #*-- global variables
 use vars ('%inside',	#*-- hash to indicate if within a tag during parse
           '%links',	#*-- hash of links in a page
           '%images',	#*-- hash of images in a page
           '$acc_text',	#*-- accumulated text of a page
           '%met_data',	#*-- hash for meta data in the page
           '$fsize',	#*-- font size 
           '$X2',	#*-- weight for level 4 headings
           '$X4',	#*-- wieght for level 3 headings
           '$X8',	#*-- weight for level 2 headings
           '$X16',	#*-- weight for level 1 headings
           '$gurl', 	#*-- URL for page
           '$gbase', 	#*-- base URL for page
           '$dlink',	#*-- current link being processed
           '$socket_err', '$html_err', '$parse_err');

 #*-- set the error messages
 BEGIN 
  { $socket_err = "MyURL Error: Problem with socket: "; 
    $html_err   = "MyURL Error: No response: "; 
    $parse_err  = "MyURL Error: Could not parse HTML: ";
  }

 #*------------------------------------------------------------
 #*- fetch the url within the specified timeout and
 #*- place the html and optional images in the same directory
 #*------------------------------------------------------------
 sub fetch_URL
 {
  my ($url,		#*-- URL to be retrieved
      $timeout,		#*-- timeout in seconds to retrieve the URL
      $filename,	#*-- name of the file to save the HTML
      $get_html,	#*-- flag to fetch HTML
      $get_images,	#*-- flag to get images 
      $debug,		#*-- debug flag
      $spi_id		#*-- optional parameter for spider id
     ) = @_;

  #*-- set default values
  $timeout = 60 unless ($timeout); 
  $spi_id = 0   unless ($spi_id);

  #*-- build the command line to run the process to fetch the URL
  #*-- escape the ampersand in an URL -- Feb 15th, 2005
  $url =~ s/&/\\&/g; 
  my @cmdline = ("-I$UTILS_DIR", "$UTILS_DIR" . 'fetch_b_url.pl ', 
     join ('___', "$url", "$timeout", "$filename", "$get_html", 
     "$get_images", "$debug", "$spi_id") );

  #*-- running without taint
  unlink ($filename);
  my $stat_msg = &create_process(\@cmdline, 1, 'Perl.exe ', "$PERL_EXE");
  return ($stat_msg) if ($stat_msg);

  #*-- wait in a loop till timeout or length of file is > 0
  #*-- give 2 secs. for the process to start and create the file
  my $i = 0; sleep(2); my $file_size; 
  do { sleep(1); $i++; $file_size = -s $filename || 0; }
  until ( ($i > $timeout) || ($file_size > 0) );

  #*-- return 0 if successful
  return( ($i <= $timeout) ? 0: 1);
 }

 #*---------------------------------------------
 #*- return the HTML associated with an URL
 #*---------------------------------------------
 sub get_URL
  {

   my ($url, $timeout) = @_;

   #*-- set the timeout for the url
   $timeout = 60 unless($timeout);

   #*-- add leading http and remove trailing slash
   $url =~ s%^%http://%i if ($url !~ m%^http://%i); $url =~ s%/$%%; 

   my $src  = &get_src($url);
   my $base = &get_base($url);

   return (\$src, \$base);
  }

 #*---------------------------------------------
 #*- return the text and links for the HTML
 #*- modify with base URL as needed
 #*---------------------------------------------
 sub parse_HTML
  {

   my ($html, $base) = @_;
   my ($parser, $reg1);

   #*-- get the base for the URL and initialize vars
   return(\'', \'', \'', \'') unless($html); 

   #*-- set the base for the URL, use the base href if present
   $base = '' unless ($base);
   $gbase = ($html =~ m%<base href="?(http://[^"]*?)"?>%i ) ? $1: $base;

   #*-- set the base directory name and url name
   $gurl = $gbase; $gbase = 'http://' . &get_base($gbase);

   #*-- build the word weights
   %links = %images = %inside = ();
   $acc_text = ""; my $ret_val;

   #*-- set the weights for word types, higher weights for 
   #*-- larger fonts or bold text
   $X2 = int(2 * ( (length($html) / 16384) + 1));
   $X4 = 2 * $X2; $X8 = 2 * $X4; $X16 = 2 * $X8;

   #*-- allocate the parser and handlers
   $parser = HTML::Parser->new(api_version => 3,
                               start_h => [\&start_tag, "tagname, attr"],
                               end_h   => [\&end_tag, "tagname, attr"],
                               text_h  => [\&text, "dtext"],
                               marked_sections => 1,
                              );
   $parser->parse($html) || return( \"$parse_err $!\n", \'', \'', \'');

   $acc_text =~ s/\s+/ /g;
   return (\$acc_text, \%links, \%images, \%met_data);

 }

 #*---------------------------------------------
 #*- return the text and links for the URL
 #*---------------------------------------------
 sub parse_URL
  {
   my ($url, $timeout) = @_;
   my ($src, $base) = &get_URL($url, $timeout);
   &parse_HTML( $src, $base );
   return (\$acc_text, \%links);
  }

 #*---------------------------------------------
 #*- return the site for an URL 
 #*---------------------------------------------
 sub get_site
  { (my $url) = @_; 
    $url = "http://" . $url if ($url !~ /^http:/i);
    my $uri_url = new URI::URL($url);
    return($uri_url->host() ); }

 #*---------------------------------------------
 #*- return the base for an URL
 #*---------------------------------------------
 sub get_base
  { (my $url) = @_; 

    #*-- return if ends with slash
    $url =~ s%^http://%%;
    return($url) if ($url =~ m%[/\\]$%); 

    #*-- return with filename/path stripped from URL
    $url =~ s%[/\\][^/\\]*?$%% if ( ($url =~ m%\.[^./\\]{2,8}$%) ||
                                    ($url =~ m%\?.*$%) );
    #*-- add a trailing slash
    $url .= '/';
    return($url); }

 #*----------------------------------
 #*- parse the beginning of the tag
 #*----------------------------------
 sub start_tag
 {
   my($tag, $attr) = @_;
   
   $inside{$tag} = 1 unless ($inside{$tag});

   #*-- handle the rspider_url tag for local pages
   #*-- this overrides the previous setting of gbase
   if ($tag eq "rspider_url")
    { $gurl = $attr->{src}; $gbase = 'http://' . &get_base($gurl); }

   #*-- handle the anchor and map tags
   if ( ($tag eq "a") || ($tag eq "map") )
    {
     return unless ($dlink = $attr->{href});
     return if ( ($dlink =~/^mailto:/i) || ($dlink =~/^javascript:/i) ||
                 ($dlink =~ /window\.open\(/i) );

     $dlink = &clean_link($dlink); #*-- initialize the anchor text
     $links{$dlink} = ' ' unless (exists($links{$dlink}));  
    }

   #*-- handle the image tags
   if ( $tag eq "img" && $attr->{src} )
    { $dlink = &clean_link($attr->{src});
      $images{$dlink}++ unless (exists($images{$dlink}) ); } 

   #*-- get any background images
   if ( $tag eq "body" && $attr->{background} )
    { $dlink = &clean_link($attr->{background});
      $images{$dlink}++ unless (exists($images{$dlink}) ); } 

   #*-- handle the form input tags
   if ( $tag eq "input" && $attr->{type} && $attr->{type} eq "text")
    { $acc_text .= $attr->{value} if $attr->{value}; }

   #*-- handle the frame tags
   if ($tag eq "frame")
    {
     $dlink = &clean_link($attr->{src});
     $links{$dlink}++ unless (exists($links{$dlink}) );  
    }

   #*-- handle the meta tags, give more weight to meta tags
   if ( ($tag eq "meta") &&  $attr->{name} &&
        ($attr->{name} =~ /description|keywords/i) )
    { if ($attr->{content})
        { $acc_text .= $attr->{content};
          $met_data{$X4} .= $attr->{content} . ' '; }
    } 

   #*-- set the size for font tags
   if ($tag =~ /^(?:basefont|font)/i)
    { $fsize = ($attr->{size}) ? $attr->{size}: 3; } 
 }

 #*----------------------------------
 #*- clean up the link and return
 #*----------------------------------
 sub clean_link
 { 
   my ($link) = @_; 
   
   #*-- strip anchor part of link
   $link =~ s/#.*$//; return ($gurl) unless ($link);

   #*-- if link starts with http then use no prefix,
   #*-- if link starts with /, then use the hostname as prefix,
   #*-- otherwise, use the base name as prefix
   #*-- $gbase is set before calling clean_link
   local $" = '|'; 
   my $prefix = ($link =~ m%^(?:@SCHEMES)%i) ? '': 
                ($link =~ m%^/%) ? &get_site($gbase): $gbase;
   my $url = $prefix . $link;

   #*-- handle periods in the path
   while ($url =~ s%/\./%/%g) {}
   while ($url =~ s%^(.*?)/([^/]+)/\.\./(.*)%$1/$3%g) { }

   #*-- remove any excess .. in the URL
   while ($url =~ s%//\.\./%//%g) { }
   local $" = ' ';

   $url =~ s%^http://%%;
   return($url); }

 #*----------------------------------
 #*- parse the end of the tag
 #*----------------------------------
 sub end_tag
 { my($tag, $attr) = @_; 
   $inside{$tag} = 0 if ($inside{$tag}); }

 #*----------------------------------
 #*- Stuff the text variable 
 #*----------------------------------
 sub text
 {
  my($dtext) = @_;

  #*-- skip javascript and stylesheets
  return if $inside{rspider_url} || $inside{script} || $inside{style};
  $dtext = "frame link" if ( ($dtext !~ /\w/) && ($inside{frame}) );

  #*-- capture the anchor text for a link
  #*-- the anchor text for dup links in a page will be concatenated
  $links{$dlink} .= $dtext . ' '
   if ($dlink && $links{$dlink} && ($inside{a} || $inside{frame}) );

  #*-- accumulate the text
  $acc_text .= ' ' . $dtext unless ($dtext =~ /^\s*$/);
 
  #*-- handle weighted text, set the font size
  my %font = (); $font{$fsize}++ if ($inside{basefont} || $inside{font});
  my $met_tag = 0; my $ret_val;

  #*-- check if inside any of the following tags
  foreach ( qw/bold big em i strong font basefont h4 h3 h2 h1 title/)
   { $met_tag = 1 if ($inside{$_}); }
  
  if ( ($met_tag) && ($dtext =~ /\w/) )
   {
    $dtext =~ s/\s+/ /g;
    if ($inside{bold}   || $inside{big} || $inside{em} || $inside{i} ||
        $inside{strong} || $inside{h4}  || $font{4} )
     { $met_data{$X2} .= $dtext . ' '; }

    if ($inside{title}   || $inside{h3}  || $font{5} )
     { $met_data{$X4} .= $dtext . ' '; }

    if ($inside{h2}  || $font{6} )
     { $met_data{$X8} .= $dtext . ' '; }

    if ($inside{h1}  || $font{7} )
     { $met_data{$X16} .= $dtext . ' '; }
   } #*-- end of met_tag
  
 }

 #*---------------------------------------------
 #*- Accept the HTML and substitutions.    
 #*- Return the modified HTML        
 #*---------------------------------------------
 sub sub_HTML
 { my ($html,	#*-- HTML to be replaced
       $reps	#*-- replacement strings
      ) = @_;

   my @reps = @$reps;
   my @ok_reps = (); my $n_html = '';

   #*-- replace the spaces with /s
   foreach (@reps) { s/ /\\r\?\\s+/g; }
 
   #*-- verify the replacement strings
   foreach (@reps) { push(@ok_reps, $_) if ( eval{qr/$_/i} ); } 

   #*-- color the substitution string darkred in the HTML 
   my $parser = HTML::Parser->new(unbroken_text => 1,
    default_h => [ sub {$n_html .= "@_"; }, "text" ],
    text_h    => [ sub 
     { my $t_html .= "@_"; 
       foreach (sort {length($b) <=> length($a)} @ok_reps)
        { $t_html =~ s%$_%<font size=+1 color=darkred>$1</font>%igs; }
       $n_html .= $t_html; }, 
                 "text" ],
                 );
   $parser->parse($html) || return( \"$parse_err $!\n");
   return($n_html);
 }

1;

=head1 NAME

MyURL - TextMine MyURL

=head1 SYNOPSIS

use TextMine::MyURL;

=head1 DESCRIPTION

 A group of functions to fetch, parse, and substitute text from  
 web pages. 

=head2 get_URL, fetch_URL

 get_URL: Release the database and statement handles 
 for the database.
 
 fetch_URL: Starts a process to retrieve an URL and terminates 
 within a specified timeout if the URL could not be fetched.
 Otherwise, 0 is returned.

=head2 parse_HTML, sub_HTML

 parse_HTML: Accept HTML and return references to text, links 
 in the page, images in the page and weighted text 

 sub_HTML: Replace text in HTML with a different color       

=head2 get_site, get_base, clean_link

 get_site: Return the host name associated with an URL    

 get_base: Return the base of the URL 

 clean_link: Return an aboslute URL 

=head1 AUTHOR

Manu Konchady <mkonchady@yahoo.com>
