-- Upgrade an existing AITUMeet database without removing accounts or content.
-- When connecting Supabase, disable Confirm email in Auth > Providers > Email.
-- This migration does not change Supabase Auth settings or existing auth.users records.
begin;
create or replace function public.aitu_is_member() returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from aitu_private.student_accounts a join auth.users u on u.id=a.user_id
 where a.user_id=auth.uid() and lower(u.email) ~ '^[0-9]{6}@astanait\.edu\.kz$');
$$;
revoke all on function public.aitu_is_member() from public, anon;
grant execute on function public.aitu_is_member() to authenticated;
commit;
