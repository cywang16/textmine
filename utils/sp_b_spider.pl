#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

#*----------------------------------------------------------------
#*- sp_b_spider.pl
#*-  
#*-   Summary: Multiple copies of this spider run concurrently.
#*-            Each spider is started with a separate spider
#*-            number. Some functions are performed by a master
#*-            spider (spider 0) alone. Other functions which
#*-            can be performed concurrently are run on all
#*-            spider processes. Communication between spiders
#*-            is exclusively through database tables. Locks on
#*-            tables to read and write are used to manage concurrency.
#*-
#*-   Usage: sp_b_spider.pl <no. of spiders>__<spider no.>__<search id>
#*----------------------------------------------------------------

 use strict; use warnings;
 use WWW::RobotRules;
 use Digest::MD5 qw(md5_base64);
 use TextMine::DbCall;
 use TextMine::Utils     qw(clean_array);
 use TextMine::Index     qw(text_match add_index);
 use TextMine::Tokens    qw(load_token_tables);
 use TextMine::Constants qw($DB_NAME clean_filename);
 use TextMine::Summary   qw(summary);
 use TextMine::MyURL     qw(parse_HTML fetch_URL get_site);

 #*-- set the constants
 use constant MIN_RELEVANCY => 10;
 use constant RELEVANCE_WT  => 1000;

 our (
	$dbh,		#*-- database handle
	$sth,		#*-- statement handle
	$db_msg,	#*-- database error message
	$command,	#*-- SQL Command variable
	%sp,		#*--
 	$spider_num,	#*-- number of this spider 
	$num_spiders,	#*-- no. of spiders in this ensemble 
   	$spi_id,	#*-- spider id for this search
	$tid,		#*-- process number
	$link_table,	#*-- table of links for this search
	$url_count,	#*-- count of no. of URLs fetched
	@SPARMS,	#*-- a list of parms in the search table
	@blocked,	#*-- list of blocked sites
	@selected, 	#*-- list of search sites
	@keys, 		#*-- keywords for choosing links to follow or not
   	$start_time,	#*-- start time in epoch seconds
	$hash_refs,	#*-- reference to token tables
	$robot_rules	#*-- reference to a WWW::RobotRules object
     );

 #*-- some initial processing   
 &set_vars();

 #*-- get the spider parameters
 &get_parameters();

 #*-- recompute the priority and relevancy before start
 &recompute();
 
 #*-- check for any urls to run
 while (my $p_url = &check_for_urls() ) { &process_url($p_url); }

 &quit('Done');
 exit(0);

 #*-----------------------------------------------------
 #*- Set some global vars            
 #*-----------------------------------------------------
 sub set_vars
 {

  ($num_spiders, $spider_num, $spi_id) = $ARGV[0] =~ /(\d+)__(\d+)__(\d+)/;
  my $userid = 'tmadmin'; my $password = 'tmpass';
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
      'Userid' => $userid, 'Password' => $password,
      'Dbname' => $DB_NAME);

  $hash_refs = &load_token_tables($dbh);
  $start_time = time(); 
  $tid = $$; my $status = 'Running';

  #*-- make an entry in the proctab for the spider
  #*--- LOCK ----*#
  $dbh->execute_stmt("lock tables co_proctab write");

  #*-- clean up the proctab
  if ($spider_num == 0)
   { 
    #*-- remove old entries
    $command = "delete from co_proctab where pri_start_time " .
               " < ($start_time - 36000)";
    (undef, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg); 

    #*-- remove entries for earlier recent crawls
    $command = "delete from co_proctab where prc_sub_tid = " . 
       $dbh->quote($spi_id) . " and pri_start_time < $start_time";
    (undef, $db_msg) = $dbh->execute_stmt($command);
     &quit("Command: $command failed --> $db_msg") if ($db_msg); 
   }

  #*-- add the new entries
  $command = "replace into co_proctab values ($tid, $start_time, 
      'Spider $spider_num: Running', '$spi_id', '')";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  $dbh->execute_stmt("unlock tables");
  #*--- UNLOCK ----*#

  &upd_stat("Started processing spider $spider_num for task no. $spi_id");

  #*-- verify the arguments passed, i.e. no. of spiders, spider id, search id
  &quit("Invalid number of spiders") unless ($num_spiders  =~ /\d+/);
  &quit("Invalid Spider number")     unless ($spider_num   =~ /\d+/);
  &quit("Invalid search id")         unless ($spi_id       =~ /\d+/);

  #*--- LOCK ----*#
  $dbh->execute_stmt("lock tables sp_search read");
  $command = "select count(*) from sp_search where spi_id = $spi_id";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  &quit("Bad search id") unless ( ($dbh->fetch_row($sth))[0]);
  $dbh->execute_stmt("unlock tables");
  #*--- UNLOCK ----*#

  #*-- list of parameters for a search
  @SPARMS = qw/spi_id spi_date spi_url_limit spi_url_count 
               spi_url_timeout spi_spiders spi_time_limit    
               spi_maxsite_urls spi_level_limit spi_directory_limit 
               spc_search_type spc_get_images spc_recompute
               spc_status spc_descr spc_keywords
               spc_priority_domain spc_link_file spc_results_dir
               spc_blocked_sites spc_selected_sites/;
  $robot_rules = new WWW::RobotRules('Rspider');

 } #*-- end of set_vars

 #*------------------------------------------------------------
 #*- get the spider parameters and prepare the link table
 #*- for processing
 #*------------------------------------------------------------ 
 sub get_parameters
 {
  #*-- get the search parms into a hash
  #*--- LOCK ----*#
  $dbh->execute_stmt("lock tables sp_search read");
  $command = "select * from sp_search where spi_id = $spi_id";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  %sp = %{my $sp = $dbh->fetch_row($sth, 1)}; #*-- fetch a hash ref
  $dbh->execute_stmt("unlock tables");
  #*--- UNLOCK ----*#

  #*-- get the list of blocked and selected sites
  my @temp = ();
  foreach (split/\s+/, $sp{spc_blocked_sites})
   { push (@temp, $_); push (@temp, 'www.' . $_) unless ($_ =~ /^www\./); }
  @blocked  = &clean_array(@temp);

  foreach (split/\s+/, $sp{spc_selected_sites} )
   { push (@temp, $_); push (@temp, 'www.' . $_) unless ($_ =~ /^www\./); }
  @selected = &clean_array(@temp);

  @keys = &clean_array(split/\s+/, $sp{spc_keywords} );

  #*-- clean up the link table
  (my $descr = substr($sp{spc_descr},0,20)) =~ s/[^A-Za-z]/o/g;
  $link_table = "sp_" . $descr . "_links";

  #*-- set the url count for the spider, first check for the highest
  #*-- no. from a previous run
  $command = "select spc_html_file from $link_table where " .
             "spi_spider = $spider_num order by spi_lid desc";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  (my $tfile) = $dbh->fetch_row($sth); 
  
  #*---------------------------------------------------------
  #*- moved clean up of tfile to else section, Feb 10, 2005
  #*---------------------------------------------------------
  unless ($tfile) { $url_count = 0; }
  else            
   { 
     $tfile =~ s/^\s+//; $tfile =~ s/\s+$//;
     $tfile =~ m%_(\d+)\.html$%; $url_count = ($1) ? $1: 0; }

  #*-- scan the link table and reset any URLs which were being visited
  if ($spider_num == 0)
   {
    #*--- LOCK ----*#
    $dbh->execute_stmt("lock tables $link_table write");
    $command = "update $link_table set spc_status = 'New'";
    $command   .= " where spc_status = 'Visiting'";
    (undef, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);

    #*-- remove any links from blocked sites
    if (@blocked)
     { 
      my @where_cl = ();
      foreach my $b_site (@blocked)
       { push (@where_cl, ' spc_site = ' . $dbh->quote($b_site) ) 
         if ($b_site); }
      $command = "delete from $link_table where " .
                  join(' or ', @where_cl);
      (undef, $db_msg) = $dbh->execute_stmt($command);
      &quit("Command: $command failed --> $db_msg") if ($db_msg);
     }

    #*-- remove any links not in selected sites
    if (@selected)
     {
      my @where_cl = ();
      foreach my $s_site (@selected)
       { push (@where_cl, ' spc_site != ' . $dbh->quote($s_site) ) 
         if ($s_site); }
      $command = "delete from $link_table where " . 
                  join(' and ', @where_cl);
      (undef, $db_msg) = $dbh->execute_stmt($command);
      &quit("Command: $command failed --> $db_msg") if ($db_msg);
     }

    $dbh->execute_stmt("unlock tables");
    #*--- UNLOCK ----*#
   } #*-- end of if spider == 0

 } #*-- end of get parameters
  
 #*--------------------------------------------------
 #*- check if there any URLs for processing
 #*--------------------------------------------------
 sub check_for_urls
 {
  my ($url);

  #*-- check for termination criteria
  &upd_stat("Checking for URLs to process");

  #*-- check the limits for the crawl
  #*--- LOCK ----*#
  $dbh->execute_stmt("lock tables sp_search read");
  $command  = "select spi_url_count from sp_search where spi_id = $spi_id "; 
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  my ($done_count) = $dbh->fetch_row($sth);
  $dbh->execute_stmt("unlock tables");
  #*--- UNLOCK ----*#

  #*-- check if the number of URLs that have been processed
  #*-- exceeds the limit
  if ($done_count >= $sp{spi_url_limit}) 
    { &quit("URL count exceeds limit"); } 

  #*-- check if the run time of the spider exceeds the limit
  if ( (time() - $start_time) > ($sp{spi_time_limit} * 3600) ) 
    { &quit("Run time exceeds limit"); } 
  &quit('Done') if (&not_running);

  #*-- try and get a URL to process
  return ($url) if ($url = &get_link() );
  
  #*-- give spiders a max. of 5 minutes to find more URLs, if necessary
  &upd_stat("Did not get an URL yet");
  my $i = 0;
  while (&spiders_busy() && ($i < 60) )
   { 
    return($url) if ($url = &get_link());
    &quit('Done') if (&not_running);
    &upd_stat("Waiting for a Spider to fetch URLs...");
    sleep(5); $i++;
   }
  &upd_stat("No URLs found....");
  &quit("Done"); #*-- no urls found for processing
 }
  
 #*-----------------------------------------------------------
 #*- return true if any spider is busy doing something useful
 #*- i.e. not waiting or not terminated
 #*-----------------------------------------------------------
 sub spiders_busy
 {
  my ($retval, $status);
  $retval = 0;
  #*--- LOCK ----*#
  $dbh->execute_stmt("lock tables co_proctab read");
  ($sth) = $dbh->execute_stmt("select prc_status from co_proctab " .
                             " where prc_sub_tid = '$spi_id'");
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  while ( ($status) = $dbh->fetch_row($sth) )
   { if ($status !~ /(terminated|stopped|waiting|done)/i)
        { $retval = 1; last; } }
  $dbh->execute_stmt("unlock tables");
  #*--- UNLOCK ----*#
  return($retval);
 }
  
 #*--------------------------------------------------
 #*- return an URL in descending order of priority
 #*--------------------------------------------------
 sub get_link
 {
 
  #*-- get the list of sites being visited
  &upd_stat("Looking for URLs...");
  
  #*-- lock the url table and get the top URL in descending order of pr.
  #*--- LOCK ----*#
  (undef, $db_msg) = $dbh->execute_stmt("lock tables $link_table write" );
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  $command = "select spc_link from $link_table where spc_status = 'New'" .
             " order by spf_priority desc";
  ($sth, $db_msg) = $dbh->execute_stmt($command );
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  (my $url) = $dbh->fetch_row($sth);

  #*-- return with a message if no URL was found
  my $msg = '';
  unless ($url) { $msg = "Could not find a URL"; }
  else
   {
    $command  = "update $link_table set spc_status = 'Visiting' " .
                " where spc_link = " . $dbh->quote($url);
    (undef, $db_msg) = $dbh->execute_stmt($command );
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    $msg = "Will process $url";
   }

  $dbh->execute_stmt("unlock tables" );
  #*--- UNLOCK ----*#

  &upd_stat($msg); 
  return($url);
  
 }
 
 #*--------------------------------------------------
 #*- Get the text and links.
 #*--------------------------------------------------
 sub process_url
  {
   my ($url) = @_;
 
   #*-- fetch the web page
   my $status = my $html = '';
   &upd_stat("Retrieving URL: $url");
   my $filename = "$sp{spc_results_dir}/" . "sp_" . "$spi_id" . 
                  "_$spider_num" .  "_$url_count" . ".html";
   $url_count++;
   my $get_images = ($sp{spc_get_images} =~ /y/i) ? 'Y': 'N';
   my $debug = 0; my $start_t = time();
   $status = &fetch_URL($url, $sp{spi_url_timeout}, 
                        $filename, 1, $get_images, $debug, $spi_id);
   unless ($status)
    {
     open (IN, "<", &clean_filename("$filename")) || 
        &quit("Process_url: Could not open $filename $!\n"); 
     undef($/); $html = <IN>; close(IN);

     #*-- check for length of page returned
     if ( length($html) < 50 )
     { $status = 'reject'; 
       &upd_stat("Rejected page because of size: ", length($html) ); }

     #*-- check if retrieval was successful 
     elsif ( $html =~ m%TextMine get_src cannot fetch%i )
     { $status = 'reject'; 
       &upd_stat("Could not fetch page $url"); }

     #*-- if empty line
     elsif ($html !~ m%<rspider.*?></rspider_url>.*?\w+%s)
     { $status = 'reject'; 
       &upd_stat("Page for $url was empty"); }

     #*-- set the message for a successful retrieval
     else
     { my $elapsed_t = time() - $start_t;
       &upd_stat("Fetched page in $elapsed_t secs."); } 
    }
   #*-- set the message for a timeout retrieval
   else
    { &upd_stat("Failed to fetch $url in $sp{spi_url_timeout} seconds"); }

   #*-- parse the HTML and links
   my ($text, $spi_lid, $spi_level, $signature, %links, $relevancy);
   unless ($status)
    {
     &quit('Done') if (&not_running);
     $html =~ s/<![^>]+>//g; #*-- strip out HTML comments before parsing
     (my $r_text, my $r_links) = &parse_HTML($html, $url);
     $text = $$r_text; %links = (); 

     #*-- strip links within pages and clean the anchor text
     foreach my $olink (keys %$r_links) 
      { (my $link = $olink) =~ s/(\#|%23).*$//; 
        ($links{$link} = $$r_links{$olink}) =~ s/[^\w]/ /g; }

     #*-- get the link id and level
     #*--- LOCK ----*#
     $dbh->execute_stmt("lock tables $link_table read");
     $command  = "select spi_lid, spi_level from $link_table " .
                 " where spc_link = " . $dbh->quote($url);
     ($sth, $db_msg) = $dbh->execute_stmt($command );
     &quit("Command: $command failed --> $db_msg") if ($db_msg);
     ($spi_lid, $spi_level) = $dbh->fetch_row($sth);

     #*-- check if a dup page exists with the same signature
     $signature  = $dbh->quote(md5_base64($html));
     $command  = "select spc_link from $link_table " .
                 " where spc_signature = $signature ";
     ($sth, $db_msg) = $dbh->execute_stmt($command );
     &quit("Command: $command failed --> $db_msg") if ($db_msg);
     my ($dup_link) = $dbh->fetch_row($sth);
     $dbh->execute_stmt("unlock tables" );
     #*--- UNLOCK ----*#
     &upd_stat("Start computing relevancy of $url..");
     
     #*-- check if a duplicate page exists with the same HTML
     if ($dup_link)
      { $status = 'Duplicate';
        &upd_stat("A duplicate page $dup_link with same HTML."); }

     #*-- compute the relevancy and reject URLs with low relevancies
     elsif ( ( $relevancy = &compute_relevancy($text) ) > MIN_RELEVANCY)
      { $status = 'Done'; }

     #*-- otherwise, check if the page has moved
     else
      { 
       #*-- page is re-directed or contains frames
       if ( ($text =~ /document.*?moved/i) || ($text =~ /<frame>/) )  
        { 
         $status = 'Redirect';
         &upd_stat("Parsing links from redirect $url..");
         foreach my $link (keys %links)
          { &add_links($link, $url, $spi_level, $links{$link}) }
        }
       else { $status = "Reject"; 
              &upd_stat("URL text was not relevant: $relevancy"); }
      }
    } #*-- end of unless $status

   #*-- clean up the link table and return for non-match
   unless ($status eq 'Done')
    { 
     #*--- LOCK ----*#
     $dbh->execute_stmt("lock tables $link_table write"); 
     $command = "delete from $link_table where spc_link = ". 
                 $dbh->quote($url); 
     (undef, $db_msg) = $dbh->execute_stmt($command );
     &quit("Command: $command failed --> $db_msg") if ($db_msg);
     $dbh->execute_stmt("unlock tables");
     #*--- UNLOCK ----*#
     return();
    } #*-- end of unless
   
   #*-- update the entry in the link table
   &upd_stat("$url was relevant: $relevancy");
   my $site       = &get_site($url); 
   my $abstract   = $dbh->quote(&compute_abstract($text));
   my $q_filename = $dbh->quote($filename);
   my $q_url      = $dbh->quote($url);
   #*--- LOCK ----*#
   $dbh->execute_stmt("lock tables $link_table write, sp_search write");
   $command  = <<"EOF";
      update $link_table set spf_relevance = $relevancy, 
             spc_status    = 'Done',    spi_spider    = $spider_num, 
             spc_abstract  = $abstract, spc_html_file = $q_filename,
             spc_signature = $signature 
             where spc_link = $q_url
EOF
   (undef, $db_msg) = $dbh->execute_stmt($command);
   &quit("Command: $command failed --> $db_msg") if ($db_msg);

   $command = "select count(*) from $link_table where spc_status = 'Done'";
   ($sth, $db_msg) = $dbh->execute_stmt($command);
   &quit("Command: $command failed --> $db_msg") if ($db_msg);
   (my $ucount) = $dbh->fetch_row($sth);

   $command = "update sp_search set spi_url_count = $ucount " .
              "where spi_id = $spi_id";
   (undef, $db_msg) = $dbh->execute_stmt($command);
   &quit("Command: $command failed --> $db_msg") if ($db_msg);

   $dbh->execute_stmt("unlock tables");
   #*--- UNLOCK ----*#

   #*-- add to the index
   (my $descr = substr($sp{spc_descr},0,20)) =~ s/[^A-Za-z]/o/g;
   &add_index($spi_lid, $text, "sp_$descr", $dbh, 'web');
 
   #*-- add the links to the link table
   if ( $sp{spi_level_limit} >= ($spi_level + 1) )
    {
     &upd_stat("Parsing links from $url..");
     foreach my $link (keys %links)
      { &add_links($link, $url, $spi_level, $links{$link}) 
          if ( ($links{$link} =~ /frame link/i) ||
             (&valid_link($link, $links{$link}, $url, $relevancy) ) ); }
    } #*-- end of if
   &upd_stat("Finished parsing links from $url..");
  }

 #*--------------------------------------------------
 #*- add the new link to the link table
 #*--------------------------------------------------
 sub add_links
  {
   my ($link, $url, $ulevel, $anchor) = @_;
 
   $link =~ s%/$%%; #*-- strip a trailing slash
   $ulevel = ($ulevel) ? $ulevel: 0;

   #*-- get the site (google links are handled separately) 
   my $site;
   if ($link =~ m%cache:.*?:(.*?)(/|\+)%) { $site = $1; } 
   else  { $site = &get_site($link); } 

   #*-- don't fetch any more urls from a 'full site'
   #*--- LOCK ----*#
   $dbh->execute_stmt("lock tables $link_table read");
   $command  = "select count(*) from $link_table where " .
         "spc_site = " . $dbh->quote($site) . " and spc_status = 'done'";
   ($sth, $db_msg) = $dbh->execute_stmt($command);
   &quit("Command: $command failed --> $db_msg") if ($db_msg);
   (my $site_count) = $dbh->fetch_row($sth);
   $dbh->execute_stmt("unlock tables");
   #*--- UNLOCK ----*#

   #*-- remove links from full sites from the link table
   if ( $site_count >= $sp{spi_maxsite_urls})
    { 
     #*--- LOCK ----*#
     $dbh->execute_stmt("lock tables $link_table read");
     $command = "delete from $link_table where spc_site = " .
                $dbh->quote($site) . " and spc_status = 'New'";
     ($sth, $db_msg) = $dbh->execute_stmt($command);
     &quit("Command: $command failed --> $db_msg") if ($db_msg);
     $dbh->execute_stmt("unlock tables");
     #*--- UNLOCK ----*#
      return(); } 

   #*-- check the blocked and selected site restrictions for links 
   foreach my $b_site (@blocked)  { return() if ($site =~ /$b_site/i); }
   my $site_ok = (@selected) ? 0: 1;
   foreach my $s_site (@selected) { $site_ok = 1 if ($site =~ /$s_site/i); } 
   return() unless ($site_ok);

   #*-- count the number of levels in the link and return if the
   #*-- directory level is below the limit
   (my $tlink = $link) =~ s%^http://%%;
   my $level = 0; while ($tlink =~ m%/[^/]%g) { $level++; }
   return() if ($level < $sp{spi_directory_limit});

   #*-- check if the site has an entry in the robots table
   #*--- LOCK ----*#
   $dbh->execute_stmt("lock tables sp_robots read");
   $command = "select spc_robots_txt from sp_robots where " .
              " spc_site = '$site'";
   ($sth, $db_msg) = $dbh->execute_stmt($command);
   &quit("Command: $command failed --> $db_msg") if ($db_msg);
   (my $robots_txt) = $dbh->fetch_row($sth);
   $dbh->execute_stmt("unlock tables");
   #*--- UNLOCK ----*#

#*--- TEMPORARY
$robots_txt = 'blank';
#*--- TEMPORARY

   #*-- if a robots.txt file has not been retrieved for site
   if ( ($robots_txt ne "blank") && ($robots_txt !~ /\w/) )
    { 
     my $txt = '';
     &upd_stat("Getting the robots file for $site");
     my $filename = "$sp{spc_results_dir}/" . "sp_$spider_num" .
                    "_$url_count" . ".txt";
     $url_count++;
     $txt = '';
     unless (&fetch_URL(
       "$site" . "/robots.txt", $sp{spi_url_timeout}, $filename, 1, 0, 0))
      { open (IN,"<", &clean_filename($filename)) || 
          &quit("Add_links: Could not open $filename $!\n"); 
        undef($/); $txt = <IN>; close(IN); }
    
     &quit('Done') if (&not_running);
     $txt =~ s%<rspider_url.*</rspider_url>%%;  #*-- strip header
    # $txt =~ s/[^\w ]/ /g; 
     $robots_txt =  ( ($txt !~ /\w/) || ($txt =~ /<html>/i) ||
                      ($txt =~ /TextMine get_src cannot fetch/i) ) ? 
                    "blank": $txt;
     unless ($robots_txt eq 'blank') 
          { &upd_stat("Fetched the robots.txt for $site"); }
     else { &upd_stat("Did not find/get a robots.txt for $site"); }

     #*--- LOCK ----*#
     $dbh->execute_stmt("lock tables sp_robots write");
     $command = "replace into sp_robots values ( " .
                "'$site', " . $dbh->quote($robots_txt) . ")";
     (undef, $db_msg) = $dbh->execute_stmt($command );
     &quit("Command: $command failed --> $db_msg") if ($db_msg);
     $dbh->execute_stmt("unlock tables");
     #*--- UNLOCK ----*#
    } #*-- end of if robots.txt
 
   #*-- check the robots file and proceed, allow level 0
   $robot_rules->parse("http://$site" . "/robots.txt", $robots_txt)
             if ($robots_txt ne "blank");
   if ( !$ulevel || ($robots_txt eq "blank") || 
        ($robot_rules->allowed("http://" . "$link")) )
   {  
    (my $domain) = $site =~ /\.?([^.]+\.[^.]+)$/;
    my $priority = &compute_priority(
       $site, $domain, $ulevel+1, $link, $anchor);
 
    #*-- make an entry in the urls table for the link
    #*--- LOCK ----*#
    $dbh->execute_stmt("lock tables $link_table write");

    #*-- check one more time for dups, and return if an entry exists
    $command = "select count(*) from $link_table where " .
               "spc_link = " . $dbh->quote($link);
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    if ( ($dbh->fetch_row($sth))[0]) 
     { $dbh->execute_stmt("unlock tables"); return(0); }
 
    my $l_site = $dbh->quote($site); my $l_link = $dbh->quote($link);
    my $l_url  = $dbh->quote($url);  my $l_level = $ulevel + 1;

    $command  = << "EOF";
     insert into $link_table values ( 
      0, 0.0, $priority, $l_level, -1, 'New', '', $l_site, '', 
      $l_link, $l_url, '')
EOF
    (undef, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    $dbh->execute_stmt("unlock tables");
    #*--- UNLOCK ----*#
 
   }
   else
   { &upd_stat("$site did not allow link $link"); } 
   #*-- end of if robot rules

   return(1);
 
  }
  
 #*--------------------------------------------------
 #*- recompute the priority for unprocessed URLs and
 #*- the relevancy for processed URLs
 #*--------------------------------------------------
 sub recompute
 {
 
  #*-- get the list of unprocessed URLs for this spider
  &upd_stat("Refreshing the priority and relevancy");

  #*--- LOCK ----*#
  $dbh->execute_stmt("lock tables $link_table read");
  $command = "select spc_link, spi_level from $link_table where spc_status";
  $command .= " = 'New' and spf_priority > 0";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  my @links = my @levels = (); my ($link, $level);
  while ( ($link, $level) = $dbh->fetch_row($sth) ) 
   { push(@links, $link); push(@levels, $level); }
  $dbh->execute_stmt("unlock tables");
  #*--- UNLOCK ----*#
 
  for my $i (0..$#links)
   { 
    #*-- distribute the load evenly
    next unless ( ($i % $num_spiders) == $spider_num);

    my $site = "http://" . &get_site($links[$i]);
    (my $domain) = $site =~ /\.?([^.]+\.[^.]+)$/;
    my $priority = &compute_priority($site, $domain, $levels[$i]);

    #*--- LOCK ----*#
    $dbh->execute_stmt("lock tables $link_table write");
    $command  = "update $link_table set spf_priority = $priority ";
    $command .= "where spc_link = " . $dbh->quote($links[$i]);
    (undef, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    $dbh->execute_stmt("unlock tables");
    #*--- UNLOCK ----*#
   }
  &quit('Done') if (&not_running);
 
  #*-- get the list of processed URLs
  #*--- LOCK ----*#
  $dbh->execute_stmt("lock tables $link_table read");
  $command = "select spi_lid, spc_html_file from $link_table where " .
             " spc_status = 'Done'";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  my %uids = (); my ($uid, $spc_html_file);
  while ( ($uid, $spc_html_file) = $dbh->fetch_row($sth) ) 
   { next unless ($spc_html_file); $uids{$uid} = $spc_html_file; }
  $dbh->execute_stmt("unlock tables");
  #*--- UNLOCK ----*#
 
  my $i = 0;
  foreach my $uid (keys %uids)
   {
    #*-- skip  relevancy recompute unless requested
    next unless ($sp{spc_recompute} =~ /y/i);
    next unless ( ($i++ % $num_spiders) == $spider_num);  
                #*-- distribute the load
    open (IN, "<", &clean_filename($uids{$uid})) || 
        &quit("Recompute: Could not open $uids{$uid} $!"); 
    undef($/); my $html = <IN>; close(IN);
    (my $ref_text) = &parse_HTML($html, ''); 

    #*--- LOCK ----*#
    $dbh->execute_stmt("lock tables $link_table write");
    $command  = "update $link_table set spf_relevance = " . 
        &compute_relevancy($$ref_text) . "where spi_lid = $uid";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    $dbh->execute_stmt("unlock tables");
    #*--- UNLOCK ----*#
    &quit('Done') if (&not_running);
   }

 }
  
 #*--------------------------------------------------
 #*-- compute the relevancy based on
 #*--  1. The frequency of occurrence of keywords
 #*--  2. The distance between keywords in the text
 #*--------------------------------------------------
 sub compute_relevancy
  {
   my ($text) = @_;
 
   #*-- assign a default relevance in the absence of keywords
   return (10 + sprintf("%6.4f", rand() ) ) unless (@keys);

   #*-- check for occurrence of the keywords globally in text
   #*-- assign relevancy in descending order of keywords
   my $relevancy = 0;
   local $" = '|'; my $q_reg = qr/(@keys)/i; $" = ' ';
   while ($text =~ /$q_reg/g) 
    { 
     my $key = $1; my $kval = -1;
     for my $i (0..$#keys) { $kval = $i if ($key =~ /$keys[$i]/i); }
     $relevancy += RELEVANCE_WT / (2 ** $kval) if ($kval >= 0);
    }

   #*-- relevancy is inversely proportional to dist. between words
  # my @q_reg = ();
  # for my $i (0..($#keys - 1))
  #  { push (@q_reg, qr/$keys[$i](.*?)$keys[$i+1]/); }
  # 
  # for my $i (0..($#keys - 1))
  #  { while ($text =~ /$q_reg[$i]/g)
  #     { $relevancy += 5 / (length($1) + 1); }    
  #  } #*-- end of for
       

   #*-- add a random fraction value to generate consistent rankings
   #*-- for identitical relevancies
   return ($relevancy + sprintf("%6.4f", rand() ) );
 
  }
 
 #*--------------------------------------------------
 #*- return the priority
 #*--------------------------------------------------
 sub compute_priority
 {
  my ($site, $domain, $level, $link, $anchor) = @_;
 
  #*-- set the priority based on 
  #*-- 1. A high priority Domain 
  #*-- 2. Breadth first or depth first 
  #*-- 3. No. of Pages from this site
  #*-- 4. Occurrence of search keywords in anchor or link

  #*-- baseline priority
  my $priority  = 10;	

  #*-- 1. check for priority domain
  $priority += 100 if ( $sp{spc_priority_domain} && 
                        ($domain =~ /$sp{spc_priority_domain}/i) );

  #*-- 2. assign priority based on depth first or breadth first
  $priority += (RELEVANCE_WT / ( ($level * 10) + 1) ) 
               if ($sp{spc_search_type} =~ /^b/i );
  $priority += ($level * 10)
               if ($sp{spc_search_type} =~ /^d/i );
 
  #*-- 3. count the number of pages from this site and reduce priority 
  #*-- for pages from same site
  #*--- LOCK ----*#
  $dbh->execute_stmt("lock tables $link_table read");
  $command = "select count(*) from $link_table " .
             " where spc_site = " . $dbh->quote($site);
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  $priority -= ( ($dbh->fetch_row($sth))[0] * 10);
  $dbh->execute_stmt("unlock tables");
  #*--- UNLOCK ----*#

  #*-- 4. check if the link or anchor contains any of the keywords
  #*--    decreasing importance in order of keywords 
  foreach my $val ($link, $anchor)
   { next unless($val);  next if ($val !~ /\w/);
     foreach my $i (0..$#keys)
      { 
        if ( ($keys[$i] =~ /\w/) && ($val =~ /$keys[$i]/i) ) 
          { $priority += (RELEVANCE_WT / (2 ** $i) ); } 
      }
   }

  return ($priority);
 }
  
 #*--------------------------------------------------
 #*-- compute the abstract based on
 #*--------------------------------------------------
 sub compute_abstract
 {
  my ($text) = @_;
  my ($abs);

  #*-- build the regular expression, starting with the
  my $separator = "..!!!..";
  unless (@keys)
    { ($abs) = $text =~ /^(.{0,255}\b)/; $abs .= "$separator"; }
#    { $summary = &summary(\$text, 'web', 'brief', $dbh, '', 2, $hash_refs); }
  else
   { #*-- build some text on either side of the key
    my $re = '(\b.{0,30})(';
    foreach my $key (@keys)
     {$key =~ s/%/\\%/g;$key =~ s/^\s+//;$key =~ s/\s+$//;$re .= "$key|";}
    $re =~ s/\|$/)/; $re .= '(.{0,30}\b)';

    $abs = ""; my $i = 0; #*-- keep the first 3 lines
    while ($text =~ m%$re%gi)
     { $abs .= "$1" . "$2" . "$3" . "$separator"; last if (++$i == 3); }
    if (length($abs) < 100)  #*-- if abstract is small, pad with text
      { $text =~ /^(.{0,155}\b)/; $abs .= "$1" . "$separator"; }
   }

  #*-- clean the abstract
  $abs =~ s/[^a-zA-Z0-9\.,;:]/ /sg; $abs =~ s/\ +/ /g;
  $abs =~ s/$separator/...\n/g; 
  return ($abs);
 }
       
 
 #*--------------------------------------------------
 #*- check if the link is valid or not, return t or f
 #*--------------------------------------------------
 sub valid_link
 {
   my ($link, $anchor, $url, $relevancy) = @_;

   my $mval = 10; #*-- start match value

   #*-- skip ads and media files and other links
   return(0) if ( ($link !~ m%^[\w/]%)  
         || ($link =~ /\.(jpg|jpeg|gif|pdf|ps|doc|xls|ppt|mpg|mpeg|gz)$/i)
         || ($link =~ /doubleclick/i) );

   #*-- check if the link or anchor match any one of the keywords
   #*-- if a keyword matches, we don't want to lose the link
   if (@keys)
    { foreach my $i (0..$#keys) 
        { $mval += RELEVANCE_WT / (2 ** $i) 
            if ( ($anchor =~ /$keys[$i]/i) || ($link =~ /$keys[$i]/i) ); } }
   else { $mval += RELEVANCE_WT; }

   #*-- get the dir names of the url and link, and check if the link
   #*-- is below the dir of the url
   my $lsite = &get_site($link); my $usite = &get_site($url); 
   $url =~ s%[^/]+$%% if ($url =~ m%/%); 
   $mval += 100 if ( ($link =~ /$url/i) || ($link =~ m%^/%) );

   #*-- assign a higher values to external links
   $mval += ($usite =~ /$lsite/i) ? 10:30; 

  #*-- weight by relevance of page
  # $mval *= ($relevancy / 100); 

   return(0) if ($mval < 30); #*-- a cut off limit for traversal
   return(1);
 }

 #*--------------------------------------------------
 #*- check if we are running or not
 #*--------------------------------------------------
 sub not_running
 {
  #*-- check for termination criteria
  #*--- LOCK ----*#
  $dbh->execute_stmt("lock tables sp_search read");
  my $command  = "select spc_status from sp_search where spi_id = $spi_id";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  my $retval = ( ($dbh->fetch_row($sth))[0] !~ /running/i) ? 1:0;
  $dbh->execute_stmt("unlock tables");
  #*--- UNLOCK ----*#
  return($retval);
 }

 #*--------------------------------------------------
 #*- Update the co_proctab table entry for the spider
 #*--------------------------------------------------
 sub upd_stat
 {
  my ($stat) = @_;
  my ($diff, $diff_hour);

  #*-- prefix a timer in front of the status line
  $diff = time() - $start_time; 
  $stat = (gmtime($diff))[1] . ":" . (gmtime($diff))[0] . " => $stat";
  $stat =~ s/^(\d+):(\d) /$1:0$2 /; 
  $diff_hour = (gmtime($diff))[2];
  if ($diff_hour > 0)
   { $stat = "$diff_hour:" . $stat; $stat =~ s/^(\d+):(\d):/$1:0$2:/; }
  $stat = "S$spider_num " . $stat;

  #*--- LOCK ----*#
  $dbh->execute_stmt("lock tables co_proctab write");
  my $command = "select prc_logdata from co_proctab where pri_tid = $tid";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  my ($prc_logdata) = $dbh->fetch_row($sth);
  $prc_logdata .= " $stat ###"; 

  $command  = "update co_proctab set prc_status = " . $dbh->quote($stat) .
    " , prc_logdata = " . $dbh->quote($prc_logdata) . " where pri_tid = $tid";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  $dbh->execute_stmt("unlock tables");
  #*--- UNLOCK ----*#

  return();
 }

 #*--------------------------------------------------
 #*- clean up and exit 
 #*--------------------------------------------------
 sub quit
 {
  my ($tstat) = @_;
  my $status;

  #*-- check if completed normally
  $dbh->execute_stmt("unlock tables", 1);
  if ($tstat eq 'Done') { $status = 'Done'; }
  else                  { $status = 'Stopped'; &upd_stat("$tstat"); }

  #*--- LOCK ----*#
  $dbh->execute_stmt("lock tables sp_search write");
  (undef, $db_msg) = $dbh->execute_stmt(  
     "update sp_search set spc_status = '$status' where spi_id = $spi_id")
     if ($spider_num == 0);
  $dbh->execute_stmt("unlock tables", 1);
  #*--- UNLOCK ----*#

  &upd_stat(" Spider $spider_num was stopped:");
  $dbh->disconnect_db($sth);
  exit;
 
 }
 
__DATA__

=head1 NAME

sp_b_spider

=head1 SYNOPSIS

 Multiple copies of this spider run concurrently.
 Each spider is started with a separate spider
 number. Some functions are performed by a master
 spider (spider 0) alone. Other functions which
 can be performed concurrently are run on all
 spider processes. Communication between spiders
 is exclusively through database tables. Locks on
 tables to read and write are used to manage concurrency.

=head1 DESCRIPTION

 This spider runs tull termination criteria are met or
 explicitly stopped. Each spider makes an entry in a 
 process table. Each row of the process table contains
 a log and the current status of the spider. A spider
 checks a table for urls to process. If none, are available,
 it waits for 10 minutes to allow other spiders to load
 the table. Otherwise, it terminates

 If an URL is available, it is retrieved and processed, i.e.
 links are extracted and the relevancy of the text of the
 URL is computed. Priorities are assigned to the links from
 the URL depending on various parameters.

=head1 Function Call Structure

 - Main
   :set_vars
   :get_parameters
   :recompute
   :check_for_urls
   :process_url
 - process_url
   :fetch_url
   :compute_relevancy
   :add_links
 - recompute
   :compute_priority
   :compute_relevancy
 - quit

=head1 AUTHOR

Manu Konchady (mkonchady@yahoo.com)
