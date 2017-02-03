#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------------------------
 #*- tsplit.pl
 #*-  
 #*- Summary: Test the splitting of text into sentences 
 #*-----------------------------------------------------------------------

 use strict; use warnings;
 use TextMine::WordUtil qw(text_split);
 use TextMine::Tokens qw(load_token_tables);
 use TextMine::DbCall;
 use TextMine::Constants;

 my $userid = 'tmadmin'; my $password = 'tmpass';
 my ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
        'Userid' => $userid, 'Password' => $password, 'Dbname' => $DB_NAME);

 my $text = <<"EOT";
OTTAWA, March 3 - Canada's real gross domestic product,
seasonally adjusted, rose 1.1 pct in the fourth quarter of
1986, the same as the growth as in the previous quarter,
Statistics Canada said.
    That left growth for the full year at 3.1 pct, which is
down from 1985's four pct increase. The rise was also slightly 
below the 3.3 pct growth rate Finance Minister Michael Wilson 
predicted for 1986 in February's budget. He also forecast GDP 
would rise 2.8 pct in 1987.
    Statistics Canada said final domestic demand rose 0.6 pct
in the final three months of the year after a 1.0 pct gain in
the third quarter.
    Business investment in plant and equipment rose 0.8 pct in
the fourth quarter, partly reversing the cumulative drop of 5.8
pct in the two previous quarters.

"You remind me," she remarked, "of your mother."

"Wo-ho!" said the coachman. "So, then!  One more pull and you're
at the top and be damned to you, for I have had trouble enough to
get you to it!--Joe!"
EOT

  my $hash_refs = &load_token_tables($dbh);
  my ($r1) = &text_split(\$text, '', $dbh, $hash_refs, 30);
  my @tchunks = @$r1;          #*-- end locations of text chunks
  for my $i (0..$#tchunks)
  { my $start = $i ? ($tchunks[$i-1] + 1): 0; my $end = $tchunks[$i];
    my $sentence = substr($text, $start, $end - $start + 1);
    $sentence =~ s/^\s+//; $sentence =~ s/\s+$//;
    print $i+1, ": $sentence\n\n";
  }

 $dbh->disconnect_db();
 exit(0);
