-- Microsoft Entra sign-in support, searchable posts and database-backed moderation.
begin;

-- Microsoft OAuth users do not pass the email/password registration form's metadata.
-- Keep the institutional email check authoritative and assign a private starter tag.
create or replace function aitu_private.create_student_profile() returns trigger
language plpgsql security definer set search_path='' as $$
declare
 chosen_username text:=lower(trim(new.raw_user_meta_data->>'username'));
 chosen_name text:=nullif(trim(new.raw_user_meta_data->>'name'),'');
 chosen_group text:=coalesce(new.raw_user_meta_data->>'group_number','');
begin
 if new.email is null or lower(new.email) !~ '^[0-9]{6}@astanait\.edu\.kz$' then
  raise exception 'aitu_invalid_student_email';
 end if;
 if chosen_username is null or chosen_username !~ '^[a-z][a-z0-9_]{2,23}$' then
  chosen_username:='student_'||replace(new.id::text,'-','');
 end if;
 if chosen_group !~ '^[0-9]{2}$' then chosen_group:=''; end if;
 if chosen_name is null then chosen_name:=split_part(new.email,'@',1); end if;
 insert into aitu_private.student_accounts(user_id,student_code)
 values(new.id,split_part(new.email,'@',1));
 insert into public.aitu_profiles(id,username,name,program_code,course,group_number)
 values(new.id,chosen_username,left(chosen_name,60),coalesce(new.raw_user_meta_data->>'program_code','6B07102'),
 coalesce(nullif(new.raw_user_meta_data->>'course','')::smallint,1),chosen_group);
 return new;
end; $$;
revoke all on function aitu_private.create_student_profile() from public,anon,authenticated;

create table aitu_private.moderators (
 user_id uuid primary key references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
revoke all on aitu_private.moderators from public,anon,authenticated;

create or replace function aitu_private.is_moderator() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from aitu_private.moderators where user_id=(select auth.uid()));
$$;
revoke all on function aitu_private.is_moderator() from public,anon;
grant execute on function aitu_private.is_moderator() to authenticated;
create or replace function public.aitu_is_moderator() returns boolean
language sql stable security invoker set search_path='' as $$ select aitu_private.is_moderator(); $$;
revoke all on function public.aitu_is_moderator() from public,anon;
grant execute on function public.aitu_is_moderator() to authenticated;

alter table public.aitu_posts add column if not exists moderation_hidden boolean not null default false;
create table if not exists public.aitu_reports (
 id uuid primary key default gen_random_uuid(),
 reporter_id uuid not null references public.aitu_profiles(id) on delete cascade,
 post_id uuid not null references public.aitu_posts(id) on delete cascade,
 reason text not null check(reason in ('spam','harassment','inappropriate','other')),
 details text not null default '' check(char_length(details)<=1000),
 status text not null default 'pending' check(status in ('pending','resolved','dismissed')),
 reviewed_by uuid references aitu_private.moderators(user_id),
 reviewed_at timestamptz,
 created_at timestamptz not null default now(),
 unique(reporter_id,post_id)
);
create index if not exists aitu_reports_queue_idx on public.aitu_reports(status,created_at desc);
alter table public.aitu_reports enable row level security;
revoke all on public.aitu_reports from public,anon,authenticated;
grant select on public.aitu_reports to authenticated;
grant insert on public.aitu_reports to authenticated;
grant update(status,reviewed_by,reviewed_at) on public.aitu_reports to authenticated;
drop policy if exists aitu_reports_create on public.aitu_reports;
drop policy if exists aitu_reports_moderator_read on public.aitu_reports;
drop policy if exists aitu_reports_moderator_update on public.aitu_reports;
create policy aitu_reports_create on public.aitu_reports for insert to authenticated
 with check((select public.aitu_is_member()) and reporter_id=(select auth.uid()));
create policy aitu_reports_moderator_read on public.aitu_reports for select to authenticated
 using((select aitu_private.is_moderator()));
create policy aitu_reports_moderator_update on public.aitu_reports for update to authenticated
 using((select aitu_private.is_moderator()))
 with check((select aitu_private.is_moderator()) and reviewed_by=(select auth.uid()));

grant update(moderation_hidden) on public.aitu_posts to authenticated;
drop policy if exists aitu_posts_moderator_update on public.aitu_posts;
create policy aitu_posts_moderator_update on public.aitu_posts for update to authenticated
 using((select aitu_private.is_moderator()))
 with check((select aitu_private.is_moderator()));

-- Preserve the existing view's public column order; hidden posts never enter the feed.
create or replace view public.aitu_feed with(security_invoker=true) as
select p.id,p.author_id,p.body,p.image_path,p.tag,p.created_at,u.username,u.name,u.avatar_path,u.major,
 (select count(*) from public.aitu_likes where post_id=p.id) as likes,
 (select count(*) from public.aitu_comments where post_id=p.id) as comments,
 exists(select 1 from public.aitu_likes where user_id=auth.uid() and post_id=p.id) as liked,
 exists(select 1 from public.aitu_bookmarks where user_id=auth.uid() and post_id=p.id) as saved
from public.aitu_posts p join public.aitu_profiles u on u.id=p.author_id
where not p.moderation_hidden;
revoke all on public.aitu_feed from public,anon;
grant select on public.aitu_feed to authenticated;
commit;

