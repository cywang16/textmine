#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*-----------------------------------------------------------
 #*- words.pl
 #*-   Test the different methods to manage words
 #*-----------------------------------------------------------
 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::WordNet qw/in_dict_table in_dictionary base_words
               similar_words get_rel_words/;
 use TextMine::Pos qw/get_pos pos_tagger lex_tagger/;
 use TextMine::Entity qw/get_etype entity_ex/;
 use TextMine::Tokens qw/assemble_tokens/;
 use TextMine::Constants;

 #*-- get the database handle
 my (@words, @ans, $g_errs, $errs);
 print "Started word method tests\n";
 my ($dbh) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => $DB_NAME);

 #*-- check the function to search the dictionary tables w/o base words
IN_DICT_TABLE:
 @words = @ans = (); $g_errs = $errs = '';
 push(@ans, 1); push(@words, 'text mining');
 push(@ans, 1); push(@words, 'natural language processing');
 push(@ans, 1); push(@words, 'natural');
 push(@ans, 1); push(@words, 'valuable');
 push(@ans, 0); push(@words, 'valuables');
 push(@ans, 0); push(@words, 'missspelts');
 for my $i (0..$#words)
  {
    my $result = &in_dict_table($words[$i], $dbh);
    $errs .= "\tError --> $words[$i] \n"
             if ( ( $ans[$i] && !$result ) ||
                  ( !$ans[$i] && $result ) );
  }
 if ($errs) { print "IN_DICT_TABLE *********Errors:\n$errs"; $g_errs++;  }
 else       { print "IN_DICT_TABLE tests OK\n"; }

 #*-- check the function to search the dictionary tables with base words
IN_DICTIONARY:
 @words = @ans = (); $errs = '';
 push(@ans, 1); push(@words, 'text mining');
 push(@ans, 1); push(@words, 'natural language processing');
 push(@ans, 1); push(@words, 'natural');
 push(@ans, 1); push(@words, 'valuable');
 push(@ans, 1); push(@words, 'valuables');
 push(@ans, 0); push(@words, 'missspelts');
 for my $i (0..$#words)
  {
    my $result = &in_dictionary($words[$i], $dbh);
    $errs .= "\tError --> $words[$i] \n"
             if ( ( $ans[$i] && !$result ) ||
                  ( !$ans[$i] && $result ) );
  }
 if ($errs) { print "IN_DICTIONARY *********Errors:\n$errs";  $g_errs++;}
 else       { print "IN_DICTIONARY tests OK\n"; }

 #*-- extract the POS for individual words w/o context
GET_POS:
 @words = @ans = (); $errs = '';
 push(@ans, 'n'); push(@words, 'text mining');
 push(@ans, 'n'); push(@words, 'natural language processing');
 push(@ans, 'an'); push(@words, 'natural');
 push(@ans, 'an'); push(@words, 'valuable');
 push(@ans, 'n'); push(@words, 'valuables');
 push(@ans, 'n'); push(@words, 'missspelts');
 for my $i (0..$#words)
 {
   my $result =  &get_pos($words[$i], $dbh);
   $errs .= "\tNo. $i Error --> $words[$i] P: $result A: $ans[$i] \n" 
             unless ($result eq $ans[$i]);
 }
 if ($errs) { print "GET_POS *********Errors:\n$errs";  $g_errs++;}
 else       { print "GET_POS tests OK\n"; }

 #*-- check base_words
BASE_WORDS:
 @words = @ans = (); $errs = '';
 push(@ans, ['valuable'  => 'n']);  push(@words, 'valuables');
 push(@ans, ['addendum'  => 'n']);  push(@words, 'addenda');
 push(@ans, ['gas'       => 'nv']); push(@words, 'gasses');
 push(@ans, ['be'        => 'v',
             'is'	 => 'n']);  push(@words, 'is');
 push(@ans, []);                    push(@words, 'missspelts');
 for my $i (0..$#words)
 { my %bwords = &base_words($words[$i], $dbh, 1); my %ans = @{$ans[$i]};
   foreach (sort keys %bwords)
    { $errs .= "Mismatch: -->$_<-- -->$bwords{$_}<-- and -->$ans{$_}<--\n"
      unless ( $bwords{$_} && $ans{$_} && 
              ($bwords{$_} eq $ans{$_}) ); }
 }

 if ($errs) { print "BASE_WORDS *********Errors:\n$errs";  $g_errs++;}
 else       { print "BASE_WORDS tests OK\n"; }

 #*-- check the entity type for text
GET_ETYPE:
 @words = @ans = (); $errs = '';
 push(@ans, 'n');  push(@words, 'valuables');
 push(@ans, 'y');  push(@words, 'Bank of England');
 push(@ans, 'y');  push(@words, 'bank of england');
 push(@ans, 'n');  push(@words, 'natural');
 push(@ans, 'y');  push(@words, 'missspelts');
 for my $i (0..$#words)
 { my $result =  &get_etype($words[$i], $dbh);
   $errs .= "\tError --> $words[$i] \n" unless ($result eq $ans[$i]); }

 if ($errs) { print "GET_ETYPE *********Errors:\n$errs";  $g_errs++;}
 else       { print "GET_ETYPE tests OK\n"; }

 #*-- check the assembly of tokens from text
ASSEMBLE_TOK:
 $errs = ''; 
 my $text = <<"EOT";
 This is a test of the emergency broadcast system. In case of an error
 it will not work.
EOT
 my ($rtok) = &assemble_tokens(\$text, $dbh);
 my @toks = @$rtok; 
 my @ttoks = qw/This is a test of the emergency broadcast system .
                In_case of an error it_will not work ./;
 for my $i (0..$#toks) 
  { (my $temp = $ttoks[$i]) =~ s/_/ /g; 
    $errs .= "Error: $temp did not match $toks[$i]\n" 
        if ($toks[$i] ne $temp); }

 if ($errs) { print "ASSEMBLE_TOK *********Errors:\n$errs";  $g_errs++;}
 else       { print "ASSEMBLE_TOK tests OK\n"; }

 #*-- check the lexical tagger
LEX_TAGGER:
 $errs = ''; 
 $text = <<"EOT";
 This is a test of the emergency broadcast system. In case of an error,
 it will not work.
EOT
 ($rtok, undef, my $rtypes) = &lex_tagger(\$text, $dbh);
 @toks = @$rtok; my @types = @$rtypes;
 my %ltags = ('This'      => 'p', 
              'is'        => 'v',
              'a'         => 'dn',
              'test'      => 'nv',
              'of'        => 'o',
              'the'       => 'd',
              'emergency' => 'n',
              'broadcast' => 'nv',
              'system'    => 'n',
              '.'         => 'u',
              'In case'   => 'cr',
              'of'        => 'o',
              'an'        => 'dn',
              'error'     => 'n',
              ','         => 'u',
              'it will'   => 'p',
              'not'       => 'r',
              'work'      => 'nv',
               '.'        => 'u',
              );
 for my $i (0..$#toks) 
  {  
    $errs .= "Error: $toks[$i] $ltags{$toks[$i]} != $types[$i]\n" 
        if ($ltags{$toks[$i]} ne $types[$i]); }

 if ($errs) { print "LEX_TAGGER *********Errors:\n$errs";  $g_errs++;}
 else       { print "LEX_TAGGER tests OK\n"; }

 #*-- check the pos tagger
POS_TAGGER:
 $errs = ''; 
 $text = <<"EOT";
 This is a test of the emergency broadcast system. In case of an error,
 it will not work.
EOT
 ($rtok, undef, $rtypes) = &pos_tagger(\$text, $dbh);
 @toks = @$rtok; @types = @$rtypes;
 %ltags = (   'This'      => 'p', 
              'is'        => 'v',
              'a'         => 'd',
              'test'      => 'n',
              'of'        => 'o',
              'the'       => 'd',
              'emergency' => 'n', #*-- pos error
              'broadcast' => 'n', #*-- pos error
              'system'    => 'n',
              '.'         => 'u',
              'In case'   => 'c',
              'of'        => 'o',
              'an'        => 'd',
              'error'     => 'n',
              ','         => 'u',
              'it will'   => 'p',
              'not'       => 'r',
              'work'      => 'n',
               '.'        => 'u',
              );
 for my $i (0..$#toks) 
  {  
    $errs .= "Error: $toks[$i] $ltags{$toks[$i]} != $types[$i]\n" 
        if ($ltags{$toks[$i]} ne $types[$i]); }

 if ($errs) { print "POS_TAGGER *********Errors:\n$errs";  $g_errs++;}
 else       { print "POS_TAGGER tests OK\n"; }

 #*-- check the entity extractor
ENTITY_EX:
 $errs = ''; 
 $text = <<"EOT";
Hotel real estate investment trust Patriot American Hospitality Inc. 
said Tuesday it had agreed to acquire Interstate Hotels Corp.
EOT
 ($rtok, undef, $rtypes) = &entity_ex(\$text, $dbh);
 @toks = @$rtok; @types = @$rtypes;
 %ltags = (   
	'Hotel'		=> 'org',
	'real estate investment trust'	=> '',
	'Patriot'	=> 'org',
	'American'	=> 'org',
	'Hospitality'	=> 'org',
	'Inc.'		=> 'org',
	'said'		=> '',
	'Tuesday'	=> 'time',
	'it'		=> '',
	'had'		=> '',
	'agreed'	=> '',
	'to'		=> '',
	'acquire'	=> '',
	'Interstate'	=> 'org',
	'Hotels' 	=> 'org',
	'Corp.'		=> 'org'
              );
 for my $i (0..$#toks) 
  {  
    $errs .= "Error: $toks[$i] $ltags{$toks[$i]} != $types[$i]\n" 
        if ($ltags{$toks[$i]} ne $types[$i]); }

 if ($errs) { print "ENTITY_EX *********Errors:\n$errs";  $g_errs++;}
 else       { print "ENTITY_EX tests OK\n"; }

 #*-- get the similar words
SIMILAR_WORDS:
 @words = @ans = (); $errs = '';
 push(@ans, 'of_value useful worthful');  push(@words, 'valuable');
 push(@ans, 'bonus inducement motivator');  push(@words, 'incentive');
 for my $i (0..$#words)
 { my @result =  &similar_words($words[$i], $dbh, 1);
   $errs .= "\tError --> $words[$i] @result \n" 
      unless ("@result" eq $ans[$i]); }

 if ($errs) { print "FULL SIMILAR_WORDS *********Errors:\n$errs";  $g_errs++;}
 else       { print "FULL SIMILAR_WORDS tests OK\n"; }

 @words = @ans = (); $errs = '';
 push(@ans, 'of_value useful worthful');  push(@words, 'valuable');
 push(@ans, 'inducement motivator');      push(@words, 'incentive');
 for my $i (0..$#words)
 { my @result =  &similar_words($words[$i], $dbh, 0);
   $errs .= "\tError --> $words[$i] @result \n" 
      unless ("@result" eq $ans[$i]); }

 if ($errs) { print "BRIEF SIMILAR_WORDS *********Errors:\n$errs";  $g_errs++;}
 else       { print "BRIEF SIMILAR_WORDS tests OK\n"; }

OPPOSITE_WORDS:
 @words = @ans = (); $errs = '';
 push(@ans, 'valuable');   push(@words, 'worthless');
 push(@ans, 'worthless');  push(@words, 'valuable');
 for my $i (0..$#words)
 { my %result =  &get_rel_words($words[$i], 'antonym', $dbh);
   my @result = values %result;
   $errs .= "\tError --> $words[$i] --@result-- and --$ans[$i]-- \n" 
      unless ("@result" =~ /$ans[$i]/i); }

 if ($errs) { print "OPPOSITE_WORDS *********Errors:\n$errs";  $g_errs++;}
 else       { print "OPPOSITE_WORDS tests OK\n"; }

HYPERNYMS:
 @words = @ans = (); $errs = '';
 push(@ans, 'pony');   push(@words, 'mustang');
 push(@ans, 'wood Acer genus_Acer angiospermous_tree flowering_tree');   
                                                 push(@words, 'maple');
 for my $i (0..$#words)
 { my %result =  &get_rel_words($words[$i], 'hypernym', $dbh);
   my @result = values %result;
   $errs .= "\tError --> $words[$i] --@result-- and --$ans[$i]-- \n" 
      unless ("@result" =~ /$ans[$i]/i); }

 if ($errs) { print "HYPERNYMS *********Errors:\n$errs";  $g_errs++;}
 else       { print "HYPERNYMS tests OK\n"; }

EXIT:

 $dbh->disconnect_db();
 print $g_errs ? "$g_errs test failed": "All test OK.......";
 print "\nEnded word method tests\n";

exit(0);
