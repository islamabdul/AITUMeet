-- Allow a recipient to mark a message as read (RLS still restricts row ownership).
grant update(read_at) on public.aitu_messages to authenticated;

-- Allow administration to lift an old or active ban (RLS remains admin-only).
grant update(lifted_at, lifted_by) on public.aitu_bans to authenticated;

-- Expired but not formally lifted bans still occupy the partial unique index.
-- Lift them before automatically issuing a new threshold ban.
create or replace function aitu_private.issue_warning(target_user_id uuid, warning_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare warning_count integer; ban_days integer; new_ban_id uuid;
begin
 if (select auth.uid()) is null or not aitu_private.is_admin() then raise exception 'aitu_admin_required'; end if;
 if target_user_id=(select auth.uid()) then raise exception 'aitu_cannot_warn_self'; end if;
 if warning_reason is null or char_length(trim(warning_reason)) not between 3 and 1000 then raise exception 'aitu_invalid_warning_reason'; end if;
 insert into public.aitu_warnings(user_id,issued_by,reason) values(target_user_id,(select auth.uid()),trim(warning_reason));
 select count(*) into warning_count from public.aitu_warnings where user_id=target_user_id and revoked_at is null;
 ban_days:=case warning_count when 3 then 1 when 5 then 3 else null end;
 if ban_days is not null then
  update public.aitu_bans b set lifted_at=now(),lifted_by=(select auth.uid())
   where b.user_id=target_user_id and b.lifted_at is null and b.expires_at is not null and b.expires_at<=now();
  if not exists(select 1 from public.aitu_bans b where b.user_id=target_user_id and b.lifted_at is null
    and (b.expires_at is null or b.expires_at>now())) then
   insert into public.aitu_bans(user_id,issued_by,reason,expires_at)
    values(target_user_id,(select auth.uid()),format('Автоматическая блокировка за %s предупреждения. Последнее предупреждение: %s',warning_count,trim(warning_reason)),now()+make_interval(days=>ban_days))
    returning id into new_ban_id;
  end if;
 end if;
 return jsonb_build_object('warning_count',warning_count,'ban_days',ban_days,'ban_id',new_ban_id);
end; $$;
revoke all on function aitu_private.issue_warning(uuid,text) from public,anon;
grant execute on function aitu_private.issue_warning(uuid,text) to authenticated;
