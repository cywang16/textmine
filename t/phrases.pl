#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*-----------------------------------------------------------
 #*- phrases.pl
 #*-   Extract phrases from the text
 #*-----------------------------------------------------------
 use Text::Wrap qw(wrap 80);
 use TextMine::DbCall;
 use TextMine::Summary qw/phrases_ex/;
 use TextMine::Constants;

 #*-- get the database handle
 my ($dbh) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => $DB_NAME);

 undef($/); my $text = <DATA>; 

 #*-- dump the bigrams and highlighted text
 print (" Phrases with POS\n\n");
 my ($r1, $r2) = &phrases_ex(\$text, 10, $dbh, 1);
 foreach (@$r1) { print ("\t: $_\n"); }
 print ("----------------------------------------\n\n");
 #print (&wrap('','', $$r2), "\n");

 #*-- dump the bigrams and highlighted text
 print (" Phrases w/o POS\n\n");
 ($r1, $r2) = &phrases_ex(\$text, 10, $dbh);
 foreach (@$r1) { print ("\t: $_\n"); }
 print ("----------------------------------------\n\n");
 #print (&wrap('','', $$r2), "\n");

 $dbh->disconnect_db();

exit(0);

__DATA__
Sun imagines world of virtual servers
By Stephen Shankland CNET News.com

SAN FRANCISCO--Sun Microsystems uncloaked "N1" on Thursday, a stealth 
project that the company hopes will ease operations at data centers 
filled with servers and storage systems.

As first reported by CNET News.com, the N1 project is an attempt to 
"virtualize" computing equipment, making servers and storage look 
like giant pools of resources with computing processes swimming within.

Sun Chief Technology Officer Greg Papadopoulos unveiled the concept 
Thursday at the company's analyst conference here. Essentially, N1 
describes what happens when a network of computers and storage systems 
is assembled into a much larger whole. "This is just like what an 
operating system did for a computer over the last 20 years. It's all 
the stuff we did in Unix and redid in Linux," he said.

The concept resembles efforts under way at some of Sun's biggest 
competitors. IBM is working on "grid" computing that unites servers 
and storage into a large pool. Grid computing grew out of academia, 
though, and focuses more on mathematical calculations than the business 
processes at the heart of N1.

Compaq Computer also is a fan of grid computing, and Sun itself has 
released its own grid software as an open-source project. Meanwhile, 
Hewlett-Packard has its own planetary computing initiative similar to 
the grid efforts.

Research group

IDC terms the concept behind N1 "service-centric infrastructure," said 
analyst Vernon Turner. "You won't organize boxes anymore, you'll 
organize resources." Papadopoulos said the trend is starting in storage. 
Some computing jobs require lots of storage, but others require little. 
When each server comes with its own directly attached storage system, 
some space goes unused, depending on the job. Through virtualization, 
storage space is pooled so its storage can be used more efficiently.
The next stage after storage will be to create a virtual world for 
computing resources, Papadopoulos said. In vogue today is a 
combination of large and small servers for data centers. The small, 
inexpensive "edge" servers handle chores such as sending 
Web pages or audio streams. And in the heart of the data center are 
large, expensive symmetric multiprocessing servers with 
many CPUs (central processing units) and high-end features.

N1 will understand all the components of this data center, 
Papadopoulos said. With it, administrators will be able to allocate 
more computing power to important tasks and better manage less important 
ones, a process similar in concept to the way high-end Unix servers 
and mainframes can be partitioned so they can run several jobs with 
shifting priorities.

But to fulfill the promise of N1, Sun will have to deal with computing 
hardware from other companies, Turner said. It's likely computing 
processes themselves will run using Sun's Java software and the 
industry-favored XML (Extensible Markup Language) data description 
language, because those technologies work well across different 
companies' products. But a company's data center is likely to be 
populated with many different companies' hardware.

Sun is well aware of this reality. Java runs on any major server, 
while Sun is working to spread its Sun One software plan to Linux. 
Additionally, the company sells software that enables sophisticated 
data-protection features that work with any storage system.

N1 has the potential to work on mammoth computing systems, Papadopoulos 
said. "This doesn't stop at hundreds of processors," he said, but 
rather spans all the way up to tens of thousands of CPUs as well as 
petabytes and exabytes of storage.

These mammoth systems will be needed to match the computing demand 
imposed by all the network-enabled devices Sun expects.  There are 
about 100 million desktop computers and servers in existence, but 
Papadopoulus expects about 100 billion Internet-enabled cell phones, 
cars, appliances and other devices soon, with about 100 trillion 
Internet-enabled thermostats, mail packages, articles of clothing 
and other devices in the more remote future.
