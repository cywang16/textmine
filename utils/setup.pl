
 use lib qw/../;

 #*----------------------------------------------------------------
 #*- setup.pl
 #*-  
 #*- Summary: Create the database, tables and load the data
 #*----------------------------------------------------------------
 use strict; use warnings; 
 use TextMine::DbCall;
 use TextMine::Constants qw($DB_NAME $UTILS_DIR $PPM_DIR 
                            $PACK_DIR $ROOT_DIR $PERL_EXE $OSNAME $DB_HOST
     clean_filename fetch_dirname); 

 #*-- userid and password for Mysql
 # our ($USERID, $PASSWORD) = ('root', '');
 our ($USERID, $PASSWORD) = ('keycloak', 'test');

 print ("Started setup.pl\n");
 print ("Setting up the database ...\n");
 our ($inline);
 &setup_db();
 print ("Finished setting up the database ...\n");

 print ("Continue installation (Y/N): "); 
 exit(0) if ( ($inline = <STDIN>) =~ /n/i);

 print ("Creating platform dependent code\n");
 &create_myproc();
 print ("Finished creating platform dependent code\n");

 print ("Finished setup.pl\n");

 #*-------------------------------------------------------------
 #*- setup the database and load some tables
 #*-------------------------------------------------------------
 sub setup_db
 {

 #*-- read the sql to create mysql authorization tables and
 #*-- application tables
 $inline = my $line = ''; 
 open (IN, "<", "tables.sql") || die ("could not open tables.sql $!\n");
 while ($line = <IN>)
  { next if ($line =~ /^\s*#/); $inline .= $line; }
 close(IN);
 $inline =~ s/\n//g;
 my @ins = split(/;/, $inline);

 #*-- create the database, if it does not exist
 my ($dbh, $sth, $command, @tables, $db_msg);
 print ("Started creating and loading the database....\n");
 TextMine::DbCall::create_db("$DB_NAME", $USERID, $PASSWORD);
 ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => $DB_HOST,
       'Userid' => $USERID, 'Password' => $PASSWORD, 'Dbname' => $DB_NAME);
 print ("DB Error Message: $db_msg\n") if ($db_msg);

 #*-- create the tables and run other SQL commands
 print ("Creating authorization and application tables...\n");
 @tables = $dbh->show_tables();
 foreach $command (@ins)
  { 
   if ($command =~ /connect\s+([^ ]+)/i)
    { 
     #*-- connect to the appropriate database
     $dbh->disconnect_db($sth) if ($dbh);
     # ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
     #   'Userid' => $USERID, 'Password' => $PASSWORD, 'Dbname' => $1); }
     ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => 'mysql',
       'Userid' => $USERID, 'Password' => $PASSWORD, 'Dbname' => $1); }
   else
    { (undef, $db_msg) = $dbh->execute_stmt($command); }
   print ("DB Error Message: $db_msg\n") if ($db_msg);
  }

 $dbh->disconnect_db($sth) if ($dbh);
 # ($dbh, undef) = TextMine::DbCall->new ( 'Host' => '',
 #       'Userid' => 'root', 'Password' => $PASSWORD, 'Dbname' => $DB_NAME);
 ($dbh, undef) = TextMine::DbCall->new ( 'Host' => 'mysql',
       'Userid' => 'root', 'Password' => 'roottest', 'Dbname' => $DB_NAME);
 $/ = "\n";
 print ("Loading the tables ....\n");
 my %files = (
                "./data/co_abbrev.dat"      => "co_abbrev",
                "./data/co_colloc.dat"      => "co_colloc",
                "./data/co_colloc_lead.dat" => "co_colloc_lead",
                "./data/co_entity.dat"      => "co_entity",
                "./data/co_org.dat"         => "co_org",
                "./data/co_person.dat"      => "co_person",
                "./data/co_place.dat"       => "co_place",
                "./data/co_rulepos.dat"     => "co_rulepos",
                "./data/co_ruleent.dat"     => "co_ruleent",
                "./data/qu_perlfaq.dat"     => "qu_perlfaq",
                "./data/qu_categories.dat"  => "qu_categories",
                "./data/wn_synsets.dat"     => "wn_synsets",
                "./data/wn_synsets_rel.dat" => "wn_synsets_rel",
		"./data/wn_words_a_b.dat"   => "wn_words_a_b",
		"./data/wn_words_c_d.dat"   => "wn_words_c_d",
		"./data/wn_words_e_g.dat"   => "wn_words_e_g",
		"./data/wn_words_h_l.dat"   => "wn_words_h_l",
		"./data/wn_words_m_p.dat"   => "wn_words_m_p",
		"./data/wn_words_q_s.dat"   => "wn_words_q_s",
		"./data/wn_words_t_z.dat"   => "wn_words_t_z",
                "./data/wn_words_rel.dat"   => "wn_words_rel",
                "./data/wn_words_all.dat"   => "wn_words_all",
                "./data/wn_exc_words.dat"   => "wn_exc_words",
              );
 foreach my $file (keys %files)
  { 
    print ("Loading the $files{$file} table....\n");
    $dbh->execute_stmt("delete from $files{$file}");
    $command = <<"EOT";
       load data local infile '$file' replace into table $files{$file}
       fields terminated by ':' escaped by '!'
EOT
    $dbh->execute_stmt("$command");
    #*-- optional
  #  $command = "repair table $files{$file} quick";
  #  $dbh->execute_stmt("$command");
  }
 $dbh->disconnect_db($sth);
 print ("Finished creating and loading the database....\n");

 #*------------------------------------------------------------------
 #*- Optional: following tables are read only and can be packed
 #*------------------------------------------------------------------
 #foreach (qw/
 #            co_abbrev      co_colloc    co_colloc_lead
 #            qu_perlfaq     wn_synsets   wn_synsets_rel
 #            wn_words_rel   wn_words_all wn_exc_words  wn_words_a_b
 #            wn_words_c_d   wn_words_e_g wn_words_h_l  wn_words_m_p
 #            wn_words_q_s   wn_words_t_z
 #           /)
 # { print "Packing table $_ .....\n";
 #   my $command = "$mysql_bdir/myisampack -v $mysql_ddir/$_" . '.MYI';
 #   system($command);
 #   $command = "$mysql_bdir/myisamchk -rq $mysql_ddir/$_";
 #   system($command); }

 }

 #*-------------------------------------------------------------
 #*- Copy from MyWin.pm or MyNix.pm to MyProc
 #*-------------------------------------------------------------
 sub create_myproc
 {
  my $old_name = ($OSNAME eq "win") ? "MyWin": "MyNix";
  my $file = "../TextMine/$old_name";
  open (IN, "<", "$file") || die ("Could not open $file $!\n");
  my @lines = <IN>; close(IN);
  $file = "../TextMine/MyProc.pm";
  open (OUT, ">", "$file") || die ("Could not open $file $!\n");
  binmode OUT, ":raw";
  print OUT ("@lines\n"); close(OUT);
 }
