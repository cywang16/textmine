#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------------
 #*-- entry_check.pl
 #*--   Description: Check if the file data was successfully 
 #*--   created in the tables correctly
 #*---------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Constants;
 
 our ($dbh, $db_msg, $sth);

 #*-- establish a connection with the db
 ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
    'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => $DB_NAME);
 &quit("Connect failure: $db_msg") if ($db_msg);

 printf ("%20s\tLines\tRows\n", 'Table');
 foreach (qw/co_abbrev.dat  co_colloc.dat  co_colloc_lead.dat co_entity.dat 
             co_org.dat     co_person.dat  co_place.dat       co_rulepos.dat
             co_ruleent.dat   qu_perlfaq.dat        qu_categories.dat
       	     wn_exc_words.dat wn_synsets_rel.dat  wn_words_all.dat
             wn_synsets.dat   wn_words_rel.dat    wn_words_a_b.dat
             wn_words_c_d.dat wn_words_e_g.dat    wn_words_h_l.dat
             wn_words_m_p.dat wn_words_q_s.dat    wn_words_t_z.dat
            /)
  {
   (my $table = $_) =~ s/\.dat$//;
   my $count = `wc -l $_`; $count =~ /.*?(\d+)/; $count = $1;
   my $command = "select count(*) from $table";
   ($sth, $db_msg) = $dbh->execute_stmt($command);
   my ($tcount) = $dbh->fetch_row($sth);
   printf ("%20s\t%5d\t%5d\n", $table, $count, $tcount);
   print ("-----> ERROR <---- \n") unless ($tcount == $count);
  }
 &quit('');

 #*---------------------------------------------------------------
 #*- Exit with a message            
 #*---------------------------------------------------------------
 sub quit
 {
  $dbh->disconnect_db($sth);
  print ("$_[0]\n"); 
  exit(0);
 }
