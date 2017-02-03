#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------------------
 #*- ne_rss_collector.pl
 #*-  
 #*-   Summary: Collect the news and save the information in tables
 #*-            This process runs in parallel. It receives 2 parameters
 #*-            the process number and the total number of processes
 #*-            in the ensemble. Process 0 performs the sequential
 #*-            parts and the other processes the parallel tasks.
 #*-
 #*-  DB Tables		Description
 #*-  ----------	-------------------------------------------
 #*-  ne_sources	A list of sources that provide links to articles
 #*-  ne_articles	List of articles collected with assoc. info
 #*-  ne_clusters	List of clusters with member articles
 #*-  ne_index		Index to search the articles
 #*-
 #*----------------------------------------------------------------

 use strict; use warnings;
 use XML::RSS::Parser;
 use TextMine::DbCall;
 use TextMine::Constants qw($TMP_DIR $DB_NAME $DELIM clean_filename);
 use TextMine::MyURL     qw(parse_HTML fetch_URL get_site);
 use TextMine::Index     qw(add_index text_match);
 use TextMine::Tokens    qw(load_token_tables);
 use TextMine::Summary   qw(phrases_ex summary);
 use TextMine::Cluster;
 use TextMine::Utils;

 #*-- global variables
 our ($dbh,		#*-- database handle
      $sth,		#*-- statement handle
      $db_msg,		#*-- database error message
      $command,		#*-- SQL command
      $proc_num,	#*-- process number
      $num_procs,	#*-- total number of processes
      $TMP,		#*-- temporary directory name
      $debug,		#*-- debug flag
      @ids		#*-- ids for collected articles
     );

 #*-- do initial processing
 &set_vars();
                                 
 #*-- collect the text of the news web pages
 &collect_data();

 #*-- Generate summary and index 
 &gen_summary();

 #*-- leave the rest to process 0
 &clean_up() if ($proc_num); 

 #*-- cluster the documents
 &gen_clusters();

 #*-- exit
 &clean_up();

 #*----------------------------------------------
 #*- Initialize variables                
 #*----------------------------------------------
 sub set_vars
 {
  #*-- get the processor number and number of processors
  ($proc_num, $num_procs) = split/$DELIM/, $ARGV[0];

  my $userid = 'tmadmin'; my $password = 'tmpass';
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
        'Userid' => $userid, 'Password' => $password, 'Dbname' => $DB_NAME);

  #*-- Complete sequential parts in proc 0, clean up the news tables
  $TMP = $TMP_DIR . 'news';
  unless ($proc_num)
   {
    (undef, $db_msg) = 
       $dbh->execute_stmt("lock tables ne_index write, ne_sources write,
                           ne_articles write, ne_clusters write");
    (undef, $db_msg) = $dbh->execute_stmt("delete from ne_index");
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    (undef, $db_msg) = $dbh->execute_stmt("delete from ne_articles");
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    (undef, $db_msg) = $dbh->execute_stmt("delete from ne_clusters");
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    (undef, $db_msg) = $dbh->execute_stmt(
                       "update ne_sources set nec_status = ' '");
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    (undef, $db_msg) = $dbh->execute_stmt("unlock tables");
    mkdir $TMP unless (-e $TMP);
    unlink glob("$TMP/*");  #*-- clean out the temporary directory
   }                        #*-- give processor 0 time to finish
  else { sleep(3); }        #*-- end of unless

  $debug = 1;  
  my $filen = "$TMP/debug_" . "$proc_num" . ".txt";
  if ($debug) { open (OUT, ">", "$filen") || 
     &quit ("Unable to open $filen $!\n"); binmode OUT, ":raw"; }
 }


 #*----------------------------------------------
 #*- Collect the pages in parallel       
 #*----------------------------------------------
 sub collect_data
 {
  #*-- get the urls, match condition, and images flag for each source
  (undef, $db_msg) = $dbh->execute_stmt("lock tables ne_sources read");
  $command = "select nec_url, nec_match_condition, nec_get_images" 
          .  " from ne_sources";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  my @urls = my @conditions = my @get_images = ();
  while ( my ($url, $condition, $get_images) = $dbh->fetch_row($sth) )
   { push (@urls, $url); push (@conditions, $condition); 
     push (@get_images, $get_images); }
  (undef, $db_msg) = $dbh->execute_stmt("unlock tables");

  #*-- get the web page associated with each URL
  #*-- distribute the load evenly based on the processor number
  #*-- lock not needed here.......
  my $timeout = 60; my $q_status = ''; 
  for my $i (0..$#urls)
  {
   next unless ( ($i % $num_procs) == $proc_num);
   print OUT "Will process $urls[$i]\n" if ($debug);
   my $filename = "$TMP/" . "nec_$i" . "_$proc_num" . ".xml"; my $html;
   unless ( &fetch_URL($urls[$i], $timeout, $filename, 1, $get_images[$i], 
                       $debug, $proc_num) )
    {
     open (IN, "<", &clean_filename("$filename")) ||
        &quit("Could not open $filename $!\n");
     undef($/); $html = <IN>; 
     $html =~ s/^.*<\?xml/<?xml/si; #*-- remove first line added 
     close(IN);

     #*-- get the links to the stories from the source page
     print OUT "Fetched page of length ", length($html), " \n" if ($debug);

     #*-- Parse the XML File to get the links to news articles
     #*-- with the description
     my %links = ();
     my $rss_parser = new XML::RSS::Parser;
     my $rss_feed = $rss_parser->parsefile(&clean_filename("$filename") );
     foreach my $i ( $rss_feed->items )
      {
        my $link = $i->children("link")->value;
        my $description = $i->children("description")->value;
        $links{$link} = $description;
      }
                                                                                
     #*-- populate the ne_articles table
     print OUT "Found ", scalar keys %links, " links: $urls[$i] \n" if ($debug);
     (undef, $db_msg) = $dbh->execute_stmt( "lock tables ne_articles write");
     foreach my $link (keys %links)
      {
       my $q_link = $dbh->quote($link);
       my $q_descr = $dbh->quote($links{$link});
       $command = <<"EOF";
        insert into ne_articles set nei_nid = 0, nec_url = $q_link,
        nec_local_url = '', nec_abstract = $q_descr, nei_size = 0,
        nec_similar_ids = '', nec_text = '', nec_status = '', nei_cdate = 0
EOF
       (undef, $db_msg) = $dbh->execute_stmt($command);
       &quit("Command: $command failed --> $db_msg") if ($db_msg);
      }
     (undef, $db_msg) = $dbh->execute_stmt("unlock tables");
     $q_status = "'Done'";
    }
   else { $q_status = $dbh->quote("Failed to fetch $i in $timeout secs."); }

   #*-- update the status of the source to done or failed..
   (undef, $db_msg) = $dbh->execute_stmt("lock tables ne_sources write");
   my $q_url = $dbh->quote($urls[$i]);
   $command = "update ne_sources set nec_status = $q_status where " .
              "nec_url = $q_url";
   (undef, $db_msg) = $dbh->execute_stmt($command);
   &quit("Command: $command failed --> $db_msg") if ($db_msg);
   (undef, $db_msg) = $dbh->execute_stmt("unlock tables");

  } #*-- end of for my $i

  #*-- wait till all processes finish populating the articles table
  my $i = 0;
  while ( &not_extracted() ) { sleep(3); last if (++$i >= 10); }

  #*-- get the list of all articles to be processed
  (undef, $db_msg) = $dbh->execute_stmt("lock tables ne_articles read");
  $command = "select nei_nid, nec_url from ne_articles";
  ($sth, $db_msg) = $dbh->execute_stmt("$command");
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  @urls = @ids = ();
  while ( (my $id, my $url) = $dbh->fetch_row($sth) )
   { push(@ids, $id); push (@urls, $url); }
  (undef, $db_msg) = $dbh->execute_stmt("unlock tables");

  #*-- loop thru all articles till completion
  #*-- distribute the load evenly based on the processor number
  my ($q_stat, $q_url, $q_text, $size);
  for my $i (0..$#ids)
  {
   next unless ( ($i % $num_procs) == $proc_num);
   my $filename = "$TMP/" . "nea_$i" . "_$proc_num" . ".html"; my $html;

   #*-- use the printable version of the URL
   if ($urls[$i] =~ /bbc\.co/i)
    { $urls[$i] =~ s%^http://%%;
      $urls[$i] = 'http://newsvote.bbc.co.uk/mpapps/pagetools/print/' .  
                  $urls[$i]; 
    }
   elsif ($urls[$i] =~ /yahoo/i)
    { $urls[$i] .= '&printer=1'; }

   #*-- fetch the news article
   print OUT "Fetching $urls[$i] \n" if ($debug);
   unless ( &fetch_URL($urls[$i], $timeout, $filename, 1, 0, 
                                  $debug, $proc_num) )
    {
     open (IN, "<", &clean_filename("$filename")) ||
        &quit("Could not open $filename $!\n");
     undef($/); $html = <IN>; close(IN);

     #*-- clean up the html and get the article text alone
     $size = length($html);
     if ( length($html) < 10 )
     { $q_stat = $dbh->quote("$urls[$i] contained too little text"); 
       $q_url = $q_text = "''"; }
     else
     {
       (my $r_text, undef) = &parse_HTML($html, '');
       $q_stat = $dbh->quote("Text found");
       $q_text = $dbh->quote($$r_text);
       $q_url  = $dbh->quote('file://localhost/' . $filename);
     } #*-- end if length....
    }
   else
    { $q_stat =  $dbh->quote("Failed to fetch $ids[$i] in $timeout secs.");
      $q_url = $q_text = "''"; $size = 0; }

   #*-- update the ne_articles table
   print OUT "Updating $ids[$i] with status $q_stat\n" if ($debug);
   (undef, $db_msg) = $dbh->execute_stmt(
                             "lock tables ne_articles write");
   my $cdate = time();
   $command = <<"EOF";
      update ne_articles set nei_size = $size, nec_status = $q_stat, 
        nec_local_url = $q_url, nec_text = $q_text, nei_cdate = $cdate
        where nei_nid = $ids[$i]
EOF
   (undef, $db_msg) = $dbh->execute_stmt($command);
   &quit("Command: $command failed --> $db_msg") if ($db_msg);
   (undef, $db_msg) = $dbh->execute_stmt("unlock tables");

  } #*-- end of for

 }

 #*----------------------------------------------
 #*- Generate the summary and dump        
 #*----------------------------------------------
 sub gen_summary
 {

  #*-- get the ids of articles w/o an abstract that have been 
  #*-- successfully fetched 
  (undef, $db_msg) = $dbh->execute_stmt("lock tables ne_articles read");
  $command = "select nei_nid from ne_articles where nec_status = 'Text found'";
  ($sth, $db_msg) = $dbh->execute_stmt("$command");
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  @ids = ();
  while ( (my $id) = $dbh->fetch_row($sth) ) { push(@ids, $id); }
  (undef, $db_msg) = $dbh->execute_stmt("unlock tables");

  #*-- load the token tables
  my $hash_refs = &load_token_tables($dbh);

  #*-- compute the summary for each article in parallel
  for my $i (0..$#ids)
   {
    next unless ( ($i % $num_procs) == $proc_num); 

    #*-- fetch the text of the artile
    (undef, $db_msg) = $dbh->execute_stmt("lock tables ne_articles read");
    $command = "select nec_text from ne_articles where nei_nid = $ids[$i] ";
    ($sth, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    (my $text) = $dbh->fetch_row($sth);
    (undef, $db_msg) = $dbh->execute_stmt("unlock tables");

    #*-- index the document
    print OUT "Computing index for $ids[$i]\n" if ($debug);
    &add_index($ids[$i], $text, 'ne', $dbh);
    (undef, $db_msg) = $dbh->execute_stmt("unlock tables");
    
   } #*-- end of for
 }

 #*----------------------------------------------
 #*- Cluster the documents
 #*----------------------------------------------
 sub gen_clusters
 {
  #*-- get the list of documents with abstracts
  my @docs = @ids = ();
  $command = "select nei_nid, nec_text from ne_articles where " .
             "nec_status = 'Text found' and nec_abstract != ''";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  while (my ($id, $text) = $dbh->fetch_row($sth) )
   { push (@ids, $id); push @docs, \"$text"; }
  
  #*-- build the clusters using IDF, one_link clusters, and a 0.2 threshold 
  my ($r_clusters, $r_matrix) = 
     &cluster(\@docs, 'idf', $dbh, 'news', 'one_link', '0.2');

  #*-- use the matrix to find related ids
  my @matrix = @{$r_matrix};
  for my $i (0..$#docs)
   { 
    my $members = ''; my $j = 0;
    for my $id (sort {$matrix[$i][$b] <=> $matrix[$i][$a]} (0..$#docs) )
     { $members .= "$ids[$id],"; last if (++$j == 10); }
    $members =~ s/,$//;
    (undef, $db_msg) = $dbh->execute_stmt("lock tables ne_articles write");
    $command = "update ne_articles set nec_similar_ids = '$members' " .
               " where nei_nid = $ids[$i]";
    (undef, $db_msg) = $dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    (undef, $db_msg) = $dbh->execute_stmt("unlock tables");
   } #*-- end of for

  #*-- build the label for each cluster
  my @clusters = @$r_clusters; 
  my @titles = my @sizes = my @members = ();
  foreach my $i (0..$#clusters)
   {
    #*-- build the text for the cluster member
    my @c_docs = split/,/, $clusters[$i];
    if ($i == $#clusters) 
     { push (@titles, 'Miscellaneous Cluster'); push (@sizes, 0); }
    else
     { 
      my $text = ''; $text .= ${$docs[$_]} foreach (@c_docs);

      #*-- extract the phrases
      (my $r_bigrams) = &phrases_ex(\$text, 3, $dbh);
      push (@titles,  join ("; ", @$r_bigrams) );
      push (@sizes,   scalar @c_docs);
     } #*-- end of if

    push (@members, join (",",  map { $ids[$_] } @c_docs) );
   } #*-- end of for clusters

  #*-- build the clusters table - size, title, member list
  (undef, $db_msg) = $dbh->execute_stmt("lock tables ne_clusters write");
  $command = "delete from ne_clusters";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);

  for my $i (0..$#clusters)
  {
   my $q_members  = $dbh->quote($members[$i]);
   my $q_title    = $dbh->quote($titles[$i]);
   $command = <<"EOF";
     insert into ne_clusters set nei_cid = 0, nei_size = $sizes[$i],
       nec_members = $q_members, nec_title = $q_title
EOF
   (undef, $db_msg) = $dbh->execute_stmt($command);
   &quit("Command: $command failed --> $db_msg") if ($db_msg);
  } #*-- end of for
  (undef, $db_msg) = $dbh->execute_stmt("unlock tables");

 }

 #*------------------------------------------------------------------------
 #*- return T or F depending on whether all article links have been extracted
 #*------------------------------------------------------------------------
 sub not_extracted
 {  
  my $retval = 0;
  (undef, $db_msg) = $dbh->execute_stmt("lock tables ne_sources read");
  $command = "select nec_status from ne_sources";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  while ( (my $status) = $dbh->fetch_row($sth) )
   { unless ($status =~ /\S/) { $retval = 1; last; } } 
  (undef, $db_msg) = $dbh->execute_stmt("unlock tables");
  return ($retval);
 }

 #*----------------------------------------------
 #*- clean up and terminate 
 #*----------------------------------------------
 sub clean_up
 { $dbh->disconnect_db(); close(OUT) if ($debug); exit(0); }

 #*----------------------------------------------
 #*- dump a message if possible and exit
 #*----------------------------------------------
 sub quit
 {
  my ($msg) = @_;
  if ($debug)
   { print OUT ("$msg\n"); print OUT ("Terminated\n"); close(OUT); }
  (undef, undef) = $dbh->execute_stmt("unlock tables");
  $dbh->disconnect_db();
  exit(0);
 }
