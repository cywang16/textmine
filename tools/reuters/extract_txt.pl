#!/usr/bin/perl
 use lib ("/home/manuk/textmine-0.2/");

 #*----------------------------------------------------------------
 #*- extract_txt.pl
 #*-   Extract documents based on entities 
 #*-   Reuters collection
 #*----------------------------------------------------------------
 use strict; use warnings;
 use TextMine::DbCall;
 use TextMine::Constants;
 use TextMine::WordUtil qw/text_split/;

 #*-- get a database handle
 my ($dbh, undef) = TextMine::DbCall->new ( 'Host' => '',
   'Userid' => 'tmadmin', 'Password' => 'tmpass', 'Dbname' => $DB_NAME);

 #*-- read the code, description and type
 my %descr = ();
 while (my $text = <DATA>)
  { chomp($text);
    my ($code, $descr) = split/!!!/, $text; $descr{lc($code)} = $descr; }
   
 #*-- build the file list
 my @files = qw/reut2-000.sgm reut2-001.sgm reut2-002.sgm reut2-003.sgm
             reut2-004.sgm reut2-005.sgm reut2-006.sgm reut2-007.sgm
             reut2-008.sgm reut2-009.sgm reut2-010.sgm reut2-011.sgm 
             reut2-012.sgm reut2-013.sgm reut2-014.sgm reut2-015.sgm
             reut2-016.sgm reut2-017.sgm reut2-018.sgm reut2-019.sgm
             reut2-020.sgm reut2-021.sgm/;

 my $num_files = 0;
 open (OUT, ">r_train.txt") || die ("Unable to open r_train.txt $!");
 binmode OUT, ":raw";
 foreach my $file (@files)
  {
   print ("processing $file....\n");
   #*-- read the file into text
   open (IN, $file) || die ("Could not open $file $!\n");
   undef($/); my $text = <IN>; close(IN);

   my @tagged_s = (); 
   while ($text =~ m%.*?(<PLACES>.*?</ORGS>).*?<BODY>(.*?)</BODY>%sgi)
    {
     #*-- get the codes for the entities in the article
     my ($tags, $body) = ($1, $2); my %codes = ();
     foreach my $etype (qw/PLACES PEOPLE ORGS/)
      {
       if ( ($tags =~ m%<$etype>(.*?)</$etype>%i) && $1)
        { my $code = lc($1);
          while ($code =~ m%<D>(.*?)</D>%isg) 
           { next if ($1 eq 'usa'); $codes{$1} = $etype; }
        }
      }
     next unless (scalar keys %codes); #*-- skip articles w/o entities

     #*-- split the text into sentences
     my ($rloc, undef) = &text_split(\$body, '', $dbh);
     my @sentences = ();
     for my $i (0..(@$rloc - 1))
      { my $start = $i ? ($$rloc[$i-1] + 1): 0; my $end = $$rloc[$i];
        my $ctext = substr($body, $start, $end - $start + 1);
        push (@sentences, \"$ctext"); }

     #*-- build the match patterns from the codes
     my %patterns = ();
     foreach my $code (keys %codes)
      { next unless($descr{$code});
        $patterns{$descr{$code}} = $codes{$code};
        next unless ($codes{$code} eq 'PEOPLE');
        foreach (split/\s+/, $descr{$code}) {$patterns{$_} = $codes{$code}; }
      }

     #*-- tag the entities in the sentences
     foreach my $sentence (@sentences)
      {
       #*-- check for a pattern match in the sentence
       PATT: foreach my $patt 
             (sort {length($b) <=> length($a)} keys %patterns)
        {
         (my $qpatt = $patt) =~ s/ /\\s/g;
         if ( $$sentence =~ s%\b$qpatt\b%
              <$patterns{$patt}>$patt</$patterns{$patt}>%xig)
            { push(@tagged_s, $$sentence); last PATT; } }
      } #*-- end of outer for
    } #*-- end of while
 
   #*-- dump the tagged sentences
   foreach my $sentence (@tagged_s)
   {
    $sentence =~ s/^\s+//; $sentence =~ s/\s+$//;
    $sentence =~ s/\n/ /g; $sentence =~ s/\s+/ /g;
    $sentence =~ s/PLACES>/PLACE>/g; $sentence =~ s/PEOPLE>/PERSON>/g;
    $sentence =~ s/ORGS>/ORG>/g;
    print OUT ("$sentence\n");
   }
   last if (++$num_files == 10);
  } #*-- end of foreach files...
 close(OUT);

 $dbh->disconnect_db();
 exit(0);

#*---------------------------------------------------
#*- the code table follows
#*-   Code	Description
#*---------------------------------------------------

__DATA__
ABDEL-HADI-KANDEEL!!!Abdel-Hadi Kandeel
ADB-AFRICA!!!African Development Bank
ADB-ASIA!!!Asian Development Bank 
AFGHANISTAN!!!Afghanistan
AIBD!!!Association of International Bond Dealers
AID!!!Agency for International Development 
ALBANIA!!!Albania
ALFONSIN!!!Raul Alfonsin
ALGERIA!!!Algeria
ALHAJI-ABDUL-AHMED!!!Alhaji Abdul Ahmed
ALPTEMOCIN!!!Ahmet Kurtcebe Alptemocin
AMATO!!!Guiliano Amato
AMERICAN-SAMOA!!!American-samoa
ANDERSEN!!!Anders Andersen
ANDORRA!!!Andorra
ANDRIESSEN!!!Frans Andriessen
ANGOLA!!!Angola
ANGUILLA!!!Anguilla
ANRPC!!!Association of Natural Rubber Producing Countries
ANTIGUA!!!Antigua
AQAZADEH!!!Gholamreza Aqazadeh
AQUINO!!!Corazon Aquino
ARAFAT!!!Yasser Arafat
ARGENTINA!!!Argentina
ARUBA!!!Aruba
ASEAN!!!Association of South East Asian Nations
ATPC!!!Association of Tin Producing Countries
AUSTDLR!!!Dollar
AUSTRAL!!!Austral
AUSTRALIA!!!Australia
AUSTRIA!!!Austria
BABANGIDA!!!Ibrahim Babangida
BAHAMAS!!!Bahamas
BAHRAIN!!!Bahrain
BALLADUR!!!Edouard Balladur
BANGEMANN!!!Martin Bangemann
BANGLADESH!!!Bangladesh
BARBADOS!!!Barbados
BARRETO!!!Alvaro Barreto
BELGIUM!!!Belgium
BELIZE!!!Belize
BENIN!!!Benin
BERGE!!!Gunnar Berge
BERMUDA!!!Bermuda
BETETA!!!Ramon Beteta
BFR!!!Franc
BHUTAN!!!Bhutan
BIS!!!Bank for International Settlements
BLIX!!!Hans Blix
BOESKY!!!Ivan Boesky
BOLIVIA!!!Bolivia
BOND!!!Alan Bond
BOTHA!!!P.W. Botha
BOTSWANA!!!Botswana
BOUEY!!!Gerald K. Bouey
BRAKS!!!Gerrit Braks
BRAZIL!!!Brazil
BRESSER-PEREIRA!!!Luiz Carlos Bresser Pereira
BRITISH-VIRGIN-ISLANDS!!!British-virgin-islands
BRODERSOHN!!!Mario Brodersohn
BRUNDTLAND!!!Gro Harlem Brundtland
BRUNEI!!!Brunei
BULGARIA!!!Bulgaria
BURKINA-FASO!!!Burkina-faso
BURMA!!!Burma
BURUNDI!!!Burundi
Bob) Hawke (HAWKE!!!Robert
CAMDESSUS!!!Michel Camdessus
CAMEROON!!!Cameroon
CAN!!!Dollar
CANADA!!!Canada
CAPE-VERDE!!!Cape-verde
CARLSSON!!!Ingvar Carlsson
CARO!!!Manuel Romero Caro
CASTELO-BRANCO!!!Jose Hugo Castelo Branco
CASTRO!!!Fidel Castro
CAVACO-SILVA!!!Anibal Cavaco Silva
CAYMAN-ISLANDS!!!Cayman-islands
CENTRAL-AFRICAN-REPUBLIC!!!Central-african-republic
CHAD!!!Chad
CHAVES!!!Aureliano Chaves
CHIANG-CHING-KUO!!!Chiang Ching-kuo
CHIEN!!!Robert Chien
CHILE!!!Chile
CHINA!!!China
CHIRAC!!!Jacques Chirac
CIAMPI!!!Carlo Ciampi
CIPEC!!!Inter-Government Council of Copper Exporting Countries
COLOMBIA!!!Colombia
COLOMBO!!!Emilio Colombo
COMECON!!!Council for Mutual Economic Assistance
CONABLE!!!Barber Conable
CONCEPCION!!!Jose Concepcion
CONGO!!!Congo
CORRIGAN!!!Gerald Corrigan
COSSIGA!!!Francesco Cossiga
COSTA-RICA!!!Costa-rica
CROW!!!John Crow
CRUZADO!!!Cruzado
CUBA!!!Cuba
CYPRUS!!!Cyprus
CZECHOSLOVAKIA!!!Czechoslovakia
DADZIE!!!Kenneth Dadzie
DAUSTER!!!Jorio Dauster
DE-CLERCQ!!!Willy de Clercq
DE-KOCK!!!Gerhard de Kock
DE-KORTE!!!Rudolf De Korte
DE-LA-MADRID!!!Miguel de la Madrid
DE-LAROSIERE!!!Jacques de Larosiere
DEL-MAZO!!!Alfredo Del Mazo
DELAMURAZ!!!Jean-Pascal Delamuraz
DELORS!!!Jacques Delors
DEMENTSEV!!!Viktor Dementsev
DENG-XIAOPING!!!Deng Xiaoping
DENMARK!!!Denmark
DENNIS!!!Bengt Dennis
DFL!!!Guilder Florin
DHILLON!!!Gurdial Singh Dhillon
DJIBOUTI!!!Djibouti
DKR!!!Krone Crown
DLR!!!Dollar
DMK!!!Mark
DOMINGUEZ!!!Carlos Dominguez
DOMINICA!!!Dominica
DOMINICAN-REPUBLIC!!!Dominican-republic
DOUGLAS!!!Roger Douglas
DRACHMA!!!Drachma
DU-PLESSIS!!!Barend du Plessis
DUISENBERG!!!Wim Duisenberg
DUNKEL!!!Arthur Dunkel
EAST-GERMANY!!!East-germany
EC!!!European Community
ECA!!!Economic Commission for Africa
ECAFE!!!Economic Commission for Asia and the Far East
ECE!!!Economic Commission for Europe
ECLA!!!Economic Commission for Latin America and The Caribbean
ECSC!!!European Coal and Steel Community
ECUADOR!!!Ecuador
ECWA!!!Economic Commission for West Asia
EDELMAN!!!Asher Edelman
EFTA!!!European Free Trade Association
EGYPT!!!Egypt
EIB!!!European Investment Bank
EL-SALVADOR!!!El-salvador
EMCF!!!European Monetary Cooperation Fund
ENGGAARD!!!Knud Enggaard
EQUATORIAL-GUINEA!!!Equatorial-guinea
ESCAP!!!Economic and Social Commission for Asia and the Pacific
ESCUDO!!!Escudo
ESER!!!Guenter Eser
ETHIOPIA!!!Ethiopia
EURATOM!!!European Atomic Energy Community
EVREN!!!Kenan Evren
EYSKENS!!!Mark Eyskens
FAO!!!Food and Agriculture Organisation
FELDT!!!Kjell-Olof Feldt
FERNANDEZ!!!Jose Fernandez
FERRARI!!!Cesar Ferrari
FFR!!!Franc
FIJI!!!Fiji
FINLAND!!!Finland
FINNBOGADOTTIR!!!Vigdis Finnbogadottir
FRANCE!!!France
FRENCH-GUIANA!!!French-guiana
FUJIOKA!!!Masao Fujioka
GABON!!!Gabon
GADDAFI!!!Muammar Gaddafi
GAMBIA!!!Gambia
GANDHI!!!Rajiv Gandhi
GARCIA!!!Alan Garcia
GATT!!!General Agreement on Tariffs and Trade
GAVA!!!Antonio Gava
GCC!!!Gulf Cooperation Council
GHANA!!!Ghana
GIBRALTAR!!!Gibraltar
GODEAUX!!!Jean Godeaux
GONZALEZ!!!Felipe Gonzalez
GORBACHEV!!!Mikhail Gorbachev
GORIA!!!Giovanni Goria
GOSTYEV!!!Boris Gostyev
GRAF!!!Robert Graf
GREECE!!!Greece
GREENSPAN!!!Alan Greenspan
GRENADA!!!Grenada
GROMYKO!!!Andrei Gromyko
GROSZ!!!Karoly Grosz
GUADELOUPE!!!Guadeloupe
GUAM!!!Guam
GUATEMALA!!!Guatemala
GUILLAUME!!!Francois Guillaume
GUINEA!!!Guinea
GUINEA-BISSAU!!!Guinea-bissau
GUYANA!!!Guyana
HAITI!!!Haiti
HALIKIAS!!!Dimitris Halikias
HAMAD-SAUD-AL-SAYYARI!!!Hamad Saud al-Sayyari
HANNIBALSSON!!!Jon Baldvin Hannibalsson
HAUGHEY!!!Charles Haughey
HE-KANG!!!He Kang
HERRINGTON!!!John Herrington
HILLERY!!!Patrick Hillery
HISHAM-NAZER) !!!Hisham Nazer
HK!!!Dollar
HOEFNER!!!Ernst Hoefner
HOFFMEYER!!!Erik Hoffmeyer
HOLBERG!!!Britta Schall Holberg
HOLKERI!!!Harri Holkeri
HONDURAS!!!Honduras
HONECKER!!!Erich Honecker
HONG-KONG!!!Hong-kong
HOVMAND!!!Svend Erik Hovmand
HOWARD-BAKER!!!Howard Baker
HUNGARY!!!Hungary
HUSAK!!!Gustav Husak
IAEA!!!International Atomic Energy Authority
IATA!!!International Air Transport Association
ICAHN!!!Carl Icahn
ICCO!!!International Cocoa Organisation
ICELAND!!!Iceland
ICO-COFFEE!!!International Coffee Organisation
ICO-ISLAM!!!Islamic Conference Organisation
IDA!!!International Development Association
IEA!!!International Energy Agency
IISI!!!International Iron and Steel Institute
ILO!!!International Labour Organisation
ILZSG!!!International Lead and Zinc Study Group
IMCO!!!Inter-Governmental Maritime Consultative Organisation
IMF!!!International Monetary Fund
INDIA!!!India
INDONESIA!!!Indonesia
INRO!!!International Natural Rubber Organisation
IRAN!!!Iran
IRAQ!!!Iraq
IRELAND!!!Ireland
IRSG!!!International Rubber Study Group
ISA!!!International Sugar Agreement
ISRAEL!!!Israel
ITALY!!!Italy
ITC!!!International Tin Council
IVORY-COAST!!!Ivory-coast
IWC-WHALE!!!International Whaling Commission
IWC-WHEAT!!!International Wheat Council
IWCC!!!International Wrought Copper Council
IWS!!!International Wool Secretariat
IWTO!!!International Wool Textile Organisation
Ibn Abdulaziz) (KING-FAHD!!!Fahd
JAMAICA!!!Jamaica
JAMES-BAKER!!!James Baker
JAMES-MILLER!!!James Miller
JAPAN!!!Japan
JARUZELSKI!!!Wojciech Jaruzelski
JAYME!!!Vicente Jayme
JOHNSTON!!!Bob Johnston
JORDAN!!!Jordan
KAMINSKY!!!Horst Kaminsky
KAMPUCHEA!!!Kampuchea
KAUFMAN!!!Henry Kaufman
KEATING!!!Paul Keating
KENYA!!!Kenya
KHAMEINI!!!Hojatoleslam Ali Khameini
KHOMEINI!!!Ruhollah Khomeini
KIECHLE!!!Ignaz Kiechle
KOHL!!!Helmut Kohl
KOIVISTO!!!Mauno Koivisto
KONDO!!!Tetsuo Kondo
KOREN!!!Stephan Koren
KULLBERG!!!Rolf Kullberg
KUWAIT!!!Kuwait
LACINA!!!Ferdinand Lacina
LAFTA!!!Latin American Free Trade Association
LANGE!!!David Lange
LANGUETIN!!!Pierre Languetin
LAOS!!!Laos
LAWSON!!!Nigel Lawson
LEBANON!!!Lebanon
LEE-TA-HAI!!!Lee Ta-hai
LEE-TENG-HUI!!!Lee Teng-hui
LEENANON!!!Harn Leenanon
LEITZ!!!Bruno Leitz
LESOTHO!!!Lesotho
LI-PENG!!!Li Peng
LI-XIANNIAN!!!Li Xiannian
LIBERIA!!!Liberia
LIBYA!!!Libya
LIECHTENSTEIN!!!Liechtenstein
LIIKANEN!!!Erkki Liikanen
LIT!!!Lira
LUBBERS!!!Ruud Lubbers
LUKMAN!!!Rilwanu Lukman
LUXEMBOURG!!!Luxembourg
LYNG!!!Richard Lyng
MACAO!!!Macao
MACHINEA!!!Jose Luis Machinea
MACSHARRY!!!Ray MacSharry
MADAGASCAR!!!Madagascar
MALAWI!!!Malawi
MALAYSIA!!!Malaysia
MALHOTRA!!!R.N. Malhotra
MALI!!!Mali
MALTA!!!Malta
MANCERA-AGUAYO!!!Miguel Mancera Aguayo
MARTENS!!!Wilfried Martens
MARTIN!!!Preston Martin
MARTINIQUE!!!Martinique
MASSE!!!Marcel Masse
MAURITANIA!!!Mauritania
MAURITIUS!!!Mauritius
MAXWELL!!!Robert Maxwell
MAYSTADT!!!Philippe Maystadt
MEDGYESSY!!!Peter Medgyessy
MESSNER!!!Zbigniew Messner
MEXICO!!!Mexico
MEXPESO!!!Peso
MFA!!!Multi-Fibres Arrangement
MIKULIC!!!Branko Mikulic
MILLIET!!!Fernando Milliet
MITTERRAND!!!Francois Mitterrand
MIYAZAWA!!!Kiichi Miyazawa
MOHAMMAD-IBRAHIM-JAFFREY-BALUCH!!!Mohammad Ibrahim Jaffrey Baluch
MOHAMMAD-KHAN-JUNEJO!!!Mohammad Khan Junejo
MOHAMMAD-YASIN-KHAN-WATTOO!!!Mohammad Yasin Khan Wattoo
MOHAMMED-AHMED-AL-RAZAZ!!!Mohammed Ahmed al-Razaz
MOHAMMED-ALI-ABAL-KHAIL!!!Mohammed Ali Abal-Khail
MOHAMMED-SALAHEDDIN-HAMID!!!Mohammed Salaheddin Hamid
MONACO!!!Monaco
MORALES-BERMUDEZ!!!Remigio Morales Bermudez
MOROCCO!!!Morocco
MOUSAVI!!!Mir-Hossein Mousavi
MOYLE!!!Colin Moyle
MOZAMBIQUE!!!Mozambique
MUBARAK!!!Hosni Mubarak
MULRONEY!!!Brian Mulroney
MURDOCH!!!Rupert Murdoch
MUSTAPHA!!!Youssri mustapha
NAKAO!!!Eiichi Nakao
NAKASONE!!!Yasuhiro Nakasone
NAMIBIA!!!Namibia
NASKO!!!Mohammed Gado Nasko
NEMETH!!!Karoly Nemeth
NEPAL!!!Nepal
NETHERLANDS!!!Netherlands
NETHERLANDS-ANTILLES!!!Netherlands-antilles
NEW-CALEDONIA!!!New-caledonia
NEW-ZEALAND!!!New-zealand
NICARAGUA!!!Nicaragua
NIGER!!!Niger
NIGERIA!!!Nigeria
NKR!!!Krone Crown
NOBREGA!!!Mailson Nobrega
NORTH-KOREA!!!North-korea
NORWAY!!!Norway
NZDLR!!!Dollar
O-COFAIGH!!!Tomas O'Cofaigh
O-KENNEDY!!!Michael O'Kennedy
OAPEC!!!Organisation of Arab Petroleum Exporting Countries
OECD!!!Organisation for Economic Cooperation and Development
OEIEN!!!Arne Oeien
OKONGWU!!!Chu Okongwu
OMAN!!!Oman
ONGPIN!!!Jaime Ongpin
OPEC!!!Organisation of Petroleum Exporting Countries
ORTEGA!!!Daniel Ortega
OZAL!!!Turgut Ozal
PAKISTAN!!!Pakistan
PALSSON!!!Thorsteinn Palsson
PANAMA!!!Panama
PANDOLFI!!!Maria Pandolfi
PAPANDREOU!!!Andreas Papandreou
PAPUA-NEW-GUINEA!!!Papua-new-guinea
PARAGUAY!!!Paraguay
PARKINSON!!!Cecil Parkinson
PAYE!!!Jean-Claude Paye
PEMBERTON) !!!Robin Leigh-Pemberton
PEREZ-DE-CUELLAR!!!Javier Perez de Cuellar
PERU!!!Peru
PESETA!!!Peseta
PETRICIOLI!!!Gustavo Petricioli
PHILIPPINES!!!Philippines
PICKENS!!!T. Boone Pickens
POEHL!!!Karl Otto Poehl
POLAND!!!Poland
PORTUGAL!!!Portugal
POTTAKIS!!!Yannis Pottakis
PRAWIRO!!!Radius Prawiro
QASSEMI!!!Majid Qassemi
QATAR!!!Qatar
RAFNAR!!!Jonas G. Rafnar
RAFSANJANI!!!Hojatoleslam Ali Hashemi Rafsanjani
RAND!!!Rand
REAGAN!!!Ronald Reagan
REZENDE!!!Iris Rezende
RIBERIO-CADILHE!!!Miguel Riberio Cadilhe
RICH!!!Marc Rich
RIKANOVIC!!!Svetozar Rikanovic
RINGGIT!!!Ringitt
ROJAS!!!Francisco Rojas
ROMANIA!!!Romania
ROMERO!!!Carlos Romero
ROUMELIOTIS!!!Panayotis Roumeliotis
ROWLAND!!!Roland Rowland
RUBIO!!!Mariano Rubio
RUDER!!!David S. Ruder
RUDING!!!Onno Ruding
RUPIAH!!!Rupiah
RUSSELL!!!Spencer Russell
RWANDA!!!Rwanda
RYZHKOV!!!Nikolai Ryzhkov
SABERBEIN!!!Gustavo Saberbein Chevalier
SALINAS!!!Abel Salinas
SAMOJLIK!!!Bazyli Samojlik
SANTER!!!Jacques Santer
SARACOGLU!!!Rusdu Saracoglu
SARNEY!!!Jose Sarney
SARTZETAKIS!!!Christos Sartzetakis
SATHE!!!Vasant Sathe
SAUDI-ARABIA!!!Saudi-arabia
SAUDRIYAL!!!Riyal
SCHLUETER!!!Poul Schlueter
SEDKI!!!Atef Sedki
SENEGAL!!!Senegal
SEYCHELLES!!!Seychelles
SFR!!!Franc
SIERRA-LEONE!!!Sierra-leone
SIMITIS!!!Kostas Simitis
SIMONSEN!!!Palle Simonsen
SINGAPORE!!!Singapore
SINGDLR!!!Dollar
SINGHASANEH!!!Suthee Singhasaneh
SIREGAR!!!Arifin Siregar
SKAANLAND!!!Hermud Skaanland
SKR!!!Krona Crown
SOARES!!!Mario Soares
SOLCHAGA!!!Carlos Solchaga
SOMALIA!!!Somalia
SOURROUILLE!!!Juan Sourrouille
SOUTH-AFRICA!!!South-africa
SOUTH-KOREA!!!South-korea
SPAIN!!!Spain
SPRINKEL!!!Beryl Sprinkel
SRI-LANKA!!!Sri-lanka
STEEG!!!Helga Steeg
STG!!!Sterling
STICH!!!Otto Stich
STOLTENBERG!!!Gerhard Stoltenberg
STOPH!!!Willi Stoph
STROUGAL!!!Lubomir Strougal
SUBROTO!!!Subroto
SUDAN!!!Sudan
SUHARTO!!!Suharto
SUMITA!!!Satoshi Sumita
SUOMINEN!!!Ilkka Suominen
SURINAME!!!Suriname
SWAZILAND!!!Swaziland
SWEDEN!!!Sweden
SWITZERLAND!!!Switzerland
SYRIA!!!Syria
TAIWAN!!!Taiwan
TAKESHITA!!!Noboru Takeshita
TAMURA!!!Hajime Tamura
TANZANIA!!!Tanzania
TAVARES-MOREIA!!!Jose Tavares Moreia
THAILAND!!!Thailand
THATCHER!!!Margaret Thatcher
TIMAR!!!Matyas Timar
TINSULANONDA!!!Prem Tinsulanonda
TIWARI!!!Narain Dutt Tiwari
TOERNAES!!!Laurits Toernaes
TOGO!!!Togo
TOMAN!!!Miroslav Toman
TONGA!!!Tonga
TRINIDAD-TOBAGO!!!Trinidad-tobago
TSOVOLAS!!!Dimitris Tsovolas
TUNISIA!!!Tunisia
TURKEY!!!Turkey
UAE!!!Uae
UGANDA!!!Uganda
UK!!!Uk
UN!!!United Nations
UNCTAD!!!United Nations Conference on Trade and Development
URUGUAY!!!Uruguay
US-VIRGIN-ISLANDS!!!Us-virgin-islands
USA!!!Usa
USSR!!!Ussr
VANCSA!!!Jenoe Vancsa
VANUATU!!!Vanuatu
VATICAN!!!Vatican
VENEZUELA!!!Venezuela
VENKATARAMAN!!!Ramaswamy Venkataraman
VERA-LA-ROSA!!!Alberto Vera La Rose
VERITY!!!C. William Verity
VIETNAM!!!Vietnam
VILLANYI!!!Miklos Villanyi
VLATKOVIC!!!Dusan Vlatkovic
VOLCKER!!!Paul Volcker
VON-WEIZSAECKER!!!Richard Von Weizsaecker
VRANITZKY!!!Franz Vranitzky
WALDHEIM!!!Kurt Waldheim
WALI!!!Youssri Wali
WALSH!!!Peter Walsh
WANG-BINGQIAN!!!Wang Bingqian
WARDHANA!!!Ali Wardhana
WASIM-AUN-JAFFREY!!!Wasim Aun Jaffrey
WEST-GERMANY!!!West-germany
WESTERN-SAMOA!!!Western-samoa
WHO!!!World Health Organisation
WILSON!!!Michael Wilson
WISE!!!John Wise
WORLDBANK!!!World Bank
YEMEN-ARAB-REPUBLIC!!!Yemen-arab-republic
YEMEN-DEMO-REPUBLIC!!!Yemen-demo-republic
YEN!!!Yen
YEUTTER!!!Clayton Yeutter
YOUNG!!!Young
YU-KUO-HUA!!!Yu Kuo-hua
YUGOSLAVIA!!!Yugoslavia
ZAIRE!!!Zaire
ZAK!!!Jaromir Zak
ZAMBIA!!!Zambia
ZHAO-ZIYANG!!!Zhao Ziyang
ZHENG-TUOBIN!!!Zheng Tuobin
ZIA-UL-HAQ!!!Zia-ul-Haq
ZIMBABWE!!!Zimbabwe
