begin;

-- Reject new Google OAuth identities even if the provider is still configured
-- in Supabase Auth. Existing non-Google identities are unaffected.
create or replace function aitu_private.reject_google_oauth_signup()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if lower(coalesce(new.raw_app_meta_data->>'provider',''))='google' then
   raise exception using errcode='42501', message='aitu_google_auth_disabled';
 end if;
 return new;
end; $$;
revoke all on function aitu_private.reject_google_oauth_signup() from public,anon,authenticated;
drop trigger if exists aitu_reject_google_oauth_signup on auth.users;
create trigger aitu_reject_google_oauth_signup before insert on auth.users
 for each row execute function aitu_private.reject_google_oauth_signup();

commit;
