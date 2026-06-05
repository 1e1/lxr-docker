-- LXR PostgreSQL schema: tables, counters, functions, triggers.
-- The database and role are created by the postgres container, so this
-- only (re)creates tables and is safe on first start and on every full
-- reindex (genxref --reindexall) without dropping the database.

drop table if exists lxr_filenum;
drop table if exists lxr_symnum;
drop table if exists lxr_typenum;

create table lxr_filenum
	( rcd int primary key
	, fid int
	);
insert into lxr_filenum
	(rcd, fid) VALUES (0, 0);

create table lxr_symnum
	( rcd int primary key
	, sid int
	);
insert into lxr_symnum
	(rcd, sid) VALUES (0, 0);

create table lxr_typenum
	( rcd int primary key
	, tid int
	);
insert into lxr_typenum
	(rcd, tid) VALUES (0, 0);


drop table if exists lxr_files cascade;
drop index if exists lxr_filelookup;
drop table if exists lxr_symbols cascade;
drop table if exists lxr_definitions cascade;
drop index if exists lxr_i_definitions;
drop table if exists lxr_releases cascade;
drop table if exists lxr_usages cascade;
drop index if exists lxr_i_usages;
drop table if exists lxr_status cascade;
drop table if exists lxr_langtypes cascade;
drop table if exists lxr_times cascade;
/* Base version of files */
/*	revision:	a VCS generated unique id for this version
				of the file
 */
create table if not exists lxr_files
	( fileid		int   not null primary key -- given by filenum
	, filename		bytea not null
	, revision		bytea not null
	, constraint lxr_uk_files
		unique		(filename, revision)
	);
create index
	lxr_filelookup
	on lxr_files
	using btree (filename);

/* Status of files in the DB */
/*	fileid:		refers to base version
	relcount:	number of releases associated with base version
	indextime:	time when file was parsed for references
	status:		set of bits with the following meaning
		1	declaration have been parsed
		2	references have been processed
	Though this table could be merged with 'files',
	performance is improved with access to a very small item.
 */
create table if not exists lxr_status
	( fileid	int      not null primary key
	, relcount  int
	, indextime int
	, status	smallint not null
	, constraint lxr_fk_sts_file
		foreign key (fileid)
		references lxr_files(fileid)
-- 		on delete cascade
	);

/* The following trigger deletes no longer referenced files
 * (from releases), once status has been deleted so that
 * foreign key constrained has been cleared.
 */
drop function if exists lxr_erasefile();
create function lxr_erasefile()
	returns trigger
	language PLpgSQL
	as $$
		begin
			delete from lxr_files
				where fileid = old.fileid;
			return old;
		end;
	$$;

create trigger lxr_remove_file
	after delete on lxr_status
	for each row
	execute procedure lxr_erasefile();

/* Aliases for files */
/*	A base version may be known under several releaseids
	if it did not change in-between.
	fileid:		refers to base version
	releaseid:	"public" release tag
 */
create table if not exists lxr_releases
	( fileid    int   not null
	, releaseid bytea not null
	, constraint lxr_pk_releases
		primary key	(fileid, releaseid)
	, constraint lxr_fk_rls_fileid
		foreign key (fileid)
		references lxr_files(fileid)
	);

/* The following triggers maintain relcount integrity
 * in status table after insertion/deletion of releases
 */
drop function if exists lxr_increl();
create function lxr_increl()
	returns trigger
	language PLpgSQL
	as $$
		begin
			update lxr_status
				set relcount = relcount + 1
				where fileid = new.fileid;
			return new;
		end;
	$$;

create trigger lxr_add_release
	after insert on lxr_releases
	for each row
	execute procedure lxr_increl();

/* Note: a release is erased only when option --reindexall
 * is given to genxref; it is thus necessary to reset status
 * to cause reindexing, especially if the file is shared by
 * several releases
 */
drop function if exists lxr_decrel();
create function lxr_decrel()
	returns trigger
	language PLpgSQL
	as $$
		begin
			update lxr_status
				set	relcount = relcount - 1
-- 				,	status = 0
				where fileid = old.fileid
				and relcount > 0;
			return old;
		end;
	$$;

create trigger lxr_remove_release
	after delete on lxr_releases
	for each row
	execute procedure lxr_decrel();

/* Types for a language*/
/*	declaration:	provided by generic.conf
 */
create table if not exists lxr_langtypes
	( typeid		smallint     not null -- given by typenum
	, langid		smallint     not null
	, declaration	varchar(255) not null
	, constraint lxr_pk_langtypes
		primary key	(typeid, langid)
	);

/* Symbol name dictionary */
/*	symid:		unique symbol id for name
	symcount:	number of definitions and usages for this name
	symname:	symbol name
 */
create table if not exists lxr_symbols
	( symid		int   not null primary key -- given by symnum
	, symcount  int
	, symname	bytea not null
	, constraint lxr_uk_symbols
		unique (symname)
	);
-- create index lxr_symlookup
-- 	on lxr_symbols
-- 	using btree (symname);

/* The following function decrements the symbol reference count
 * for a definition
 * (to be used in triggers).
 */
drop function if exists lxr_decdecl();
create function lxr_decdecl()
	returns trigger
	language PLpgSQL
	as $$
		begin
			update lxr_symbols
				set	symcount = symcount - 1
				where symid = old.symid
				and symcount > 0;
			if old.relid is not null
			then update lxr_symbols
				set	symcount = symcount - 1
				where symid = old.relid
				and symcount > 0;
			end if;
			return new;
		end;
	$$;

/* The following function decrements the symbol reference count
 * for a usage
 * (to be used in triggers).
 */
drop function if exists lxr_decusage();
create function lxr_decusage()
	returns trigger
	language PLpgSQL
	as $$
		begin
			update lxr_symbols
				set	symcount = symcount - 1
				where symid = old.symid
				and symcount > 0;
			return new;
		end;
	$$;

/* Definitions */
/*	symid:	refers to symbol name
	fileid and line define the location of the declaration
	langid:	language id
	typeid:	language type id
	relid:	optional id of the englobing declaration
			(refers to another symbol, not a definition)
 */
create table if not exists lxr_definitions
	( symid		int      not null
	, fileid	int      not null
	, line		int      not null
	, typeid	smallint not null
	, langid	smallint not null
	, relid		int
	, constraint lxr_fk_defn_symid
		foreign key (symid)
		references lxr_symbols(symid)
	, constraint lxr_fk_defn_fileid
		foreign key (fileid)
		references lxr_files(fileid)
-- 	, index (typeid, langid)
	, constraint lxr_fk_defn_type
		foreign key (typeid, langid)
		references lxr_langtypes (typeid, langid)
	, constraint lxr_fk_defn_relid
		foreign key (relid)
		references lxr_symbols(symid)
	);
create index
	lxr_i_definitions
	on lxr_definitions
	using btree (symid, fileid);

/* The following trigger maintains correct symbol reference count
 * after definition deletion.
 */
-- drop function if exists lxr_proxy_rem_def();
-- create function lxr_proxy_rem_def()
-- 	returns trigger
-- 	language PLpgSQL
-- /*@IF	1 */
-- 	as $$
-- /*@ELSE*/
-- 	as $$
-- /*@ENDIF	1 */
-- 		begin
-- 			perform lxr_decsym(old.symid);
-- 			if old.relid is not null
-- 			then perform lxr_decsym(old.relid);
-- 			end if;
-- 		end;
-- /*@IF	1 */
-- 	$$;
-- /*@ELSE*/
-- 	$$;
-- /*@ENDIF	1 */
create trigger lxr_remove_definition
	after delete on lxr_definitions
	for each row
	execute procedure lxr_decdecl();

/* Usages */
create table if not exists lxr_usages
	( symid		int not null
	, fileid	int not null
	, line		int not null
	, constraint lxr_fk_use_symid
		foreign key (symid)
		references lxr_symbols(symid)
	, constraint lxr_fk_use_fileid
		foreign key (fileid)
		references lxr_files(fileid)
	);
create index
	lxr_i_usages
	on lxr_usages
	using btree (symid, fileid);

/* The following trigger maintains correct symbol reference count
 * after usage deletion.
 */
-- drop function if exists lxr_proxy_rem_usg();
-- create function lxr_proxy_rem_usg()
-- 	returns trigger
-- 	language PLpgSQL
-- /*@IF	1 */
-- 	as $$
-- /*@ELSE*/
-- 	as $$
-- /*@ENDIF	1 */
-- 		begin
-- 			perform lxr_decsym(old.symid);
-- 		end;
-- /*@IF	1 */
-- 	$$;
-- /*@ELSE*/
-- 	$$;
-- /*@ENDIF	1 */
create trigger lxr_remove_usage
	after delete on lxr_usages
	for each row
	execute procedure lxr_decusage();

/* Statistics */
/*	releaseid:	"public" release tag
 *	reindex  :	reindex-all flag
 *	stepname :	step name
 *	starttime:	step start time
 *	endtime  :	step end time
 */
drop table if exists lxr_times;
create table lxr_times
	( releaseid bytea
	, reindex   int
	, stepname  char(1)
	, starttime int
	, endtime   int
	);

/*
 *
 */
grant select on lxr_files       to public;
grant select on lxr_symbols     to public;
grant select on lxr_definitions to public;
grant select on lxr_releases    to public;
grant select on lxr_usages      to public;
grant select on lxr_status      to public;
grant select on lxr_langtypes   to public;
grant select on lxr_times       to public;
