-- AITUMeet. Run once in a NEW Supabase project via SQL Editor.
-- No demo records. Email confirmation must remain enabled in Supabase Auth.
begin;
create schema if not exists aitu_private;
revoke all on schema aitu_private from public, anon, authenticated;

create table aitu_private.student_accounts (
 user_id uuid primary key references auth.users(id) on delete cascade,
 student_code text unique not null check (student_code ~ '^[0-9]{6}$')
);
revoke all on aitu_private.student_accounts from public, anon, authenticated;

create table public.aitu_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 username text unique not null check (username ~ '^[a-z][a-z0-9_]{2,23}$'),
 name text not null check (char_length(trim(name)) between 1 and 60),
 bio text not null default '' check (char_length(bio)<=500),
 major text not null default '' check (char_length(major)<=80),
 course smallint not null default 1 check (course between 1 and 4),
 interests text not null default '' check (char_length(interests)<=180),
 avatar_path text not null default '', cover_path text not null default '',
 created_at timestamptz not null default now(),
 check (avatar_path='' or avatar_path like id::text || '/%'),
 check (cover_path='' or cover_path like id::text || '/%')
);
create table public.aitu_posts (
 id uuid primary key default gen_random_uuid(),
 author_id uuid not null references public.aitu_profiles(id) on delete cascade,
 body text not null default '' check (char_length(body)<=4000),
 image_path text not null default '',
 tag text not null default 'campus' check (tag in ('campus','study','projects','life')),
 created_at timestamptz not null default now(),
 check (char_length(trim(body))>0 or image_path<>''),
 check (image_path='' or image_path like author_id::text || '/%')
);
create index aitu_posts_created_idx on public.aitu_posts(created_at desc,id desc);
create index aitu_posts_author_idx on public.aitu_posts(author_id);
create table public.aitu_likes (
 user_id uuid not null references public.aitu_profiles(id) on delete cascade,
 post_id uuid not null references public.aitu_posts(id) on delete cascade,
 primary key(user_id,post_id)
);
create table public.aitu_bookmarks (
 user_id uuid not null references public.aitu_profiles(id) on delete cascade,
 post_id uuid not null references public.aitu_posts(id) on delete cascade,
 primary key(user_id,post_id)
);
create table public.aitu_comments (
 id uuid primary key default gen_random_uuid(),
 author_id uuid not null references public.aitu_profiles(id) on delete cascade,
 post_id uuid not null references public.aitu_posts(id) on delete cascade,
 body text not null check (char_length(trim(body)) between 1 and 1000),
 created_at timestamptz not null default now()
);
create index aitu_comments_post_idx on public.aitu_comments(post_id,created_at);
create table public.aitu_follows (
 follower_id uuid not null references public.aitu_profiles(id) on delete cascade,
 following_id uuid not null references public.aitu_profiles(id) on delete cascade,
 primary key(follower_id,following_id), check(follower_id<>following_id)
);
create index aitu_follows_target_idx on public.aitu_follows(following_id);
create table public.aitu_messages (
 id uuid primary key default gen_random_uuid(),
 sender_id uuid not null references public.aitu_profiles(id) on delete cascade,
 recipient_id uuid not null references public.aitu_profiles(id) on delete cascade,
 body text not null check (char_length(trim(body)) between 1 and 2000),
 created_at timestamptz not null default now(), read_at timestamptz,
 check(sender_id<>recipient_id)
);
create index aitu_messages_sender_idx on public.aitu_messages(sender_id,created_at desc);
create index aitu_messages_recipient_idx on public.aitu_messages(recipient_id,created_at desc);

create function public.aitu_is_member() returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from aitu_private.student_accounts a join auth.users u on u.id=a.user_id
 where a.user_id=auth.uid() and u.email_confirmed_at is not null);
$$;
revoke all on function public.aitu_is_member() from public, anon;
grant execute on function public.aitu_is_member() to authenticated;

-- Only auth.users.email is authoritative. Mutable user_metadata never grants access.
create function aitu_private.validate_student_email() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 if new.email is null or lower(new.email) !~ '^[0-9]{6}@astanait\.edu\.kz$' then
  raise exception 'aitu_invalid_student_email';
 end if;
 if TG_OP='UPDATE' and new.email is distinct from old.email then
  raise exception 'aitu_student_email_is_immutable';
 end if;
 return new;
end; $$;
create trigger aitu_validate_student_email before insert or update of email on auth.users
for each row execute function aitu_private.validate_student_email();

create function aitu_private.create_student_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
declare chosen_username text := lower(trim(new.raw_user_meta_data->>'username'));
begin
 if chosen_username is null or chosen_username !~ '^[a-z][a-z0-9_]{2,23}$' then
  raise exception 'aitu_invalid_username';
 end if;
 insert into aitu_private.student_accounts(user_id,student_code) values(new.id,split_part(new.email,'@',1));
 insert into public.aitu_profiles(id,username,name) values(new.id,chosen_username,trim(new.raw_user_meta_data->>'name'));
 return new;
end; $$;
create trigger aitu_create_student_profile after insert on auth.users for each row
execute function aitu_private.create_student_profile();
revoke all on function aitu_private.validate_student_email() from public, anon, authenticated;
revoke all on function aitu_private.create_student_profile() from public, anon, authenticated;

alter table public.aitu_profiles enable row level security;
alter table public.aitu_posts enable row level security;
alter table public.aitu_likes enable row level security;
alter table public.aitu_bookmarks enable row level security;
alter table public.aitu_comments enable row level security;
alter table public.aitu_follows enable row level security;
alter table public.aitu_messages enable row level security;

revoke all on public.aitu_profiles,public.aitu_posts,public.aitu_likes,public.aitu_bookmarks,
 public.aitu_comments,public.aitu_follows,public.aitu_messages from anon,authenticated;
grant select on public.aitu_profiles to authenticated;
grant update(username,name,bio,major,course,interests,avatar_path,cover_path) on public.aitu_profiles to authenticated;
grant select,insert,delete on public.aitu_posts,public.aitu_likes,public.aitu_bookmarks,public.aitu_comments,public.aitu_follows to authenticated;
grant select,insert on public.aitu_messages to authenticated;
grant update(read_at) on public.aitu_messages to authenticated;

create policy aitu_profiles_read on public.aitu_profiles for select to authenticated using ((select public.aitu_is_member()));
create policy aitu_profiles_update on public.aitu_profiles for update to authenticated
using ((select public.aitu_is_member()) and id=(select auth.uid())) with check (id=(select auth.uid()));
create policy aitu_posts_read on public.aitu_posts for select to authenticated using ((select public.aitu_is_member()));
create policy aitu_posts_insert on public.aitu_posts for insert to authenticated with check ((select public.aitu_is_member()) and author_id=(select auth.uid()));
create policy aitu_posts_delete on public.aitu_posts for delete to authenticated using ((select public.aitu_is_member()) and author_id=(select auth.uid()));
create policy aitu_likes_read on public.aitu_likes for select to authenticated using ((select public.aitu_is_member()));
create policy aitu_likes_insert on public.aitu_likes for insert to authenticated with check ((select public.aitu_is_member()) and user_id=(select auth.uid()));
create policy aitu_likes_delete on public.aitu_likes for delete to authenticated using ((select public.aitu_is_member()) and user_id=(select auth.uid()));
create policy aitu_bookmarks_own on public.aitu_bookmarks for all to authenticated
using ((select public.aitu_is_member()) and user_id=(select auth.uid())) with check ((select public.aitu_is_member()) and user_id=(select auth.uid()));
create policy aitu_comments_read on public.aitu_comments for select to authenticated using ((select public.aitu_is_member()));
create policy aitu_comments_insert on public.aitu_comments for insert to authenticated with check ((select public.aitu_is_member()) and author_id=(select auth.uid()));
create policy aitu_comments_delete on public.aitu_comments for delete to authenticated using ((select public.aitu_is_member()) and author_id=(select auth.uid()));
create policy aitu_follows_read on public.aitu_follows for select to authenticated using ((select public.aitu_is_member()));
create policy aitu_follows_insert on public.aitu_follows for insert to authenticated with check ((select public.aitu_is_member()) and follower_id=(select auth.uid()));
create policy aitu_follows_delete on public.aitu_follows for delete to authenticated using ((select public.aitu_is_member()) and follower_id=(select auth.uid()));
create policy aitu_messages_read on public.aitu_messages for select to authenticated
using ((select public.aitu_is_member()) and (sender_id=(select auth.uid()) or recipient_id=(select auth.uid())));
create policy aitu_messages_send on public.aitu_messages for insert to authenticated
with check ((select public.aitu_is_member()) and sender_id=(select auth.uid()));
create policy aitu_messages_mark_read on public.aitu_messages for update to authenticated
using ((select public.aitu_is_member()) and recipient_id=(select auth.uid())) with check (recipient_id=(select auth.uid()));

-- These views obey the caller's RLS; neither exposes email or the student barcode.
create view public.aitu_profile_cards with (security_invoker=true) as
select p.*,
 (select count(*) from public.aitu_posts where author_id=p.id) as posts,
 (select count(*) from public.aitu_follows where following_id=p.id) as followers,
 (select count(*) from public.aitu_follows where follower_id=p.id) as following,
 exists(select 1 from public.aitu_follows where follower_id=auth.uid() and following_id=p.id) as followed
from public.aitu_profiles p;
create view public.aitu_feed with (security_invoker=true) as
select p.*,u.username,u.name,u.avatar_path,u.major,
 (select count(*) from public.aitu_likes where post_id=p.id) as likes,
 (select count(*) from public.aitu_comments where post_id=p.id) as comments,
 exists(select 1 from public.aitu_likes where user_id=auth.uid() and post_id=p.id) as liked,
 exists(select 1 from public.aitu_bookmarks where user_id=auth.uid() and post_id=p.id) as saved
from public.aitu_posts p join public.aitu_profiles u on u.id=p.author_id;
revoke all on public.aitu_profile_cards,public.aitu_feed from anon;
grant select on public.aitu_profile_cards,public.aitu_feed to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('aitu-media','aitu-media',false,2097152,array['image/png','image/jpeg','image/webp']);
create policy aitu_media_read on storage.objects for select to authenticated
using (bucket_id='aitu-media' and (select public.aitu_is_member()));
create policy aitu_media_upload on storage.objects for insert to authenticated
with check(bucket_id='aitu-media' and (select public.aitu_is_member()) and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy aitu_media_delete on storage.objects for delete to authenticated
using(bucket_id='aitu-media' and (select public.aitu_is_member()) and (storage.foldername(name))[1]=(select auth.uid())::text);
-- ACADEMICS PATCH START
-- AITU catalogue checked on 2026-10-22: https://astanait.edu.kz/ru/bachelor
-- Group prefixes use project-owner-approved abbreviations, not an official group registry.
create table if not exists public.aitu_schools (
 code text primary key, name_ru text not null, name_en text not null, name_kk text not null
);
create table if not exists public.aitu_programs (
 code text primary key, school_code text not null references public.aitu_schools(code),
 name text unique not null, group_prefix text not null check(group_prefix ~ '^[A-Z]{2,8}$')
);
alter table public.aitu_schools enable row level security;
alter table public.aitu_programs enable row level security;
revoke all on public.aitu_schools,public.aitu_programs from public,anon,authenticated;
grant select on public.aitu_schools,public.aitu_programs to anon,authenticated;
drop policy if exists aitu_schools_read on public.aitu_schools;
drop policy if exists aitu_programs_read on public.aitu_programs;
create policy aitu_schools_read on public.aitu_schools for select to anon,authenticated using(true);
create policy aitu_programs_read on public.aitu_programs for select to anon,authenticated using(true);
insert into public.aitu_schools(code,name_ru,name_en,name_kk) values
('software','Школа программной инженерии','School of Software Engineering','Бағдарламалық инженерия мектебі'),
('ai-data','Школа искусственного интеллекта и науки о данных','School of Artificial Intelligence and Data Science','Жасанды интеллект және деректер ғылымы мектебі'),
('cybersecurity','Школа кибербезопасности','School of Cybersecurity','Киберқауіпсіздік мектебі'),
('intelligent','Школа интеллектуальных систем','School of Intelligent Systems','Зияткерлік жүйелер мектебі'),
('creative','Школа креативных индустрий','School of Creative Industries','Креативті индустриялар мектебі'),
('digital-government','Школа цифрового государственного управления','School of Digital Public Administration','Цифрлық мемлекеттік басқару мектебі'),
('general','Школа общеобразовательных дисциплин','School of General Education Disciplines','Жалпы білім беру пәндері мектебі')
on conflict(code) do update set name_ru=excluded.name_ru,name_en=excluded.name_en,name_kk=excluded.name_kk;
insert into public.aitu_programs(code,school_code,name,group_prefix) values
('6B06102','software','Software Engineering','SE'),
('6B06101','ai-data','Computer Science','IT'),
('6B06103','ai-data','Big Data Analysis','BDA'),
('6B06107','ai-data','Mathematical and Computational Science','MCS'),
('6B06301','cybersecurity','Cybersecurity','CYB'),
('6B06302','cybersecurity','Smart Security Technologies','SST'),
('6B07101','intelligent','Industrial Internet of Things','IIOT'),
('6B07102','intelligent','Electronic Engineering','EE'),
('6B06202','intelligent','Smart Technologies','ST'),
('6B07103','intelligent','Digital Technologies in Nuclear Power Engineering','DNE'),
('6B06105','creative','Media Technologies','MT'),
('6B03201','creative','Digital Journalism','DJ'),
('6B04104','digital-government','Digital Public Administration','DPA'),
('6B04201','digital-government','Digital Jurisprudence','DL'),
('6B04103','digital-government','AI Business','AIB'),
('6B04101','digital-government','IT Management','ITM'),
('6B04102','digital-government','IT Entrepreneurship','ITE')
on conflict(code) do update set school_code=excluded.school_code,name=excluded.name,group_prefix=excluded.group_prefix;

alter table public.aitu_profiles add column if not exists program_code text references public.aitu_programs(code);
alter table public.aitu_profiles add column if not exists group_number text not null default '' check(group_number='' or group_number ~ '^[0-9]{2}$');
alter table public.aitu_profiles add column if not exists group_name text not null default '';
-- Preserve unrecognised legacy free-text majors. The owner can choose the right programme next time.
update public.aitu_profiles p set program_code=c.code from public.aitu_programs c
where p.program_code is null and lower(trim(p.major))=lower(c.name);
update public.aitu_profiles set program_code='6B07102',major='Electronic Engineering'
where program_code is null and trim(major)='';
alter table public.aitu_profiles alter column program_code set default '6B07102';

create or replace function aitu_private.normalize_study_profile() returns trigger
language plpgsql security definer set search_path='' as $$
declare selected public.aitu_programs%rowtype;
begin
 select * into selected from public.aitu_programs where code=new.program_code;
 if not found then raise exception 'aitu_invalid_program'; end if;
 if new.course is null or new.course not between 1 and 3 then raise exception 'aitu_invalid_course'; end if;
 if new.group_number is null or (new.group_number<>'' and new.group_number !~ '^[0-9]{2}$') then raise exception 'aitu_invalid_group'; end if;
 new.major:=selected.name;
 -- Academic year 2026/27: 1 -> 26, 2 -> 25, 3 -> 24. Keep in sync with public/academics.js.
 new.group_name:=case when new.group_number='' then '' else selected.group_prefix || '-' || right((2027-new.course)::text,2) || new.group_number end;
 return new;
end; $$;
drop trigger if exists aitu_normalize_study_profile on public.aitu_profiles;
create trigger aitu_normalize_study_profile before insert or update on public.aitu_profiles
for each row execute function aitu_private.normalize_study_profile();
revoke all on function aitu_private.normalize_study_profile() from public,anon,authenticated;
-- Refresh canonical values when reapplying the catalogue after a prefix correction.
update public.aitu_profiles set group_number=group_number
where program_code is not null and course between 1 and 3;
-- Canonical major and group name are set by the trigger, never by a browser-supplied string.
revoke update(major) on public.aitu_profiles from authenticated;
grant update(program_code,group_number) on public.aitu_profiles to authenticated;

create or replace function aitu_private.create_student_profile() returns trigger
language plpgsql security definer set search_path='' as $$
declare chosen_username text:=lower(trim(new.raw_user_meta_data->>'username'));
begin
 if chosen_username is null or chosen_username !~ '^[a-z][a-z0-9_]{2,23}$' then raise exception 'aitu_invalid_username'; end if;
 if coalesce(new.raw_user_meta_data->>'group_number','') !~ '^[0-9]{2}$' then raise exception 'aitu_invalid_group'; end if;
 insert into aitu_private.student_accounts(user_id,student_code) values(new.id,split_part(new.email,'@',1));
 insert into public.aitu_profiles(id,username,name,program_code,course,group_number)
 values(new.id,chosen_username,trim(new.raw_user_meta_data->>'name'),
 coalesce(new.raw_user_meta_data->>'program_code','6B07102'),
 coalesce((new.raw_user_meta_data->>'course')::smallint,1),new.raw_user_meta_data->>'group_number');
 return new;
end; $$;
revoke all on function aitu_private.create_student_profile() from public,anon,authenticated;

-- Preserve the original view column order; append new columns for backwards-compatible upgrades.
create or replace view public.aitu_profile_cards with(security_invoker=true) as
select p.id,p.username,p.name,p.bio,p.major,p.course,p.interests,p.avatar_path,p.cover_path,p.created_at,
 (select count(*) from public.aitu_posts where author_id=p.id) as posts,
 (select count(*) from public.aitu_follows where following_id=p.id) as followers,
 (select count(*) from public.aitu_follows where follower_id=p.id) as following,
 exists(select 1 from public.aitu_follows where follower_id=auth.uid() and following_id=p.id) as followed,
 p.program_code,p.group_number,p.group_name
from public.aitu_profiles p;
revoke all on public.aitu_profile_cards from public,anon;
grant select on public.aitu_profile_cards to authenticated;
-- ACADEMICS PATCH END
commit;
