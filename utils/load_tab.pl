#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------
 #*-  load_tab.pl
 #*-    Load data into tables
 #*----------------------------------------------------

 use warnings; use strict;
 use TextMine::DbCall;
 use TextMine::Constants qw($DB_NAME); 

 our ($dbh, $command);
 ($dbh, undef) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => 'root', 'Password' => '', 'Dbname' => $DB_NAME);
 $/ = "\n";
 print ("Loading the tables ....\n");
 our %files = (
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
  #  $command = "repair table $files{$file} quick";
  #  $dbh->execute_stmt("$command");
  }
 $dbh->disconnect_db();
 print ("Finished loading tables ....\n");

 exit(0);
