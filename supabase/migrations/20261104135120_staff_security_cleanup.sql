-- Move the membership SECURITY DEFINER helper out of the exposed public schema.
begin;
drop function if exists public.aitu_my_account_status();
create or replace function aitu_private.is_member() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from aitu_private.student_accounts a join auth.users u on u.id=a.user_id
  where a.user_id=(select auth.uid()) and u.email_confirmed_at is not null)
 and not exists(select 1 from public.aitu_bans b where b.user_id=(select auth.uid()) and b.lifted_at is null
  and (b.expires_at is null or b.expires_at>now()));
$$;
revoke all on function aitu_private.is_member() from public,anon;
grant execute on function aitu_private.is_member() to authenticated;
create or replace function public.aitu_is_member() returns boolean
language sql stable security invoker set search_path='' as $$ select aitu_private.is_member(); $$;
revoke all on function public.aitu_is_member() from public,anon;
grant execute on function public.aitu_is_member() to authenticated;

create index if not exists aitu_reports_post_idx on public.aitu_reports(post_id);
create index if not exists aitu_reports_reviewed_by_idx on public.aitu_reports(reviewed_by);
create index if not exists aitu_warnings_issued_by_idx on public.aitu_warnings(issued_by);
create index if not exists aitu_warnings_revoked_by_idx on public.aitu_warnings(revoked_by);
create index if not exists aitu_bans_issued_by_idx on public.aitu_bans(issued_by);
create index if not exists aitu_bans_lifted_by_idx on public.aitu_bans(lifted_by);
commit;
