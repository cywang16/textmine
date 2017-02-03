#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------------------
 #*- tgen.pl
 #*-  A random text generator 
 #*-  Usage tgen.pl <number of sentences>
 #*-  Note: Some of these phrases were taken from a fog script
 #*-        written in Rexx at IBM
 #*----------------------------------------------------------------

 use strict; use warnings;
 my $num_sentences = $ARGV[0] ? $ARGV[0]: 2;

 #*-- list of lead phrases
 my @leadin = (
  'In particular, ', 
  'On the other hand, ', 
  'However, ', 
  'Similarly,', 
  'As a resultant implication,' ,
  'In this regard,' ,
  'In hindsight,' ,
  'Without foresight,' ,
  'For example,' ,
  'Thus,' ,
  'In respect to specific goals,' ,
  'Interestingly enough,' ,
  'Without going into the technical details,' ,
  'Of course,' ,
  'As a matter of fact, ' ,
  'In theory,' ,
  'It is assumed that' ,
  'Conversely,' ,
  'We can see in retrospect,' ,
  'It is intuitively obvious that, '); 

 #*-- list of subject phrases
 my @subject = (
  'a large portion of interface coordination communication',
  'a constant flow of effective communication',
  'the characterization of specific criteria',
  'initiation of critical subsystem development',
  'the fully integrated test program',
  'the product configuration baseline',
  'any associated supporting element',
  'the incorporation of additional project constraints',
  'the independent functional principle',
  'the interrelation of system and/or subsystem technologies',
  'the product assurance architecture');

 #*-- list of verb phrases
 my @verb = (
  'must utilize and be functionally interwoven with',
  'maximizes the probability of project success, yet minimizes, cost and time required for',
  'adds explicit performance limits to',
  'necessitates that urgent consideration be applied to',
  'requires considerable systems analysis and trade-off studies to arrive at',
  'is further compounded when taking into account',
  'presents extremely interesting challenges to',
  'recognizes other systems\' importance and the necessity for',
  'effects a significant implementation of',
  'adds overriding performance constraints to',
  'mandates staff-meeting-level attention to',
  'is functionally equivalent and parallel to');

 #*-- list of object phrases
 my @object = (
  'the sophisticated hardware.' ,
  'the anticipated fifth-generation equipment.' ,
  'the subsystem compatibility testing.' ,
  'the structural design, based on system engineering concepts.' ,
  'the preliminary qualification limit.' ,
  'the evolution of specifications over a given time period.' ,
  'the philosophy of commonality and standardization.' ,
  'the greater fight-worthiness concept.' ,
  'any discrete configuration mode.' ,
  'the management-by-contention principle.' ,
  'the total system rationale.' ,
  'possible bidirectional logical relationship approaches.' ,
  'the postulated use of dialog management technology.' ,
  'the two phase design commit technique.' ,
  'the overall negative profitability.');

 #*-- generate the random sentences
 for (1..$num_sentences)
  { print ""   . $leadin[int (rand (@leadin))]  .
          " "  . $subject[int (rand (@subject))] .
          " "  . $verb[int (rand (@verb))]  .
          " "  . $object[int (rand (@object))] . "\n\n"; }
 
 exit(0);
