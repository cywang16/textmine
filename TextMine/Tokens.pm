
 #*--------------------------------------------------------------------
 #*- Tokens.pm						
 #*- Description: A set of Perl functions to build tokens from text
 #*--------------------------------------------------------------------

 package TextMine::Tokens;

 use strict; use warnings;
 use Time::Local;
 use Config;
 use lib qw/../;
 use TextMine::DbCall;
 use TextMine::WordNet qw/base_words/;
 require Exporter;
 our @ISA = qw(Exporter);
 our @EXPORT = qw( tokens load_token_tables assemble_tokens 
                   stem build_stopwords );
 our @EXPORT_OK = qw();
 use vars qw ($PCHAR);

 #*-- set the constants     
 BEGIN 
  {  #*-- punctuation characters
     $PCHAR = '?,.!;:()+={}\[\]/\<>-'; }

 #*-------------------------------------------------------
 #*- Input:  Reference to a text string
 #*- Output: Reference to a list of tokens
 #*-         Reference to an index of the last char
 #*-         in every token in the text string
 #*- Consecutive \s chars form a single token.
 #*- All other chars from single tokens.
 #*-------------------------------------------------------
 sub tokens
 {
  my ($r_text,		#*-- text to be parsed
      $add_tchars	#*-- optional additional token char types
     ) = @_;

  #*-- initialize the arrays for the tokens and corresponding locations
  my @tokens = my @loc = (); 

  #*-- set of chars that can be concatenated
  #*-- anything else can be a token separator
  my $tchar = ($add_tchars) ? "[a-zA-Z0-9$add_tchars]": '[a-zA-Z0-9]'; 
  my $token =  my $c_char = ''; my $p_char;

  #*-- inner subroutine to build tokens
  my $add = sub { push (@tokens, $_[0]); push (@loc, $_[1]); $token = ''; };
  
  #*-- scan the text, one char at a time
  while ( $$r_text =~ /(.)/gs)
   {
    #*-- restrict char space to visible chars in Ascii range 32 - 122
    my $a_val = ord $1;
    $c_char = ( (31 < $a_val) && ($a_val < 123) ) ? $1: ' ';
    CHAR: {

      #*-- handle the token chars, add the previous token
      #*-- if any, otherwise concatenate to the current token
      if ($c_char =~ /$tchar/)
       { $add->($token, pos($$r_text) - 2) 
              if (defined($p_char) && $p_char !~ /$tchar/);
         $token .= $c_char; last CHAR; }

      #*-- handle spaces, consecutive spaces form one token
      if ($c_char =~ /\s/)
       { $add->($token, pos($$r_text) - 2) 
              if (defined($p_char) && $p_char !~ /\s/);
         $token = ' '; last CHAR; }

      #*-- default, all other characters form a separate token
      $add->($token, pos($$r_text) - 2) if (defined($p_char));
      $token = $c_char;

    } #*-- end of switch

    $p_char = $c_char;
   } #*-- end of while
  
  #*-- add the last token
  if ($token) { $add->($token, length($$r_text) - 1); }  

  return(\@tokens,\@loc);

 }

 #*----------------------------------------------------------
 #*- Load the tables to assemble tokens and return the
 #*- address of the hashes in an array
 #*----------------------------------------------------------
 sub load_token_tables
 {
  my ($dbh) = @_;

  #*-- load the abbreviations
  my %abbrev = (); my ($word);
  my $command = "select enc_name from co_abbrev where enc_type = 'a'";
  (my $sth, undef) = $dbh->execute_stmt($command);
  $abbrev{$word}++ while ( ($word) = $dbh->fetch_row($sth) );

  #*-- load the internet country codes
  my %c_codes = (); 
  $command = "select enc_name from co_abbrev where enc_type = 'ic'";
  ($sth, undef) = $dbh->execute_stmt($command);
  $c_codes{$word}++ while ( ($word) = $dbh->fetch_row($sth) );

  #*-- load the internet protocols
  my %i_protocol = (); 
  $command = "select enc_name from co_abbrev where enc_type = 'ip'";
  ($sth, undef) = $dbh->execute_stmt($command);
  $i_protocol{$word}++ while ( ($word) = $dbh->fetch_row($sth) );

  #*-- load the emoticons
  my %e_icons = (); 
  $command = "select enc_name from co_abbrev where enc_type = 'e'";
  ($sth, undef) = $dbh->execute_stmt($command);
  $e_icons{$word}++ while ( ($word) = $dbh->fetch_row($sth) );

  #*-- preload collocations for some common lead words
  my %colloc = ();
  foreach (qw/a all and as at be by c day do e ex for g get go
              in man mid new no non not o of off old on one p pro
              see t the to too u up x :/)
   {
    $colloc{$_} = '';
    $command = "select coc_words from co_colloc where " .
               "coc_lead_word = '$_'";
    ($sth, undef) = $dbh->execute_stmt($command);
    while ( (my $words) = $dbh->fetch_row($sth) )
     { $colloc{$_} .= "$words "; }
   }

  #*-- load the collocation lead words
  my %colloc_lead = ();
  $command = "select coc_lead_words from co_colloc_lead";
  ($sth, undef) = $dbh->execute_stmt($command);
  while ( (my $words) = $dbh->fetch_row($sth) )
   { $colloc_lead{$_}++ foreach (split/\s+/, $words); }

  #*-- return a hash of references to hashes for loaded tables
  my $hash_refs = { 'abbrev'      => \%abbrev,
                    'c_codes'     => \%c_codes,
                    'colloc'      => \%colloc,
                    'colloc_lead' => \%colloc_lead,
                    'e_icons'      => \%e_icons,
                    'i_protocol'  => \%i_protocol };

  return ($hash_refs);
 }

 #*----------------------------------------------------------
 #*- assemble_tokens
 #*-   Accept text and a database handle and return a list
 #*-   of words or syntactic units
 #*-   Table of token types and codes
 #*- 
 #*-   Type		Code
 #*-   ---------------  ----
 #*-   Abbreviation	a
 #*-   Combined		b
 #*-   Collocation	c
 #*-   Emoticon		e
 #*-   Internet		i
 #*-   Number		n
 #*-   Punctuation	u
 #*-   Unknown		x
 #*----------------------------------------------------------
 sub assemble_tokens
 {
  my ($rtext,		#*-- reference to a text string
      $dbh,		#*-- database handle
      $hash_refs,	#*-- reference to token tables
      $expand,		#*-- optional flag to expand short forms
      $base_w,		#*-- optional flag to handle base words in collocations
      $add_tchars	#*-- optional additional token char types
     ) = @_;

  return ('') unless ($$rtext && $dbh);

  #*-- inner subroutine to check for numeric IP addresses
  my $ipnum = sub { return (0) unless ($_[0] =~ /^\d+$/);
                    return ( ( (0 <= $_[0]) && ($_[0] <= 255) ) ? 1:0 ); };

  #*-- check if the token tables have been preloaded
  $hash_refs = &load_token_tables($dbh) unless ($hash_refs);
  my %abbrev  = %{$$hash_refs{abbrev}}; 
  my %c_codes = %{$$hash_refs{c_codes}};
  my %colloc  = %{$$hash_refs{colloc}};
  my %colloc_lead = %{$$hash_refs{colloc_lead}};
  my %i_protocol  = %{$$hash_refs{i_protocol}};
  my %e_icons  = %{$$hash_refs{e_icons}};

  #*-- convert the text to tokens, the used array defines token types
  my ($rt, $rl) = &tokens($rtext, $add_tchars);
  my @tokens = @$rt; my @end = @$rl; 

  #*-- pass 1a, check for abbreviations such as 1.5m. or 2bn.
  for my $i (1..$#tokens)
   { 
    if ( ($tokens[$i] eq '.') && ($tokens[$i-1] =~ /([+-]?[\d\.Ee]+)(\w+)/) &&
         ($abbrev{lc("$2")}) ) 
     { 
      my ($num, $word) = ($1, $2);
      #*-- verify that $num is a number
      my (undef, undef, $r1) = &assemble_tokens(\$num, $dbh, $hash_refs);
      next unless ($$r1[0] =~ /n/);
      splice(@tokens, $i-1, 1, $num, $word);
      splice(@end, $i-1, 1, $end[$i-2] + length($num), 
             $end[$i-2] + length($num. $word)); }
   }

  #*-- pass 1b, check for abbreviations with periods
  #*-- start with longer tokens
  my @used = ('x') x @tokens;	#*-- assign the unknown type to all tokens
  for my $i (1..$#tokens)
   { 
     @used[$i-3..$i] = ('a','a','a', 'a')
      if ( $tokens[$i-3] && ($tokens[$i] eq '.') && 
           $abbrev{lc($tokens[$i-3] . '_' . $tokens[$i-1])} );

     @used[$i-1,$i] = ('a','a') #*-- check for an initial
      if ( ($tokens[$i] eq '.') && 
           ( ($tokens[$i-1] =~ /^[A-Z]$/) || $abbrev{lc($tokens[$i-1])} ) ); 
   }
  
  #*-- pass 1c, check for abbreviations without periods
  #*-- Feb 28th, 05': Only check for abbreviations that start with
  #*-- upper case letters
  for my $i (0..$#tokens)
   { 
     next if ($used[$i] =~ m%[a]%);
     @used[$i-2..$i] = ('a','a','a')
      if ( $tokens[$i-2] && ($tokens[$i-2] =~ /^[A-Z]/)
           && $abbrev{$tokens[$i-2] . '_' . $tokens[$i]} );
     $used[$i] = 'a'
      if ( ($tokens[$i] =~ /^[A-Z]/) && $abbrev{$tokens[$i]} ); }
                                                                                
  #*-- pass 1d, check for emoticons
  for my $i (0..$#tokens)
   { next if ($used[$i] =~ m%[a]%);
     next unless ($colloc_lead{$tokens[$i]});
     INNER: for my $j (reverse $i+1..$i+10)
      { next unless ($tokens[$j]); 
        my $e_icon = join('', @tokens[$i..$j]);
        if ( $e_icons{$e_icon} )
         { @used[$i..$j] = ('e') x ($j - $i + 1); last INNER; } 
      } #*-- end of inner for
   }

  #*-- pass 2, combine words with '/+&_ or - between
  for my $i (0..($#tokens-1) )
   { @used[$i-1..$i+1] = ('b','b','b')
        if ($i && ($tokens[$i] =~ m%['/+&_-]%) &&
            ($tokens[$i-1] =~ m%^\w%) && ($tokens[$i+1] =~ m%^\w%) ); }

  #*-- pass 3, check for IP addresses or site names
  for my $i (0..$#tokens)
   {
    next if ($used[$i] =~ m%[bi]%);

    #*-- check for a numeric IP address
    @used[$i..($i+6)] = ('i') x 7
    if (defined($tokens[$i+6]) 
          && $ipnum->($tokens[$i+0]) && ($tokens[$i+1] eq '.') 
          && $ipnum->($tokens[$i+2]) && ($tokens[$i+3] eq '.') 
          && $ipnum->($tokens[$i+4]) && ($tokens[$i+5] eq '.') 
          && $ipnum->($tokens[$i+6]) );

    #*-- handle alphabetic IP addresses, country codes includes
    #*-- .com, .edu, etc.
    if (defined($tokens[$i-1]) && defined($tokens[$i+1])      && 
        ($tokens[$i] eq '.')   && $c_codes{lc($tokens[$i+1])} && 
        ($tokens[$i-1] =~ /^\w/) )
     { my $j = $i;
       while ( defined($tokens[$j-1]) && ($tokens[$j-1] ne ' ') )
       { @used[$j-1..$i+1] = ('i') x ($i-$j+3); $j--; }
     }

    #*-- check for e-mail addresses
    if ( ($used[$i] eq 'i') && defined($tokens[$i-2]) 
         && ($tokens[$i-1] eq '@') )
     {
      my $j = $i-1;
      while ( defined($tokens[$j-1]) && ($tokens[$j-1] ne ' ') )
       { @used[$j-1..$i-1] = ('i') x ($i-$j+1); $j--; }
     }
    
    #*-- check for an URL (http or ftp)
    local $" = '';
    if ( $i_protocol{lc($tokens[$i])} && defined($tokens[$i+3]) &&
         ("@tokens[$i+1..$i+3]" eq '://') )
     { @used[$i..$i+3] = ('i') x 4; my $j = $i + 4;
       $used[$j++] = 'i' while ($tokens[$j] && ($tokens[$j] ne ' ') ); }
   }
  
  #*-- pass 4, build the number tokens
  for my $i (0..$#tokens)
   { 
    #*-- a number followed by percent sign
    if (defined($tokens[$i-1]) && $used[$i-1] eq 'n' && ($tokens[$i] eq '%'))
     { $used[$i] = 'n'; next; }
    next unless ( ($tokens[$i] =~ /^\d+$/) && ($used[$i] !~ /[abein]/) );
    $used[$i] = 'n';

    #*-- handle optional leading sign
    $used[$i-1] = 'n' if ($tokens[$i-1] =~ /^[+-]$/);

    #*-- handle numbers with embedded commas
    my $j = $i+1;
    while (defined($tokens[$j]) && defined($tokens[$j+1]) && 
           ($tokens[$j] eq ',') && ($tokens[$j+1] =~ /^\d+$/) )
     { @used[$j..$j+1] = ('n', 'n'); $j += 2; }
    
    #*-- handle decimal numbers
    @used[$i+1,$i+2] = ('n','n')
      if (defined($tokens[$i+2]) && ($tokens[$i+1] =~ /[.]/) && 
                           ($tokens[$i+2] =~ /^\d+$/) );

    #*-- handle unsigned exponent
    @used[($i+1),($i+2)] = ('n','n')
      if ( defined($tokens[$i+2]) && ($tokens[$i+1] eq '.') && 
           ($tokens[$i+2] =~ /^\d+[Ee]\d+$/) );

    #*-- handle signed exponent
    @used[($i+1)..($i+4)] = ('n') x 4
      if ( defined($tokens[$i+4]) && ($tokens[$i+1] eq '.') && 
           ($tokens[$i+2] =~ /^\d+[Ee]$/) && ($tokens[$i+3] =~ /^[+-]$/) && 
           ($tokens[$i+4] =~ /^\d+$/) );

   } #*-- end of for
  
  #*-- pass 5, check for collocation words
  for my $i (0..($#tokens-1))
   {
    #*-- skip internet and collocation tokens
    next if ($used[$i] =~ /[abice]/); 
    my $l_token = lc($tokens[$i]);
    next unless ($l_token && $colloc_lead{$l_token});

    #*-- get the collocation words for this lead word
    #*-- if it is preloaded, then skip DB lookup
    unless ($colloc{$l_token})
     {
      $colloc{$l_token} = ''; my $q_token = $dbh->quote($l_token);
      my $command = "select coc_words from co_colloc where " .
                 "coc_lead_word = $q_token";
      (my $sth, undef) = $dbh->execute_stmt($command);
      while ( (my $words) = $dbh->fetch_row($sth) )
       { $colloc{$l_token} .= "$words "; }
     }

    #*-- try each of the collocation words for a match
    #*-- table format for a collocation is collocation|||number
    #*-- the number is the number of tokens in the collocation
    COLLOC: while ($colloc{$l_token} =~ m%\s?([^|]+)\|\|\|(\d+)%g)
     { 
       my ($collocation, $num_tokens) = ($1, $2);
       local $" = ''; my $end = $i + $num_tokens - 1;

       #*-- check for a match and handle possible cases where
       #*-- a collocation does not exist - e.g. in the Middle East
       #*-- should not create 'in the Middle' 
       next COLLOC unless ($tokens[$end]);

       #*-- build a list of candidate collocations
       my @l_colloc;
       push (@l_colloc, lc("@tokens[$i..$end]") );

       #*-- optionally handle cases like venetian blind and venetian blinds
       #*-- call to base_words slows down the token assembly, while
       #*-- calling stem may introduce errors such as put one becoming put on
       if ($base_w)
        { my %b_words = &base_words($tokens[$end], $dbh);
          foreach (keys %b_words)
           { push (@l_colloc, lc("@tokens[$i..$end-1]") . $_); }
        }

       foreach my $t_colloc (@l_colloc)
        {
         if ($t_colloc eq $collocation ) 
           { next COLLOC if ( ("@tokens[$i..$end]" =~ /^[a-z]/) && 
                              ("@tokens[$i..$end]" =~ / [A-Z]/) );
             #*-- zap combined tokens from pass 2 that have a collocation
             if ("@used[$i..$end]" =~ /[b]/) 
              { my $j = $end + 1; $used[$j++] = 'x' while ($used[$j] eq 'b'); }
              @used[$i..$end] = ('c') x $num_tokens;
           } #*-- end of if
        } #*-- end of for

     } #*-- end of while
    
   } #*-- end of for

  #*-- pass 6, build the new token list
  my @n_tokens = my @n_end = my @n_type = (); my $i = 0;
  do
   { 
    #*-- skip space tokens
    if ($tokens[$i] =~ /^\s$/) { $i++; } 

    #*-- check for punctuation tokens
    elsif ($used[$i] eq 'x')
     { push (@n_tokens, "$tokens[$i]"); push(@n_end, $end[$i]); 
       push (@n_type, ($tokens[$i] =~ /^[$PCHAR]$/) ? 'u': 'x'); $i++; }

    #*-- collapse consecutive tokens of the same type into a single token
    else
     { 
      my $new_token = ''; my $t_type = $used[$i];
      while ( ($i <= $#tokens) && ($used[$i] eq $t_type) ) 
         { $new_token .= $tokens[$i]; $i++; }

      #*-- expand short forms if requested
      my $created = 0;
      if ($expand)
       { 
        my %sforms = &bld_sform_table();
        SFORM: foreach my $sform (keys %sforms)
         { if ( (my $prefix_w) = $new_token =~ /^(.*)$sform$/)
            { $prefix_w = 'are' if ($prefix_w =~ /ai/);
              push (@n_tokens, $prefix_w); push(@n_end, $end[$i-1]);
              push (@n_type, $t_type);  
              push (@n_tokens, "$sforms{$sform}"); push(@n_end, $end[$i-1]);
              push (@n_type, $t_type); $created++; last SFORM; 
            } 
         } #*-- end of for
       } #*-- end of inner if

      unless ($created)
       { push (@n_tokens, "$new_token"); push(@n_end, $end[$i-1]);
         push (@n_type, $t_type); } 
     } #*-- end of outer if
   }
  while ($i <= $#tokens);

  #*-- return the tokens, end locations in text, and the type lists
  return(\@n_tokens, \@n_end, \@n_type);

 }

 #*---------------------------------------------------------
 #*-  Porter's stemming algorithm
 #*-  copied 'as is' from the Web
 #*-  Author: Ian Phillipps <ian@unipalm.pipex.com>
 #*---------------------------------------------------------

 sub stem
  {
   my @parms = @_;
   foreach( @parms )
    {
        $_ = lc $_;

        # Step 0 - remove punctuation
        s/'s$//; s/^[^a-z]+//; s/[^a-z]+$//;
        next unless /^[a-z]+$/;

        # step1a_rules
        if( /[^s]s$/ ) { s/sses$/ss/ || s/ies$/i/ || s/s$// }

        # step1b_rules. The business with rule==106 is embedded in the
        # boolean expressions here.
        (/[aeiouy][^aeiouy].*eed$/ && s/eed$/ee/ ) ||
            ( s/([aeiou].*)ed$/$1/ || s/([aeiouy].*)ing$/$1/ ) &&
            ( # step1b1_rules
                s/at$/ate/ || s/bl$/ble/ || s/iz$/ize/ || s/bb$/b/ ||
                s/dd$/d/   || s/ff$/f/   || s/gg$/g/   || s/mm$/m/ ||
                s/nn$/n/   || s/pp$/p/   || s/rr$/r/   || s/tt$/t/ ||
                s/ww$/w/   || s/xx$/x/   ||
                # This is wordsize==1 && CVC...addanE...
                s/^[^aeiouy]+[aeiouy][^aeiouy]$/$&e/
            );
        # step1c_rules
        s/([aeiouy].*)y$/$1i/;

        # step2_rules

        if (    s/ational$/ate/ || s/tional$/tion/ || s/enci$/ence/     ||
                s/anci$/ance/   || s/izer$/ize/    || s/iser$/ise/      ||
                s/abli$/able/   || s/alli$/al/     || s/entli$/ent/     ||
                s/eli$/e/       || s/ousli$/ous/   || s/ization$/ize/   ||
                s/isation$/ise/ || s/ation$/ate/   || s/ator$/ate/      ||
                s/alism$/al/    || s/iveness$/ive/ || s/fulnes$/ful/    ||
                s/ousness$/ous/ || s/aliti$/al/    || s/iviti$/ive/     ||
                s/biliti$/ble/
            ) {
            my ($l,$m) = ($`,$&);
            $_ = $l.$m unless $l =~ /[^aeiou][aeiouy]/;
        }
        # step3_rules
        if (    s/icate$/ic/    || s/ative$//   || s/alize$/al/ ||
                s/iciti$/ic/    || s/ical$/ic/  || s/ful$//     ||
                s/ness$//
            ) {
            my ($l,$m) = ($`,$&);
            $_ = $l.$m unless $l =~ /[^aeiou][aeiouy]/;
        }

        # step4_rules
        if (    s/al$//    || s/ance$// || s/ence$//    || s/er$//      ||
                s/ic$//    || s/able$// || s/ible$//    || s/ant$//     ||
                s/ement$// || s/ment$// || s/ent$//     || s/sion$/s/   ||
                s/tion$/t/ || s/ou$//   || s/ism$//     || s/ate$//     ||
                s/iti$//   || s/ous$//  || s/ive$//     || s/ize$//     ||
                s/ise$//
            ) {
            my ($l,$m) = ($`,$&);
        # Look for two consonant/vowel transitions
        # NB simplified...
            $_ = $l.$m unless $l =~ /[^aeiou][aeiouy].*[^aeiou][aeiouy]/;
        }

        # step5a_rules
        s/e$// if ( /[^aeiou][aeiouy].*[^aeiou][aeiouy].*e$/ ||
          ( /[aeiou][^aeiouy].*e/ && ! /[^aeiou][aeiouy][^aeiouwxy]e$/) );

        # step5b_rules
        s/ll$/l/ if /[^aeiou][aeiouy].*[^aeiou][aeiouy].*ll$/;

        # Cosmetic step
        s/(.)i$/$1y/;
    }
    \@parms;
 }

 #*---------------------------------------------
 #*- build the stopwords based on the types
 #*---------------------------------------------
 sub build_stopwords
 {
  my ($stopwords, $ftypes) = @_;

  $ftypes = '' unless ($ftypes);
  &build_common_stopwords($stopwords);
  foreach (split/\s+/, $ftypes)
   { &build_web_stopwords($stopwords)   if /web/;
     &build_news_stopwords($stopwords)  if /news/;
     &build_email_stopwords($stopwords) if /email/; }
 }

 #*---------------------------------------------
 #*- build the list of web stop words
 #*---------------------------------------------
 sub build_web_stopwords
 {
  my ($stopwords) = @_;
  foreach ( qw/
        address adobe background book com edu foreground net org spam www
        net ftp jpeg gif jpg png web gmt htm html bin com
    / ) { $$stopwords{$_}++; }
 }


 #*---------------------------------------------
 #*- build the list of news stop words
 #*---------------------------------------------
 sub build_news_stopwords
 {
  my ($stopwords) = @_;
  foreach ( qw/
        reuters ap iht upi
    / ) { $$stopwords{$_}++; }
 }

 #*---------------------------------------------
 #*- build the list of email stop words
 #*---------------------------------------------
 sub build_email_stopwords
 {
  my ($stopwords) = @_;
  foreach ( qw/
        address book spam fyi acknowledge
    / ) { $$stopwords{$_}++; }
 }

 #*---------------------------------------------
 #*- build the list of common stop words
 #*---------------------------------------------
 sub build_common_stopwords
 {
  my ($stopwords) = @_;
  foreach ( qw/
        about add ago after all also an and another any are as at be
        because been before being between big both but by came can come
        could did do does due each else end far few for from get got had
        has have he her here him himself his how if in into is it its
        just let lie like low make many me might more most much must
        my never no nor not now of off old on only or other our out over
        per pre put re said same see she should since so some still such
        take than that the their them then there these they this those
        through to too under up use very via want was way we well were
        what when where which while who will with would yes yet you your
    / ) { $$stopwords{$_}++; }
 }

 #*------------------------------------------
 #*- build the short form table
 #*------------------------------------------
 sub bld_sform_table
 {
  my %sform_tab = ( 'n\'t' => 'not',
               '\'nt' => 'not',
               '\'d' => 'would',
               '\'ll' => 'will',
               '\'ve' => 'have',
               '\'m' => 'am',
               '\'re' => 'are');
  return (%sform_tab);
 }

1; #return true 
=head1 NAME

Tokens - TextMine Tokens Extractor

=head1 SYNOPSIS

use TextMine::Tokens;

=head1 DESCRIPTION

=head2 tokens

  Extract the basic tokens from the passed text. A token is
  either a space, consecutive alphanumeric characters, or
  a non-alphanumeric character. Consecutive spaces are
  collapsed into a single space.

=head2 build_stopwords

  Pass the type of text (email, news, web or null) and get a
  hash of the stopwords for the type.

=head2 assemble_tokens

  Receive text and return a list of tokens, end locations of
  tokens in the text, and the type of tokens,

  Type		Description
   a		abbreviation
   b		combined
   c		collocation
   e		emoticon
   i		internet
   n		number
   u		punctuation
   x		unknown
   
=head1 EXAMPLE

  $text = <<"EOT";
Jaguar is about to sell its new XJ-6 model in the U.S.
and expects an 11 pct growth to 830.4 mln
(check into www.jaguar.com or contact myname\@jaguar.com 703-555-1111 ::-) )
EOT

  ($r1, $r2, $r3) = &assemble_tokens(\$text, $dbh);
  @r1 = @$r1; @r3 = @$r3;
  for my $i (0..$#r1)
   { print "$r1[$i]\t$r3[$i]\n"; }

 generates the following output
 ----------------------------------------------------------------
 Jaguar                  x
 is                      x
 about                   x
 to                      x
 sell                    x
 its                     x
 new                     x
 XJ-6                    b
 model                   x
 in                      x
 the                     x
 U.S.                    c
 and                     x
 expects                 x
 an                      x
 11                      n
 pct                     a
 growth                  x
 to                      x
 830.4                   n
 mln                     a
 (                       u
 check into              c
 www.jaguar.com          i
 or                      x
 contact                 x
 myname@jaguar.com       i
 703-555-111		 b
 ::-)                    e
 )                       u
 -------------------------------------------------------------------

=head1 AUTHOR

Manu Konchady <mkonchady@yahoo.com>
