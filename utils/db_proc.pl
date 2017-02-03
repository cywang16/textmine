#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*---------------------------------------------------------------------
 #*- db_proc.pl
 #*-  
 #*-   Summary: Run an independent process to either backup or restore
 #*-     
 #*-   Proctab contains process information which is checked by scripts
 #*-   run from a browser
 #*- 
 #*-   Tid - The unique task id
 #*- 
 #*---------------------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Constants qw($DB_NAME $ISEP $EQUAL $DELIM clean_filename);

 use vars (
   '$g_dbh',	#*-- database handle for db of tables
   '$l_dbh',	#*-- database handle for tm
   '$dbh',	#*-- general database handle
   '$l_sth',	#*-- stmt. handle for tm
   '$g_sth',	#*-- stmt. handle for tables
   '$command',	#*-- SQL Command
   '$db_msg',	#*-- database error message
   '$tid',	#*-- task id
   '$function',	#*-- backup or restore
   '$tables',	#*-- a list of tables
   '$db',	#*-- database name
   '$file',	#*-- name of file for backup or restore 
   '$start_time',
   );

 &setup_vars();
 &backup()  if ($function =~ /backup/i);
 &restore() if ($function =~ /restore/i);
 &quit();

 #*----------------------------------------------------------
 #*- Set up some parameters 
 #*----------------------------------------------------------
 sub setup_vars
  {
   #*-- retrieve the passed arguments and initialize fields
   ($tid, my $userid, my $password) = split/$ISEP/, $ARGV[0];
   ($l_dbh) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $userid, 'Password' => $password, 'Dbname' => $DB_NAME);

   #*-- clean up the proctab and get data from the entry
   $start_time = time();
   (undef, $db_msg) = $l_dbh->execute_stmt("lock tables co_proctab WRITE");

   $command = "select prc_logdata from co_proctab where pri_tid = $tid";
   ($l_sth, $db_msg) = $l_dbh->execute_stmt($command); 
   &quit("Command: $command failed --> $db_msg") if ($db_msg);
   my ($prc_logdata) = $l_dbh->fetch_row($l_sth);

   $command = "update co_proctab set pri_start_time = $start_time " .
              "where pri_tid = $tid";
   (undef, $db_msg) = $l_dbh->execute_stmt($command); 
   &quit("Command: $command failed --> $db_msg") if ($db_msg);

   $command = "delete from co_proctab where pri_start_time < " .
              "($start_time - 86400)";
   (undef, $db_msg) = $l_dbh->execute_stmt($command); 
   &quit("Command: $command failed --> $db_msg") if ($db_msg);
   (undef, $db_msg) = $l_dbh->execute_stmt("unlock tables");
   
   #*-- extract the parameters for this run
   my @ldata = split/$EQUAL/, $prc_logdata;
   ($function, $tables, $db, $file) = split/$ISEP/, 
                                     (split/$EQUAL/, $prc_logdata)[0];

   &quit("Not enough data ") unless ($function && $tables && $db && $file);

   #*-- set up the database, tables and columns                
   ($g_dbh) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => $userid, 'Password' => $password, 
       'Dbname' => $db);
   $dbh = $g_dbh->{'dbh'}; #*-- $dbh->{AutoCommit} = 0;

  }

 #*----------------------------------------------------------
 #*- Run the backup function
 #*----------------------------------------------------------
 sub backup
  {

   open (OUT, ">>", "$file") || &quit("Unable to write to $file $!");
   binmode OUT, ":raw";
   my @tables = split/\s+/, $tables; my $num_lines = 0;
   local $" = ",";
   foreach my $table (sort @tables)
   {
    &upd_log("Started backing up table $table");
    
    #*-- get the list of columns and types
    (my $ref_col, my $ref_type) = $g_dbh->show_columns($table);
    my @cols = @$ref_col;

    #*-- set the blob_field and numeric field arrays
    my %num_field = my %blob_field = my %text_field = ();
    for my $i(0..$#cols)
     { $blob_field{$cols[$i]}++  if (@$ref_type[$i] =~ /^\s*blob/i);
       $num_field{$cols[$i]}++   if (@$ref_type[$i] =~ /^\s*(?:int|float)/i);
       $text_field{$cols[$i]}++  if (@$ref_type[$i] =~ /^\s*text/i); }

    #*-- fix @cols, do not handle binary fields
    for my $i (0..$#cols)
     { splice(@cols, $i, 1) if ($blob_field{$cols[$i]}); }

    #*-- format for tables:
    #*-- No. of rows (n) Table: Table name___Name of Col1___Name of Col2___....
    #*-- n lines data for col1, data for col2, .... 
    #*-- build and dump the table line
    $command = "select count(*) from $table";
    ($g_sth, $db_msg) = $g_dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    (my $row_count) = $g_dbh->fetch_row($g_sth);
    print OUT "$row_count Table: ", join ($DELIM, $table, "@cols"), "\n"; 

    $command = "select @cols from $table";
    ($g_sth, $db_msg) = $g_dbh->execute_stmt($command);
    &quit("Command: $command failed --> $db_msg") if ($db_msg);
    while (my @coldata = $g_dbh->fetch_row($g_sth) )
     { my $line = '';
       for my $i (0..$#coldata)
        { unless ($num_field{$cols[$i]}) 
           { $coldata[$i] = $dbh->quote($coldata[$i]); } }
       print OUT "@coldata\n";
       unless (++$num_lines % 500)
        { &upd_log("Dumped $num_lines rows"); &check_stat(); } 
     } #*-- end of while
     
    &upd_log("Finished backing up table $table");
    } #*-- end of foreach table
   close(OUT);
   &upd_log("<font color=darkred> Backup task done... </font>");
   &upd_stat("Backup task done...");

  }

 #*----------------------------------------------------------
 #*- Run the restore function
 #*----------------------------------------------------------
 sub restore
  {
   open (IN, "<", "$file") || &quit("Unable to read from $file $!");
   my ($inline, $rows, $table, $cols, $s_table, $s_cols, $s_rows,$num_lines);
   while ($inline = <IN> )
    { 
     #*-- set the table name and columns
     chomp($inline); 
     if (($rows, $table, $cols) = $inline =~ 
                     /^(\d+) Table:\s+(.*?)$DELIM(.*)$/)
      { &upd_log("Started restoring $table....\n"); $num_lines = 0; 
        $s_table = $table; $s_cols = $cols; $s_rows = $rows; next; }

     #*-- skip tables which were not selected
     next unless ($s_table && ($tables =~ /$s_table/i) && $s_cols);

     #*-- replace the tables
     my $command = "replace into $s_table ($s_cols) values ($inline)"; 
     (undef, $db_msg) = $g_dbh->execute_stmt($command); 
     &quit("Command: $command failed --> $db_msg") if ($db_msg);
     &upd_log("Finished restoring $s_table") if (++$num_lines == $s_rows);
     &check_stat() unless ($num_lines % 500);
    }
   close(IN);
   &upd_log("<font color=darkred> Restore task done... </font>");
   &upd_stat("Restore task done...");
  }

 #*----------------------------------------------------------
 #*- Check the status in proctab and take appropriate action
 #*----------------------------------------------------------
 sub check_stat
  {
   (undef, $db_msg) = $l_dbh->execute_stmt("lock tables co_proctab READ");
   $command = "select prc_status from co_proctab where pri_tid = $tid";
   ($l_sth, $db_msg) = $l_dbh->execute_stmt($command); 
   &quit("Command: $command failed --> $db_msg") if ($db_msg);
   (undef, $db_msg) = $l_dbh->execute_stmt("unlock tables");
   if ( ($l_dbh->fetch_row($l_sth))[0] =~ /stop/i)
    { #$dbh->rollback; 
      #&upd_log("$function did not complete, rollback attempted");
      &quit(); }
  }

 #*--------------------------------------------------
 #*- Update the co_proctab table entry 
 #*--------------------------------------------------
 sub upd_log
 {
  my ($log) = @_;
  my ($diff, $diff_hour);

  #*-- prefix a timer in front of the log line
  $diff = time() - $start_time;
  $log = (gmtime($diff))[1] . ":" . (gmtime($diff))[0] . " => $log";
  $log =~ s/^(\d+):(\d) /$1:0$2 /;
  $diff_hour = (gmtime($diff))[2];
  if ($diff_hour > 0)
   { $log = "$diff_hour:" . $log; $log =~ s/^(\d+):(\d):/$1:0$2:/; }
  my $e_log = $l_dbh->quote("###$log");

  $l_dbh->execute_stmt("lock tables co_proctab write");
  $command  = "update co_proctab set prc_logdata = " .
              " CONCAT(prc_logdata, $e_log) where pri_tid = $tid";
  (undef, $db_msg) = $l_dbh->execute_stmt($command);
  &quit("Command: $command failed --> $db_msg") if ($db_msg);
  $l_dbh->execute_stmt("unlock tables");
  return();
 }

 #*--------------------------------------------------
 #*- Update the co_proctab status table entry for the spider
 #*--------------------------------------------------
 sub upd_stat
 { $command = "update co_proctab set prc_status = " . $l_dbh->quote($_[0]) .
             " where pri_tid = $tid";
   (undef, $db_msg) = $l_dbh->execute_stmt($command);
   &quit("Command: $command failed --> $db_msg") if ($db_msg); }

 #*----------------------------------------------------------
 #*-- Change the status in the co_proctab for the tid 
 #*----------------------------------------------------------
 sub quit
  { my ($msg) = @_;
    if ($msg)
     { &upd_log($msg) if ($msg); &upd_stat("Task was stopped"); }
    $l_dbh->execute_stmt("unlock tables");
    $l_dbh->disconnect_db($l_sth) if ($l_sth);
    $g_dbh->disconnect_db($g_sth) if ($g_sth);
    exit(0); 
  }
