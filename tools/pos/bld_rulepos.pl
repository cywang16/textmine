#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*--------------------------------------------------------------------
 #*- bld_rulepos.pl
 #*- create the POS rule table using untagged and tagged text
 #*- Backward rules are used to resolve the second part of a sequence
 #*- Forward rules are used to resolve the first part of a sequence
 #*---------------------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::WordUtil qw/text_split/;
 use TextMine::Tokens   qw/load_token_tables/;
 use TextMine::Pos      qw/lex_tagger/;
 use TextMine::Constants;

 #*-- get the database handle
 print ("Started building POS rules\n");
 my ($dbh) = TextMine::DbCall->new ( 'Host' => '',
    'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => $DB_NAME);

 #*-- get the list of rule stopwords, build rules for these words alone
 #*-- to limit the number of rules
 my %twords = ();
 open (IN, "rule_stopword.txt") || 
      die ("Could not open rule stopword list $!\n");
 while (my $inline = <IN>) { chomp($inline); $twords{$inline}++; }
 close(IN);

 #*-- read the untagged text and split into sentences.
 undef($/); my $text = <DATA>; my $untagged_len = length($text);
 my @sentences = ();
 my ($rsentences) = &text_split(\$text, '', $dbh);
 print ("Read text and generated sentences\n");
  for my $i (0..(@$rsentences-1))
   { 
     my $start = $i ? ($$rsentences[$i-1] + 1): 0; 
     my $end = $$rsentences[$i];

     #*-- extract and clean the sentence and keep in a list
     my $ctext = substr($text, $start, $end - $start + 1);
     $ctext =~ s/\n/ /g;
     $ctext =~ s/^\s+//; $ctext =~ s/\s+$//; $ctext =~ s/\s+/ /g;
     push (@sentences, "$ctext"); }

 #*-- use the lexical tagger to get tags
 #*-- and build the rule table
 my %rules = (); my $num_sentences = @sentences; my $j = 0;
 my $hash_refs = &load_token_tables($dbh);
 foreach my $sentence (@sentences)
  {
   my ($rt, $rl, $rg) = &lex_tagger(\$sentence, $dbh, $hash_refs, 1);

   #*-- resolve the tag based on the frequency of usage
   #*-- according to the wordnet freq.
   my @tokens = @$rt; my @stags  = @$rg; my @tags = my @fre = (); 
   foreach my $i (0..$#stags)
    { my $max_freq = -1;
      while ($stags[$i] =~ /(.)_(\d+)/g) 
       { if ($2 > $max_freq) { $tags[$i] = $1; $max_freq = $fre[$i] = $2; } }
    }

   for my $i (0..$#tags)
   { 
    $tokens[$i] = lc($tokens[$i]);

    #*-- check to the left of the token  
    $rules{"WB!!!$tokens[$i-1] $tags[$i]!!!$tags[$i-1]"}+= $fre[$i-1] 
        if ($tokens[$i-1] && $twords{$tokens[$i-1]});

    #*-- check to the right of the token  
    $rules{"WF!!!$tags[$i] $tokens[$i+1]!!!$tags[$i+1]"}+= $fre[$i+1]
      if ($tokens[$i+1] && $twords{$tokens[$i+1]})

    } #*-- end of inner for

   print ("Finished $j of $num_sentences\n") unless ($j++ % 10);
  } #*-- end of outer for

 #*-- scan the tagged text
 print ("Finished untagged text and starting tagged text\n");
 open (IN, "pos_training.txt") || 
       die ("Could not open pos_training.txt $!\n");
 undef($/); my $inline = <IN>; close(IN);

 #*-- higher weight for rules from tagged text than untagged text 
 #*-- proportional to the ratio of untagged text to tagged text
 my $tagged_len = length($inline);
 my $w_factor = (50 * int ($untagged_len / $tagged_len)) + 10;
 my @words = my @tags = ();
 while ($inline =~ /(.*?)\s+<(.*?)>/sg)
  { my ($word, $tag) = ($1, $2);
    $word =~ s/^\s+//; $word =~ s/\s+$//;
    $tag  =~ s/^\s+//; $tag  =~ s/\s+$//;
    push (@words, lc($word)); push (@tags, $tag); }

 #*-- supervised rules
 for my $i (0..$#words)
  { 
   if ($twords{$words[$i]})
    {
     $rules{"WB!!!$words[$i] $tags[$i+1]!!!$tags[$i]"} += $w_factor
        if ($words[$i+1]);
     $rules{"WF!!!$tags[$i-1] $words[$i]!!!$tags[$i]"} += $w_factor 
        if ($words[$i-1]); 
    }
  }
 print ("Finished tagged text\n");

 #*----------------------------------------------------------
 #*- Pick the rule with higher frequency when resolving
 #*- duplicate rules
 #*----------------------------------------------------------
 my %orules = %rules; %rules = my %seen = (); 
 foreach (sort { $orules{$b} <=> $orules{$a} } keys %orules)
  {
   #*-- check for dup. rules
   my ($type, $part1, $part2) = $_ =~ /^(..)!!!(.*?)\s(.*?)!!!/;
   next if $seen{"$type:$part1:$part2"};
   $rules{$_} = $orules{$_}; $seen{"$type:$part1:$part2"} = $orules{$_};
  }

 #*-- load the unnormalized rules into the clean table
 $dbh->execute_stmt("delete from co_rulepos");
 foreach (sort keys %rules)
  { my ($type, $part1, $part2) = $_ =~ /^(.*?)!!!(.*?)\s(.*)$/;
    my $wtag = ($part2 =~ s/!!!(.*?)$//) ? $1: " "; 
    next unless ($part1 && $part2);
    my $command = "replace into co_rulepos values ('$type', $rules{$_}, " .
               "'$wtag', '$part1', '$part2')";
    $dbh->execute_stmt($command);
  }

 #*-- compute the sum of frequencies by type and word 
 #*-- following or preceding
 my %sum = ();
 my $command = "select SUM(rui_frequency), ruc_part1 from co_rulepos " .
              "where ruc_type = 'WB' group by ruc_part1";
 my ($sth) = $dbh->execute_stmt($command);
 while (my ($sum, $p1) = $dbh->fetch_row($sth) )
  { $sum{"WB" . $p1} = $sum; }

 $command = "select SUM(rui_frequency), ruc_part2 from co_rulepos " .
              "where ruc_type = 'WF' group by ruc_part2";
 ($sth) = $dbh->execute_stmt($command);
 while (my ($sum, $p2) = $dbh->fetch_row($sth) )
  { $sum{"WF" . $p2} = $sum; }

 open (OUT, ">co_rulepos.dat") ||
  die ("Unable to open co_rulepos.dat $!\n");
 binmode OUT, ":raw";
 foreach (sort keys %rules)
  { my ($type, $part1, $part2) = $_ =~ /^(.*?)!!!(.*?)\s(.*)$/;
    my $wtag = ($part2 =~ s/!!!(.*?)$//) ? $1: " "; 
    next unless ($part1 && $part2);
    my $key = ($type =~ /B$/i) ? $part1: $part2;
    my $sum = $sum{"$type" . $key} ? $sum{"$type" . $key}: 1.0;
    $rules{$_} /= $sum; $rules{$_} = sprintf("%7.5f", $rules{$_});
    print OUT ("$type:$rules{$_}:$wtag:$part1:$part2:\n"); 
  }
 close(OUT);

 $dbh->disconnect_db();
 print ("Finished printing rules\n");

exit(0);

__DATA__
Argentine grain board figures show
crop registrations of grains, oilseeds and their products to
February 11, in thousands of tonnes, showing those for futurE
shipments month, 1986/87 total and 1985/86 total to February
12, 1986, in brackets:
The sharp decline in soybean crush ratios
seen in the last few weeks, accelerating in recent days, has
pushed margins below the cost of production at most soybean
processing plants and prompted many to cut output of soybean
meal and oil.
    The weekly U.S. soybean crush rate was reported by the
National Soybean Processors Association this afternoon at 21.78
mln bushels, down from the 22 mln bushel plus rate seen over
the past two months when crush margins surged to the best
levels seen in over a year.
    Active soymeal export loadings at the Gulf had pushed
soybean futures and premiums higher, prompting a pick-up in the
weekly crush number.
    However, much of that export demand seems to have been met,
with most foreign meal users now waiting for the expected surge
in shipments of new crop South American soymeal over the next
few months.
    U.S. processors are now finding domestic livestock feed
demand is very light for this time of year due to the milder
than normal winter, so they steadily dropped offering prices in
an attempt to find buying interest, soyproduct dealers said.
    Soybean meal futures have also steadily declined in recent
weeks, setting a new contract low of 139.70 dlrs per ton in the
nearby March contract today.
    "Many speculators down here bought March soymeal and sold
May, looking for no deliveries (on first notice day tomorrow,
which would cause March to gain on deferreds)," one CBT crush
trader said.
    "But they've been bailing out this week because the March
has been acting like there will be a lot delivered, if not
tomorrow, then later in the month," he added.
    As a result of the weakness in soymeal, the March crush
ratio (The value of soyproducts less the cost of the soybeans)
fell from the mid 30s earlier this month to 22.6 cents per
bushel today, dropping over five cents in just the last two
days.
    The May crush ended today just over 17 cents, so no
processors will want to lock in a ratio at that unprofitable
level, the trader said. Hopefully, they will now start to cut
back production to get supplies in line with demand, he added.
    With futures down, processors are finding they must bid
premiums for cash soybeans, further reducing crush margins.
    A central Illinois processor is only making about 30 cents
for every bushel of soybeans crushed at current prices, down
sharply from levels just seen just a few weeks ago and below
the average cost of production, cash dealers said.
    Most soybean processing plants are still in operation, with
little talk of taking temporary down-time, so far. But
processors will start halting production in the next few weeks
it they continue to face unprofitable margins, they added.

Defense Secretary Caspar Weinberger
ordered an increase in cost-of-living allowances for many U.S.
military personnel abroad because of the decreased value of the
dollar against foreign currencies, the Pentagon said.
    The allowances are expected to rise between 10 and 20 per
cent in many areas beginning this month, the Pentagon said..
    Weinberger also is providing for some family members of
financially-pressed troops to fly home from West Germany,
Japan, Italy and Spain on military transports if they desire.
    He said in a statement to the military that the
cost-of-living increases "will help keep your overseas
purchasing power close to your stateside counterparts."
 
Talks on the possibility of reintroducing
global coffee export quotas have been extended into today, with
sparks flying yesterday when a dissident group of exporters was
not included in a key negotiating forum.
    The special meeting of the International Coffee
Organization (ICO) council was called to find a way to stop a
prolonged slide in coffee prices.
    However, delegates said no solution to the question of how
to implement quotas was yet in sight.
    World coffee export quotas -- the major device used to
regulate coffee prices under the International Coffee Agreement
-- were suspended a year ago when prices soared in reaction to
a drought which cut Brazil"s output by nearly two thirds.
    Brazil is the world"s largest coffee producer and exporter.
    Producers and consumers now are facing off over the
question of how quotas should be calculated under any future
quota distribution scheme, delegates said.
    Tempers flared late Saturday when a minority group of eight
producing countries was not represented in a contact group of
five producer and five consumer delegates plus alternates which
was set up to facilitate debate.
    The big producers "want to have the ball only in their court
and it isn"t fair," minority producer spokesman Luis Escalante of
Costa Rica said.
    The majority producer group has proposed resuming quotas
April 1, using the previous ad hoc method of carving up quota
shares, with a promise to try to negotiate basic quotas before
September 30, delegates said.
    Their plan would perpetuate the status quo, allowing Brazil
to retain almost all of its current 30 pct share of the export
market, Colombia 17 pct, Ivory Coast seven pct and Indonesia
six pct, with the rest divided among smaller exporters.
    But consuming countries and the dissident producer group
have tabled separate proposals requiring quotas be determined
by availability, using a formula incorporating exportable
production and stocks statistics.
    Their proposals would give Brazil a smaller quota share and
Colombia and Indonesia a larger share, and bring a new quota
distribution scheme into effect now rather than later.
    Brazil has so far been unwilling to accept any proposal
that would reduce its quota share, delegates said.
    Delegates would not speculate on prospects for agreement on
a quota package. "Anything is possible at this phase," even
adjournment of the meeting until March or April, one said.
    If the ICO does agree on quotas, the price of coffee on the
supermarket shelf is not likely to change sinnificantly as a
result, industry sources said.
    Retail coffee prices over the past year have remained about
steady even though coffee market prices have tumbled, so an
upswing probably will not be passed onto the consumer either,
they said.
 
In a world where we must cope with terrorism and disease, software
sometimes seems trivial. When our civil liberties are in danger, how
important is source code? Are the rights assured by the GNU General
Public License important when people are starving?

To understand the role of software in our complex society, we must
investigate the role of mass communication in a democracy, and the way
that computer networking may help to democratize mass communication,
and thus lead us to better and more democratic societies.

It shouldn't be a surprise that a non-democratic regime instigated the
violence on 9/11 . It's more of a surprise to view the failure of the
democratic process that has proceeded in the purportedly democratic
nations now involved in that war. Most obvious was the failure of
the mass media in the United States and elsewhere in their duty to
analyze and criticise. Whether a war is justified or not, a television
network's job should be to provoke thought, not cheerleading, among
their viewers. Had they been fulfilling that role, and had they been
presenting to the American people before 9/11 what other cultures thought
of Americans, things might have been different. This gives us a measure
of the importance of the mass media.

The dialogue between a people and their government depends on
mass communication. Until the advent of inexpensive mass printing
based on movable type, heralded by Motoki Shozo in the East and
Gutenberg in the West, the world's only democratic councils were
themselves elites. Politics was the exclusive domain of the wealthy
and well-connected, the only people who could afford to come together
in person regularly to discuss politics. Until the printing press, news
and craft were communicated mostly by voice, and the common person had
little idea of what was going on farther away than the horizon. How much
could that person participate in governing his nation?

The printing press has been superceded by the broadcast media, the
second generation of mass media. The third generation, of course, is the
internet. Many individuals already use the web as their primary source
of news.

Let's talk about that second genration: the broadcast media.  Mass
communication is key to democracy, and today's mass communication
depends on scarce and expensive resources, such as radio spectrum,
that are administered by the government or are the effective property
of a wealthy few. Their control of our mass communications gives that
wealthy few too much power over what voters are told. Voters will cast
their votes on the information they've been given, accurate or not.

This is why we should be concerned about the web and internet. The web
is the most important tool for democracy since Shozo and Gutenberg. And
this is why the web, and the software that enables it, are a treasure
to be guarded and protected by any true democracy.

With a web site, anyone is a broadcaster. The only scarce resource is the
attention of web readers, and of course some of the web's most popular
sites started very small.  If our societies are to be democratic ones
in the future, internet-based discussion will be the main way in which
we carry out the dialogue between people and their government.

But can we maintain the internet as a channel for democracy, or will
it too become the property of a wealthy few? Will the individual still
be able to participate as much as he can today? There are a few clouds
on that horizon.  Monopolies are the enemy of economic competition and
democracy. And it's possible for a few monopolies to gain control of the
internet to a much greater extent than today. To protect democracy and
capitalism, we must make sure that control of the internet remains in the
hands of the many, rather than the few.  No company should have a monopoly
on internet software, internet connections, or internet content. These
areas need to be maintained as level playing fields for competition.

Operating systems, until then, had been the province of very large
companies, and these Free Software nut-cases proposed to do it in
their spare time, or at school, or as a low-priority task at work,
and they would give it away to all comers, and allow you to copy it
without cost. Obviously, the had no hope of success, right? But those
50 crazy people became 50,000.  And they changed the world. Why did such
a different idea succeed?

It was the power of the Internet that made widespread Open Source
development practical. The Internet made it practical for a software
developer in Japan to carry out a close collaboration with another
developer in France or Africa, and for people with very limited
resources to combine them and come up with enough power to get the job
done. Open Source development was probably an optimal task for the
early internet. Programmers are often very comfortable with textual
communication, and thus they were happy to use simple e-mail lists for
their communication, and FTP for their file exchanges. They were happy
without web browsers. But they weren't content to stay that way.

Thanks to the Hubble telescope, we know the universe contains more 
than 40 billion galaxies. And for the first time, the Cosmic Background 
Explorer satellite gives us a single picture of the entire Milky Way, 
our "little" home in space, and a spot well worth getting to know 
this summer. 

If you're in the city or crowded suburbs, take your family and friends 
for a drive in the country to a place where the night sky does not 
compete with neon. Bring a blanket, bug spray, and a flashlight with a 
red light (white light keeps our eyes from adjusting to their innate 
night vision).

The best time for stargazing is after midnight, with no moonlight or 
clouds. Dates when the skies will be moonless this summer include: 
June 6-14; July 6-14; August 4-12.

After your eyes adjust to the dark, take in the quiet grandeur of 
sparkling infinity. Watch long, and steadily. Bring along a 
pair of binoculars. Engage with the Milky Way, travel within its 
infinite vastness, and your imagination will be changed forever. 
As you look out into space you are looking back in time, thousands 
and millions of years back.

We live in a medium-sized spiral galaxy that is a relatively flat 
disk shape with a bulge in its center and spiral arms that 
radiate from its center like a colossal cosmic pinwheel. It stretches 
100,000 light- years from side to side, and 13,000 light-years 
from top to bottom at its center.

Spiral galaxies have an extended halo of faint, billions-of-years-old 
stars at their extremities. Their disks are rich in gas and 
dust, while the galactic bulge or nucleus at the center contains 
the greatest number of newly formed stars. If the Milky Way 
were a city, our sun would be in a distant suburb, 27,000 light-years 
from the galactic center.

One way to wrap your imagination around the size of our galaxy is 
to realize that it takes the sun 240 million earth years to 
make one orbit around the Milky Way. Given that our galaxy is 
some 4.5 billion years old (and our sun is traveling at 484,000 mph 
around the galaxy, give or take 25,000 mph), it has made 20 revolutions 
around the Milky Way.

In June, the mid-latitudes of the Northern Hemisphere tilt toward 
the sun more directly than at any other time of the year. 
Nights are shortest  and warm. This season offers the most favorable 
conditions for observing (not just looking at) the 
luminous river of stars that comprise the Milky Way streaming from 
north to south across the sky.

Remember, you are looking into the Milky Way (and just a part of it; 
you can't see through to the other end). What you are 
seeing represents a narrow band of the sky, albeit where the most stars 
are visible to the naked eye.

I grew up in New York, three miles from Kennedy Airport. When someone 
said, "Look, there's the first star," my reaction 
was a shrug. There would only be a couple of dozen visible. But my i
attitude changed when I was 19 and lived in a rural valley in 
southwest Mexico.

My first night there, I looked up at the sky and asked, "What's that 
funny cloud?" It was the Milky Way, stretching as far as 
my eye could see and my neck could crane. At that instant, my whole 
being was tranformed. and what I saw became the 
felt presence of infinity.

Looking for planets, stars, and constellations links us to one of 
the oldest activities of the human race. It is our destiny to look up. 
This column will share that destiny. And first, we need to get a feel 
for the forest rather than the trees. The Milky Way is a star forest.
