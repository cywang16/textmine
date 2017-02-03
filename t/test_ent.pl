#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");
 #*------------------------------------------------------------
 #*- test entity extraction of the text below
 #*------------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Entity qw/entity_ex/;
 use TextMine::Constants qw/$DB_NAME/;

 my ($dbh) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => $DB_NAME);

 print "Started test_ent.pl\n";
 undef($/); my $text = <DATA>;
 my ($r1, $r2, $r3, $r4) = &entity_ex(\$text, $dbh);
 my @tokens = @$r1;
 my @loc = @$r2;
 my @types = @$r3;
 my @sent = @$r4;
 open (OUT, ">test_ent_results.txt") || die ("Could not open results $!");
 binmode OUT, ":raw";
 printf OUT ("%-6s\t%-20s\t%-10s\n", 'Pos.', 'Word', 'Type');
 for my $i (0..$#tokens)
  { printf OUT ("%-6d\t%-20s\t%-10s\n", $loc[$i], $tokens[$i], $types[$i]); }

 for (@sent)
  { print OUT ("-->$_\n"); }
 close(OUT);

 $dbh->disconnect_db();
 print "Finished test_ent.pl\n";
 
exit(0);
__DATA__
NEW YORK (Reuters) - Hotel real estate investment trust Patriot American Hospitality Inc. said Tuesday it had agreed to acquire Interstate Hotels Corp, a hotel management company, in a cash and stock transaction valued at $2.1 billion, including the assumption of $785 million of Interstate debt.
        
Interstate's portfolio includes 40 owned hotels and resorts, primarily upscale, full-service facilities leases for 90 hotels and management-service agreements for 92 hotels.
 
On completion of the Interstate deal and its pending acquisition of Wyndham Hotel Corp. and WHG Reuters and Casinos Inc., Patriot's portfolio will consist of 455 owned, leased, managed, franchised, or serviced properties with about 103,000 rooms.

A definities agreement between Patriot and Interstate values Interstate at $37.50 per share. Patriot will pay cash for 40 percent of Interstate's shares and will exchange Patriot paired shares for the rest. Paired shares trade jointly for real estate investment trusts and their paired operating companies.

Patriot said it expects the transaction to be about 8 percent accretive to its funds from operations.

It said the agreement had been approved by the boards of Interstate and Wyndham Patriot said it did not expect the deal to delay the closing if its transaction with Wyndham, which is to close by year-end.
