begin;

-- Keep report history if the reporter or the reported post is later removed.
alter table public.aitu_reports alter column reporter_id drop not null;
alter table public.aitu_reports drop constraint if exists aitu_reports_reporter_id_fkey;
alter table public.aitu_reports add constraint aitu_reports_reporter_id_fkey
 foreign key(reporter_id) references public.aitu_profiles(id) on delete set null;
alter table public.aitu_reports alter column post_id drop not null;
alter table public.aitu_reports drop constraint if exists aitu_reports_post_id_fkey;
alter table public.aitu_reports add constraint aitu_reports_post_id_fkey
 foreign key(post_id) references public.aitu_posts(id) on delete set null;

-- Moderators and administrators may inspect sanctions, while only administrators
-- retain the existing warning/ban issuance and revocation permissions.
drop policy if exists aitu_warnings_read on public.aitu_warnings;
create policy aitu_warnings_read on public.aitu_warnings for select to authenticated
 using(user_id=(select auth.uid()) or (select aitu_private.is_moderator()));
drop policy if exists aitu_bans_read on public.aitu_bans;
create policy aitu_bans_read on public.aitu_bans for select to authenticated
 using(user_id=(select auth.uid()) or (select aitu_private.is_moderator()));

-- Only an existing administrator can grant, change, or revoke staff roles.
create or replace function aitu_private.set_staff_role(target_user_id uuid, target_role text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if (select auth.uid()) is null or not aitu_private.is_admin() then
   raise exception 'aitu_admin_required';
 end if;
 if target_user_id=(select auth.uid()) then
   raise exception 'aitu_cannot_change_own_role';
 end if;
 if target_role is not null and target_role not in ('moderation','administration') then
   raise exception 'aitu_invalid_staff_role';
 end if;
 if not exists(select 1 from auth.users where id=target_user_id) then
   raise exception 'aitu_staff_target_not_found';
 end if;
 if target_role is null then
   delete from public.aitu_staff_roles where user_id=target_user_id;
 else
   insert into public.aitu_staff_roles(user_id,role) values(target_user_id,target_role)
   on conflict(user_id) do update set role=excluded.role;
 end if;
end; $$;
revoke all on function aitu_private.set_staff_role(uuid,text) from public,anon;
grant execute on function aitu_private.set_staff_role(uuid,text) to authenticated;
create or replace function public.aitu_set_staff_role(target_user_id uuid, target_role text)
returns void language sql security invoker set search_path='' as $$
 select aitu_private.set_staff_role(target_user_id,target_role);
$$;
revoke all on function public.aitu_set_staff_role(uuid,text) from public,anon;
grant execute on function public.aitu_set_staff_role(uuid,text) to authenticated;

commit;
