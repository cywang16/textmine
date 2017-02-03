#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*-----------------------------------------------------------
 #*- test the summarizer
 #*-----------------------------------------------------------

 use TextMine::DbCall;
 use TextMine::Summary;
 use TextMine::Tokens qw/load_token_tables/;
 use TextMine::Constants qw/$DB_NAME/;

 my ($dbh, $db_msg) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => "$DB_NAME");
 my $hash_refs = &load_token_tables($dbh);

 my $short_article = << "EOF";
Central bank governor Chang Chi-cheng
rejected a request by textile makers to halt the rise of the
Taiwan dollar against the U.S. Dollar to stop them losing
orders to South Korea, Hong Kong and Singapore, a spokesman for
the Taiwan Textile Federation said.
    He quoted Chang as telling representatives of 19 textile
associations last Saturday the government could not fix the
Taiwan dollar exchange rate at 35 to one U.S. Dollar due to
U.S. Pressure for an appreciation of the local currency.
    The Federation asked the government on February 19 to hold
the exchange rate at that level.
    The federation said in its request that many local textile
exporters were operating without profit and would go out of
business if the rate continued to fall.

EOF

 my $long_article = << "EOF";

Eastman Kodak Co said it is introducing
four information technology systems that will be led by today's
highest-capacity system for data storage and retrieval.
    The company said information management products will be
the focus of a multi-mln dlr business-to-business
communications campaign under the threme "The New Vision of
Kodak."
    Noting that it is well-known as a photographic company,
Kodak said its information technology sales exceeded four
billion dlrs in 1986. "If the Kodak divisions generating those
sales were independent, that company would rank among the top
100 of the Fortune 500," it pointed out.
    The objective of Kodak's "new vision" communications
campaign, it added, is to inform others of the company's
commitment to the business and industrial sector.
    Kodak said the campaign will focus in part on the
information management systems unveiled today --
    -- The Kodak optical disk system 6800 which can store more
than a terabyte of information (a trillion bytes).
    - The Kodak KIMS system 5000, a networked information
management system using optical disks or microfilm or both.
    -- The Kodak KIMS system 3000, an optical-disk-based system
that allows users to integrate optical disks into their current
information management systems.
    -- The Kodak KIMS system 4500, a microfilm-based,
computer-assisted system which can be a starter system.
    Kodak said the optical disy system 6800 is a
write-once/ready-many-times type its Mass Memory Division will
market on a limited basis later this year and in quantity in
1988.
    Each system 6800 automated disk library can accommodate up
to 150, 14-inch optical disks. Each disk provides 6.8 gigabytes
of randomly accessible on-line storage. Thus, Kodak pointed
out, 150 disks render the more-than-a-terabyte capacity.
    Kodak said it will begin deliveries of the KIMS system 5000
in mid-1987. The open-ended and media-independent system
allows users to incorporate existing and emerging technologies,
including erasable optical disks, high-density magnetic media,
fiber optics and even artificial intelligence, is expected to
sell in the 700,000 dlr range.
    Initially this system will come in a 12-inch optical disk
version which provides data storage and retrieval through a
disk library with a capacity of up to 121 disks, each storing
2.6 gigabytes.
    Kodak said the KIMS system 3000 is the baseline member of
the family of KIMS systems. Using one or two 12-inch manually
loaded optical disk drives, it will sell for about 150,000 dlrs
with deliveries beginning in mid-year.
    The company said the system 3000 is fulling compatibal with
the more powerful KIMS system 5000.
    It said the KIMS system 4500 uses the same hardware and
software as the system 5000. It will be available in mid-1987
and sell in the 150,000 dlr range.
EOF

 local $" = "\n\n";
 print ("Summary of long article:\n");
 $summary = &summary(\$long_article, 'news', $dbh, 0, 4, $hash_refs);
 @summary = split/<br>/, $summary;
 print "@summary\n\n";

 print ("Summary of short article:\n");
 $summary = &summary(\$short_article, 'news', $dbh, 0, 4, $hash_refs);
 @summary = split/<br>/, $summary;
 print "@summary\n\n";
 $dbh->disconnect_db();

 exit(0);
