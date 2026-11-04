-- Hide moderated post text and its comments at the table boundary, too.
drop policy if exists aitu_posts_read on public.aitu_posts;
create policy aitu_posts_read on public.aitu_posts for select to authenticated
using((select public.aitu_is_member()) and (not moderation_hidden or author_id=(select auth.uid()) or (select aitu_private.is_moderator())));

drop policy if exists aitu_comments_read on public.aitu_comments;
create policy aitu_comments_read on public.aitu_comments for select to authenticated
using((select public.aitu_is_member()) and exists(
 select 1 from public.aitu_posts p where p.id=aitu_comments.post_id
 and (not p.moderation_hidden or p.author_id=(select auth.uid()) or (select aitu_private.is_moderator()))
));
