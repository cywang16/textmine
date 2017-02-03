#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*-------------------------------------------------------
 #*- pack.pl
 #*-   compress the read only tables
 #*-------------------------------------------------------

 use strict; use warnings;
 use TextMine::Constants;

 #*-- search for the mysql executable in the PATH env. var
 if ($ENV{PATH} !~ /mysql/i)
   { print "Cannot find mysql in path\n"; exit(0);}
 (my $mysql_bdir) = ($ENV{PATH} =~ m%(?:^|;)(.*?mysql.*?)(?:$|;)%);
 if ($mysql_bdir !~ /bin/i)
   { print "Cannot find the bin directory for mysql \n"; exit(0); }
 (my $mysql_ddir = $mysql_bdir) =~ s/bin/data/;
 $mysql_ddir .= "/$DB_NAME";
 unless (-d $mysql_ddir)
   { print ("Mysql data directory $mysql_ddir does not exist\n"); exit(0); }
 unless (-d $mysql_bdir)
   { print ("Mysql bin  directory $mysql_bdir does not exist\n"); exit(0); }

 #*------------------------------------------------------------------
 #*- following tables are read only and can be packed
 #*------------------------------------------------------------------
 foreach (qw/
             co_colloc    co_colloc_lead
             qu_perlfaq   wn_synsets   wn_synsets_rel
             wn_words_rel wn_words_all wn_exc_words  wn_words_a_b
             wn_words_c_d wn_words_e_g wn_words_h_l  wn_words_m_p
             wn_words_q_s wn_words_t_z
            /)
  { print "Packing table $_ .....\n";
    my $command = "$mysql_bdir/myisampack -v $mysql_ddir/$_" . '.MYI';
    system($command); sleep(3);
    $command = "$mysql_bdir/myisamchk -rq $mysql_ddir/$_";
    system($command); sleep(3); }

 exit(0);
