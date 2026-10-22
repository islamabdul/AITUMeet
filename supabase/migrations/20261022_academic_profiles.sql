-- Upgrade an existing AITUMeet v0.2 Supabase schema. No accounts or posts are deleted.
begin;
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
