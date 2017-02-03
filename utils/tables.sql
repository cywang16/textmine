
#*--------------------------------------------------------
#*- SQL to create tables and userids
#*- 
#*- Tables are created in the tm database. The database
#*- name can be changed in Constants.pm
#*- Two userids - tmadmin and tmuser are created
#*-
#*-   co_ : Common table for multiple functions
#*-   me_ : Tables for My Search Engine
#*-   ne_ : Tables for News Collection 
#*-   em_ : Tables for E-Mail Archive
#*-   sp_ : Tables for Spider
#*-   wn_ : Tables for WordNet
#*--------------------------------------------------------

connect mysql;

grant select, insert, update, delete on mysql.* to tmadmin@localhost
      identified by 'tmpass';

grant all privileges on tm.* to tmadmin@localhost
      identified by 'tmpass' with grant option;

grant select, insert, update, delete on tm.* to tmuser@localhost
      identified by 'tmpass';

flush privileges;

connect tm;

drop table if exists co_session;
create table co_session (
 sec_session   	char(50) not null primary key unique,
 sec_userid     char(50) not null,
 sei_expiry    	integer unsigned,
 sec_data  	text
 );

drop table if exists co_code_subs;
create table co_code_subs (
 coi_sid	integer not null primary key unique auto_increment,
 coc_dir   	char(255) not null,
 coc_file   	char(255) not null,
 coc_sub        char(255) not null,
 coc_calls_to   text,
 coc_calls_from text
 );

drop table  if exists co_org;
create table co_org (
 enc_name               char(100) not null primary key unique,
 enc_type               char(50),
 enc_description        char(50)
 );

drop table  if exists co_place;
create table co_place (
 enc_name               char(100) not null,
 enc_type               char(50)  not null,
 enc_description        char(50),
 unique index (enc_name, enc_type)
 );

drop table if exists co_person;
create table co_person (
 enc_name               char(100) not null primary key unique,
 enc_type               char(50),
 enc_description        char(50)
 );

drop table  if exists co_entity;
create table co_entity (
 enc_name               char(100) not null,
 enc_type               char(50),
 enc_description        char(50),
 unique index (enc_name, enc_type)
 );

drop table if exists co_colloc_lead;
create table co_colloc_lead (
 coc_lead_words         char(255) not null
 );

drop table if exists co_colloc;
create table co_colloc (
 coc_lead_word          char(30) not null,
 coc_words              char(255) not null,
 index co_colloc_ix (coc_lead_word)
 );

drop table if exists co_abbrev;
create table co_abbrev (
 enc_name               char(100) not null,
 enc_type               char(50),
 enc_description        char(50),
 index co_abbrev_ix (enc_name)
 );

drop table if exists co_proctab;
create table co_proctab (
 pri_tid   	integer unsigned not null primary key unique,
 pri_start_time integer unsigned not null,
 prc_status    	char(255),
 prc_sub_tid  	char(255),
 prc_logdata  	text
 );

drop table if exists co_rulepos;
create table co_rulepos (
 ruc_type	char(5) not null,
 rui_frequency  float,
 ruc_wtag       char(5) not null,
 ruc_part1      char(15) not null,
 ruc_part2      char(15),
 unique index ru_pos_ix (ruc_type, ruc_part1, ruc_part2)
 );

drop table if exists co_ruleent;
create table co_ruleent (
 ruc_feature  	char(100) not null primary key unique,
 rui_place	float not null,
 rui_person	float not null,
 rui_org	float not null,
 rui_time	float not null,
 rui_dimension	float not null,
 rui_currency	float not null,
 rui_miscellaneous float not null,
 rui_number	float not null,
 rui_tech	float not null
 );

drop table if exists em_abook_home;
create table em_abook_home (
 abc_identity  		char(100) not null primary key unique,
 abc_email    		char(255) not null,
 abc_name		char(100),
 abc_notes	 	text,
 abc_public_key		text,
 abc_private_key 	text,
 abc_signature 		text,
 abc_keywords 	 	text
 );

drop table if exists em_abook;
create table em_abook (
 abc_identity     	char(100) not null primary key unique,
 abc_email     		char(255) not null,
 abc_name      		char(100),
 abc_notes 		text,
 abc_public_key  	text 
 );

drop table if exists em_category;
create table em_category (
 emi_catid		integer not null primary key unique auto_increment,
 emi_level     		integer not null,
 emi_text_size		integer not null,
 emi_parent		integer not null,
 emc_end_train 		ENUM ('Y', ' '),
 emc_catname		char(255),
 emc_descr		char(255),
 emc_centroid		text
 );

drop table if exists em_dlist;
create table em_dlist (
 dlc_name		char(100) not null primary key unique,
 dlc_description	char(255)
 );

drop table if exists em_dlist_abook;
create table em_dlist_abook (
 dlc_name	char(100) not null,
 dlc_identity	char(100) not null,
 primary key (dlc_name, dlc_identity)
 );

drop table if exists em_email;
create table em_email (
 emi_id		integer not null primary key unique auto_increment,
 emi_date	integer unsigned not null,
 emi_catid	integer unsigned not null,
 emc_dflag	ENUM ('D', ' '),
 emc_status     char(10),
 emc_subject	char(255),
 emc_digest	char(255),
 emc_from	char(255),
 emc_to		text,
 emc_cc		text,
 emc_text	text
 );

drop table if exists em_index;
create table em_index (
 inc_word	char(100) not null,
 inc_ids	char(255),
 index em_index_ix (inc_word)
 #fulltext       (inc_word)
 );

drop table if exists em_network;
create table em_network (
 nec_from	char(100) not null,
 nec_from_name	char(100),
 nec_to		char(100) not null, 
 nec_to_name	char(100),
 nei_count	integer not null,
 primary key (nec_from, nec_to)
 );

drop table if exists em_worklist;
create table em_worklist (
 emi_id		integer not null primary key unique auto_increment,
 emi_date	integer unsigned not null,
 emc_type	ENUM ('Receive', 'Send') not null default 'Receive',
 emc_period	ENUM ('Weekly', 'Monthly', 'Annual', 'Once') 
                      not null default 'Once',
 emc_address	char(255),
 emc_descr	char(255)
 );

drop table if exists me_list;
create table me_list (
 lii_id        		integer not null primary key unique auto_increment,
 lii_date      		integer unsigned not null,
 lic_file      		char(255),
 lic_description  	text,
 lic_signature 		char(255)
 );

drop table if exists me_index;
create table me_index (
 inc_word	char(50) not null,
 inc_ids	char(255),
 index me_index_ix (inc_word)
 #fulltext       (inc_word)
 );

drop table if exists ne_clusters;
create table ne_clusters (
 nei_cid	integer not null primary key unique auto_increment,
 nei_size	integer not null,
 nec_members	char(255),
 nec_title	char(255)
 );

drop table if exists ne_index;
create table ne_index (
 inc_word	char(100) not null,
 inc_ids	char(255),
 index ne_index_ix (inc_word)
 #fulltext       (inc_word)
 );
 
drop table if exists ne_sources;
create table ne_sources (
 nei_nid		integer not null primary key unique auto_increment,
 nec_get_images		ENUM ('y', 'n') not null default 'n',
 nec_status		char(255),
 nec_description	char(255),
 nec_url		char(255),
 nec_match_condition	char(255)
 );

drop table if exists ne_articles;
create table ne_articles (
 nei_nid		integer not null primary key unique auto_increment,
 nei_size		integer not null,
 nei_cdate		integer,
 nec_status		char(255),
 nec_url		char(255),
 nec_local_url		char(255),
 nec_similar_ids	char(255),
 nec_abstract		text,
 nec_text		text
 );

drop table if exists qu_categories;
create table qu_categories (
 qui_catid 	 integer not null primary key unique auto_increment,
 quc_ans_ents	 text,
 quc_que_phrases text,
 quc_cat_terms   text,
 quc_iwords	 text,
 quc_inouns	 text,
 quc_vector      text,
 quc_weights	 text
 );

drop table if exists qu_perlfaq;
create table qu_perlfaq (
 qui_qid	integer not null primary key unique auto_increment,
 quc_sim_ids	char(255),
 quc_question   text,
 quc_answer     text,
 quc_inouns	text,
 quc_iwords	text,
 quc_iphrases	text,
 quc_vector     text
 );

drop table if exists sp_robots;
create table sp_robots (
 spc_site       char(255) not null primary key unique,
 spc_robots_txt text
 );

drop table if exists sp_images;
create table sp_images (
 spi_id        		integer not null,
 spc_local_file         char(255) not null,
 spc_remote_url		char(255) not null
 );


drop table if exists sp_search;
create table sp_search (
 spi_id        		integer not null unique auto_increment,
 spi_date     		integer unsigned,
 spi_url_limit   	integer,
 spi_url_count   	integer,
 spi_url_timeout   	integer,
 spi_spiders   		integer,
 spi_maxsite_urls   	integer,
 spi_time_limit   	integer,
 spi_level_limit   	integer,
 spi_directory_limit   	integer,
 spc_search_type   	ENUM ('Breadth', 'Depth') not null default 'Breadth',
 spc_get_images   	ENUM ('Yes', 'No') not null default 'No',
 spc_recompute   	ENUM ('Yes', 'No') not null default 'No',
 spc_status   		char(10),
 spc_descr   		char(255) not null primary key,
 spc_match_condition   	char(255) not null,
 spc_keywords   	char(255) not null,
 spc_priority_domain   	char(255) not null,
 spc_link_file   	char(255) not null,
 spc_results_dir   	char(255) not null,
 spc_blocked_sites   	text,
 spc_selected_sites   	text
 );

drop table if exists wn_exc_words;
create table wn_exc_words (
 wnc_excl_word               char(50) not null,
 wnc_base_word               char(50) not null,
 wnc_type                    char(1) not null,
 unique (wnc_excl_word, wnc_type)
 );

drop table if exists wn_words_a_b;
create table wn_words_a_b (
 wnc_word		char(35) not null,
 wnc_pos		char(1) not null,
 wnc_etype   		ENUM ('y', 'n') not null default 'n',
 wnc_synsets		text,
 unique (wnc_word, wnc_pos)
 );

drop table if exists wn_words_c_d;
create table wn_words_c_d (
 wnc_word		char(35) not null,
 wnc_pos		char(1) not null,
 wnc_etype   		ENUM ('y', 'n') not null default 'n',
 wnc_synsets		text,
 unique (wnc_word, wnc_pos)
 );

drop table if exists wn_words_e_g;
create table wn_words_e_g (
 wnc_word		char(35) not null,
 wnc_pos		char(1) not null,
 wnc_etype   		ENUM ('y', 'n') not null default 'n',
 wnc_synsets		text,
 unique (wnc_word, wnc_pos)
 );

drop table if exists wn_words_h_l;
create table wn_words_h_l (
 wnc_word		char(35) not null,
 wnc_pos		char(1) not null,
 wnc_etype   		ENUM ('y', 'n') not null default 'n',
 wnc_synsets		text,
 unique (wnc_word, wnc_pos)
 );

drop table if exists wn_words_m_p;
create table wn_words_m_p (
 wnc_word		char(35) not null,
 wnc_pos		char(1) not null,
 wnc_etype   		ENUM ('y', 'n') not null default 'n',
 wnc_synsets		text,
 unique (wnc_word, wnc_pos)
 );

drop table if exists wn_words_q_s;
create table wn_words_q_s (
 wnc_word		char(35) not null,
 wnc_pos		char(1) not null,
 wnc_etype   		ENUM ('y', 'n') not null default 'n',
 wnc_synsets		text,
 unique (wnc_word, wnc_pos)
 );

drop table if exists wn_words_t_z;
create table wn_words_t_z (
 wnc_word		char(35) not null,
 wnc_pos		char(1) not null,
 wnc_etype   		ENUM ('y', 'n') not null default 'n',
 wnc_synsets		text,
 unique (wnc_word, wnc_pos)
 );

drop table if exists wn_words_rel;
create table wn_words_rel (
 wnc_word_a		char(35) not null,
 wnc_word_b		char(35) not null,
 wnc_rel		char(35),
 unique (wnc_word_a, wnc_word_b, wnc_rel)
 );

drop table if exists wn_synsets;
create table wn_synsets (
 wnc_synset		char(9) not null,
 wnc_words		text not null,
 wnc_gloss		text,
 index wn_synsets_ix (wnc_synset)
 );

drop table if exists wn_synsets_rel;
create table wn_synsets_rel (
 wnc_synset_a		char(9) not null,
 wnc_synset_b		char(9) not null,
 wnc_rel		char(35),
 unique (wnc_synset_a, wnc_synset_b)
 );

drop table if exists wn_words_all;
create table wn_words_all (
 wnc_start_letters	char(2) not null,
 wnc_end_letters	char(2) not null,
 wnc_words		char(255) not null,
 index wn_words_all_ix (wnc_start_letters, wnc_end_letters)
 );
