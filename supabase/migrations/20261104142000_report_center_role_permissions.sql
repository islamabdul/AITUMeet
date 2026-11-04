begin;

-- Keep reports in a user's history after the reported post is deleted.
alter table public.aitu_reports alter column post_id drop not null;
alter table public.aitu_reports drop constraint if exists aitu_reports_post_id_fkey;
alter table public.aitu_reports add constraint aitu_reports_post_id_fkey
 foreign key(post_id) references public.aitu_posts(id) on delete set null;
alter table public.aitu_reports drop constraint if exists aitu_reports_reviewed_by_fkey;
alter table public.aitu_reports add constraint aitu_reports_reviewed_by_fkey
 foreign key(reviewed_by) references auth.users(id) on delete set null;

create or replace function public.aitu_is_admin() returns boolean
language sql stable security invoker set search_path='' as $$ select aitu_private.is_admin(); $$;
revoke all on function public.aitu_is_admin() from public,anon;
grant execute on function public.aitu_is_admin() to authenticated;

-- Warning issuance and the automatic 3/5 warning bans happen atomically in the database.
create or replace function aitu_private.issue_warning(target_user_id uuid, warning_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare warning_count integer; ban_days integer; new_ban_id uuid;
begin
 if (select auth.uid()) is null or not aitu_private.is_admin() then raise exception 'aitu_admin_required'; end if;
 if target_user_id=(select auth.uid()) then raise exception 'aitu_cannot_warn_self'; end if;
 if warning_reason is null or char_length(trim(warning_reason)) not between 3 and 1000 then raise exception 'aitu_invalid_warning_reason'; end if;
 insert into public.aitu_warnings(user_id,issued_by,reason)
 values(target_user_id,(select auth.uid()),trim(warning_reason));
 select count(*) into warning_count from public.aitu_warnings
 where user_id=target_user_id and revoked_at is null;
 ban_days:=case warning_count when 3 then 1 when 5 then 3 else null end;
 if ban_days is not null and not exists(select 1 from public.aitu_bans b where b.user_id=target_user_id
   and b.lifted_at is null and (b.expires_at is null or b.expires_at>now())) then
  insert into public.aitu_bans(user_id,issued_by,reason,expires_at)
  values(target_user_id,(select auth.uid()),format('Автоматическая блокировка за %s предупреждения. Последнее предупреждение: %s',warning_count,trim(warning_reason)),now()+make_interval(days=>ban_days))
  returning id into new_ban_id;
 end if;
 return jsonb_build_object('warning_count',warning_count,'ban_days',ban_days,'ban_id',new_ban_id);
end; $$;
revoke all on function aitu_private.issue_warning(uuid,text) from public,anon,authenticated;
grant execute on function aitu_private.issue_warning(uuid,text) to authenticated;
create or replace function public.aitu_issue_warning(target_user_id uuid, warning_reason text)
returns jsonb language sql security invoker set search_path='' as $$
 select aitu_private.issue_warning(target_user_id,warning_reason); $$;
revoke all on function public.aitu_issue_warning(uuid,text) from public,anon;
grant execute on function public.aitu_issue_warning(uuid,text) to authenticated;

-- Members see their own report history; both staff roles can inspect the queue.
drop policy if exists aitu_reports_moderator_read on public.aitu_reports;
drop policy if exists aitu_reports_moderator_update on public.aitu_reports;
drop policy if exists aitu_reports_own_read on public.aitu_reports;
drop policy if exists aitu_reports_staff_read on public.aitu_reports;
drop policy if exists aitu_reports_admin_update on public.aitu_reports;
create policy aitu_reports_read on public.aitu_reports for select to authenticated
 using(reporter_id=(select auth.uid()) or (select aitu_private.is_moderator()));
create policy aitu_reports_admin_update on public.aitu_reports for update to authenticated
 using((select aitu_private.is_admin()))
 with check((select aitu_private.is_admin()) and reviewed_by=(select auth.uid()));

-- Administration alone can issue/revoke warnings or bans and decide reports.
drop policy if exists aitu_warnings_issue on public.aitu_warnings;
drop policy if exists aitu_warnings_revoke on public.aitu_warnings;
drop policy if exists aitu_warnings_read on public.aitu_warnings;
create policy aitu_warnings_read on public.aitu_warnings for select to authenticated
 using(user_id=(select auth.uid()) or (select aitu_private.is_admin()));
create policy aitu_warnings_admin_revoke on public.aitu_warnings for update to authenticated
 using((select aitu_private.is_admin())) with check((select aitu_private.is_admin()) and revoked_by=(select auth.uid()));
revoke insert,update on public.aitu_warnings from authenticated;
grant update(revoked_at,revoked_by) on public.aitu_warnings to authenticated;

drop policy if exists aitu_bans_issue on public.aitu_bans;
drop policy if exists aitu_bans_lift on public.aitu_bans;
drop policy if exists aitu_bans_read on public.aitu_bans;
create policy aitu_bans_read on public.aitu_bans for select to authenticated
 using(user_id=(select auth.uid()) or (select aitu_private.is_admin()));
create policy aitu_bans_admin_issue on public.aitu_bans for insert to authenticated
 with check((select aitu_private.is_admin()) and issued_by=(select auth.uid()) and user_id<>(select auth.uid()));
create policy aitu_bans_admin_lift on public.aitu_bans for update to authenticated
 using((select aitu_private.is_admin())) with check((select aitu_private.is_admin()) and lifted_by=(select auth.uid()));

-- Staff removal is supported by DELETE policies; no staff member can hide/edit a post.
drop policy if exists aitu_posts_moderator_update on public.aitu_posts;
revoke update(moderation_hidden) on public.aitu_posts from authenticated;

commit;
