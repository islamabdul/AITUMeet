alter table public.aitu_reports drop constraint if exists aitu_reports_reviewed_by_fkey;
alter table public.aitu_reports add constraint aitu_reports_reviewed_by_fkey foreign key(reviewed_by) references auth.users(id) on delete set null;
drop policy if exists aitu_reports_own_read on public.aitu_reports;
drop policy if exists aitu_reports_staff_read on public.aitu_reports;
drop policy if exists aitu_reports_read on public.aitu_reports;
create policy aitu_reports_read on public.aitu_reports for select to authenticated using(reporter_id=(select auth.uid()) or (select aitu_private.is_moderator()));
