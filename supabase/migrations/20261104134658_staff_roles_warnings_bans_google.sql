-- Explicit staff roles, profile badges, warnings, bans and Google OAuth accounts.
begin;

create table public.aitu_staff_roles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 role text not null check(role in ('administration','moderation')),
 created_at timestamptz not null default now()
);
alter table public.aitu_staff_roles enable row level security;
revoke all on public.aitu_staff_roles from public,anon,authenticated;
grant select on public.aitu_staff_roles to authenticated;
create policy aitu_staff_roles_read on public.aitu_staff_roles for select to authenticated
 using((select public.aitu_is_member()));

-- Preserve existing moderator assignments and keep the old private list as a compatibility source.
insert into public.aitu_staff_roles(user_id,role)
select user_id,'moderation' from aitu_private.moderators
on conflict(user_id) do nothing;

create or replace function aitu_private.is_moderator() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.aitu_staff_roles where user_id=(select auth.uid()) and role in ('moderation','administration'))
 or exists(select 1 from aitu_private.moderators where user_id=(select auth.uid()));
$$;
revoke all on function aitu_private.is_moderator() from public,anon;
grant execute on function aitu_private.is_moderator() to authenticated;

create or replace function aitu_private.is_admin() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.aitu_staff_roles where user_id=(select auth.uid()) and role='administration');
$$;
revoke all on function aitu_private.is_admin() from public,anon;
grant execute on function aitu_private.is_admin() to authenticated;

create table public.aitu_warnings (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.aitu_profiles(id) on delete cascade,
 issued_by uuid not null references auth.users(id),
 reason text not null check(char_length(trim(reason)) between 3 and 1000),
 created_at timestamptz not null default now(),
 revoked_at timestamptz,
 revoked_by uuid references auth.users(id)
);
create index aitu_warnings_user_idx on public.aitu_warnings(user_id,created_at desc);
alter table public.aitu_warnings enable row level security;
revoke all on public.aitu_warnings from public,anon,authenticated;
grant select,insert on public.aitu_warnings to authenticated;
grant update(revoked_at,revoked_by) on public.aitu_warnings to authenticated;
create policy aitu_warnings_read on public.aitu_warnings for select to authenticated
 using(user_id=(select auth.uid()) or (select aitu_private.is_moderator()));
create policy aitu_warnings_issue on public.aitu_warnings for insert to authenticated
 with check((select aitu_private.is_moderator()) and issued_by=(select auth.uid()) and user_id<>(select auth.uid()));
create policy aitu_warnings_revoke on public.aitu_warnings for update to authenticated
 using((select aitu_private.is_moderator()))
 with check((select aitu_private.is_moderator()) and revoked_by=(select auth.uid()));

create table public.aitu_bans (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.aitu_profiles(id) on delete cascade,
 issued_by uuid not null references auth.users(id),
 reason text not null check(char_length(trim(reason)) between 3 and 1000),
 created_at timestamptz not null default now(),
 expires_at timestamptz,
 lifted_at timestamptz,
 lifted_by uuid references auth.users(id)
);
create unique index aitu_bans_one_open_idx on public.aitu_bans(user_id) where lifted_at is null;
alter table public.aitu_bans enable row level security;
revoke all on public.aitu_bans from public,anon,authenticated;
grant select,insert on public.aitu_bans to authenticated;
grant update(lifted_at,lifted_by) on public.aitu_bans to authenticated;
create policy aitu_bans_read on public.aitu_bans for select to authenticated
 using(user_id=(select auth.uid()) or (select aitu_private.is_moderator()));
create policy aitu_bans_issue on public.aitu_bans for insert to authenticated
 with check((select aitu_private.is_moderator()) and issued_by=(select auth.uid()) and user_id<>(select auth.uid()));
create policy aitu_bans_lift on public.aitu_bans for update to authenticated
 using((select aitu_private.is_moderator()))
 with check((select aitu_private.is_moderator()) and lifted_by=(select auth.uid()));

create or replace function public.aitu_is_member() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from aitu_private.student_accounts a join auth.users u on u.id=a.user_id
 where a.user_id=(select auth.uid()) and u.email_confirmed_at is not null)
 and not exists(select 1 from public.aitu_bans b where b.user_id=(select auth.uid()) and b.lifted_at is null
   and (b.expires_at is null or b.expires_at>now()));
$$;
revoke all on function public.aitu_is_member() from public,anon;
grant execute on function public.aitu_is_member() to authenticated;

-- Replaced by the RLS-scoped own-row lookup in the following cleanup migration.
create or replace function public.aitu_my_account_status() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce((select jsonb_build_object('banned',true,'reason',b.reason,'expires_at',b.expires_at)
 from public.aitu_bans b where b.user_id=(select auth.uid()) and b.lifted_at is null
 and (b.expires_at is null or b.expires_at>now()) order by b.created_at desc limit 1),
 jsonb_build_object('banned',false));
$$;
revoke all on function public.aitu_my_account_status() from public,anon;
grant execute on function public.aitu_my_account_status() to authenticated;

-- Staff can delete any post. The column-level update grant still limits moderation updates to visibility only.
drop policy if exists aitu_posts_delete on public.aitu_posts;
create policy aitu_posts_delete on public.aitu_posts for delete to authenticated
 using((select public.aitu_is_member()) and (author_id=(select auth.uid()) or (select aitu_private.is_moderator())));

-- Append the public staff label so existing profile-card consumers keep their column order.
create or replace view public.aitu_profile_cards with(security_invoker=true) as
select p.id,p.username,p.name,p.bio,p.major,p.course,p.interests,p.avatar_path,p.cover_path,p.created_at,
 (select count(*) from public.aitu_posts where author_id=p.id) as posts,
 (select count(*) from public.aitu_follows where following_id=p.id) as followers,
 (select count(*) from public.aitu_follows where follower_id=p.id) as following,
 exists(select 1 from public.aitu_follows where follower_id=auth.uid() and following_id=p.id) as followed,
 p.program_code,p.group_number,p.group_name,
 (select r.role from public.aitu_staff_roles r where r.user_id=p.id) as staff_role
from public.aitu_profiles p;
revoke all on public.aitu_profile_cards from public,anon;
grant select on public.aitu_profile_cards to authenticated;
commit;
