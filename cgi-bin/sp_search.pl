#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
 #*----------------------------------------------------------------
 #*- sp_search.pl
 #*-  
 #*-   Summary: View and create searches for the spider  
 #*----------------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Constants;
 use TextMine::Utils;
 use TextMine::MyProc;
 use TextMine::MyURL qw(get_site);
 use TextMine::MailUtil;

 #*-- set the constants
 use vars (
  '$dbh',		#*-- database handle
  '$sth',		#*-- statement handle
  '$stat_msg',		#*-- status message for the page
  '$db_msg',		#*-- database error message
  '$command',		#*-- field for SQL command
  '$ref_val',		#*-- reference variable
  '%esq',		#*-- escaped form fields
  '$FORM',		#*-- name of form 
  '%in',		#*-- hash for form fields
  '@PARMS',		#*-- a spider search parameters
  '$e_session'		#*-- URL encoded session field
  );

 #*-- retrieve and set variables
 &set_vars();

 #*-- handle the selection of the link file
 &file_chooser();

 #*-- handle the selection of a directory
 &dir_chooser();

 #*-- handle the e_opshuns 
 &vis_search()    if ($in{e_opshun} eq 'Visualize');
 &add_search()    if ($in{e_opshun} eq 'Save');
 &upd_search()    if ($in{e_opshun} eq 'Update');
 &res_search()    if ($in{e_opshun} eq 'Reset');
 &del_search()    if ($in{e_opshun} eq 'Delete');
 &fil_search()    if ($in{e_opshun} eq 'Edit');
 &start_search()  if ($in{e_opshun} eq 'Start');
 &stop_search()   if ($in{e_opshun} eq 'Stop');

 #*-- dump the header, status, body and tail html 
 &head_html(); 
 my $body_html = 
    ${$ref_val = ($in{opshun} eq 'View') ? &view_html(): &entry_html()};
 &msg_html($stat_msg) if ($stat_msg); 
 print ("$body_html\n");
 &tail_html(); 

 exit(0);

 #*-----------------------------------------------------
 #*- Set some global vars            
 #*-----------------------------------------------------
 sub set_vars
 {
  #*-- retrieve the passed parameters
  $0 =~ s%.*[/\\]%%; $FORM = "$CGI_DIR" . "$0";
  %in    = %{$ref_val = &parse_parms};

  #*-- establish a DB connection
  ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $in{userid}, 'Password' => $in{password},
       'Dbname' => $DB_NAME);

  #*-- check and make sure that there is at least one search
  #*-- LOCK --
  $dbh->execute_stmt("lock tables sp_search read");
  ($sth,$db_msg) = $dbh->execute_stmt("select count(*) from sp_search");
  &quit("$command failed: $db_msg") if ($db_msg);
  $in{opshun} = 'New' unless ( ($dbh->fetch_row($sth))[0] );
  $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --

  #*-- define the fields for the spider search
  @PARMS = qw/
 	      spi_url_limit     spi_url_timeout  spi_url_count 
	      spi_spiders 	spi_maxsite_urls spc_priority_domain
              spi_time_limit    spi_level_limit  spi_directory_limit   
              spc_search_type   spc_get_images   spc_recompute   
              spc_status        spc_descr        spc_keywords      
              spc_link_file   	spc_results_dir 
              spc_blocked_sites spc_selected_sites     
             /;

  #*-- set the forgetful parms
  &mod_session($dbh, $in{session}, 'del', 'opshun', 'e_opshun', 
   'n_opshun', 'dir_opshun', 'file_opshun');

  #*-- initialize the parms
  foreach (qw/dir_opshun file_opshun e_opshun opshun n_opshun/)
   { $in{$_} = '' unless $in{$_}; }
  $e_session = &url_encode($in{session}); $stat_msg = '';
 }

 #*--------------------------------------------
 #*- return the number of entries in sp_search
 #*--------------------------------------------
 #sub count_entries
 #{
 # ($sth, $db_msg) = $dbh->execute_stmt("select count(*) from sp_search");
 # &quit("$command failed: $db_msg") if ($db_msg);
 # return ( ($dbh->fetch_row($sth))[0] );
 #}

 #*-----------------------------------------
 #*- Choose the directory for the results 
 #*-----------------------------------------
 sub dir_chooser
 {
  #*-- if choosing a directory
  return() if ($in{file_opshun});
  if ($in{dir_opshun} eq 'selecting_dir')
   {
    &mini_head_html();
    my $body_html = ${$ref_val =
    &dirChooser($FORM,$in{dir_cdrive},
              'Select a Directory',0,$in{session})};
    print ("$body_html\n");
    &mini_tail_html();
    exit(0);
   }

  #*-- if we have chosen a directory, then set the results drive field
  if ($in{dir_opshun} eq "OK")
   { $in{spc_results_dir} = $in{dir_cdrive}; $in{opshun} = 'Edit';return(); }

  #*-- if option is to choose a dir, display the select screen
  if ($in{dir_opshun} eq "Select a Directory")
   {
    &mini_head_html();
    my $body_html = ${$ref_val =
     &dirChooser($FORM,$in{spc_results_dir}, 
                          $in{dir_opshun}, 0, $in{session})};
    print ("$body_html\n");
    &mini_tail_html();
    exit(0);
   }

 }

 #*-----------------------------------------
 #*- Choose the file for the links 
 #*-----------------------------------------
 sub file_chooser
 {
  #*-- if choosing a file
  return() unless ($in{file_opshun});
  if ($in{dir_opshun} eq 'selecting_dir')
   {
    $in{dir_opshun} = '';
    &mini_head_html();
    my $body_html = ${$ref_val = &dirChooser( $FORM,
       $in{dir_cdrive}, 'Select a File', 1, $in{session}) };
    print ("$body_html\n");
    &mini_tail_html();
    exit(0);
   }

  #*-- if we have chosen a directory, then set the current drive field
  if ($in{dir_opshun} eq "OK")
   { $in{spc_link_file} = $in{dir_cdrive};
     $stat_msg .= " --<font color=red> Warning: </font> $in{spc_link_file}"
               .  " is not a file or does not exist...<br>"  
                  unless(-f $in{spc_link_file});
     $in{opshun} = 'Edit';
     return(); }

  #*-- if option is to choose a file, display the select screen
  if ($in{file_opshun} eq "Select a File")
   {
    &mini_head_html();
    my $body_html = ${$ref_val = &dirChooser( $FORM,
       $in{spc_link_file}, "Select a File", 1, $in{session})};
    print ("$body_html\n");
    &mini_tail_html();
    exit(0);
   }

 }

 #*---------------------------------------------------------------
 #*- add the search, if possible and set the status message
 #*---------------------------------------------------------------
 sub add_search
 {

  #*-- check for any errors in entering data
  my $fh; return() if ( ($fh = &edit_fields()) eq 'Error');

  if ( ($dbh->fetch_row($sth))[0])
   { $stat_msg .= "<font color=darkblue>" . $in{spc_descr} . 
                  "</font> exists in the table, Press Update<br>"; 
     $in{opshun} = 'Edit';
     return(); }

  #*-- build the insert statement
  #*-- LOCK --
  $esq{spc_status} = "'New Search'";
  $dbh->execute_stmt("lock tables sp_search write");
  $command = "insert into sp_search set spi_id = 0, spi_date = " . time();
  $command .= " ,$_ = $esq{$_}" foreach (@PARMS);
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --
                               
  #*-- create the link table for the search
  (my $descr = substr($in{spc_descr},0,20)) =~ s/[^A-Za-z]/o/g; 
  my $link_table    = "sp_" . $descr . "_links"; 

  $command = "drop table if exists $link_table";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  $command = <<"EOF";
  create table $link_table (
    spi_lid        integer not null unique auto_increment,
    spf_relevance  float,
    spf_priority   float,
    spi_level      integer, 
    spi_spider     integer,
    spc_status     char(15),
    spc_html_file  char(100),
    spc_site       char(100),
    spc_abstract   char(255),
    spc_link       char(255) not null primary key,
    spc_parent_link char(255) not null,
    spc_signature  char(255)
   )
EOF
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  #*-- load the link table
  my @lines = <$fh>;
  close($fh);
  #*------------------------------------------------------
  #*- changed insert to replace in sql stmt. to avoid
  #*- problems with dups in links
  #*------------------------------------------------------
  foreach my $link (@lines)
   {
    #*-- skip comments
    chomp($link);           next if ($link =~ /^#/);
    $link =~ s%^http://%%i; $link =~ s%[/\\]$%%; #*-- strip trailing slash
    my $stat = ($link =~ s/^!//) ? "'Skip'": "'New'";
    my $site = &get_site($link);
    $site = $dbh->quote($site); $link = $dbh->quote($link);
    $command = <<"EOF";
      replace into $link_table values (0, 0.0, 5000.0, 0, -1, $stat, ' ',
          $site, '', $link, $link, '')
EOF
    (undef, $db_msg) = $dbh->execute_stmt($command);
    &quit("$command failed: $db_msg") if ($db_msg);

   } #*-- end of foreach

  #*-- create the index table for the search
  my $index_table    = "sp_" . $descr . "_index";
  my $index_table_ix = $index_table . "_ix";
  $command = "drop table if exists $index_table";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  $command = <<"EOF";
  create table $index_table (
    inc_word       char(100) not null,
    inc_ids        char(255),
    index $index_table_ix (inc_word)
   )
EOF
#    fulltext (inc_word)
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);

  $stat_msg .= "-- The <font color=darkblue> " . $in{spc_descr} . 
               "</font> search was added,<br>";

 }

 #*---------------------------------------------------------------
 #*- Update an existing entry 
 #*---------------------------------------------------------------
 sub upd_search
 {
  #*-- check for any errors in entering data
  my $fh; return() if ( ($fh = &edit_fields()) eq 'Error');

  unless ( ($dbh->fetch_row($sth))[0])
   { $stat_msg .= "<font color=darkblue>" . $in{spc_descr} . 
                  "</font> does not exist in the table, Press Save,<br>"; 
     return(); }

  #*-- load the link table, but first get the list of completed links
  (my $descr = substr($in{spc_descr},0,20)) =~ s/[^A-Za-z]/o/g; 
  my $link_table    = "sp_" . $descr . "_links"; 
  my ($link, %done_links);
  #*-- LOCK --
  $dbh->execute_stmt("lock tables $link_table read");
  $command = "select spc_link from $link_table where spc_status = 'Done'";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  $done_links{$link}++ while ( ($link) = $dbh->fetch_row($sth) );
  $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --

  my @lines = <$fh>;
  close($fh);
  foreach $link (@lines)
   {
    next if ($link =~ /^#/);
    chomp($link); $link =~ s%^http://%%i;
    next if ($done_links{$link});
    my $stat = ($link =~ s/^!//) ? "'Skip'": "'New'";
    my $site = &get_site($link);
    $site = $dbh->quote($site); $link = $dbh->quote($link);
  #*-- LOCK --
    $dbh->execute_stmt("lock tables $link_table write");
    $command = <<"EOF";
      replace into $link_table values (0, 0.0, 5000.0, 0, -1, $stat, ' ', 
         $site, '', $link, $link, '')  
EOF
    (undef, $db_msg) = $dbh->execute_stmt($command);
    &quit("$command failed: $db_msg") if ($db_msg);
    $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --
   }

  #*-- build the replace statement
  #*-- LOCK --
  $dbh->execute_stmt("lock tables sp_search write");
  $command = "update sp_search set spi_date = " . time();
  $command .= " ,$_ = $esq{$_}" foreach (@PARMS);
  $command .= " where spc_descr = " . $dbh->quote($in{spc_descr});
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --

  $in{opshun} = 'Edit';
  $stat_msg .= "<font color=darkblue>" . $in{spc_descr} . 
               "</font> was changed successfully,<br>";
 }

 #*---------------------------------------------------------------
 #*- Reset an existing entry 
 #*---------------------------------------------------------------
 sub res_search
 {
  #*-- check for any errors in entering data
  my $fh; return() if ( ($fh = &edit_fields()) eq 'Error');

  unless ( ($dbh->fetch_row($sth))[0])
   { $stat_msg .= "<font color=darkblue>" . $in{spc_descr} . 
                  "</font> does not exist in the table, Press Save,<br>"; 
     return(); }

  #*-- load the link table, but first delete the list of links
  (my $descr = substr($in{spc_descr},0,20)) =~ s/[^A-Za-z]/o/g; 
  my $link_table    = "sp_" . $descr . "_links"; 
  #*-- LOCK --
  $dbh->execute_stmt("lock tables $link_table write");
  (undef, $db_msg) = $dbh->execute_stmt("delete from $link_table");
  $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --
  &quit("$command failed: $db_msg") if ($db_msg);

  #*-- delete the index table
  #*-- LOCK --
  my $index_table    = "sp_" . $descr . "_index";
  $dbh->execute_stmt("lock tables $index_table write");
  (undef, $db_msg) = $dbh->execute_stmt("delete from $index_table");
  &quit("$command failed: $db_msg") if ($db_msg);
  $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --
  &quit("$command failed: $db_msg") if ($db_msg);

  my @lines = <$fh>; close($fh);
  foreach my $link (@lines)
   {
    chomp($link); next if ($link =~ /^#/);
    $link =~ s%^http://%%i; $link =~ s%[/\\]$%%; #*-- strip trailing slash
    my $stat = ($link =~ s/^!//) ? "'Skip'": "'New'";
    my $site = &get_site($link);
    $site = $dbh->quote($site); $link = $dbh->quote($link);
  #*-- LOCK --
    $dbh->execute_stmt("lock tables $link_table write");
    $command = <<"EOF";
        insert into $link_table values (0, 0.0, 5000.0, 0, -1, $stat, ' ', 
             $site, '', $link, $link, '')  
EOF
    (undef, $db_msg) = $dbh->execute_stmt($command);
    &quit("$command failed: $db_msg") if ($db_msg);
    $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --
   }

  #*-- build the replace statement
  #*-- LOCK --
  $esq{spc_status} = "'New Search'";
  $dbh->execute_stmt("lock tables sp_search write");
  $command = "update sp_search set spi_date = " . time();
  $command .= " ,$_ = $esq{$_}" foreach (@PARMS);
  $command .= " where spc_descr = " . $dbh->quote($in{spc_descr});
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --

  #*-- clean up the proctab for any previous spider runs
  #*-- LOCK --
  $dbh->execute_stmt("lock tables co_proctab write");
  $command = "delete from co_proctab where prc_sub_tid = $in{spi_id}";
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --

  $in{opshun} = 'Edit';
  $stat_msg .= "<font color=darkblue>" . $in{spc_descr} . 
               "</font> was reset successfully,<br>";
  $in{spc_status} = 'New Search';
 }


 #*---------------------------------------------------------------
 #*- Edit the fields  
 #*---------------------------------------------------------------
 sub edit_fields
 {
  #*--- check for mandatory entries
  unless ($in{spc_descr})  
    { $stat_msg .= "-- The Title field is mandatory,<br>"; }
  unless ($in{spc_link_file})  
    { $stat_msg .= "-- The Link File is mandatory,<br>"; }
  unless ($in{spc_results_dir})  
    { $stat_msg .= "-- The Results Directory is mandatory,<br>"; }
  return('Error') unless ( $in{spc_descr} && $in{spc_link_file} && 
                           $in{spc_results_dir} );

  #*-- check if the link file exists
  unless (-f $in{spc_link_file})
   { $stat_msg .= "$in{spc_link_file} is not a valid file <br>"; 
     return('Error'); }
  open (IN, "<", &clean_filename($in{spc_link_file})) || eval
   { $stat_msg .= "$in{spc_link_file} could not be opened $!<br>"; 
     return('Error'); };

  #*-- check if the directory for the search exists
  unless (-d $in{spc_results_dir})
   { $stat_msg .= "$in{spc_results_dir} is not a valid dir<br>"; 
     return('Error'); }

  #*-- check for a duplicate
  &escape_q(); 
  #*-- LOCK --
  $dbh->execute_stmt("lock tables sp_search read");
  $command  = "select count(*) from sp_search where ";
  $command .= "spc_descr = $esq{spc_descr}";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --

  return(*IN);
 }

 #*---------------------------------------------------------------
 #*- Visualize an existing entry's network using Pajek
 #*---------------------------------------------------------------
 sub vis_search
 {
  #*-- check for any errors in entering data
  my $fh; return() if ( ($fh = &edit_fields()) eq 'Error');
  $in{opshun} = 'Browse';

  #*-- create a .net file with the vertice and edges information
  my $tfile = $TMP_DIR . "spider.net";
  open (OUT, ">", &clean_filename("$tfile")) || 
       &quit ("Unable to open $tfile $!\n");
  #binmode OUT, ":raw";
  &escape_q(); 

  #*-- build the from/to URLs network
  my %vertices = my %arcs =  my %relevance = ();
  (my $descr = substr($in{spc_descr},0,20)) =~ s/[^A-Za-z]/o/g; 
  my $link_table    = "sp_" . $descr . "_links"; 
  #*-- LOCK --
  $dbh->execute_stmt("lock tables $link_table read");
  $command  = "select spc_parent_link, spc_link, spf_relevance from " .
              " $link_table where spc_status = 'Done'" ;
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  my $i = 1;
  while ( my ($from, $to, $relevance) = $dbh->fetch_row($sth) )
   { 
    next unless ($from && $to);
    $to = lc($to); $from = lc($from);
    $vertices{$to}   = $i++ unless($vertices{$to});
    $vertices{$from} = $i++ unless($vertices{$from});
    $relevance{$to} = $relevance;
    $arcs{"$from$ISEP$to"} = 1; 
   }
  $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --

  #*-- first dump the vertices
  print OUT "*Vertices ", scalar keys %vertices, "\n";
  foreach my $key (sort {$vertices{$a} <=> $vertices{$b}} keys %vertices)
   { print OUT "$vertices{$key} \"$key\"\n"; } 

  #*-- next dump the arcs
  print OUT "*Arcs\n";
  foreach my $key (sort keys %arcs)
   { (my $from, my $to) = $key =~ /(.*?)$ISEP(.*)/;
     print OUT "$vertices{$from} $vertices{$to} $arcs{\"$from$ISEP$to\"}\n"; }
  close(OUT);

  #*-- generate the vector file
  $tfile = $TMP_DIR . "spider.vec";
  open (OUT, ">", &clean_filename("$tfile")) || 
       &quit ("Unable to open $tfile $!\n");
  print OUT "*Vertices ", scalar keys %vertices, "\n";
  foreach my $key (sort {$vertices{$a} <=> $vertices{$b}} keys %vertices)
   { my $relevance = ($relevance{$key}) ? $relevance{$key}: 0.0;
     printf OUT ("     %10.6f\n", $relevance); } 
  
  close(OUT);

  $stat_msg .= "-- Created visualization files in $TMP_DIR ";    

 }

 #*---------------------------------------------------------------
 #*- Delete an existing search 
 #*---------------------------------------------------------------
 sub del_search
 {
  #*-- check for any errors in entering data
  my $fh; return() if ( ($fh = &edit_fields()) eq 'Error');
  #*--- check for mandatory entries
  unless ($in{spc_descr})  
    { $stat_msg .= "-- The Title field is mandatory,<br>"; return(); }
  &escape_q(); 

  #*-- delete the search 
  #*-- LOCK --
  $dbh->execute_stmt("lock tables sp_search write");
  $command = "delete from sp_search where spc_descr = " . 
             $dbh->quote($in{spc_descr});
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --
 
  #*-- drop the supplementary tables for the search
  (my $descr = substr($in{spc_descr},0,20)) =~ s/[^A-Za-z]/o/g; 
  
  foreach ( ("sp_$descr" . "_links", "sp_" . $descr . "_index") )
   {
    (undef, $db_msg) = $dbh->execute_stmt("drop table $_");
    &quit("$command failed: $db_msg") if ($db_msg);
   }

  $stat_msg .= "-- The <font color=darkblue>" . $in{spc_descr} . 
               "</font> search was deleted,<br>";
  $in{opshun} = 'View'; 
  foreach (@PARMS) { $in{$_} = ' ' if ($_ =~ /^spc/); }

 }

 #*---------------------------------------------------------------
 #*- Start a search, change the status for the search to 'running'
 #*- and spawns as many spiders as needed  
 #*---------------------------------------------------------------
 sub start_search
 {
  #*-- get the id for the search
  #*-- LOCK --
  $dbh->execute_stmt("lock tables sp_search read");
  $command = "select spi_id from sp_search where spc_descr = " .
             $dbh->quote($in{spc_descr});
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --
  my $id = ($dbh->fetch_row($sth))[0];
  unless($id)
   { $stat_msg .= "Cannot start the search, it does not exist,<BR>";
     return(); }

  #*-- verify the cached images for the search and clean up any
  #*-- invalid entries in the table
  $command = "select spc_local_file from sp_images where spi_id = $id";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  my @del_files = ();
  while ( (my $lfile) = $dbh->fetch_row($sth) )
   { push (@del_files, $lfile) unless (-s $lfile); }
  foreach (@del_files)
   { $command = "delete from sp_images where spc_local_file = " .
                $dbh->quote($_);
     (undef, $db_msg) = $dbh->execute_stmt($command);
     &quit("$command failed: $db_msg") if ($db_msg); }

  #*-- update the status to running
  #*-- LOCK --
  $dbh->execute_stmt("lock tables sp_search write");
  $command = "update sp_search set spc_status = 'running' " .
             "where spc_descr = " . $dbh->quote($in{spc_descr});
  (undef, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --

  #*-- start an independent process
  for my $i (0..($in{spi_spiders} - 1))
   {
    #*-- skip taint mode
    my @cmdline = ("$UTILS_DIR" . "sp_b_spider.pl " , 
                  join('__', "$in{spi_spiders}", "$i", "$id") );
    &create_process(\@cmdline, 1,'Perl.exe ', "$PERL_EXE");
    sleep(1); #*-- stagger the start of the spiders
   }
  $stat_msg = "...Search in progress.... <br>";
  $in{opshun} = 'Edit'; $in{spc_status} = 'running';
  
 }

 #*---------------------------------------------------------------
 #*- Stop a search  
 #*---------------------------------------------------------------
 sub stop_search
 {
  #*-- get the id for the search
  #*-- LOCK --
  $dbh->execute_stmt("lock tables sp_search read");
  $command = "select spi_id from sp_search where spc_descr = " .
             $dbh->quote($in{spc_descr});
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --
  my $id = ($dbh->fetch_row($sth))[0];

  #*-- update the status to stopped
  if ($id)
   {
  #*-- LOCK --
    $dbh->execute_stmt("lock tables sp_search write");
    $command = "update sp_search set spc_status = 'stopped' " .
               "where spc_descr = " . $dbh->quote($in{spc_descr});
    (undef, $db_msg) = $dbh->execute_stmt($command);
    &quit("$command failed: $db_msg") if ($db_msg);
    $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --
   }
  $stat_msg .= ($id) ? "-- Search has been stopped.... $stat_msg<br>":
                       "Cannot stop the search, it does not exist,<BR>";
  $in{opshun} = 'Edit'; $in{spc_status} = 'stopped' if ($id);
 }

 #*-------------------------------
 #*- Fill in fields, if possible 
 #*-------------------------------
 sub fil_search
 {
  #*-- get the id for the search
  #*-- LOCK --
  $dbh->execute_stmt("lock tables sp_search read");
  $command = "select count(*) from sp_search where spi_id = $in{spi_id}";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --
  return() unless ( ($dbh->fetch_row($sth))[0] );

  $" = ','; 
  #*-- LOCK --
  $dbh->execute_stmt("lock tables sp_search read");
  $command = "select @PARMS from sp_search where spi_id = $in{spi_id}";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --
  my @fields = $dbh->fetch_row($sth);
  for my $i (0..$#PARMS) { $in{$PARMS[$i]} = $fields[$i]; }
  $" = ' ';
 }

 #*---------------------------------------------------------------
 #*- dump some header html
 #*---------------------------------------------------------------
 sub head_html
 {
  my $sp_image   = "$ICON_DIR" . "searchw.jpg";
  my $e_session  = &url_encode($in{session});
  my $anchor = "$CGI_DIR/co_login.pl?session=$e_session";

  print "Content-type: text/html\n\n";
  print << "EOF";
   <html>
    <head> <title> Spider Search Page </title> </head>

    <body bgcolor=white>

     <form method=POST action="$FORM">

     <center>
      <table> <tr> <td> <a href=$anchor>
              <img src="$sp_image" border=0> </a> </td> </tr> </table>
EOF
 }


 #*---------------------------------------------------------------
 #*- show a list of searches in a table
 #*---------------------------------------------------------------
 sub view_html
 {
  #*-- get the searches and dump to a table
  my ($spi_id, $spc_descr, $spi_date, $spc_status);
  my (%descr, %date, %status, %links);
  #*-- LOCK --
  $dbh->execute_stmt("lock tables sp_search read");
  $command = "select spi_id, spc_descr, spi_date, spc_status from sp_search";
  ($sth, $db_msg) = $dbh->execute_stmt($command);
  &quit("$command failed: $db_msg") if ($db_msg);
  $dbh->execute_stmt("unlock tables");
  #*-- UNLOCK --
  while ( ($spi_id, $spc_descr, $spi_date, $spc_status) = 
           $dbh->fetch_row($sth) )
   { $descr{$spi_id} = $spc_descr; 
     $status{$spi_id} = &set_status($spc_status); 
     $date{$spi_id}  = $spi_date; 
  
     #*-- count the number of links
     (my $descr = substr($spc_descr,0,20)) =~ s/[^A-Za-z]/o/g; 
     my $ssth;
     $command = "select count(*) from sp_$descr" . "_links where " .
                "spc_status = 'Done'";
     ($ssth, $db_msg) = $dbh->execute_stmt($command);
     &quit("$command failed: $db_msg") if ($db_msg);
     $links{$spi_id} = ($dbh->fetch_row($ssth))[0];
  
   }

  #*-- build the html for the table
  my $body_html .= <<"EOF";
   <br>
   <table cellspacing=0 cellpadding=0 border=0 bgcolor=white>
   <tr><td>
   <table cellspacing=4 cellpadding=0 border=2 bgcolor=lightblue>
   <tr>
     <td bgcolor=lightyellow> <font color=darkred> No. </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> Description </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> Date </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> Results </font> </td>
     <td bgcolor=lightyellow> <font color=darkred> Status </font> </td>
   </tr>
EOF

  my $i = 1; my $e_session = &url_encode($in{session});
  foreach my $id (sort keys %descr)
   {
    $descr{$id} = &trim_field($descr{$id}, 25);
    $date{$id}  = &f_date($date{$id});
    my $link_script    = $CGI_DIR . "sp_links.pl";
    $body_html .= <<"EOF";
     <tr>
      <td bgcolor=white><font color=darkblue> $i    </font> </td>
      <td bgcolor=white><font color=darkblue> 
       <a href=$FORM?session=$e_session&e_opshun=Edit&opshun=Edit&spi_id=$id>
       $descr{$id} </a> </font> </td>
      <td bgcolor=white><font color=darkblue> $date{$id} </font> </td>
      <td bgcolor=white><font color=darkblue size=+1>
        <a href=$link_script?spi_id=$id&session=$e_session> $links{$id} 
        matching pages</a> </font> </td>
      <td bgcolor=white><font color=darkblue> $status{$id} </td>
     </tr>
EOF
    $i++;
   }

  #*-- add a button to add lists
  $body_html .= <<"EOF";
     </table>
    </td> </tr>
    <tr><td colspan=5 align=center> <br>
      <input type=submit name=n_opshun value=New>
    </td></tr>
   </table>
EOF

  return(\$body_html);
 }

 #*---------------------------------------------------------------
 #*- Show the screen to view details of each entry   
 #*---------------------------------------------------------------
 sub entry_html
 {

  if ($in{n_opshun} eq 'New') 
   { foreach (@PARMS) { $in{$_} = '' unless ($_ =~ /^spi/i); }}

  #*-- URL Limit options
  $in{spi_url_limit} = 100 unless($in{spi_url_limit});
  my $url_limit_option = '';
  foreach ( (100, 200, 500, 1000, 5000) )
   { $url_limit_option .= ($_ == $in{spi_url_limit}) ?
      "<option value='$_' selected> $_": "<option value='$_'> $_"; }

  #*-- Maximum number of URLs per site option
  $in{spi_maxsite_urls} = 25 unless($in{spi_maxsite_urls});
  my $max_urls_option = '';
  foreach ( (10, 25, 50, 100, 500, 1000, 5000) )
   { $max_urls_option .= ($_ == $in{spi_maxsite_urls}) ?
      "<option value='$_' selected> $_": "<option value='$_'> $_"; }

  #*-- The total time limit for the search   
  $in{spi_time_limit} = 1 unless($in{spi_time_limit});
  my $time_limit_option = '';
  foreach ( (1, 3, 6, 12) )
   { $time_limit_option .= ($_ == $in{spi_time_limit}) ?
      "<option value='$_' selected> $_": "<option value='$_'> $_"; }

  #*-- The number of spiders for the search   
  $in{spi_spiders} = 1 unless($in{spi_spiders});
  my $spiders_option = '';
  foreach ( (1, 2, 4, 8) )
   { $spiders_option .= ($_ == $in{spi_spiders}) ?
      "<option value='$_' selected> $_": "<option value='$_'> $_"; }

  #*-- option for the number of directories
  $in{spi_directory_limit} = 0 unless($in{spi_directory_limit});
  my $directory_option = '';
  foreach ( 0..8 )
   { $directory_option .= ($_ == $in{spi_directory_limit}) ?
      "<option value='$_' selected> $_": "<option value='$_'> $_"; }

  #*-- option for timeout of URLs
  $in{spi_url_timeout} = 30 unless($in{spi_url_timeout});
  my $timeout_option = '';
  foreach ( (10, 20, 30, 60) )
   { $timeout_option .= ($_ == $in{spi_url_timeout}) ?
      "<option value='$_' selected> $_": "<option value='$_'> $_"; }

  #*-- option for number of levels to traverse
  $in{spi_level_limit} = 0 unless($in{spi_level_limit});
  my $level_option = '';
  foreach ( (0, 1, 2, 3, 6, 12) )
   { $level_option .= ($_ == $in{spi_level_limit}) ?
      "<option value='$_' selected> $_": "<option value='$_'> $_"; }

  my $re_y = my $re_n = '';
  if ($in{spc_recompute} =~ /y/i) { $re_y = 'CHECKED';}
  else                            { $re_n = 'CHECKED'; }

  my $ge_y = my $ge_n = '';
  if ($in{spc_get_images} =~ /y/i) { $ge_y = 'CHECKED';}
  else                            { $ge_n = 'CHECKED'; }

  my $br_y = my $br_n = '';
  if ($in{spc_search_type} =~ /depth/i) { $br_n = 'CHECKED';}
  else                                  { $br_y = 'CHECKED'; }

  my $status = &set_status($in{spc_status});

  my $body_html .= <<"EOF";
   <center>
   <hr>
   <table border=0 cellspacing=4 cellpadding=0>

   <tr>
    <td align=left colspan=3> <font color=darkred size=+1> Description: 
               </font> </td>
   </tr>

   <tr>
    <td> <font color=darkblue> Title*: </font> </td>
    <td colspan=2> 
      <textarea name=spc_descr rows=1 cols=80>$in{spc_descr}</textarea></td>
   </tr>

   <tr>
    <td> <font color=darkblue> Links*: </font> </td>
    <td> 
     <textarea name=spc_link_file rows=1 cols=60>$in{spc_link_file}</textarea> </td>
    <td> <input type=submit name=file_opshun value='Select a File'> </td>
   </tr>

   <tr>
    <td> <font color=darkblue> Results*: </font> </td>
    <td> 
     <textarea name=spc_results_dir rows=1 cols=60>$in{spc_results_dir}</textarea> </td>
    <td> <input type=submit name=dir_opshun value='Select a Directory'> </td>
   </tr>
   
   <tr>
    <td> <font color=darkblue> Status: </font> </td>
    <td colspan=2 bgcolor=lightyellow> 
     <font color=darkblue> $status </font> </td>
   </tr>
   </table>

   <hr>
   <table border=0 cellspacing=4 cellpadding=0>

   <tr>
    <td align=left colspan=3> <font color=darkred size=+1> Rules: 
               </font> </td>
   </tr>

   <tr>
    <td> <font color=darkblue>Use the following keywords in descending
     order of priority to find links and evaluate pages</font><br>
    <textarea name=spc_keywords rows=1 cols=80>$in{spc_keywords}</textarea> 
    </td>
   </tr>

   <tr>
    <td> <font color=darkblue>Stay within the following sites </font><br>
     <textarea name=spc_selected_sites cols=80 rows=1>$in{spc_selected_sites}</textarea> </td>
   </tr>

   <tr>
    <td> <font color=darkblue>Do not visit the following sites </font><br>
     <textarea name=spc_blocked_sites cols=80 rows=1>$in{spc_blocked_sites}</textarea> </td>
   </tr>

   <tr>
    <td> <font color=darkblue>Assign a higher priority to pages
    from the following sites </font><br>
     <textarea name=spc_priority_domain cols=80 rows=1>$in{spc_priority_domain}</textarea> </td>
   </tr>
   </table>

   <hr>
   <table border=0 cellspacing=4 cellpadding=0>

   <tr>
    <td align=left colspan=3> <font color=darkred size=+1> Limits: 
               </font> </td>
   </tr>
   <tr>
    <td> <font color=darkblue>Maximum number of URLs for the spider: </font> </td>
    <td> <strong> <select name=spi_url_limit size=1> $url_limit_option </select>
         </strong> </td>
    <td> &nbsp; </td> <td> &nbsp; </td>
    <td> <font color=darkblue>Maximum number of URLs from a site: </font> </td>
    <td>
        <strong> <select name=spi_maxsite_urls size=1> $max_urls_option 
        </select> </strong> </td>
   </tr>

   <tr>
    <td> <font color=darkblue> Time limit for the spider (Hrs.): </font> </td>
    <td> <strong> <select name=spi_time_limit size=1> $time_limit_option </select>
         </strong> </td>
    <td> &nbsp; </td> <td> &nbsp; </td>
    <td> <font color=darkblue> Stay below directory level: </font> </td>
    <td> 
     <strong> <select name=spi_directory_limit size=1> $directory_option 
         </select> </strong> </td>
   </tr>

   <tr>
    <td> <font color=darkblue> Timeout for dead links (seconds):  </td>
    <td> <strong> 
       <select name=spi_url_timeout size=1> $timeout_option </select>
       </strong> </td>
    <td> &nbsp; </td> <td> &nbsp; </td>
    <td> <font color=darkblue> Maximum number of spider levels: </font> </td>
    <td> 
     <strong> <select name=spi_level_limit size=1> $level_option 
         </select> </strong> </td>
   </tr>
   </table>

   <hr>
   <table border=0 cellspacing=4 cellpadding=0>

   <tr>
    <td> <font color=darkblue> Recompute Results for a restart: </font> </td>
    <td>
         <strong> Yes </strong>
         <input type=radio name=spc_recompute value='Yes' $re_y>
         <strong> No </strong>
         <input type=radio name=spc_recompute value='No' $re_n>
    </td>
    <td> &nbsp; </td>
    <td> <font color=darkblue> Total number of Spiders: </font> </td>
    <td>
         <strong> <select name=spi_spiders size=1> $spiders_option </select>
         </strong> </td>
   </tr>

   <tr>
    <td> <font color=darkblue> Fetch Images associated with pages: </font>
         </td>
    <td>
         <strong> Yes </strong>
         <input type=radio name=spc_get_images value='Yes' $ge_y>
         <strong> No </strong>
         <input type=radio name=spc_get_images value='No' $ge_n>
    </td>
    <td> &nbsp; </td>
    <td> <font color=darkblue> Type of search: </font> </td>
    <td> 
         <strong> Breadth </strong>
         <input type=radio name=spc_search_type value='Breadth' $br_y>
         <strong> Depth </strong>
         <input type=radio name=spc_search_type value='Depth' $br_n>
    </td>
   </tr>

   <tr>
     <td colspan=6 align=center> <br>
      <input type=submit name=e_opshun value='Save'> &nbsp;
      <input type=submit name=e_opshun value='Update'> &nbsp;
      <input type=submit name=e_opshun value='Delete'> &nbsp;
      <input type=submit name=e_opshun value='Reset'> &nbsp;
      <input type=submit name=e_opshun value='Start'> &nbsp;
      <input type=submit name=e_opshun value='Stop'> &nbsp;
      <input type=submit name=e_opshun value='Visualize'> &nbsp;
      <input type=submit name=opshun value='View'> &nbsp;
     </td>
   </tr>

  </table>
  </center>

  <input type=hidden name=spc_status value='$in{spc_status}'>
EOF

  $stat_msg .= 'Enter parameters for a new search' if ($in{opshun} eq 'New');
  return(\$body_html);
 }

 #*------------------------------------------------------
 #*-- Return the status
 #*------------------------------------------------------
 sub set_status
 {
  (my $status = $_[0]) =~ s/^c_//;
  $status = ucfirst($status);
  $status = 'New Search' unless($status);
  return($status);
 }

 #*------------------------------------------------------
 #*-- escape strings with single quotes
 #*------------------------------------------------------
 sub escape_q
 {
  %esq = ();
  foreach (@PARMS)
   { if ($in{$_}) { $in{$_} =~ s/^\s+//; $in{$_} =~ s/\s+$//; }
     $esq{$_} = ($_ =~ /^spc/) ? $dbh->quote($in{$_}): 
                ($in{$_}) ? $in{$_}: 0; }
 }

 #*---------------------------------------------------------------
 #*- Exit with a message            
 #*---------------------------------------------------------------
 sub quit
 { 
   $dbh->execute_stmt("unlock tables", 1);
   &head_html(); &msg_html($_[0] . "<br>$stat_msg"); &tail_html(); 
   exit(0); }

 #*---------------------------------------------------------------
 #*- Dump an error message           
 #*---------------------------------------------------------------
 sub msg_html
 {
  my ($msg) = @_;
  $msg =~ s/,\s*<br>$/<br>/;
  print << "EOF";
    <table> <tr> <td bgcolor=lightyellow>
                 <font color=darkred size=4> $msg </font> </td>
    </tr> </table>
EOF
 }
 

 #*---------------------------------------------------------------
 #*- Dump the end of the html page 
 #*---------------------------------------------------------------
 sub tail_html
 {
  $dbh->disconnect_db($sth);
  print << "EOF";
    </center>
    <input type=hidden name=session value=$in{session}>
   </form>
  </body>
  </html>
EOF
 }


 #*---------------------------------------------------------------
 #*- display a small header
 #*---------------------------------------------------------------
 sub mini_head_html
 {
  print "Content-type: text/html\n\n";
  print << "EOF";
   <html>
    <head>
     <title> Page for Searches </title>
    </head>

    <body bgcolor=white>

     <form method=POST action="$FORM">
     <center>
EOF
 }


 #*---------------------------------------------------------------
 #*- Dump a smaller end of the html page
 #*---------------------------------------------------------------
 sub mini_tail_html
 {
  $dbh->disconnect_db($sth);
  print << "EOF";
    </center>
     <input type=hidden name=session value=$in{session}>
   </form>
  </body>
  </html>
EOF
 }
