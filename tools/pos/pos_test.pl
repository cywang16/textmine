#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*-------------------------------------------------------------
 #*- pos_test.pl
 #*-  Test the POS Tagger 
 #*-------------------------------------------------------------

 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Tokens qw/assemble_tokens load_token_tables/;
 use TextMine::Pos qw/pos_tagger lex_tagger/;
 use TextMine::Constants;

 my ($dbh) = TextMine::DbCall->new ( 'Host' => '',
       'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => $DB_NAME);
 undef($/); my $text = <DATA>;
 my @words = my @tags = ();
 while ($text =~ /(.*?)\s<(.*?)>/sg)
   { my $word = lc($1); my $tag = $2;
     $word =~ s/^\s+//; $word =~ s/\s+$//; 
     $tag  =~ s/^\s+//; $tag  =~ s/\s+$//;
     push (@words, $word); push (@tags, $tag); }

 local $" = ' '; $text = "@words";
 my $hash_refs = &load_token_tables($dbh);
 my ($r1, $r2, $r3) = &pos_tagger(\$text, $dbh, $hash_refs);
 my @tokens = @$r1;
 my @loc = @$r2;
 my @types = @$r3;
 
 open (OUT, ">pos_test_results.txt") || 
      die ("Unable to open pos_test_results.txt $!\n");
 binmode OUT, ":raw";
 print OUT ("Fre.\tToken\t Correction (Wrong --> Correct)\n"); 
 my $match = 0; my %errors = ();
 for my $i (0..$#tokens)
  { if ($tokens[$i] ne $words[$i])
     { print OUT ("Mismatch $tokens[$i] and $words[$i] \n"); }
    if ($types[$i] eq $tags[$i]) { $match++; }
    else { $errors{"$tokens[$i] $types[$i] --> $tags[$i]"}++; }
  }

 foreach (sort {$errors{$b} <=> $errors{$a}} keys %errors)
  { print OUT ("$errors{$_}\t$_\n"); }

 my $prec = int (100 * $match / @tokens) . '%';
 print OUT ("Precision: $prec (Matched $match out of ",scalar @tokens,")\n");

 close(OUT);

 $dbh->disconnect_db();
 
exit(0);
__DATA__
if <c>your <p>library <n>is <v>on <o>a <d>network <n>and <c>has <v>the
<d>dynix <n>gateways <n>product <n>, <u>patrons <n>and <c>staff <n>at
<o>your <p>library <n>can <v>use <v>gateways <n>to <o>access <v>information
<n>on <o>other <d>systems <n>as well <r>. <u>for example <r>, <u>you <p>can
<v>search <v>for <o>items <n>and <c>place <v>holds <n>on <o>items <n>at
<o>other <d>libraries <n>, <u>research <n>computer <n>centers <n>, <u>and
<c>universities <n>. <u>typically <r>, <u>there <p>are <v>multiple
<a>search <n>menus <n>on <o>your <p>system <n>, <u>each <d>of <o>which
<d>is <v>set up <v>differently <r>. <u>the <d>search <n>menu <n>in <o>the
<d>circulation <n>module <n>may <v>make <v>additional <a>search <n>methods
<n>available <a>to <o>library <n>staff <n>. <u>for example <r>, <u>an
<d>alphabetical <a>search <n>on <o>the <d>word <n>" <u>ulysses <n>"
<u>locates <v>all <d>titles <n>that <p>contain <v>the <d>word <n>"
<u>ulysses <n>. <u>" <u>displays <v>the <d>records <n>that <p>have <v>a
<d>specific <a>word <n>or <c>words <n>in <o>the <d>title <n>, <u>contents
<n>, <u>subject <n>, <u>or <c>series <n>fields <n>of <o>the <d>bib
<n>record <n>, <u>depending on <o>which <d>fields <v>have <v>been
<v>included <v>in <o>each <d>index <n>. <u>for example <r>, <u>you <p>can
<v>use <v>an <d>accelerated <v>search <n>command <n>to <o>perform <v>an
<d>author <n>authority <n>search <n>or <c>a <d>title <n>keyword <n>search
<n>. <u>the <d>search <n>abbreviation <n>is <v>included <v>in
<o>parentheses <n>following <v>the <d>search <n>name <n>: <u>a <d>system
<n>menu <n>. <u>any <d>screen <n>where <r>you <p>can <v>enter <v>" <u>so
<n>" <u>to <o>start <v>a <d>search <n>over <r>. <u>certain <a>abbreviations
<n>may <v>work at <v>one <a>prompt <n>but <c>not <u>at <o>another <d>.
<u>to <o>perform <v>an <d>accelerated <v>search <n>, <u>follow <v>these
<d>instructions <n>: <u>that <c>item's <n>full <a>bib <n>display <n>appears
<v>. <u>write down <v>any <d>information <n>you <p>need <v>, <u>or
<c>select <v>the <d>item <n>if <c>you are <p>placing <v>a <d>hold <n>.
<u>alphabetical <a>title <n>search <n>. <u>enter <v>the <d>line <n>number
<n>of <o>the <d>alphabetical <a>title <n>search <n>option <n>. <u>a <d>bib
<n>summary <n>screen <n>appears <v>, <u>listing <v>the <d>titles <n>that
<p>match <v>your <p>entry <n>: <u>when <r>you <p>access <v>the <d>bib
<n>record <n>you <p>want <v>, <u>you <p>can <v>print <v>the <d>screen <n>,
<u>write down <v>any <d>information <n>you <p>need <v>, <u>or <c>select
<v>the <d>item <n>if <c>you are <p>placing <v>a <d>hold <n>. <u>the
<d>cursor <n>symbol <n>( <u>> <u>) <u>appears <v>on <o>the <d>alphabetical
<a>list <n>next to <o>the <d>heading <n>that <c>most <r>closely <r>matches
<v>your <p>request <n>. <u>byzantine empire <n>. <u>when <r>you are
<p>editing <v>a <d>document <n>, <u>you <p>want <v>to <o>be <v>able <a>to
<o>move <v>quickly <r>through <o>the <d>pages <n>. <u>scrolling <v>changes
<v>the <d>display <n>but <c>does not <v>move <v>the <d>insertion
<n>point <n>. <u>to <o>use <v>keyboard <n>shortcuts <n>to <o>navigate <v>a
<d>document <n>. <u>move <v>the <d>mouse <n>pointer <n>until <c>the
<d>i-beam <n>is <v>at <o>the <d>beginning <n>of <o>the <d>text <n>you
<p>want <v>to <o>select <v>. <u>for <o>information <n>, <u>refer <v>to <o>"
<u>undoing <v>one <a>or <c>more <d>actions <n>" <u>in this <d>chapter <n>.
<u>ami <n>pro <n>provides <v>three <a>modes <n>for <o>typing <v>text <n>.
<u>in <o>insert <n>mode <n>, <u>you <p>insert <v>text <n>at <o>the
<d>position <n>of <o>the <d>insertion <n>point <n>and <c>any <d>existing
<v>text <n>automatically <r>moves <v>. <u>if <c>you <p>press <v>backspace
<n>, <u>ami <n>pro <n>deletes <v>the <d>selected <v>text <n>and <c>one
<a>character <n>to <o>the <d>left <n>of <o>the <d>selected <v>text <n>.
<u>you <p>can <v>disable <v>drag&drop <n>. <u>if <c>you <p>want <v>to
<o>move <v>the <d>text <n>, <u>position <n>the <d>mouse <n>pointer
<n>anywhere <r>in <o>the <d>selected <v>text <n>and <c>drag <v>the <d>mouse
<n>until <c>the <d>insertion <n>point <n>is <v>in <o>the <d>desired
<v>location <n>. <u>the <d>contents <n>of <o>the <d>clipboard <n>appear
<v>in <o>the <d>desired <v>location <n>. <u>to <o>move <v>or <c>copy
<v>text <n>between <o>documents <n>. <u>choose <v>edit <n>or <c>edit <n>to
<o>place <v>the <d>selected <v>text <n>on <o>the <d>clipboard <n>. <u>if
<c>the <d>document <n>into <o>which <d>you <p>want <v>to <o>paste <v>the
<d>text <n>is <v>already <r>open <v>, <u>you <p>can <v>switch <v>to that
<r>window <n>by <o>clicking <v>in <o>it <p>or <c>by <o>choosing <v>the
<d>window <n>menu <n>and <c>selecting <v>the <d>desired <v>document <n>.
<u>press <v>shift+ins <n>or <c>ctrl+v <n>. <u>select <v>the <d>text <n>you
<p>want <v>to <o>protect <v>. <u>permanently <r>inserts <v>the <d>date
<n>the <d>current <a>document <n>was <v>created <v>. <u>you <p>can
<v>select <v>off <n>, <u>1 <a>, <u>2 <a>, <u>3 <a>, <u>or <c>4 <a>levels
<n>. <u>when <r>you <p>want <v>to <o>reverse <v>an <d>action <n>, <u>choose
<v>edit <n>. <u>modifying <v>the <d>appearance <n>of <o>text <n>. <u>the
<d>following <v>are <v>suggestions <n>on <o>how <r>to <o>proceed <v>when
<r>using <v>the <d>translator's <n>workbench <n>together <r>with <o>word
<n>for <o>windows <n>6.0 <a>. <u>another <d>important <a>category <n>of
<o>non-textual <a>data <n>is <v>what <d>is <v>referred <v>to <o>as <c>"
<u>hidden <v>text <n>. <u>" <u>alternatively <r>, <u>choose <v>the <d>menu
<n>item <n>from <o>word's <n>tools <n>menu <n>. <u>thus <r>, <u>you will
<p>make sure <a>that <c>you <p>see <v>all <a>the <d>information <n>that <c>the
<d>workbench <n>manages <v>during <o>translation <n>: <u>always <r>put
<v>one <a>abbreviation <n>on <o>a <d>line <n>, <u>followed <v>by <o>a
<d>period <n>. <u>during <o>the <d>translation <n>of <o>this <d>example
<n>, <u>the <d>workbench <n>should <v>ignore <v>the <d>second <a>sentence
<n>when <r>moving <v>from <o>the <d>first <a>sentence <n>to <o>the <d>third
<a>one <p>. <u>in <o>word <n>, <u>you <p>can <v>immediately <r>recognize
<v>a <d>100% <n>match <n>from <o>the <d>color <n>of <o>the <d>target
<n>field <n>. <u>the <d>twb1 <n>button <n>, <u>also <r>labeled <v>translate
<n>until <n>next <d>fuzzy <n>match <n>, <u>tells <v>the <d>workbench <n>to
<o>do <v>precisely <r>this <d>. <u>you <p>can <v>also <r>use <v>the
<d>shortcut <n>[ <u>alt <n>] <u>+ <c>[ <u>x <n>] <u>on <o>the <d>separate
<a>numeric <a>keypad <n>to <o>start <v>this <d>function <n>. <u>that is
<r>, <u>these <d>words <n>make <v>the <d>source <n>sentence <n>longer <a>or
<c>shorter <a>than <c>the <d>tm <n>sentence <n>. <u>likewise <r>, <u>if
<c>something <p>has <v>been <v>left <v>out in <o>the <d>source <n>sentence
<n>, <u>you will <p>have <v>to <o>delete <v>the <d>corresponding
<a>parts <n>in <o>the <d>suggested <v>translation <n>as well <r>.
<u>automatic <a>substitution <n>of <o>interchangeable <a>elements <n>.
<u>if <c>the <d>workbench <n>cannot <v>find <v>any <d>fuzzy <a>match <n>,
<u>it will <p>display <v>a <d>corresponding <a>message <n>( <u>" <u>no
<d>match <n>" <u>) <u>in <o>the <d>lower <a>right <a>corner <n>of <o>its
<p>status <n>bar <n>and <c>you will <p>be <v>presented <v>with <o>an
<d>empty <a>yellow <a>target <n>field <n>. <u>then <r>go on <o>translating
<v>until <c>you <p>want <v>to <o>insert <v>the <d>next <d>translation <n>.
<u>select <v>the <d>text <n>to <o>be <v>copied <v>in <o>the <d>concordance
<n>window <n>, <u>usually <r>the <d>translation <n>of <o>the <d>sentence
<n>part <n>that <c>you have <p>searched <v>for <r>. <u>the <d>same
<d>goes <v>for <o>formatting <v>: <u>making <v>corrections <n>. <u>if
<c>you would <p>like <v>to <o>make <v>corrections <n>to <o>translations
<n>after <o>their <p>initial <a>creation <n>, <u>you <p>should <v>always
<r>do <v>this <d>in <o>tm <n>mode <n>so that <c>the <d>corrections <n>will
<v>be <v>stored <v>in <o>translation <n>memory <n>as well as <o>in <o>your
<p>document <n>. <u>but <c>consider <v>the <d>following <v>example <n>where
<r>text <n>is <v>used <v>within <o>an <d>index <n>entry <n>field <n>: <u>if
<c>a <d>perfect <a>or <c>fuzzy <a>match <n>is <v>found <v>, <u>the
<d>workbench <n>will <v>again <r>automatically <r>transfer <v>its
<p>translation <n>into <o>the <d>target <n>field <n>in <o>winword <n>. <u>
