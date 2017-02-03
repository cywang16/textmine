#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 use strict; use warnings;
 use TextMine::Cluster qw/cluster/;
 use TextMine::Summary   qw/phrases_ex/;
 use TextMine::Utils   qw/min_max/;
 use TextMine::Constants;
 use TextMine::DbCall;

 #*-----------------------------------------------------------------
 #*- cluster.pl
 #*-   Description: Test the clustering code
 #*-----------------------------------------------------------------

 my $userid = 'tmadmin'; my $password = 'tmpass';
 my ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
        'Userid' => $userid, 'Password' => $password, 'Dbname' => $DB_NAME);

 #*-- set a threshold
 my $thresh = $ARGV[0] ? $ARGV[0]: '';

 #*-- read in the doc.txt and build the @text list
 my ($inline, $text, $category, $doc_num);
 my (@text, @category);
 print ("Started cluster.pl\n");
 while ($inline = <DATA>)
  {
   chomp($inline);
   if ($inline =~ /(\d+):(.*?): -- Document Separator/i)
    { 
     #*-- this is a new document
     if ($text && $category)
      { $text[$doc_num] = $text; $category[$doc_num] = $category; }
     $text = ''; ($doc_num, $category) = ($1, $2);
    }
   else { $text .= " $inline";}
  }

 #*-- finish the last document
 if ($text && $category)
   { $text[$doc_num] = $text; $category[$doc_num] = $category; }
 my (@docs); push (@docs, \$_) foreach (@text);

 #*-- calculate the clusters
 my $vtype = 'fre'; 	#*-- vector types are fre, idf, and lsi
 my $ltype = 'full_link';#*-- link types are one_link, half_link, full_link 
 my $r_clusters = &cluster(\@docs, $vtype, $dbh, 'news', 
                           $ltype, $thresh, 'debug');

 #*-- build the label for each cluster
 print "Finished clustering\n";
 my @clusters = @$r_clusters; my @titles = my @precision = ();
 foreach my $i (0..$#clusters)
  { 
   #*-- build the text for the cluster member
   if ($i == $#clusters)
    { push (@titles, 'Miscellaneous Cluster'); push (@precision, 0.0);
      next; }

   my @c_docs = split/,/, $clusters[$i];
   my $text = ''; $text .= ${$docs[$_]} foreach (@c_docs);
  
   #*-- extract the phrases
   (my $r_bigrams) = &phrases_ex(\$text, 3, $dbh); 
   push (@titles, join(': ', @$r_bigrams) );

   #*-- compute the quality of the cluster
   my %cats = (); foreach (@c_docs) { $cats{$category[$_]}++; }
   my @cats = values %cats;
   (undef, my $max_docs) = &min_max(\@cats); my $num_docs = @c_docs;
   push (@precision, int ( 100.0 * $max_docs / $num_docs ) );
  } #*-- end of for clusters
 
 my %cats = ();
 for my $i (0..$#category) { $cats{"$category[$i]"} .= "$i,"; }
 print ("Categories:\n");
 foreach (sort { length($cats{$b}) <=> length($cats{$a}) } keys %cats)
  { print ("$_: $cats{$_}\n"); }

 #*-- dump the clusters
 print ("Clusters: \n"); 
 for my $i (0..$#clusters)
  { my $j = $i + 1; print ("CLUSTER $j: $titles[$i]\n");
    if ($i == $#clusters)
     { my @c_size = split/,/, $clusters[$i]; my $s_size = @c_size;
       print ("Misc. size is $s_size\n"); }
    $clusters[$i] = join (',', sort {$a <=> $b} split/,/, $clusters[$i]);
    print ("\tMEMBERS: $clusters[$i] "); 
    print ("PRECISION: $precision[$i]\%\n"); }

 $dbh->disconnect_db();
 print ("Ended cluster.pl\n");
 exit(0);

__DATA__
0: sugar: -- Document Separator -- reut2-021.sgm
British Sugar Plc was forced to shut its
Ipswich sugar factory on Sunday afternoon due to an acute
shortage of beet supplies, a spokesman said, responding to a
Reuter inquiry
    Beet supplies have dried up at Ipswich due to a combination
of very wet weather, which has prevented most farmers in the
factory's catchment area from harvesting, and last week's
hurricane which blocked roads.
    The Ipswich factory will remain closed until roads are
cleared and supplies of beet build up again.
    This is the first time in many years that a factory has
been closed in mid-campaign, the spokesman added.
    Other factories are continuing to process beet normally,
but harvesting remains very difficult in most areas.
    Ipswich is one of 13 sugar factories operated by British
Sugar. It processes in excess of 500,000 tonnes of beet a year
out of an annual beet crop of around eight mln tonnes.
    Despite the closure of Ipswich and the severe harvesting
problems in other factory areas, British Sugar is maintaining
its estimate of sugar production this campaign at around 1.2
mln tonnes, white value, against 1.34 mln last year, the
spokesman said.
    British Sugar processes all sugar beet grown in the U.K.
    The sugar beet processing campaign, which began last month,
is expected to run until the end of January. Sugar factories
normally work 24 hours a day, seven days a week during the
campaign.
    As of October 11, 12 pct of the U.K. Sugar crop had been
harvested, little different to the same stage last year when 13
pct had been lifted. Since then, however, very wet weather has
severely restricted beet lifting.
    Harvesting figures for the week to October 18 are not yet
available.
 
1: sugar: -- Document Separator -- reut2-021.sgm
A sharp rise in Soviet sugar consumption
since the start of the Kremlin's anti-alcohol drive indicates
home brewing is costing the state 20 billion roubles in lost
vodka sales, Pravda said.
    The Communist Party newspaper said sugar sales had
increased by one mln tonnes a year, enough to be turned into
two billion bottles of moonshine.
    At current vodka prices of 10 roubles a bottle, it said,
this meant illicit alcohol consumption had reached the
equivalent of 20 billion roubles a year, or annual revenues
from vodka sales before the May 1985 anti-alchohol decree.
    "Official statistics show a reduction in consumption of
vodka, but this is a deceptive statistic -- it does not count
home-brew," Pravda said.
    "The epidemic first engulfed the villages and has now also
firmly settled into cities, where the availability of natural
gas, running water and privacy has made it much easier."
    Kremlin leader Mikhail Gorbachev launched the anti-alcohol
campaign shortly after taking office in March 1985 as a first
step to improving Soviet economic performance, which had been
seriously hurt by drunkenness among the working population.
 
2: cocoa: -- Document Separator -- reut2-013.sgm
Leading cocoa producers will discuss
whether newly-agreed rules on an international cocoa buffer
stock will succeed in reversing a sharp fall in world prices
when they start four day's of talks here later today,
conference sources said.
    Another topic likely to be discussed at the twice-yearly
meeting of the Cocoa Producer Alliance (CPA) is the pact's
second line of market support -- a witholding scheme under
which exporters can take up to 120,000 tonnes of cocoa off the
market if buffer stock purchases fail to defend prices.
    The International Cocoa Organisation is due to discuss the
scheme at a meeting in June, and exporters could use the
Yaounde talks to work out a common position on the issue, the
sources said.
    Delegates will also be briefed on arrangements for an
international cocoa research conference due to take place in
Santo Domingo in the Dominican Republic next month, CPA
secretary general D.S. Kamga said.
    The 11-member CPA include the world's top three producers
of Ivory Coast, Brazil and Ghana and accounts for around 80 pct
of world output.
 
3: sugar: -- Document Separator -- reut2-013.sgm
Indonesia has imported 12,000 tonnes of
refined sugar from Cuba to meet consumer demand in the province
of South Sulawesi, the head of the provincial food agency said.
    The imported sugar was needed because two of three sugar
refineries in the province have been temporarily shut down. It
arrived in the provincial capital of Ujungpandang today and
will be distributed to markets in the province, the food agency
official said.
    Indonesia used to be a sugar exporter but last year it
imported 162,500 tonnes of sugar from Thailand, Angola and
Brazil to bolster its depleted stocks.
    Indonesia's sugar cane production last year was expected to
rise significantly but domestic sugar consumption has soared
because of rising demand by the food processing industry, the
head of the food logistics agency, Bustanil Arifin, has said.
    The government has forecast that sugar production in
calendar 1987 would increase 30.2 pct to 2.59 mln tonnes from
1.99 mln in 1986 but industry sources doubt whether the target
could be met due to persistent post-harvest handling and
transport problems.
 
4: sugar: -- Document Separator -- reut2-008.sgm
The U.S. Agriculture Department 
formally transmitted to Congress a long-awaited proposal to
drastically slash the sugar loan rate and compensate growers
for the cut with targeted income payments.
    In a letter to the Congressional leadership accompanying
the "Sugar Program Improvements Act of 1987", Peter Myers,
Deputy Agriculture Secretary, said the Reagan administration
wants the sugar loan rate cut to 12 cents per pound beginning
with the 1987 crop, down from 18 cts now.
    Sugarcane and beet growers would be compensated by the
government for the price support cut with targeted income
payments over the four years 1988 to 1991. The payments would
cost an estimated 1.1 billion dlrs, Myers said.
    The administration sugar proposal is expected to be
introduced in the House of Representatives next week by Rep.
John Porter, R-Ill.
    Congressional sources said the program cut is so drastic it
is unlikely to be adopted in either the House or Senate because
politically-influential sugar and corn growers
and high fructose corn syrup producers will strongly resist.
    The direct payment plan outlined by the administration 
targets subsidies to small cane and beet growers and gradually
lowers payments over four years. It also excludes from payment
any output exceeding 20,000 short tons raw sugar per grower.
    For example, on the first 350 tons of production, a grower
would receive 6 cts per lb in fiscal 1988, 4.5 cts in 1989, 3
cts in 1990 and 1.5 cts in 1991.
    The income payments would be based on the amount of
commercially recoverable sugar produced by a farmer in the 1985
or 1986 crop years, whichever is less, USDA said.
    Myers said the administration is proposing drastic changes
in the sugar program because the current high price support is
causing adverse trends in the sugar industry.
    He said the current program has artificially stimulated
domestic sugar and corn sweetener production which has allowed
corn sweeteners to make market inroads.
    U.S. sugar consumption has declined which has resulted in a
"progressive contraction" of the sugar import quota to only one
mln short tons this year, he said. This has hurt cane sugar
refiners who rely on imported sugar processing.
    Furthermore, USDA said the current sugar program gives
overseas manufacturers of sugar-containing products a
competitive advantage. The result has been higher imports of
sugar-containing products and a flight of U.S. processing
facilities overseas to take advantage of cheaper sugar.
    USDA also said the current program imposes a heavy cost on
U.S. consumers and industrial users. In fiscal 1987, USDA said
consumers are paying nearly two billion dlrs more than
necessary for sugar.
    "Enactment of this bill will reduce the price gap between
sweeteners and help to correct or stabilize the many adverse
impacts and trends which the sugar industry is currently
facing," Myers said.
    The following table lists the rate of payments, in cts per
lb, to growers and the quantity covered, in short tons
recoverable raw sugar, under the administration's proposal to
compensate sugar growers with targeted payments.
    QUANTITY            1988     1989      1990      1991
First 350 tons         6.000    4.500     3.000     1.500
Over 350 to 700        5.750    4.313     2.875     1.438
Over 700 to 1,000      5.500    4.125     2.750     1.375
Over 1,000 to 1,500    5.000    3.750     2.500     1.250
Over 1,500 to 3,000    4.500    3.375     2.250     1.125
Over 3,000 to 6,000    3.500    2.625     1.750     0.875
Over 6,000 to 10,000   2.250    1.688     1.125     0.563
Over 10,000 to 20,000  0.500    0.375     0.250     0.125
Over 20,000 tons        nil      nil       nil       nil 
 
5: coffee: -- Document Separator -- reut2-008.sgm
The Bremen green coffee market attracted
good buying interest for Colombian coffee last week, while
Brazils were almost neglected, trade sources said.
    Buyers were awaiting the opening of Brazil's export
registrations for May shipment, which could affect prices for
similar qualities, they said.
    Colombia opened export registrations and good business
developed with both the FNC and private shippers. Prices were
said to have been very attractive, but details were not
immediately available.
    Central Americans were sought for spot and afloat.
    In the robusta sector nearby material was rather scarce,
with turnover limited, the sources said.
    The following offers were in the market at the end of last
week, first or second hand, sellers' ideas for spot, afloat or
prompt shipment in dlrs per 50 kilos fob equivalent, unless
stated (previous week's prices in brackets) -
    Brazil unwashed German quals 100 (102), Colombia Excelso
105 (110), Salvador SHG 110 (108), Nicaragua SHG 109 (same),
Guatemala HB 111 (same), Costa Rica SHB 113 (112), Kenya AB FAQ
142 (134), Tanzania AB FAQ 120 (same), Zaire K-5 105 (unq),
Sumatra robusta EK-1 91 CIF (same).
 
6: coffee: -- Document Separator -- reut2-008.sgm
Uganda's state-run Coffee Marketing
Board (CMB) has been suffering a cash crisis for the past two
months due to a bottleneck in export shipments and
administrative delays in handling payments, trade sources said.
    The CMB needs between 10 and 15 billion shillings (the
equivalent of seven to 10 mln dlrs) to pay farmers and
processors for coffee already delivered, but its present export
revenue is insufficient to cover such expenditure, they said.
    The board's cash crisis has serious implications for the
economy as a whole, since coffee accounts for 95 pct of
Uganda's total exports.
    The CMB's financial difficulties first started in January
following delays in rail-freighting export consignments of
coffee to the ports of Mombasa, Dar es Salaam and Tanga.
    These delays were caused by a shortage of railway wagons in
Uganda and bottlenecks on the ferries which transport Ugandan
wagons across Lake Victoria to link up with the Kenyan and
Tanzanian railway systems, the sources said
    Marketing Minister John Sebaana-Kizito publicly
acknowledged on February 19 that the CMB had run up arrears to
local suppliers as a result of the shortage of transport for
moving exports.
    Sebaana-Kizito said at the time that the payments squeeze
would be resolved in two weeks.
    However, an accident to the rail ferry which plies between
the Ugandan lake port of Jinja and Kisumu in Kenya put it out
of action between February 21 and March 15, causing fresh
delays in cargo movements.
    Coffee exports are especially sensitive to the disruption
of rail transport since president Yoweri Museveni has banned
their haulage by road in a drive to save transport costs.
    Transport difficulties meant that by early February the CMB
was holding unsold coffee stocks of around 750,000 bags.
    These stocks were equivalent to one quarter of Uganda's
expected three mln 60-kilo bag 1986/87 (October-September)
crop, the sources said.
    According to the sources, the board's financial problems
have been aggravated by long delays in processing export
receipts.
    The coffee board was taking about eight weeks to recycle
export receipts into payments to local producers, whereas
export bills handled by local banks took half that time to
process, they said.
    The sources said the CMB's price structure had been
overtaken by Uganda's high inflation rate, unofficially
estimated at about 200 pct, and that this was a further
disincentive to producers, already owed large arrears.
    "The coffee pricing structure is wrong and three months
behind, the foreign exchange rate is unrealistic, and the
sooner the so-called economic package is put in top gear, the
better for the coffee industry and the economy as a whole," one
of the sources said.
    The government is currently negotiating a package of
economic reforms with the World Bank and International Monetary
Fund aimed at underpinning a renewed inflow of foreign aid to
help Uganda's economic recovery after 15 years of political
strife.
 
7: sugar: -- Document Separator -- reut2-011.sgm
Representatives of U.S. sugar grower
organizations said they expect some increase the area planted
to sugarbeets this year and said the prospects for the 1987
cane sugar crop also are good.
    Dave Carter, president of the U.S. beet sugar association,
said plantings may be up in two major beet growing states,
California and Michigan, while sowings could be down slightly
in the largest producing state of Minnesota.
    Overall, Carter predicted beet plantings would rise in the
midwest, and this coupled with increases in California would
increase U.S. sugarbeet plantings slightly from the 1.232 mln
acres sown last year.
    USDA later today releases its first estimate of 1987 U.S.
sugarbeet plantings in the prospective plantings report.
    The main reason for the expected increase in beet sowings
is that returns from competing crops such as soybeans and
grains are "just awful," said Carter.
    In the midwest, bankers are strongly encouraging farmers to
plant sugarbeets because the U.S. sugar program offers a loan
rate of 18 cents per pound and because payments to farmers from
beet processors are spread evenly over the growing season, said
Luther Markwart, executive vice president of the American
sugarbeet growers association.
    "The banks are putting a lot of pressure on these guys,"
Markwart said.
    In some areas there are waiting lists of farmers seeking a
contract with processors to plant beets, Markwart said.
    USDA's report today will not include any harvested area
estimates for sugarcane, but representatives of Florida, Hawaii
and Louisiana growers said crop prospects are good.
    Horis Godfrey, a consultant representing Florida and Texas
cane growers, said Florida cane is off to a good start  because
for the first time in several years there was no winter freeze.
Although area to be harvesteed is about the same as last year,
cane production may be up in Florida this year, he said.
    In Hawaii, area harvested may decline slightly this year,
but likely will be offset again in 1987 by increased yields,
said Eiler Ravnholt, vice president of the Hawaiian Sugar
Planters Association.
    The acreage planted to sugarbeets will receive more than
the usual amount of attention this year because of mounting
concern that continued increases in domestic sugar production
threaten the U.S. sugar program, industry sources said.
    The increases in beet plantings have especially caused
concern among cane growers who have not expanded plantings,
particularly in Hawaii, industry officials said.
    "We haven't had a good weather year throughout the beet and
cane areas in more than five years," said Godfrey, adding that
the U.S. may be due for a good weather year.
    Rep. Jerry Huckaby, D-La., chairman of the House
agriculture subcommittee responsible for the sugar program, has
threatened to offer legislation next year to curb domestic
sweetener output if growers fail to restrain output in 1987.
 
8: coffee: -- Document Separator -- reut2-011.sgm
The Coffee, Sugar and Cocoa Exchange
has expanded the normal daily trading limit in Coffee "C"
contracts to 6.0 cents a lb, from the previous 4.0 cents,
effective today, the CSCE said.
    The new daily limits apply to all but the two nearby
positions, currently May and July, which trade without limits.
    In addition, the 6.0 cent limit can be increased to 9.0
cents a lb if the first two limited months both make limit
moves in the same direction for two consecutive sessions,
according to the CSCE announcement.
    Before the rule change today, the CSCE required two days of
limit moves in the first three restricted contracts before
expanding the daily trading limit.
    Under new guidelines, if the first two restricted
deliveries move the 6.0 cent limit for two days the Exchange
will expand the limit. The expanded 9.0 cent limit will remain
in effect until the settling prices on both of the first two
limited months has not moved by more than the normal 6.0 cent
limit for other contracts in two successive trading sessions,
the CSCE said.
 
9: sugar: -- Document Separator -- reut2-011.sgm
A plan by European producers to sell
854,000 tonnes of sugar to European Community intervention
stocks still stands, Andrea Minguzzi, an official at French
sugar producer Beghin-Say, said.
    Last week Beghin-Say president Jean-Marc Vernes said a
possible settlement of a row with the EC would lead producers
to withdraw their offer, which was made as a protest against EC
export licensing policies.
    The EC policy is to offer export rebates, which fail to
give producers an equivalent price to that which they would get
by offering sugar into intervention stocks, Vernes said.
    But Minguzzi said the offer was a commercial affair and
that producers had no intention of withdrawing the sugar offer
already lodged with intervention boards of different European
countries. He said final quality approval for all the sugar
offered could come later this week. Some 95 pct had already
cleared quality specifications.
    The EC can only reject an offer to sell into intervention
stocks on quality grounds. Minguzzi added that under EC
regulations, the Community has until early May to pay for the
sugar. He declined to put an exact figure on the amount of
sugar offered by Beghin-Say, but said it was below 500,000
tonnes.
 
10: coffee: -- Document Separator -- reut2-011.sgm
Singapore's United Industrial Corp Ltd
(UIC) has agreed in principle to inject 16 mln dlrs in
convertible loan stock into &lt;Teck Hock and Co (Pte) Ltd>, a
creditor bank official said.
    UIC is likely to take a controlling stake in the troubled
international coffee trading firm, but plans are not finalised
and negotiations will continue for another two weeks, he said.
    Teck Hock's nine creditor banks have agreed to extend the
company's loan repayment period for 10 years although a
percentage of the new capital injection will be used to pay off
part of the debt.
    Teck Hock owes more than 100 mln Singapore dlrs and since
last December the banks have been allowing the company to
postpone loan repayments while they try to find an investor.
    The nine banks are Oversea-Chinese Banking Corp Ltd, United
Overseas Bank Ltd, Banque Paribas, Bangkok Bank Ltd, Citibank
N.A., Standard Chartered Bank Ltd, Algemene Bank Nederland NV,
Banque Nationale de Paris and Chase Manhattan Bank NA.
 
11: sugar: -- Document Separator -- reut2-014.sgm
New immigration rules relating to
alien farm workers and reportedly being drafted by the U.S.
Agriculture Department are meeting with objections in Congress,
sources on Capitol Hill said.
    USDA is drafting regulations, required by a 1986 law, that
would offer amnesty to illegal aliens if they worked in the
cultivation of fruits, vegetables and other perishable
commodities.
    The department is considering including in its definition
of perishable commodities such farm products as tobacco, hops,
Spanish reeds and Christmas trees, while excluding sugar cane,
the New York Times reported yesterday.
    Rep. Howard Berman, D-Calif., would like to see the
definition extended to include sugar cane, cultivation of which
is "a breeding ground for one of the scandals of the nation,"
Gene Smith, a spokesman for Berman, said.
    Livestock, dairy and poultry producers have been lobbying
USDA hard to have their products covered by the amnesty
provision, farm industry sources said.
    Chuck Fields of the American Farm Bureau Federation said
livestock producers were "desperate" because they fear they will
be unable to retain the many illegal aliens who have joined
that industry.
    A House staff member involved in drafting the landmark 1986
immigration law who asked not to be identified said Congress
did not mean to extend special amnesty provisions to workers
who helped cultivate tobacco, and that inclusion of hops and
Spanish reeds was "marginal."
    In addition, lawmakers made it clear during consideration
of the bill that lumber workers were not to be covered by the
the amnesty provisions, making the inclusion of Christmas trees
"a tough call," this source said.
    USDA officials declined to comment on the draft regulation
except to say it was subject to change before it will be
released, probably some time later this month.
    While lawmakers may object to the USDA rule under
consideration relating to perishable commodities, Congress is
not likely to reopen debate on the controversial immigration
question, congressional sources said.
    The amnesty provision specially designed for farm workers
was crucial to passage of the overall immigration bill.
    Congressional staff members estimate the special farm
worker amnesty provision would apply to between 250,000 to
350,000 aliens. The law would allow eligible farm workers who
worked for 90 days during the year ending May 1, 1986, to apply
for temporary, then permanent, resident status.
 
12: sugar: -- Document Separator -- reut2-014.sgm
Cuban president Fidel Castro told a
Congress of the Union of Young Communists here that the
production of crude sugar during the harvest still in progress
is 800,000 tonnes behind schedule.
    In a speech Sunday, published in today's official paper
GRANMA, Castro said unseasonable rains since January seriously
interrupted harvesting and milling operations especially in the
central and western parts of the island.
    The Cuban leader said the mechanical cane harvesters
scheduled to cut over 60 pct of the cane this year were
particularly "vulnerable," as muddy fields prevent operations.
    Neither Castro nor the Cuban press have given out figures
to estimate tonnes of crude production during the present
harvest or the goals for the sugar campaign.
    However, a cuban sugar official told Reuters that the
country will be lucky if crude output reaches last year's 7.2
mln tonnes. Output of crude for the previous 1984-85 harvest
was 8.2 mln tonnes.
    The harvest was scheduled to end April 30 but due to the
present shortfalls it will be extended into May and June, the
official said.
 
13: sugar: -- Document Separator -- reut2-014.sgm
Good rains of one to four inches in the
past 10 days have boosted moisture-stressed sugar cane crops in
the Mackay-Burdekin region of Queensland's central coast, an
Australian Sugar Producers' Association spokesman said.
    As previously reported, the region has been undergoing a
severe dry spell, partly relieved by scattered rainfall, since
December, following the virtual failure of the summer wet
season.
    Mills in the area have been reporting that their crops are
beginning to look healthy and greener and are putting on growth
since the rains began, the spokesman said from Brisbane.
    Although the Mackay-Burdekin crop outlook is much better
than it was, there will be some cane losses, the spokesman
said. But is too early to say what they will be and more rain
is needed to restore sub-soil moisture.
    Elsewhere, in far north Queensland, the Bundaberg region
and southern Queensland, the cane is in excellent condition and
some mills are forecasting record crops, he said.
    Initial 1987 crop estimates will probably be compiled
towards the end of May, he said.
    The cane crush normally runs from June to December.
 
14: sugar: -- Document Separator -- reut2-014.sgm
West German Finance Minister Gerhard
Stoltenberg said today's meetings of major industrial countries
would look at ways of strengthening the Paris accord on
stabilizing foreign exchange rates.
    Stoltenberg told journalists he saw no fundamental weakness
of the February 22 agreement of the Group of Five countries and
Canada to keep exchange rates near the then-current levels.
    But he declined to say what measures would be discussed
ahead of a communique of the Group of Seven ministers later
today.
    Stoltenberg and Bundesbank President Karl Otto Poehl said
the importance of the Paris agreement, also known as the Louvre
accord, had been underestimated.
    Stoltenberg said there is greater agreement now among major
countries than six months ago, at the time of the annual
meeting of the International Monetary Fund and World Bank,
marked by sharp discord between the United States and its major
trading partners.
    "There is no fundamental weakness of the Paris accord," he
said. "We will be looking at ways of strengthening it, but I do
not want to discuss that here.
    Stoltenberg said the Louvre agreement was working despite a
"slight firming" of the yen against the dollar.
    And Poehl noted that the dollar/mark parity was unchanged
since February 22 without the Bundesbank having had to sell
marks to support the dollar.
    "The Louvre agreement has been honored by the market," he
said.
    Poehl said West Germany had lived up to its side of the
bargain in Paris by preparing the way for tax cuts to be
accelerated as a way of stimulating growth.
    Poehl said, however, that Japan had not yet fulfilled its
pledges for economic stimulation.
    "And we will have to see if the United States is able to do
what they promised in Paris on reducing the budget deficit --
and get it through Congress," he added.
    Stoltenberg reiterated West German concern about a further
fall in the dollar, noting that the mark was up 85 pct against
the dollar and nearly 20 pct on a trade-weighted basis.
    "You cannot expect that to go unnoticed in an economy. And
it is not just a German problem, it is a European problem," he
said.
 
15: cocoa: -- Document Separator -- reut2-006.sgm
The International Cocoa Organization,
ICCO, buffer stock working group began examining a draft
proposal for buffer stock rules this afternoon, delegates said.
    The plan, presented by ICCO Executive Director Kobena
Erbynn, represented a compromise between producer, European
Community, EC, and other consumer views on how the buffer stock
should operate, they said.
    The proposal involved three key principles. First, the
buffer stock manager would be open to offers for cocoa rather
than using fixed posted prices as previously, delegates said.
    Under an offer system, the buffer stock manager would be
free to choose cocoas of varying prices, they said.
    The second provision was that non-ICCO member cocoa could
comprise a maximum 10 pct of the buffer stock, while the third
laid out a pricing system under which the buffer stock manager
would pay differentials for different grades of cocoa, to be
set by a formula, the delegates said.
    After the plan was presented, working group delegates met
briefly in smaller groups of producers, EC consumers and all
consumers to look at the proposal. Producers gave no reaction
to the scheme and will respond to it when the working group
meets tomorrow at 1000 GMT, producer delegates said.
    Consumer members accepted the proposal as a good base to
work from, one consumer delegate said.
    Delegates said the proposal was only a starting point for
negotiations on buffer stock rules and subject to change.
 
16: cocoa: -- Document Separator -- reut2-006.sgm
New Zealand's inflation and interest
rates should decline and the balance of payments improve
significantly in the fiscal year to the end of March 1988, the
Institute of Economic Research (NZIER) said.
    The independent institute said in its quarterly March issue
that it was also revising its fiscal 1987 real gross domestic
product (GDP) forecast to a fall of 0.5 pct against the one pct
drop forecast in December.
    Government figures show GDP grew at an annual 1.8 pct in
the quarter to September and 3.4 pct in the June quarter.
    The NZIER said the sharp improvement in the June and
September quarters was due mainly to a new tax structure and
the introduction of a 10 pct value-added goods and services tax
and is not expected to continue in the second half of 1986/87.
    The government's tight fiscal position is not expected to
change, it said.
    Annual inflation, measured by the consumer price index, is
forecast to fall to nine pct by next March from 18.2 pct in
calendar 1986, it said.
    "Falling inflation is likely to give significant scope for
reductions in nominal interest rates; real interest rates are
also expected to ease (albeit slightly) as the balance of
payments deficit and hence the call on overseas capital, falls
away," the NZIER said.
    Short-term interest rates are forecast to remain between 20
and 25 pct until the June quarter, but will decline over the
second half of 1987/88 to between 16 and 18 pct. Long-term
rates are expected to fall to between 14 and 16 pct.
    Five year government bond rates are currently 18.40 pct and
the key indicator 30-day bank bills 26.53 pct.
    The local dollar is expected to depreciate steadily in the
early part of the coming year and, by next March, reach 57.5 on
the Reserve Bank's trade weighted index, which is based on a
basket of currencies. The index now stands at around 66.4.
    "A marked improvement in the balance of payments is
forecast," the NZIER said. "The current account deficit is
expected to fall from 7.5 pct of GDP in 1985/86 to 4.5 pct in
1986/87 and 2.5 pct in 1987/88."
    The current account deficit is forecast to shrink to 1.32
billion N.Z. Dlrs in 1987/88 from 2.40 billion in 1986/87 and
3.33 billion in 1985/86.
    The 1987/88 budget deficit is forecast to be 2.8 billion
dlrs against an expected 2.9 billion dlrs in 1986/87 and 1.87
billion in 1985/86.
    This compares with the government's 1986/87 deficit figure
of 2.92 billion against an earlier forecast of 2.45 billion.
    "Conditions in the coming year are sufficiently subdued to
contribute to marked improvements in both the balance of
payments and the rate of inflation ...," the NZIER said.
    "Overall, these are significant gains for the New Zealand
economy and, if they continue to be improved upon, bode well
for future prospects."
 
17: cocoa: -- Document Separator -- reut2-006.sgm
International Cocoa Organization (ICCO)
producers and consumers accepted the principles of a compromise
proposal on buffer stock rules as a basis for further
negotiation, delegates said.
    The buffer stock working group then asked ICCO Executive
Director Kobena Erbynn, who wrote up the draft compromise, to
flesh out details of the principles with the assistance of a
representative group of delegates, they said.
    The working group broke up for the day, into a smaller
group of five producers and five consumers to discuss
administrative rules and into the group headed by Erbynn to
hammer out buffer stock rules details, delegates said.
    Delegates said many differences of opinion still have to be
ironed out. "Whenever we start getting into details the clouds
gather," one delegate said.
    Erbynn is likely to present fleshed out details of the
buffer stock rules proposal to the working group early
tomorrow, delegates said.
    The principles of the draft proposal included establishing
an offer system for buffer stock purchases rather than a posted
price system, a limit to the amount of non-ICCO member cocoa
that can be bought, and differentials to be paid for different
varieties of cocoa comprising the buffer stock, delegates said.
 
18: cocoa: -- Document Separator -- reut2-006.sgm
New York cocoa traders reacted with
caution to today's developments at the International Cocoa
Organization talks in London, saying there is still time for
negotiations to break down.
    "I would be extremely cautious to go either long or short
at this point," said Jack Ward, president of the cocoa trading
firm Barretto Peat. "If and when a final position comes out (of
the ICCO talks) one will still have time to put on positions.
The risk at the moment is not commensurate with the possible
gain."
    ICCO producer and consumer delegates this morning accepted
the outlines of a compromise proposal on buffer stock rules as
a basis for further negotiation. A smaller group of
representatives is now charged with fleshing out the details.
    "Market sentiment has reflected optimism, I would't put it
any stronger than that," Ward said.
    "It seems to put them slightly closer to an agreement...
but one shouldn't forget how much they have to negotiate," said
another trader of today's developments.
    Many dealers were sidelined coming into the negotiations
and have remained so, traders said.
    "The dealers have got historically small positions in
outright terms," one trader said.
    Speculators have gone net long "but only slightly so," he
added.
    The recent price strength -- gains of about 52 dlrs the
last two days -- has been due in large part to sterling's rally
against the dollar and in the process has attracted a measure
of origin selling, traders said.
 
19: sugar: -- Document Separator -- reut2-006.sgm
Latin American sugar producers
are awaiting further rises in world market prices before moving
to boost production, official and trade sources said.
    Although prices have risen to around eight from five U.S.
Cents per lb in the past six months, they are still below the
region's nine to ten cents per lb average production cost.
    The recent rise in prices has placed producers on the
alert, Manuel Rico, a consultant with the Group of Latin
American and Caribbean Sugar Exporting Countries (GEPLACEA),
told Reuters.
    However, Rico said, it would require another five to seven
cents to stimulate notable increases in output.
    "Producers are taking measures for increasing their
production when the prices are profitable," he said.
    Officials in Mexico, Guatemala and Ecuador said a continued
rise in prices would stimulate production, but industry leaders
in Panama and Costa Rica said there was still a long way to go.
    "The prices are ridiculous," said Julian Mateo, vice
president of Costa Rica's Sugar Cane Industrial-Agricultural
League. "At current prices nobody is going to consider
increasing production."
    Other producers are wary of committing funds to increasing
output, given the instability of world markets.
    An official at Colombia's National Association of Sugar
Cane Growers said they had no plans to raise export targets.
"The market is very unstable. What is happening is not yet
giving way to a pattern and so there is no reason to modify
anything."
    In 1985, the latest year for which full figures are
available, Central and South American nations produced 28 mln
tonnes, raw value, of sugar of which 12.3 mln were exported. A
year earlier, they had produced and exported about 800,000
more, according to the London-based International Sugar
Organization.
    Years of continuous low prices have plunged the sugar
industry in many countries in the region into a recession from
which it will be hard to recover.
    Miguel Guerrero, director of the Dominican Republic's
National Sugar Institute, said it would be difficult to boost
production even if prices recovered sharply.
    Output had slumped to under 450,000 tonnes a year from
900,000 in the late 1970s. Obsolete refineries, poor transport
and badly maintained plantations were barriers to any short
term recovery in output, he added.
    Plans of nearby Cuba, the world's largest cane sugar
exporter, to increase output to 10 mln tonnes a year by the end
of the decade seem ambitious, trade sources said. Output is
running well below the record 8.6 mln produced in 1970.
    Cuba suffers from run down plantations, harvesting problems
and poor processing facilities more than from low world prices,
since much of its output is sold to Eastern Bloc countries
under special deals. Last year, bad weather added to its
troubles, and output fell to 7.2 mln tonnes from 8.2 mln in
1985.
    The low world prices of recent years have led many
countries in the region to cut exportable production to levels
where they barely cover U.S. And, in the case of some Caribbean
countries, European Community (EC) import quotas, for which
they receive prices well above free market levels.
    Progressive reductions in the U.S. Quotas have led to
production stagnating or falling rather than being shifted to
the free world market.
    Peru, for example, shipped 96,000 tonnes to the U.S. In
both 1983 and 1984. This fell to 76,000 in 1986 and this year
its quota is only 37,000.
    A national cooperative official said that, as long as world
market levels continue at around half of Peru's production
cost, the future of the industry is uncertain.
    At a meeting of GEPLACEA in Brazil last October officials
stressed the need to find alternative uses for sugar cane
which, according to the group's executive-secretary Eduardo
Latorre, "grows like a weed" throughout the region.
    Brazil, the largest cane producer with output of around 240
mln tonnes, uses over half to produce alcohol fuel. Cane in
excess of internal demand for alcohol and sugar is refined into
sugar for sale abroad to earn much needed foreign currency.
    The difference in the price the state-run Sugar and Alcohol
Institute (IAA) pays local industry and what it receives from
foreign buyers costs the government some 350 mln dlrs a year.
    Soaring domestic demand for both alcohol and sugar over the
past year, coupled with a drought-reduced cane crop, has meant
Brazil will have difficulties in meeting export commitments in
1987, trade sources said. Negotiations to delay shipments to
next year have been indecisive so far, the main sticking point
being how Brazil should compensate buyers for non-delivery of
sugar it had sold at around five cents per lb and which would
cost eight cents to replace.
    Brazilian sugar industry sources said new sugar export
sales were expected to be extremely low for the next year, with
the Institute wary of exposing itself to domestic shortages of
either alcohol or sugar and because of the need to rebuild
depleted reserve stockpiles.
    However, the situation could change dramatically if the
economy goes into recession and internal demand slumps.
    Sources within Latin America and the Caribbean hold little
hope for the region's sugar industry to return to profitability
unless the U.S. And EC change their policies.
    "The agricultural policies of the European Community and of
the United States have caused our economies incalculable harm
by closing their markets, by price deterioration in
international commerce and furthermore by the unfair
competition in third countries," Brazil's Trade and Industry
Minister Jose Hugo Castelo Branco told the October GEPLACEA
meeting.
    The EC has come under prolonged attack from GEPLACEA for
what the group charges is its continued dumping of excess
output on world markets. GEPLACEA officials say this is the
main cause of low prices.
    GEPLACEA sees a new International Sugar Agreement which
would regulate prices as one of the few chances of pulling the
region's industry out of steady decline. Such an agreement
would have to have both U.S. And EC backing and industrialised
countries would have to see it as a political rather than a
merely economic pact.
    "They have to realise that the more our economies suffer,
the less capcity we have to buy their goods and repay the
region's 360 billion dollar foreign debt," GEPLACEA's Latorre
said.
 
20: sugar: -- Document Separator -- reut2-006.sgm
European sugar output on the basis of
three year average yields will be over half a mln tonnes white
value down on last year although yields do vary widely from
year to year, broker C Czarnikow said in its market review.
    European Community sowings are likely to be down compared
with last year. There have been suggestions these sowings might
respond to the recent upsurge in world prices, but Czarnikow
said "it is not the sort of fact that easily becomes known."
    The broker bases its forecasts on Licht planting estimates
which put W Germany, the Netherlands and USSR lower but
Hungary, Romania, Poland, Turkey and Yugoslavia higher.
    Czarnikow's projections in mlns tonnes white value and
three differing yields include
      '87/88  max      aver      min    1986/87
 France       3.57     3.42     3.28       3.44
 W Germany    3.08     2.88     2.64       3.19
 EC          13.82    13.01    12.13      13.76
 W Europe    17.71    16.45    14.98      16.71
 Poland       2.02     1.80     1.13       1.74
 USSR         8.65     7.60     5.71       8.05
 E Europe    13.87    12.14     9.08      12.44
 All Europe  31.58    28.58    24.06      29.15
  
21: coffee: -- Document Separator -- reut2-010.sgm
Jorge Cardenas, manager of Colombia's
coffee growers' federation, said he did not believe any
important decisions would emerge from an upcoming meeting of
the International Coffee Organization (ICO).
    The ICO executive board is set to meet in London from March
31 and could decide to call a special council session by the
end of April to discuss export quotas.
    "It's going to be a routine meeting, an update of what has
been happening in the market, but it's unlikely any major
decisions are taken," Cardenas told journalists.
    Earlier this month, talks in London to re-introduce export
quotas, suspended in February 1986, ended in failure.
    Colombian finance minister Cesar Gaviria, also talking to
reporters at the end of the weekly National Coffee Committee
meeting, said the positions of Brazil and of the United States
were too far apart to allow a prompt agreement on quotas.
    Brazil's coffee chief Jorio Dauster said yesterday Brazil
would not change its coffee policies.
    Cardenas said the market situation was getting clearer
because the trade knew the projected output and stockpile
levels of producers.
    He said according to ICO statistics there was a shortfall
of nine mln (60-kg) bags on the world market between October,
the start of the coffee year, and February.
 
22: sugar: -- Document Separator -- reut2-010.sgm
Philippine sugar production in the
1987/88 crop year ending August has been set at 1.6 mln tonnes,
up from a provisional 1.3 mln tonnes this year, Sugar
Regulatory Administration (SRA) chairman Arsenio Yulo said.
    Yulo told Reuters a survey during the current milling
season, which ends next month, showed the 1986/87 estimate
would almost certainly be met.
    He said at least 1.2 mln tonnes of the 1987/88 crop would
be earmarked for domestic consumption.
    Yulo said about 130,000 tonnes would be set aside for the
U.S. Sugar quota, 150,000 tonnes for strategic reserves and
50,000 tonnes would be sold on the world market.
    He said if the government approved a long-standing SRA
recommendation to manufacture ethanol, the project would take
up another 150,000 tonnes, slightly raising the target.
    "The government, for its own reasons, has been delaying
approval of the project, but we expect it to come through by
July," Yulo said.
    Ethanol could make up five pct of gasoline, cutting the oil
import bill by about 300 mln pesos.
    Yulo said three major Philippine distilleries were ready to
start manufacturing ethanol if the project was approved.
    The ethanol project would result in employment for about
100,000 people, sharply reducing those thrown out of work by
depressed world sugar prices and a moribund domestic industry.
    Production quotas, set for the first time in 1987/88, had
been submitted to President Corazon Aquino.
    "I think the President would rather wait till the new
Congress convenes after the May elections," he said. "But there
is really no need for such quotas. We are right now producing
just slightly over our own consumption level."
    "The producers have never enjoyed such high prices," Yulo
said, adding sugar was currently selling locally for 320 pesos
per picul, up from 190 pesos last August.
    Yulo said prices were driven up because of speculation
following the SRA's bid to control production.
    "We are no longer concerned so much with the world market,"
he said, adding producers in the Negros region had learned from
their mistakes and diversified into corn and prawn farming and
cloth production.
    He said diversification into products other than ethanol
was also possible within the sugar industry.
    "The Brazilians long ago learnt their lessons," Yulo said.
"They have 300 sugar mills, compared with our 41, but they
relocated many of them and diversified production. We want to
call this a 'sugarcane industry' instead of the sugar industry."
    He said sugarcane could be fed to pigs and livestock, used
for thatching roofs, or used in room panelling.
    "When you cut sugarcane you don't even have to produce
sugar," he said.
    Yulo said the Philippines was lobbying for a renewal of the
International Sugar Agreement, which expired in 1984.
    "As a major sugar producer we are urging them to write a new
agreement which would revive world prices," Yulo said.
    "If there is no agreement world prices will always be
depressed, particularly because the European Community is
subsidising its producers and dumping sugar on the markets."
    He said current world prices, holding steady at about 7.60
cents per pound, were uneconomical for the Philippines, where
production costs ranged from 12 to 14 cents a pound.
    "If the price holds steady for a while at 7.60 cents I
expect the level to rise to about 11 cents a pound by the end
of this year," he said.
    Yulo said economists forecast a bullish sugar market by
1990, with world consumption outstripping production.
    He said sugar markets were holding up despite encroachments
from artificial sweeteners and high-fructose corn syrup.
    "But we are not happy with the Reagan Administration," he
said. "Since 1935 we have been regular suppliers of sugar to the
U.S. In 1982, when they restored the quota system, they cut
ours in half without any justification."
    Manila was keenly watching Washington's moves to cut
domestic support prices to 12 cents a pound from 18 cents.
    The U.S. Agriculture Department last December slashed its
12 month 1987 sugar import quota from the Philippines to
143,780 short tons from 231,660 short tons in 1986.
    Yulo said despite next year's increased production target,
some Philippine mills were expected to shut down.
    "At least four of the 41 mills were not working during the
1986/87 season," he said. "We expect two or three more to follow
suit during the next season."
 
23: sugar: -- Document Separator -- reut2-010.sgm
Reports the Soviet Union has lately
extended its recent buying programme by taking five to eight
raws cargoes from the free market at around 30/40 points under
New York May futures highlight recent worldwide demand for
sugar for a variety of destinations, traders said.
    The Soviet buying follows recent whites buying by India,
Turkey and Libya, as well as possible raws offtake by China.
    Some 300,000 to 400,000 tonnes could have changed hands in
current activity, which is encouraging for a sugar trade which
previously saw little worthwhile end-buyer enquiry, they added.
    Dealers said a large proportion of the sales to the Soviet
Union in the past few days involved Japanese operators selling
Thai origin sugar.
    Prices for nearby shipment Thai sugars have tightened
considerably recently due to good Far Eastern demand, possibly
for sales to the Soviet Union or to pre-empt any large block
enquiries by China, they said.
    Thai prices for March/May 15 shipments have hardened to
around 13/14 points under May New York from larger discounts
previously, they added.
    Traders said the Soviet Union might be looking to buy more
sugar in the near term, possibly towards an overall requirement
this year of around two mln tonnes. It is probable that some
1.8 mln tonnes have already been taken up, they said.
    Turkey was reported this week to have bought around 100,000
tonnes of whites while India had further whites purchases of
two to three cargoes for Mar/Apr at near 227 dlrs a tonne cost
and freight and could be seeking more. Libya was also a buyer
this week, taking two cargoes of whites which, for an
undisclosed shipment period, were reported priced around
229/230 dlrs a tonne cost and freight, they added.
    Futures prices reacted upwards to the news of end-buyer
physicals offtake, although much of the enquiry emerged
recently when prices took an interim technical dip, traders
said.
    Pakistan is lined up shortly to buy 100,000 tonnes of
whites although traders said the tender, originally scheduled
for tomorrow, might not take place until a week later.
    Egypt will be seeking 20,000 tonnes of May arrival white
sugar next week, while Greece has called an internal EC tender
for 40,000 tonnes of whites to be held in early April, for
arrival in four equal parts in May, June, July and August.
 
24: cocoa: -- Document Separator -- reut2-010.sgm
A final compromise proposal on cocoa
buffer stock rules presented by International Cocoa
Organization, ICCO, council chairman Denis Bra Kanon is swiftly
gaining acceptance by consumer and producer members, delegates
said.
    "We are close, nearer than ever to accepting it, but we
still have some work to do," producer spokesman Mama Mohammed of
Ghana told Reuters after a producers' meeting.
    European Community, EC, delegates said EC consumers
accepted the package in a morning meeting and predicted "no
problems" in getting full consumer acceptance.
    Delegates on both sides are keen to come to some agreement
today, the last day of the fortnight-long council meeting, they
said.
    The compromise requires that buffer stock purchases from
non-ICCO member countries cannot exceed 15 pct of total buffer
stock purchases, delegates said. The non-member cocoa issue has
been among the most contentious in the rules negotiations.
    The 15 pct figure, up five percentage points from earlier
proposals, represents a concession to consumers, delegates
said. They have demanded a larger allowance for non-member
cocoa in the buffer stock than producers have wanted.
    Another problem area, delegates said, was the question of
price differentials for different origins of cocoa bought into
the buffer stock, by which the buffer stock manager could
fairly compare relative prices of different cocoas offered to
him.
    The compromise narrowed the range of differentials between
the origins from what previous proposals had detailed -- a move
some delegates described as "just fiddling."
    But the adjustments may prove significant enough to appease
some countries that were not satisfied with the original
proposed differentials assigned to them, delegates said.
    The compromise also stated buffer stock purchases on any
day would be limited to 40 pct each in nearby, intermediate or
forward positions, delegates said.
    If the compromise is accepted by the council, most
consumers and producers want buffer stock rules to take effect
next week, or as soon as practically possible.
    The full council is scheduled to meet around 1500 GMT to
discuss the compromise, and could agree on it then if all
parties are satisfied, they said. Consumers are due to meet
before the council.
 
25: sugar: -- Document Separator -- reut2-010.sgm
Dry areas of the Australian sugar cane
belt along the Queensland coast have been receiving just enough
rain to sustain the 1987 crop, an Australian Sugar Producers
Association spokesman said.
    The industry is not as worried as it was two weeks ago, but
rainfall is still below normal and good soaking rains are
needed in some areas, notably in the Burdekin and Mackay
regions, he said from Brisbane.
    Elsewhere, in the far north and the far south of the state
and in northern New South Wales, the cane crop is looking very
good after heavy falls this month, he said.
    The spokesman said it is still too early to tell what
effect the dry weather will have on the size of the crop, which
is harvested from around June to December.
    He said frequent but light falls in the areas that are
short of moisture, such as Mackay, mean they really only need
about three days of the region's heavy tropical rains to
restore normal moisture to the cane.
    But rainfall in the next two or three weeks will be crucial
to the size of the crop in the dry areas, he said.
    "It's certainly not a disastrous crop at this stage but it
might be in a month without some good falls," he said.
 
26: coffee: -- Document Separator -- reut2-010.sgm
Chances that the International Coffee
Organization, ICO, executive board meeting this week will agree
to resume negotiations on export quotas soon look remote, ICO
delegates and trade sources said.
    ICO observers doubted Brazil or key consuming countries are
ready to give sufficient ground to convince the other side that
reopening negotiations again would be worthwhile, they said.
    ICO talks on quotas last month broke down after eight days
when producers and consumers failed to reach agreement.
     "Since we have not seen signs of change in other positions,
it's difficult to see a positive outcome at this stage,"
Brazilian delegate Lindenberg Sette said. But quotas must be
negotiated sometime, he said.
     The U.S. has indicated it is open to dialogue on quotas
but that Brazil must be flexible, rather than refuse to lower
its export share as it did in the last negotiations, delegates
said.
     At this week's March 31-April 2 meeting, the 16-member ICO
board is scheduled to discuss the current market situation, the
reintroduction of quotas, verification of stocks and some
administrative matters, according to a draft agenda.
    The fact that Brazilian Coffee Institute president Jorio
Dauster, Assistant U.S. Trade Representative Jon Rosenbaum and
chief Colombian delegate Jorge Cardenas are not attending the
meeting has signalled to most market watchers that it will be a
non-event as far as negotiating quotas is concerned.
    "I would imagine there will be a lot of politicking among
producers behind closed doors to work up some kind of proposal
by September (the next scheduled council meeting)," Bronwyn
Curtis of Landell Mills Commodities Studies said.
    Traders and delegates said they have seen no sign that a
date will be set for an earlier council meeting.
    If the stalemate continues much longer, analysts expect the
coffee agreement will end up operating without quotas for the
remainder of its life, to September 30, 1989.
    When talks broke down, the U.S. and Brazil, the largest
coffee consumer and producer respectively, blamed one another
for sabotaging negotiations by refusing to compromise.
    Brazil wanted to maintain the previous export quota shares,
under which it was allocated 30 pct of world coffee exports,
but consumers and a small group of producers pressed for shares
to be redistributed using "objective criteria," which would have
threatened Brazil's share.
    At a recent meeting in Managua of Latin American producers,
Costa Rica and Honduras said they were willing to put their
objections as members of the group of eight ICO "dissident"
producers aside, in order to stem the damaging decline in
prices, Nicaraguan External Trade Minister Alejandro Martinez
Cuenca told reporters Saturday. He was in London to brief
producers on the Managua meeting.
    However, other producers said they were not aware of this
move toward producer solidarity.
    London coffee prices closed at 1,276 stg a tonne today,
down from around 1,550 at the beginning of March.
 
27: coffee: -- Document Separator -- reut2-003.sgm
THE FOLLOWING RAINFALL WAS RECORDED IN
THE AREAS OVER PAST 72 HOURS
    PARANA STATE: UMUARAMA NIL, PARANAVAI 1.5 MILLIMETRES,
LONDRINA NIL, MARINGA NIL.
    SAO PAULO STATE: PRESIDENTE PRUDENTE O.6 MM, VOTUPORANGA
12.0 MM, FRANCA 28.0 MM, CATANDUVA 10.0 MM, SAO CARLOS NIL, SAO
SIMAO NIL. REUTER11:43/VB
&#3;</BODY></TEXT>
</REUTERS>
<REUTERS TOPICS="YES" LEWISSPLIT="TRAIN" CGISPLIT="TRAINING-SET" OLDID="19459" NEWID="3041">
<DATE> 9-MAR-1987 09:25:41.63</DATE>
<TOPICS><D>acq</D></TOPICS>
<PLACES></PLACES>
<PEOPLE></PEOPLE>
<ORGS></ORGS>
<EXCHANGES></EXCHANGES>
<COMPANIES></COMPANIES>
<UNKNOWN> 
&#5;&#5;&#5;F
&#22;&#22;&#1;f0033&#31;reute
f f BC-******GENCORP-TO-SELL   03-09 0011</UNKNOWN>
<TEXT TYPE="BRIEF">&#2;
******<TITLE>GENCORP TO SELL LOS ANGELES TELEVISION STATION TO WALT DISNEY CO
</TITLE>Blah blah blah.
&#3;

</TEXT>
</REUTERS>
<REUTERS TOPICS="YES" LEWISSPLIT="TRAIN" CGISPLIT="TRAINING-SET" OLDID="19460" NEWID="3042">
<DATE> 9-MAR-1987 09:26:28.51</DATE>
<TOPICS><D>acq</D></TOPICS>
<PLACES><D>usa</D></PLACES>
<PEOPLE></PEOPLE>
<ORGS></ORGS>
<EXCHANGES></EXCHANGES>
<COMPANIES></COMPANIES>
<UNKNOWN> 
&#5;&#5;&#5;F
&#22;&#22;&#1;f0035&#31;reute
d f BC-NATIONWIDE-CELLULAR-&lt;   03-09 0073</UNKNOWN>
<TEXT>&#2;
<TITLE>NATIONWIDE CELLULAR &lt;NCEL> COMPLETES PURCHASE</TITLE>
<DATELINE>    VALLEY STREAM, N.Y., March 9 - </DATELINE><BODY>Nationwide Cellular Service
Inc said it has completed the previously-announced acquisition
of privately-held Nova Cellular Co, a Chicago reseller of
mobile telephone service with 1,800 subscribers, for about
65,000 common shares.
    Nova Cellular has an accumulated deficit of about 650,000
dlrs and had revenues of about 2,600,000 dlrs for 1986, it
said.
 
28: coffee: -- Document Separator -- reut2-003.sgm
An 11-day-old strike by
Brazilian seamen is affecting coffee shipments and could lead
to a short term supply squeeze abroad, exporters said.
    They could not quantify how much coffee has been delayed
but said at least 40 pct of coffee exports are carried by
Brazilian ships and movement of foreign vessels has also been
disrupted by port congestion caused by the strike.
    A series of labor disputes and bad weather has meant
Brazil's coffee exports have been running at an average two
weeks behind schedule since the start of the year, one source
added.
    By the end of February shipments had fallen 800,000 bags
behind registrations, leaving around 2.4 mln bags to be shipped
during March. By March 10 only 230,000 bags had been shipped,
the sources said.
    Given Brazil's port loading capacity of around 100,000 bags
a day, even if normal operations were resumed immediately and
not interrupted by bad weather, some March registered coffee
will inevitably be shipped during April, they added.

 
29: cocoa: -- Document Separator -- reut2-000.sgm
Showers continued throughout the week in
the Bahia cocoa zone, alleviating the drought since early
January and improving prospects for the coming temporao,
although normal humidity levels have not been restored,
Comissaria Smith said in its weekly review.
    The dry period means the temporao will be late this year.
    Arrivals for the week ended February 22 were 155,221 bags
of 60 kilos making a cumulative total for the season of 5.93
mln against 5.81 at the same stage last year. Again it seems
that cocoa delivered earlier on consignment was included in the
arrivals figures.
    Comissaria Smith said there is still some doubt as to how
much old crop cocoa is still available as harvesting has
practically come to an end. With total Bahia crop estimates
around 6.4 mln bags and sales standing at almost 6.2 mln there
are a few hundred thousand bags still in the hands of farmers,
middlemen, exporters and processors.
    There are doubts as to how much of this cocoa would be fit
for export as shippers are now experiencing dificulties in
obtaining +Bahia superior+ certificates.
    In view of the lower quality over recent weeks farmers have
sold a good part of their cocoa held on consignment.
    Comissaria Smith said spot bean prices rose to 340 to 350
cruzados per arroba of 15 kilos.
    Bean shippers were reluctant to offer nearby shipment and
only limited sales were booked for March shipment at 1,750 to
1,780 dlrs per tonne to ports to be named.
    New crop sales were also light and all to open ports with
June/July going at 1,850 and 1,880 dlrs and at 35 and 45 dlrs
under New York july, Aug/Sept at 1,870, 1,875 and 1,880 dlrs
per tonne FOB.
    Routine sales of butter were made. March/April sold at
4,340, 4,345 and 4,350 dlrs.
    April/May butter went at 2.27 times New York May, June/July
at 4,400 and 4,415 dlrs, Aug/Sept at 4,351 to 4,450 dlrs and at
2.27 and 2.28 times New York Sept and Oct/Dec at 4,480 dlrs and
2.27 times New York Dec, Comissaria Smith said.
    Destinations were the U.S., Covertible currency areas,
Uruguay and open ports.
    Cake sales were registered at 785 to 995 dlrs for
March/April, 785 dlrs for May, 753 dlrs for Aug and 0.39 times
New York Dec for Oct/Dec.
    Buyers were the U.S., Argentina, Uruguay and convertible
currency areas.
    Liquor sales were limited with March/April selling at 2,325
and 2,380 dlrs, June/July at 2,375 dlrs and at 1.25 times New
York July, Aug/Sept at 2,400 dlrs and at 1.25 times New York
Sept and Oct/Dec at 1.25 times New York Dec, Comissaria Smith
said.
    Total Bahia sales are currently estimated at 6.13 mln bags
against the 1986/87 crop and 1.06 mln bags against the 1987/88
crop.
    Final figures for the period to February 28 are expected to
be published by the Brazilian Cocoa Trade Commission after
carnival which ends midday on February 27.
 
30: sugar: -- Document Separator -- reut2-000.sgm
The U.S. Agriculture Department said
cumulative sugar imports from individual countries during the
1987 quota year, which began January 1, 1987 and ends December
31, 1987 were as follows, with quota allocations for the quota
year in short tons, raw value --
            CUMULATIVE     QUOTA 1987
              IMPORTS     ALLOCATIONS
 ARGENTINA        nil          39,130
 AUSTRALIA        nil          75,530
 BARBADOS         nil           7,500
 BELIZE           nil          10,010
 BOLIVIA          nil           7,500
 BRAZIL           nil         131,950
 CANADA           nil          18,876
                           QUOTA 1987
              IMPORTS     ALLOCATIONS
 COLOMBIA         103          21,840
 CONGO            nil           7,599
 COSTA RICA       nil          17,583
 IVORY COAST      nil           7,500
 DOM REP        5,848         160,160
 ECUADOR          nil          10,010
 EL SALVADOR      nil          26,019.8
 FIJI             nil          25,190
 GABON            nil           7,500
                           QUOTA 1987
              IMPORTS     ALLOCATIONS
 GUATEMALA        nil          43,680
 GUYANA           nil          10,920
 HAITI            nil           7,500
 HONDURAS         nil          15,917.2
 INDIA            nil           7,500
 JAMAICA          nil          10,010
 MADAGASCAR       nil           7,500
 MALAWI           nil           9,,100
                           QUOTA 1987
               IMPORTS    ALLOCATIONS
 MAURITIUS         nil         10,920
 MEXICO             37          7,500
 MOZAMBIQUE        nil         11,830
 PANAMA            nil         26,390
 PAPUA NEW GUINEA  nil          7,500
 PARAGUAY          nil          7,500
 PERU              nil         37,310
 PHILIPPINES       nil        143,780
 ST.CHRISTOPHER-
 NEVIS             nil          7,500
                          QUOTA 1987
                IMPORTS  ALLOCATIONS
 SWAZILAND          nil         14,560
 TAIWAN             nil         10,920
 THAILAND           nil         12,740
 TRINIDAD-TOBAGO    nil          7,500
 URUGUAY            nil          7,500
 ZIMBABWE           nil         10,920

 
31: coffee: -- Document Separator -- reut2-000.sgm
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
 
32: coffee: -- Document Separator -- reut2-000.sgm
The failure of the International Coffee
Organization (ICO) to reach agreement on coffee export quotas
could trigger a massive selloff in London coffee futures of at
least 100 stg per tonne today, coffee trade sources said.
    Prices could easily drop to as low as 1.00 dlr or even 80
cents a lb this year from around 1.25 dlrs now, they said.
    A special meeting between importing and exporting countries
ended in a deadlock late yesterday after eight days of talks
over how to set the quotas. No further meeting to discuss
quotas was set, delegates said.
    Quotas, the major device used to stabilize prices under the
International Coffee Agreement, were suspended a year ago after
prices soared following a damaging drought in Brazil.
    With no propects for quotas in sight, heavy producer
selling initially and a price war among commercial coffee
roasting companies will ensue, the trade sources predicted.
    Lower prices are sure to trickle down to the supermarket
shelf this spring, coffee dealers said.
    The U.S. And Brazil, the largest coffee importer and
exporter respectively, each laid the blame on the other for the
breakdown of the talks.
    Jon Rosenbaum, U.S. Assistant trade representative and
delegate to the talks, said in a statement after the council
adjourned, "A majority of producers, led by Brazil, were not
prepared to negotiate a new distribution based on objective
criteria.
    "We want to insure that countries receive export quotas
based on their ability to supply the market, instead of their
political influence in the ICO."
    Brazilian Coffee Institute (IBC) President Jorio Dauster
countered, "Negotiations failed because consumers tried to
dictate quotas, not negotiate them."
    Previously, quotas were determined by historical amounts
exported, which gave Brazil a 30 pct share of a global market
of about 58 mln 60-kilo bags. A majority of producers wanted
quotas to continue under this basic scheme.
    But most consumers and a maverick group of eight producers
proposed carving up the export market on the basis of
exportable production and stocks, which would reduce Brazil's
share to 28.8 pct.
    Consumer delegates said this method would reflect changes
in many countries' export capabilities and make coffee more
readily available to consumers when they need it.
    A last-minute attempt by Colombia, the second largest
exporter, to rescue the talks with a compromise interim
proposal could not bring the two sides together.
    Delegates speculated Brazil's financial problems,
illustrated by its recent suspension of interest payments on
bank debt, have increased political pressure on the country to
protect its coffee export earnings.
    Developing coffee-producing countries that depend heavily
on coffee earnings, particularly some African nations and
Colombia, are likely to be hurt the most by the ICO's failure
to agree quotas, analysts said.
    The expected drop in prices could result in losses of as
much as three billion dlrs in a year, producer delegates
forecast.
    The ICO executive board will meet March 31, but the full
council is not due to meet again until September, delegates
said.
 
33: coffee: -- Document Separator -- reut2-000.sgm
This morning's sharp decline in coffee
prices, following the breakdown late last night of negotiations
in London to reintroduce International Coffee Organization,
ICO, quotas, will be short-lived, Dutch roasters said.
    "The fall is a technical and emotional reaction to the
failure to agree on reintroduction of ICO export quotas, but it
will not be long before reality reasserts itself and prices
rise again," a spokesman for one of the major Dutch roasters
said.
    "The fact is that while there are ample supplies of coffee
available at present, there is a shortage of quality," he said.
    "Average prices fell to around 110 cents a lb following the
news of the breakdown but we expect them to move back again to
around 120 cents within a few weeks," the roaster added.
    Dutch Coffee Roasters' Association secretary Jan de Vries
said although the roasters were disappointed at the failure of
consumer and producer ICO representatives to agree on quota
reintroduction, it was equally important that quotas be
reallocated on a more equitable basis.
    "There is no absolute need for quotas at this moment because
the market is well balanced and we must not lose this
opportunity to renegotiate the coffee agreement," he said.
    "There is still a lot of work to be done on a number of
clauses of the International Coffee Agreement and we would not
welcome quota reintroduction until we have a complete
renegotiation," de Vries added.
    With this in mind, and with Dutch roasters claiming to have
fairly good forward cover, the buying strategy for the
foreseeable future would probably be to buy coffee on a
hand-to-mouth basis and on a sliding scale when market prices
were below 120 cents a lb, roasters said.
 
34: cocoa: -- Document Separator -- reut2-007.sgm
Hopes mounted for an agreement on cocoa
buffer stock rules at an International Cocoa Organization,
ICCO, council meeting which opened here today, delegates said.
    Both producer and consumer ICCO members said after the
opening session that prospects for an agreement on the cocoa
market support mechanism were improving.
    "The chances are very good as of now of getting buffer stock
rules by the end of next week," Ghanaian delegate and producer
spokesman Mama Mohammed told journalists.
    Consumer spokesman Peter Baron called the tone of the
negotiations "optimistic and realistic."
    The ICCO council failed to agree on buffer stock rules when
a new International Cocoa Agreement came into force in January,
with deep differences of opinion precluding serious discussions
on the matter at that time. The existing buffer stock of about
100,000 tonnes of cocoa was frozen, with a funds balance of 250
mln dlrs.
    The ICCO made buffer stock rules negotiations a priority at
this semi-annual council meeting in order to stop the slide in
world cocoa prices.
    Consumers and producers agreed yesterday on the principles
as a basis for negotiations.
    The council broke for lunch, and reconvenes at 1500 hrs. A
working group which has been meeting since Monday will tackle
the buffer stock rules issue again at 1600 hrs, when ICCO
executive director Kobena Erbynn presents a fleshed-out version
of a draft proposal he prepared earlier this week, delegates
said.
    Mohammed said delegates will have a much clearer indication
of prospects for an accord after details of the rules are
elaborated by Erbynn, and after producers and consumers meet
separately later today to examine the scheme.
    The draft proposal included three principles: a limit to
non- member cocoa comprising the buffer stock, an offer system
for buying buffer stock cocoa, and price differentials to be
paid for various cocoas making up the buffer stock, delegates
said.
    During the morning council session, the Ivory Coast
delegation gave "an open minded statement" that it is willing to
work out a buffer stock rules solution which could come into
effect as soon as possible, Baron said.
    Ivorian Agriculture Minister Denis Bra Kanon, chairman of
the ICCO council, was now expected to arrive in London Monday
to attend the talks, Baron said. Vice chairman Sir Denis Henry
of Grenada chaired the meeting in his place.
    Soviet and East German delegates did not attend the council
session because of a conflicting International Sugar
Organization meeting today, but could arrive this afternoon,
delegates said.
 
35: sugar: -- Document Separator -- reut2-007.sgm
Sugar which EC producers plan to sell
into intervention may be offered by the European Commission for
sale within the Community, broker C. Czarnikow says in its
latest sugar review.
    The Commission will propose to offer the sugar at a very
nominal premium of 0.01 European Currency Unit (Ecu) to the
intervention price, with detrimental consequences for
producers' returns, Czarnikow says. The move is seen as an
attempt to persuade the producers to take back the surrendered
sugar.
    The Commission may also take other steps to dissuade
producers from their chosen course, such as removing the time
limit on storage contracts, which presently means that
intervention stocks have to be removed by the end of September,
Czarnikow says. There is also the possibility of production
quotas being reduced.
    If the Commission decided to offer the sugar to traders for
export, the restitutions would have to be higher than those at
recent export tenders, Czarnikow notes. To match the difference
between the EC price and the world market price, the extra
costs might be as much as 20 Ecus per tonne, it says.
    The producers might have to repay these costs through
production levies and the proposed special elimination levy,
Czarnikow says, but it would be several months before any costs
could be recovered under EC rules.
    The primary cause of the plan to sell 775,000 tonnes of
sugar into intervention in France is dissatisfaction with the
EC export program as the restitution has increasingly failed to
bridge the gap between the EC price and the world market price,
Czarnikow notes. The French move is thus seen as a form of
protest designed to force the Commission's hand.
    In West Germany, 79,250 tonnes have been tendered for
intervention, but Czarnikow says the motive here is to ensure
that the 1986/87 price is paid for sugar that was produced in
1986. In addition to a two pct cut in the intervention price,
West German producers face a further price reduction in July
with a probable revaluation of the "green" mark.
    Even if the immediate crisis is resolved, the problem is
not expected to disappear permanently. It has appeared to
traders for some years that the EC's export policy is
insufficiently responsive to changing patterns of demand, it
says.
    The weekly tenders should respond to fluctuating demand by
increasing or reducing the tonnage awarded, Czarnikow says,
suggesting that the Commission might also take steps to cut
down the amount of "unnecessary bureaucracy" surrounding the
export tender system.
 
36: sugar: -- Document Separator -- reut2-017.sgm
Several Japanese buyers have accepted
postponement of between 150,000 and 200,000 tonnes of Cuban raw
sugar scheduled for delivery in calendar 1987 until next year
following a request from Cuba, trade sources said.
    Cuba had sought delays for some 300,000 tonnes of
deliveries, they said. It made a similar request in January
when Japanese buyers agreed to postpone some 200,000 tonnes of
sugar deliveries for 1987 until 1988.
    Some buyers rejected the Cuban request because they have
already sold the sugar on to refiners, they added.
    Japanese buyers are believed to have contracts to buy some
950,000 tonnes of raw sugar from Cuba for 1987 shipment.
    But Japan's actual raw sugar imports from Cuba are likely
to total only some 400,000 to 450,000 tonnes this year, against
576,990 in 1986, reflecting both the postponements and sales
earlier this year by Japanese traders of an estimated 150,000
tonnes of Cuban sugar to the USSR for 1987 shipment, they said.
    They estimated Japan's total sugar imports this year at 1.8
mln tonnes, against 1.81 mln in 1986, of which Australia is
expected to supply 550,000, against 470,000, South Africa
350,000, against 331,866, and Thailand 400,000, after 390,776.
 
37: sugar: -- Document Separator -- reut2-017.sgm
Good soaking rain is boosting the sugar
cane crop in the key Mackay region of Queensland following a
prolonged dry spell relieved only by intermittent falls, an
Australian Sugar Producers Association spokesman told Reuters.
    The rains began late last week, developed into heavy
downpours over the weekend and are continuing today, he said
from Brisbane.
    The Mackay and Burdekin regions, which together grow about
half the Australian cane crop, have been the Queensland cane
areas hardest hit by unseasonal dry weather since December.
    The spokesman said the rain missed the Burdekin area, just
to the north of the Mackay region on the central Queensland
coastal fringe, although recent light showers have freshened
the crop there.
    Owing to the dry spell in the Mackay and Burdekin areas,
the overall 1987 Australian cane crop is likely to be below the
25.4 mln tonnes crushed in 1986 for a 94 net titre raws outturn
of 3.37 mln tonnes, he said.
    But any decline will not be as great as seemed likely a
couple of months ago when it appeared the Mackay-Burdekin crops
were going to suffer badly, he said.
    Preliminary crop estimates are expected to be available
early next month, the spokesman said.
    The crush in the Mackay-Burdekin is likely to start later
this year, in late June or early July against mid-June last
year, to allow the cane to grow and sweeten further, he said.
    The crush normally runs to around the end of December.
    Elsewhere in the sugar belt, the cane is doing well, with
some mill areas expecting record crops, he said.
    Industry records show variations in the crop are not always
mirrored in raws output. In 1985, 24.4 mln tonnes of sweeter
cane than in 1986 produced 3.38 mln tonnes of raws.
 
38: sugar: -- Document Separator -- reut2-017.sgm
French producers have withdrawn all
offers to sell more than 700,000 tonnes of sugar into European
Community intervention stocks, EC Commission sources said.
    They also said West German producers had now withdrawn the
last 3,000 of the 79,250 tonnes they sold into EC stores on
April 1.
    The sales were made to protest against the level of export
restitutions being granted for sugar at weekly EC tenders.
    Last Friday, commission sources said the West German
producers had withdrawn all but 3,000 tonnes of their sales.
    The protest by European producers involved sales of 854,000
tonnes of sugar into intervention, of which 785,000 tonnes were
accepted by the commission.
    Under EC regulations, operators had five weeks before
receiving payment to withdraw the sugar.
    Their decision to withdraw the sugar follows what
commission sources have said is a slight shift in the
authority's stance in recent weeks. The commission last week
increased the maximum restitutions to within about 0.5 Ecus per
kilo of the prices which traders claim are needed to match
intervention prices.
 
39: cocoa: -- Document Separator -- reut2-017.sgm
Dutch cocoa processors are unhappy with
the intermittent buying activities of the International Cocoa
Organization's buffer stock manager, industry sources told
Reuters.
    "The way he is operating at the moment is doing almost
nothing to support the market. In fact he could be said to be
actively depressing it," one company spokesman said.
    Including the 3,000 tonnes he acquired on Friday, the total
amount of cocoa bought by the buffer stock manager since he
recently began support operations totals 21,000 tonnes.
    Despite this buying, the price of cocoa is well under the
1,600 Special Drawing Rights, SDRs, a tonne level below which
the bsm is obliged to buy cocoa off the market.
    "Even before he started operations, traders estimated the
manager would need to buy at least up to his 75,000 tonnes
maximum before prices moved up to or above the 1,600 SDR level,
and yet he appears reluctant to do so," one manufacturer said.
    "We all hoped the manager would move into the market to buy
up to 75,000 tonnes in a fairly short period, and then simply
step back," he added.
    "The way the manager is only nibbling at the edge of the
market at the moment is actually depressing sentiment and the
market because everyone is holding back from both buying and
selling waiting to see what the manager will do next," one
processor said.
    "As long as his buying tactics remain the same the market is
likely to stay in the doldrums, and I see no indication he is
about to alter his methods," he added.
    Processors and chocolate manufacturers said consumer prices
for cocoa products were unlikely to be affected by buffer stock
buying for some time to come.
 
40: cocoa: -- Document Separator -- reut2-017.sgm
Traders recently returned from West Africa
say some producers there are dismayed by the ineffective action
so far by the International Cocoa Organization (ICCO) buffer
stock manager on buffer stock purchases.
    One trader said some West African producers are annoyed the
Buffer Stock manager is not playing his part as required by the
International Cocoa Pact to stabilise prices from current lows.
    So far, only 21,000 tonnes of second hand cocoa have been
taken up for buffer stock purposes and this, traders noted,
only on an intermittent basis.
    They noted the purchases, of 8,000 tonnes in the first week
he bought and 13,000 in the second, are well short of the
limitations of no more than 5,000 tonnes in one day and 20,000
in one week which the cocoa agreement places on him.
    The traders recently returned from West Africa say
producers there are unhappy about the impact on cocoa prices so
far, noting producing countries are part of the international
cocoa pact and deserve the same treatment as consumers.
    London traders say terminal market prices would have to
gain around 300 stg a tonne to take the ICCO 10-day average
indicator to its 1,935 sdr per tonne midway point (or reference
price).
    However, little progress has been made in that direction,
and the 10-day average is still well below the 1,600 sdr lower
intervention level at 1,562.87 from 1,569.46 previously.
    The buffer stock manager may announce today he will be
making purchases tomorrow, although under the rules of the
agreement such action is not automatic, traders said.
    Complaints about the inaction of the buffer stock manager
are not confined to West African producers, they observed.
    A Reuter report from Rotterdam quoted industry sources
there saying Dutch cocoa processors also are unhappy with the
intermittent buffer stock buying activities.
    In London, traders expressed surprise that no more than
21,000 tonnes cocoa has been bought so far against total
potential purchases under the new agreement of 150,000 tonnes.
Carryover holdings from the previous International Cocoa
Agreement in the stock total 100,000 tonnes.
    Terminal prices today rose by up to 10 stg a tonne from
Friday's close, basis July at its high of 1,271.
    It seems that when the buffer stock manager is absent from
the market, prices go up, while when he declares his intention
to buy, quite often the reverse applies, traders said.
 
41: sugar: -- Document Separator -- reut2-017.sgm
China will not increase sugar imports
substantially this year because of foreign exchange constraints
and large stocks, despite falling production and rising
domestic demand, traders and the official press said.
    "Despite rapid increases in domestic production over the
last 30 years, imbalances between supply and demand continue to
be extremely serious," the Farmers Daily said. It said 1986
plantings fell due to removal of crop incentives, because
farmers could earn more from other crops and because technical
and seed improvements had not been widely disseminated.
    The official press had estimated the 1986/87 sugar crop
(November/March) at 4.82 mln tonnes, down from 5.2 mln a year
earlier, and domestic consumption at six mln tonnes a year.
    The Yunnan 1986/87 sugar harvest was a record 521,500
tonnes, the provincial daily said. It gave no year-earlier
figure. Output in Guangxi was 1.04 mln tonnes, the New China
News Agency said without giving a year-earlier figure.
    The Nanfang Daily said production in Guangdong province
fell to estimated 1.92 mln tonnes from 1.96 mln and that the
area under sugar was dropping.
    "Supply of cane (in Guangdong) is inadequate," the newspaper
said. Processing costs are rising and the economic situation of
nearly all the mills is not good. To guarantee supply of cane
is a major problem."
    A Western diplomat said sugar output also fell n Fujian,
south China's fourth major producer, where there was a drop in
area planted.
    He said the rural sectors in Guangdong and Fujian were wel
developed, enabling farmers to choose crops according to the
maximum return, meaning that many had avoided sugar.
    The Farmers Daily said a peasant in the ortheast province
of Heilongjiang could gross 108 yuan from one mu (0.0667
hectares) of soybeans and 112 yuan from one mu of corn but only
70 from one mu of sugarbeet.
    The paper said the profit margin of mills in China fell to
4.7 pct last year from 11.87 pct in 1980.
    Mills lacked the capital to modernise and they competed
with each other for raw materialsX, it added. This resulted in
falling utilisation rates at big, mode{nised mills.
    The price of sugar had not changed in 20 years, the
official press has said.
    Customs figures showed China imported 1.18 mln tonnes of
sugar in calendar 1986, down from 1.9 mln in 1985.
    The diplomat said stocks at end-August 1986 were 2.37 mln
tonnes, up from 1.92 a year earlier.
    A foreign trader here said China accumulated large stocks
in 1982-85 when provincial authorities were allowed to import
sugar on their own authority. This practice was stopped in 1986
when the central government resumed control of imports.
    "As China lacked storage, much of these imports was stored
in Qinghai, Inner Mongolia and other inland areas," the diplomat
said.
    The trader said transporting stocks from these areas to
consumers in east and south China was a problem, particularly
as coal had priority. "How quickly they can move the sugar is
one factor determining import levels," he said.
    Another factor was the quality of the harvest in Cuba,
China's major supplier through barter trade, he said.
    "China bought two distress cargoes last week, for about
152/153 dlrs a tonne," he added. "China is not a desperate buyer
now. But if the Cuban harvest is bad, it will have to go into
the open market."
    A Japanese trader said Peking's major concern regarding
imports was price.
    "While the foreign trade situation has improved this year,
foreign exchange restraints persist," he said.
    The diplomat said domestic demand was rising by about five
pct a year but "a communist government is in a much better
position to regulate demand than a capitalist one, if the
foreign exchange situation demands it."
 
42: cocoa: -- Document Separator -- reut2-005.sgm
A senior Ivory Coast Agriculture
Ministry official confirmed his country's backing for a new
international cocoa pact and said Ivorian delegates would be
present at talks on its buffer stock starting this week.
    The official told Reuters that Ivorian Agriculture Minister
Denis Bra Kanon would attend the opening of the talks, convened
by the International Cocoa Organization (ICCO), in London on
Monday.
    While Bra Kanon is due to return home this week for funeral
ceremonies for a sister of Ivorian President Felix
Houphouet-Boigny, scheduled to be held in the country's capital
Yamoussoukro between March 19-22, senior Ivorian delegates will
be present throughout the London talks, the official said.
    Bra Kanon is chairman of the ICCO Council and rumours that
he or Ivorian delegates might be delayed because of public
mourning in the West African nation helped depress already low
world cocoa prices Friday.
    The official said Ivory Coast continued to support the new
pact, which was agreed in principle last year by most of the
world's cocoa exporters and consumers.
    He also said Bra Kanon would fulfil his duties as ICCO
Council chairman during the talks, scheduled to end on March
27.
    The meeting aims to set rules for the operation of the
pact's buffer stock which producers hope will boost a market
hit by successive world cocoa surpluses.
    Ivory Coast did not participate in the last international
cocoa pact and its decision to join the new accord has sparked
hopes that it will be more successful in supporting prices.
 
43: cocoa: -- Document Separator -- reut2-005.sgm
A senior Ivory Coast Agriculture
Ministry official confirmed his country's backing for a new
international cocoa pact and said Ivorian delegates would be
present at talks on its buffer stock starting this week.
    The official told Reuters that Ivorian Agriculture Minister
Denis Bra Kanon would attend the opening of the talks, convened
by the International Cocoa Organization (ICCO), in London on
Monday.
    While Bra Kanon is due to return home this week for funeral
ceremonies for a sister of Ivorian President Felix
Houphouet-Boigny, scheduled to be held in the country's capital
Yamoussoukro between March 19-22, senior Ivorian delegates will
be present throughout the London talks, the official said.
    Bra Kanon is chairman of the ICCO Council and rumours that
he or Ivorian delegates might be delayed because of public
mourning in the West African nation helped depress already low
world cocoa prices Friday.
    The official said Ivory Coast continued to support the new
pact, which was agreed in principle last year by most of the
world's cocoa exporters and consumers.
    He also said Bra Kanon would fulfil his duties as ICCO
Council chairman during the talks, scheduled to end on March
27.
    The meeting aims to set rules for the operation of the
pact's buffer stock which producers hope will boost a market
hit by successive world cocoa surpluses.
    Ivory Coast did not participate in the last international
cocoa pact and its decision to join the new accord has sparked
hopes that it will be more successful in supporting prices.
 
44: cocoa: -- Document Separator -- reut2-005.sgm
The credibility of government efforts to
stabilise fluctuating commodity prices will again be put to the
test over the next two weeks as countries try to agree on how a
buffer stock should operate in the cocoa market, government
delegates and trade experts said.
    Only two weeks ago, world coffee prices slumped when
International Coffee Organization members failed to agree on
how coffee export quotas should be calculated. This week, many
of the same experts gather in the same building here to try to
agree on how the cocoa pact reached last summer should work.
    The still unresolved legal wrangle surrounding the
International Tin Council (ITC), which had buffer stock losses
running into hundreds of millions of sterling, is also casting
a shadow over commodity negotiations.
    The ITC's failure has restricted negotiators' ability to
compromise as governments do not want to be involved in pacts
with built-in flaws or unlimited liability, but want clear
lines drawn between aid and trade.
    A more hopeful sign of cooperation was agreement on basic
elements of a new International Natural Rubber Agreement in
Geneva at the weekend.
    Some importing countries insist the International Cocoa
Organization (ICCO) buffer stock rules must not be muddied with
quota type subclauses which might dictate the type of cocoa to
be bought. One consumer country delegate said this would
"distort, not support" the market.
    Trade and industry sources blame uncertainty about the ICCO
for destabilising the market as the recent collapse in coffee
prices has made traders acutely aware that commodity pacts can
founder. On Friday this uncertainty helped push London cocoa
futures down to eight month lows. The strength of sterling has
also contributed to the recent slip in prices.
    The ICCO daily and average prices on Friday fell below the
"must buy" level of 1,600 SDRs a tonne designated in the pact,
which came into force at the last ICCO session in January but
without rules for the operation of the buffer stock.
    Consumers and producers could not agree on how it should
operate and what discretion it should be given. The agreement
limits it to trading physical cocoa and expressly says it
cannot operate on futures markets.
    A cash balance of some 250 mln dlrs and a stock of almost
100,000 tonnes of cocoa, enough to mount large buying or
selling operations, were carried forward from the previous
agreement.
    Members finance the stock through a 45 dlrs a tonne levy on
all cocoa they trade. It has an upper limit of 250,000 tonnes.
    The key arguments being faced by the ICCO working group on
buffer stock rules which is meeting today and tomorrow will be
over non-member cocoa and differentials the buffer stock should
pay when trading different types of cocoa. Another working
group is scheduled to meet Wednesday to discuss administrative
matters, and the full council meets on Thursday.
    Producers have so far maintained that buffer stock funds
should not help mop up surplus cocoa produced in non-member
countries such as Malaysia.
    Consumers say when this cocoa is the cheapest the buffer
stock should buy it rather than compete with chocolate
manufacturers for premium-priced high quality cocoas.
    The argument over buying non-member cocoa is closely linked
to the one over differentials for different qualities.
    European industry and trade advisers have suggested as a
compromise that the buffer stock have a maximum share that can
represent non-member cocoa and that it use the London futures
market's existing differentials for different qualities.
    Currently, good West African cocoa is tendered at par onto
the London market.
    Discounts, which are currently under review, range up to 50
stg a tonne for Brazilian and Malaysian cocoa.
    Consumer delegates said the same arguments in reverse would
operate when prices are high - the buffer stock should sell the
highest priced cocoa in most demand, forcing all prices lower.
    The January talks were slowed by a split inside the
European Community, a key ICCO consumer group, with France
siding with producers. EC representatives met in closed session
in Brussels on Friday in an attempt to reach a common ground
and, a diplomatic source said, narrowed the range of positions
among the 12 nations.
    The source said the EC will be looking for signs of
flexibility on the part of producers in the next few days and
will be able to respond if they are there.
    One ICCO delegate describing the producer/consumer split
said consumer proposals mean buying more cocoa for less and
backs the concept of the pact which is "meant to support the
market where trade buying is not."
    In contrast, he said, producers seem to want to sell their
cocoa to the buffer stock rather than consumers.
    Other, more technical, issues still outstanding include
whether the buffer stock should buy at a single announced
"posted price" as in the previous pact or by announcing it is
buying then accepting offers.
    In either case, delegates said, it is accepted that
producers must be given a clear opportunity to make offers of
cocoa for forward shipment directly to the buffer stock in a
way that is competitive with spot offers made by dealers.
 
45: cocoa: -- Document Separator -- reut2-005.sgm
Representatives of cocoa consuming
countries at an International Cocoa Organization, ICCO, council
meeting here have edged closer to a unified stance on buffer
stock rules, delegates said.
    While consumers do not yet have a common position, an
observer said after a consumer meeting, "They are much more
fluid ... and the tone is positive."
    European Community consumers were split on the question of
how the cocoa buffer stock should be operated when the ICCO met
in January to put the new International Cocoa Agreement into
effect, delegates said.
    At the January meeting, France sided with producers on how
the buffer stock should operate, delegates said. That meeting
ended without agreement on new buffer stock rules.
    The EC Commission met in Brussels on Friday to see whether
the 12 EC cocoa consuming nations could narrow their
differences at this month's meeting.
    The Commissioners came away from the Friday meeting with an
informal agreement to respond to signs of flexibility among
producers on the key buffer stock issues, delegates said.
    The key issues to be addressed at this council session
which divide ICCO members are whether non-member cocoa should
be eligible for buffer stock purchases and what price
differentials the buffer stock should pay for different types
of cocoa, delegates said.
    A consumer delegate said producers and consumers should be
able to compromise on the non-member cocoa question.
    A working group comprising delegates from all producing and
consuming member countries met briefly this morning, then broke
up into a producer meeting and an EC meeting, followed by a
consumer meeting.
    Producers, who are in favour of the buffer stock buying a
variety of grades of cocoa and oppose non-member cocoa being
accepted, reviewed their position ahead of the working group
meeting this afternoon.
    "We are waiting to see what consumers say," a producer
delegate said. "We hope they will be flexible or it will be
difficult to negotiate."
    The ICCO comprises 33 member countries. Non-
members include the U.S., a consumer, and Malaysia, an
increasingly important producer.
 
46: coffee: -- Document Separator -- reut2-005.sgm
Private coffee exporters say Colombia's
more pragmatic coffee marketing policy will ensure that the
country does not suffer excessively from current depressed
prices and erratic market conditions.
    Gilberto Arango, president of the exporters' association,
said in an interview that Colombia, the world's second largest
producer, was in a position to withstand a prolonged absence of
International Coffee Organization (ICO) export quotas.
    "Colombia is one of the countries that will benefit most
from this situation," he said.
    Recent ICO talks in London failed to break a deadlock over
re-introduction of export quotas, suspended in February 1986,
and no date has been set for a new meeting on the issue.
    Arango said that government measures adopted here last
week, including a lower export registration price, indicated a
major change but also disclosed a welcome pragmatism.
    "This is the start of a new era in Colombia because world
market conditions are also new," he said.
    The government lowered local taxes for exporters and said
the export registration price, or reintegro, will be changed
more often in order to closely reflect market trends.
    Arango said an illustration of Colombia's new attitude was
the decision on Friday to open export registrations for an
unlimited amount.
    But he added it did not imply the country would begin heavy
selling of coffee.
    "Our marketing policy is to sell without haste but
consistently. No targets for volume will be set. We will react
to market factors adequately and Colombia has no intention of
giving its coffee away."
    Colombia's past records should be the basis for upcoming
exports, he said.
    "We will certainly not export seven mln (60-kilo) bags but
neither are we going to sell like mad. The trade knows full
well what Colombia's export potential is," he said.
    Colombia, with stockpiles standing at about 10 mln bags,
exported a record 11.5 mln bags in the 1985/86 coffee year
which ended last September, and 11.3 mln in calendar 1986.
    Arango did not want to commit himself on export predictions
but said that output for the 1986/87 coffee year would not
exceed 10.5 mln bags, compared with 12 mln forecast by the
National Coffee Growers' Federation and 12.5 mln by the U.S.
Department of Agriculture, a figure he said was "ridiculous."
    He said ageing plantations and rust, in particular in the
number one producing province of Antioquia, meant output was
likely to fall but that nationwide estimates were rare and
oscillated between 9.5 mln and 11.5 mln bags.
    On the failure of the recent ICO talks, Arango said
Colombia understandably felt frustrated at not having managed
to force a compromise.
    Jorge Cardenas, manager of the national federation and head
of his nation's delegation in London, has blamed the
intransigence of some big countries, without naming them.
    However, Arango, like Colombian Finance Minister Cesar
Gaviria last week, was more explicit and said the United States
would undoubtedly be under great political pressure in coming
weeks to revise its policy.
    "Washington will have to take into account that for many
countries, and some of its allies for instance in Central
America, a sharp fall in coffee export revenue would have
far-reaching political and economic consequences."
    Arango ruled out a fresh Colombian initiative on export
quotas saying producers had now to show a common resolve which
could emerge from continuous contacts.
 
47: cocoa: -- Document Separator -- reut2-005.sgm
The International Cocoa Organization,
ICCO, council adjourned after presenting divergent producer and
consumer views on buffer stock rules and agreeing to examine a
draft compromise proposal on the buffer stock issue tomorrow,
delegates said.
    ICCO Executive Director Kobena Erbynn will draw up what
some delegates called a "pre-compromise" and present it to the
buffer stock working group at 1130 hrs GMT Tuesday, they said.
    While consumer and producer member nations disagree how a
buffer stock should be implemented, both sides reiterated they
were willing to compromise to come to agreement, they said.
    "I am optimistic we will be able to come to an agreement --
maybe not tomorrow or the next day, but some time later in the
session," a consumer delegate said.
    Producers say they want the buffer stock to consist only of
ICCO member cocoa, comprise a representative basket of various
grade cocoas and pay different prices for different grades,
delegates said.
    Some consumers would rather the buffer stock manager be
able to buy non-member cocoa also, and pay a single price for
the buffer stock cocoa without respect to origin.
    Consumer members were not unified in their views on how the
buffer stock should operate, with several countries backing
different aspects of the producer stance, delegates said.
    The semi-annual council meeting is scheduled to run until
March 27. Consideration of the buffer stock rules is the most
controversial topic on the agenda, delegates said.
 
48: coffee: -- Document Separator -- reut2-001.sgm
Coffee producing countries must quickly
map out a fresh common strategy following the failure of the
International Coffee Organization, ICO, to reach agreement on
export quotas, Gilberto Arango, president of Colombia's private
coffee exporters' association, said.
    Arango told Reuters that the most intelligent thing now
would be to seek a unifying stand from producers, including
Brazil, in order to map out a strategy to defend prices.
    An ICO special meeting ended last night in London with
exporting and consuming nations failing to agree on a
resumption of export quotas, suspended one year ago after
prices soared following a prolonged drought in Brazil.
    Arango said there would be no imminent catastrophe but
predicted that over the short term prices would undoubtedly
plummet.
    However, he said the market should also take into account
evident factors such as Brazil's low stocks and the sale of the
near totality of the Central American crop.
    Trade sources said Colombia's coffee was today quoted at
1.14 dlrs a lb in New York, its second lowest price in the past
10 years.
    Cardenas said these countries apparently fail to understand
the true impact of such a failure for coffee producing nations
as well as for industrialized countries.
    It is difficult to believe that while efforts are made to
solve the problem of the developing world's external debt,
decisions are being taken which cut earnings used for repaying
those debts, he said.
    "In Colombia's case, we watch with consternation that,
while we try to effectively combat drug trafficking, countries
which support us in this fight seek to cut our jugular vein,"
Cardenas said.
 
49: coffee: -- Document Separator -- reut2-001.sgm
Recent heavy rains have not affected the
Peru coffee crop and producers are looking forward to a record
harvest, the president of one of Peru's four coffee cooperative
groups said.
    Justo Marin Ludena, president of the Cafe Peru group of
cooperatives which accounts for about 20 pct of Peru's exports,
told Reuters a harvest of up to 1,800,000 quintales (46 kilos)
was expected this year. He said Peru exported 1,616,101
quintales in the year to September 1986.
    A spokesman for the Villa Rica cooperative said flood
waters last month had not reached coffee plantations, and the
crop was unaffected.
    Floods in early February caused extensive damage in Villa
Rica, whose coffee cooperative exported 59,960 quintales last
year, according to the state-controlled coffee organisation.
    Marin said the rains would only affect the coffee crop if
they continued through to next month, when harvesting starts.
    He said Peruvian producers were hoping for an increase this
year in the 1.3 pct export quota, about 913,000 quintales,
assigned to them by the International Coffee Organisation, ICO.
    He said Peru exported 1,381,009 quintales to ICO members
last year with a value of around 230 mln dlrs, and another
235,092 quintales, valued at around 35 mln dlrs, to non-ICO
members.
 
50: coffee: -- Document Separator -- reut2-001.sgm
Coffee prices may have to fall even lower
to bring exporting and importing countries once more round the
negotiating table to discuss export quotas, ICO delegates and
traders said.
    The failure last night of International Coffee
Organization, ICO, producing and consuming countries to agree
export quotas brought a sharp fall on international coffee
futures markets today with the London May price reaching a
4-1/2 year low at one stage of 1,270 stg per tonne before
ending the day at 1,314 stg, down 184 stg from the previous
close.
    The New York May price was down 15.59 at 108.00 cents a lb.
    Pressure will now build up on producers returning from the
ICO talks to sell coffee which had been held back in the hope
the negotiations would establish quotas which would put a floor
under prices, some senior traders said.
    The ICO 15 day average price stood at 114.66 cents a lb for
March 2. This compares with a target range of 120 to 140 cents
a lb under the system operating before quotas were suspended in
February last year following a sharp rise in international
prices caused by drought damage to the Brazilian crop.
    In a Reuter interview, Brazilian Coffee Institute, IBC,
President Jorio Dauster urged producers not to panic and said
they need to make hard commercial decisions. "If we have failed
at the ICO, at least we have tried," Dauster said, adding "now it
is time to go and sell coffee."
    But Brazil is keeping its marketing options open. It plans
to make an official estimate of the forthcoming crop next
month, Dauster said. It is too difficult to forecast now. Trade
sources have put the crop at over 26 mln bags compared with a
previous crop of 11.2 mln. Brazil is defining details of public
selling tenders for coffee bought on London's futures market
last year.
    A basic condition will be that it does not go back to the
market "in one go" but is sold over a minimum of six months.
    The breakdown of the ICO negotiations reflected a split
between producers and consumers on how to set the yardstick for
future quotas. Consumers said "objective criteria" like average
exports and stocks should determine producer quota shares,
Dauster said.
    All elements of this proposal were open to negotiation but
consumers insisted they did not want a return to the "ad hoc" way
of settling export quotas by virtual horse trading amongst
producers whilst consumers waited in the corridors of the ICO.
    Dauster said stocks and exports to ICO members and
non-members all need to be considered when setting quotas and
that Brazil would like to apply the coffee pact with a set
ratio of overall quota reflecting stock holdings.
    It is a "simplistic misconception that Brazil can dictate"
policy to other producers. While consumer countries are welcome
to participate they cannot dictate quotas which are very
difficult to allocate as different "objective criteria" achieve
different share-outs of quota, Dauster said.
    Other delegates said there was more open talking at the ICO
and at least differences were not hidden by a bad compromise.
    Consumer delegates said they had not been prepared to
accept the producers' offer to abandon quotas if it proves
impossible to find an acceptable basis for them.
    "We want the basis of quotas to reflect availability and to
encourage stock holding as an alternative to a buffer stock if
supplies are needed at a later stage," one delegate said.
    Some consumers claimed producer support for the consumer
argument was gaining momentum towards the end of the ICO
session but said it is uncertain whether this will now collapse
and how much producers will sink their differences should
prices fall further and remain depressed.
    The ICO executive board meets here March 30 to April 1 but
both producer and consumer delegates said they doubt if real
negotiations will begin then. The board is due to meet in
Indonesia in June with a full council scheduled for September.
    More cynical traders said the pressure of market forces and
politics in debt heavy Latin American producer countries could
bring ICO members back around the negotiating table sooner than
many imagine. In that case quotas could come into force during
the summer. But most delegates and traders said quotas before
October are unlikely, while Brazil's Dauster noted the ICO has
continued although there were no quotas from 1972 to 1980.
    A clear difference between the pressures already being felt
by importers and exporters was that consumers would have been
happy to agree on a formula for future quotas even if it could
not be imposed now. At least in that way they said they could
show a direct relationship between quotas and availability.
    In contrast producers wanted stop-gap quotas to plug the
seemingly bottomless market and were prepared to allow these to
lapse should lasting agreement not be found.
    "Producers were offering us jam tomorrow but after their
failure to discuss them last year promises were insufficient
and we wanted a cast iron commitment now," one consumer said.
 
51: coffee: -- Document Separator -- reut2-001.sgm
Colombian finance minister Cesar Gaviria
blamed an inflexible U.S. position for the failure of last
week's International Coffee Organisation, ICO, talks on export
quotas.
    "We understand that the U.S. Position was more inflexible
than the one of Brazil, where current economic and political
factors make it difficult to adopt certain positions," Gaviria
told Reuters in an interview.
    The U.S. and Brazil have each laid the blame on the other
for the breakdown in the negotiations to re-introduce export
quotas after being extended through the weekend in London.
    Gaviria stressed that Colombia tried to ensure a successful
outcome of the London talks but he deplored that intransigent
attitudes, both from producing and consuming nations, made it
impossible.
    In a conversation later with local journalists, Gaviria
said the U.S. attitude would have serious economic and
political consequences, not necessarily for a country like
Colombia but certainly for other Latin American nations and for
some African countries.
    He told Reuters that Colombia, because of the relatively
high level of its coffee stocks, would probably suffer less.
    According to Gaviria, Colombia can hope to earn about 1,500
mln dlrs this calendar year from coffee exports, which
traditionally account for 55 pct of the country's total export
revenue.
    That estimate would represent a drop in revenues of 1,400
mln dlrs from 1986.
    Colombia, which held stockpiles of 10.5 mln bags at the
start of the current coffee year, exported a record 11.5 mln
bags in the 1985/86 coffee year ending last September 30.
 
52: coffee: -- Document Separator -- reut2-001.sgm
Ivory Coast today predicted that the
present coffee price crash recorded after the collapse of the
recent International Coffee Organisation (ICO) meeting in
London would not last long.
    Commenting on Monday's failure by producer and consumer
nations to agree on new export quotas needed to tighten an
oversupplied coffee market, Ivorian Agriculture Minister Denis
Bra Kanon told reporters that traders would eventually be
obliged to restore their positions.
    "I am convinced the market is going to reverse by April," he
told a news conference here at his return from the failed
London talks.
    Robusta coffee beans for May delivery ended the day in
London down about 50 sterling at 1,265 sterling a tonne, the
lowest since 1982.
    Bra Kanon estimated at at least 535 billion CFA francs
(1.76 billion dlrs) the overall loss in revenues earned by
Ivory Coast from all its commodities exports this year if the
slide on the world markets continues.
    He disclosed that his country - the world's biggest cocoa
producer and the third largest for coffee -- would spearhead an
African initiative to reach a compromise formula by the end of
next month.
    Ivory Coast has been chosen by the Abidjan-based
Inter-African Coffee Organisation (IACO) to speak on behalf of
the continent's 25 producer nations at the London talks.
    "An initiative from IACO is likely very soon," he said
without elaborating.
    "Following the London collapse, we have immediately embarked
on a concertation course to avoid breaking an already fragile
market," he said.
    Questioned by journalists, the minister said President
Felix Houphouet-Boigny estimated for the moment that his
government would not be forced to reduce the price guaranteed
by the state to Ivorian coffee-growers for the current season.
    Last year, the West African nation announced that the
coffee producer price would stay at 200 CFA francs (65 cents)
per kilo.
    Bra Kanon said that his country would strive to diversify
its agricultural production to avoid beeing too dependent from
world market fluctuation.
    A communique read over the state-run television tonight
said that during today's weekly cabinet meeting, the veteran
Ivorian leader reaffirmed "his faith in Ivory Coast's bright
(economic) future" despite the commodities price slide.
    The Agriculture Minister also announced the government
decided to earmark a sum of 7.5 billion CFA francs (24.71 mln
dlrs) to support the country's small farmers.
    Financially-strapped Ivory Coast, long regarded as one of
Africa's showpiece economies, is going through difficult times
following the sharp slump in the world price of cocoa and
coffee.
    Ivory Coast's real gross domestic product is expected to
grow only one pct this year compared to five pct in 1986,
according to a recent Finance Ministry estimate.
 
53: sugar: -- Document Separator -- reut2-001.sgm
The French sugar market intervention
board, FIRS, raised its estimate of 1986/87 beet sugar
production in the 12-member European Community to 13.76 mln
tonnes white equivalent in its end-February report from 13.74
mln a month earlier.
    Its forecast for total EC sugar production, including cane
and molasses, rose to 14.10 mln tonnes from 14.09 mln.
Portugal, which joined the Community in January 1986, was
estimated at 12.75 mln tonnes white equivalent, unchanged from
the previous forecast and compared with 12.41 mln tonnes for
1985/86.
    Production for the current campaign in Spain was higher
than reported last month at 1.03 mln tonnes compared with
997,000 tonnes.
    Beet sugar production, expressed as white equivalent, was
estimated at 3.44 mln tonnes in France, 3.17 mln tonnes in West
Germany, 1.72 mln in Italy, 1.30 mln in Britain, 1.22 mln in
the Netherlands, 936,000 tonnes in Belgium/Luxembourg, 499,000
in Denmark, 287,000 in Greece, 183,000 in Ireland and 4,000 in
Portugal.
 
54: coffee: -- Document Separator -- reut2-001.sgm
The nine creditor banks of the
Singapore coffee trader &lt;Teck Hock and Co (Pte) Ltd> are
thinking of buying a controlling stake in the company
themselves, a creditor bank official said.
    Since last December the banks have been allowing the
company to postpone loan repayments while they try to find an
overseas commodity company to make an offer for the firm.
    At least one company has expressed interest and
negotiations are not yet over, banking sources said.
    However, the banks are now prepared to consider taking the
stake if they find an investor willing to inject six to seven
mln dlrs in the company but not take control, the banking
sources said.
    Teck Hock's financial adviser, Singapore International
Merchant Bankers Ltd (SIMBL), will work on the new proposal
with the creditor banks, they said.
    Major holdings are likely to be held by the two largest
creditor banks, Standard Chartered Bank &lt;STCH.L> and
Oversea-Chinese Banking Corp Ltd &lt;OCBM.SI>, they added.
    Teck Hock owes over 100 mln Singapore dlrs and the creditor
banks earlier this week agreed to let Teck Hock fufill
profitable contracts to help balance earlier losses.
    The nine banks are Oversea-Chinese Banking Corp Ltd, United
Overseas Bank Ltd &lt;UOBM.SI>, &lt;Banque Paribas>, &lt;Bangkok Bank
Ltd,> &lt;Citibank NA>, Standard Chartered Bank Ltd, Algemene Bank
Nederland NV &lt;ABNN.AS>, Banque Nationale De Paris &lt;BNPP.PA> and
&lt;Chase Manhattan Bank NA.>
