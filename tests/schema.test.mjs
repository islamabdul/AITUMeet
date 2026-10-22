import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const module=process.env.AITU_PGLITE_MODULE||'@electric-sql/pglite';
const {PGlite}=await import(module);
const setup=async db=>db.exec(`create role anon;create role authenticated;create schema auth;create schema storage;
  create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,raw_user_meta_data jsonb);
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  grant usage on schema auth,public,storage to authenticated,anon;
  create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
  create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);
  alter table storage.objects enable row level security;
  grant select,insert,delete on storage.objects to authenticated;
  create function storage.foldername(name text) returns text[] language sql immutable as $$select string_to_array(name,'/')$$;`);

test('Supabase schema: privacy, confirmed membership, ownership and private messages',async()=>{
 const db=new PGlite();
 try{
  // An in-memory test harness, never an application database or Supabase connection.
  await setup(db);
  await db.exec(readFileSync(new URL('../supabase/schema.sql',import.meta.url),'utf8'));
  const a='11111111-1111-4111-8111-111111111111',b='22222222-2222-4222-8222-222222222222',c='33333333-3333-4333-8333-333333333333',unconfirmed='44444444-4444-4444-8444-444444444444';
  async function signup(id,email,username,confirmed=true){return db.query(`insert into auth.users values($1,$2,${confirmed?'now()':'null'},jsonb_build_object('name','Test user','username',$3::text,'group_number','01'))`,[id,email,username]);}
  await signup(a,'001234@astanait.edu.kz','alpha');await signup(b,'234567@astanait.edu.kz','beta');await signup(c,'345678@astanait.edu.kz','gamma');await signup(unconfirmed,'456789@astanait.edu.kz','pending',false);
  assert.equal((await db.query('select student_code from aitu_private.student_accounts where user_id=$1',[a])).rows[0].student_code,'001234');
  await assert.rejects(signup('55555555-5555-4555-8555-555555555555','12345@astanait.edu.kz','bad_email'));
  await assert.rejects(signup('55555555-5555-4555-8555-555555555555','123456@gmail.com','bad_domain'));
  await assert.rejects(signup('55555555-5555-4555-8555-555555555555','567890@astanait.edu.kz','alpha'));
  await assert.rejects(signup('55555555-5555-4555-8555-555555555555','567890@astanait.edu.kz','123456'));
  await assert.rejects(db.query('update auth.users set email=$1 where id=$2',['999999@astanait.edu.kz',a]));
  async function as(id,role='authenticated'){await db.exec('reset role');await db.query(`select set_config('request.jwt.claim.sub',$1,false)`,[id]);await db.exec('set role '+role);}
  assert.equal(Number((await db.query('select count(*) from public.aitu_programs')).rows[0].count),17);
  const academic=(await db.query('select program_code,major,course,group_number,group_name from public.aitu_profiles where id=$1',[a])).rows[0];
  assert.equal(academic.program_code,'6B07102');assert.equal(academic.major,'Electronic Engineering');assert.equal(academic.course,1);assert.equal(academic.group_number,'01');assert.equal(academic.group_name,'EE-2601');
  await as(a);const profile=(await db.query('select * from public.aitu_profile_cards')).rows[0];assert.ok(!('email'in profile));assert.ok(!('student_code'in profile));
  await assert.rejects(db.query('select * from aitu_private.student_accounts'));
  await assert.rejects(db.query('select * from auth.users'));
  await db.query('update public.aitu_profiles set course=2 where id=$1',[a]);
  assert.equal((await db.query('select group_name from public.aitu_profile_cards where id=$1',[a])).rows[0].group_name,'EE-2501');
  await db.query("update public.aitu_profiles set course=3,group_number='09',program_code='6B06102' where id=$1",[a]);
  const changed=(await db.query('select major,group_name from public.aitu_profile_cards where id=$1',[a])).rows[0];
  assert.equal(changed.major,'Software Engineering');assert.equal(changed.group_name,'SE-2409');
  for(const [code,prefix] of [['6B06101','IT'],['6B07103','DNE'],['6B04201','DL']]){
   await db.query('update public.aitu_profiles set program_code=$1 where id=$2',[code,a]);
   assert.equal((await db.query('select group_name from public.aitu_profile_cards where id=$1',[a])).rows[0].group_name,prefix+'-2409');
  }
  await assert.rejects(db.query("update public.aitu_profiles set group_number='1' where id=$1",[a]));
  await assert.rejects(db.query("update public.aitu_profiles set program_code='missing' where id=$1",[a]));
  await assert.rejects(db.query('update public.aitu_profiles set course=4 where id=$1',[a]));
  await assert.rejects(db.query("update public.aitu_profiles set major='Fake degree' where id=$1",[a]));
  await assert.rejects(db.query("update public.aitu_profiles set group_name='FAKE-0001' where id=$1",[a]));
  await assert.rejects(db.query("update public.aitu_programs set name='Fake degree' where code='6B07102'"));
  const post=(await db.query(`insert into public.aitu_posts(author_id,body) values($1,'Private campus post') returning id`,[a])).rows[0].id;
  await as(b);await assert.rejects(db.query(`insert into public.aitu_posts(author_id,body) values($1,'Impersonation')`,[a]));
  assert.equal((await db.query('delete from public.aitu_posts where id=$1 returning id',[post])).rows.length,0);
  assert.equal((await db.query(`update public.aitu_profiles set name='Wrong' where id=$1 returning id`,[a])).rows.length,0);
  await assert.rejects(db.query('update public.aitu_profiles set id=$1 where id=$2',[c,b]));
  await db.query(`update public.aitu_profiles set username='beta_new' where id=$1`,[b]);
  await db.query('insert into public.aitu_likes values($1,$2)',[b,post]);await db.query('insert into public.aitu_bookmarks values($1,$2)',[b,post]);
  assert.equal(Number((await db.query('select likes from public.aitu_feed where id=$1',[post])).rows[0].likes),1);
  await as(a);assert.equal((await db.query('select * from public.aitu_bookmarks')).rows.length,0);
  const message=(await db.query(`insert into public.aitu_messages(sender_id,recipient_id,body) values($1,$2,'Only participants') returning id`,[a,b])).rows[0].id;
  await as(c);assert.equal((await db.query('select * from public.aitu_messages')).rows.length,0);
  await assert.rejects(db.query(`insert into public.aitu_messages(sender_id,recipient_id,body) values($1,$2,'Spoof')`,[a,b]));
  await as(b);assert.equal((await db.query('select * from public.aitu_messages')).rows.length,1);await db.query('update public.aitu_messages set read_at=now() where id=$1',[message]);
  await assert.rejects(db.query(`update public.aitu_messages set body='Tampered' where id=$1`,[message]));
  await db.query(`insert into storage.objects(bucket_id,name) values('aitu-media',$1)`,[b+'/photo.png']);
  await assert.rejects(db.query(`insert into storage.objects(bucket_id,name) values('aitu-media',$1)`,[a+'/photo.png']));
  await as(unconfirmed);assert.equal((await db.query('select * from public.aitu_profile_cards')).rows.length,0);assert.equal((await db.query('select * from public.aitu_feed')).rows.length,0);assert.equal((await db.query('select * from storage.objects')).rows.length,0);
  await assert.rejects(db.query(`insert into public.aitu_posts(author_id,body) values($1,'Unconfirmed')`,[unconfirmed]));
  await as('', 'anon');await assert.rejects(db.query('select * from public.aitu_profiles'));await assert.rejects(db.query('select * from aitu_private.student_accounts'));
  await db.exec('reset role');const columns=(await db.query(`select table_name,column_name from information_schema.columns where table_schema='public' and table_name like 'aitu_%'`)).rows;assert.equal(columns.filter(c=>/barcode|student_code|email/.test(c.column_name)).length,0);
 }finally{await db.close();}
});

test('the academic upgrade preserves existing accounts, posts and unknown free-text majors',async()=>{
 const db=new PGlite();try{
  await setup(db);
  const schema=readFileSync(new URL('../supabase/schema.sql',import.meta.url),'utf8');
  await db.exec(schema.split('-- ACADEMICS PATCH START')[0]+'commit;');
  await db.exec(`insert into auth.users values('11111111-1111-4111-8111-111111111111','001234@astanait.edu.kz',now(),' {"name":"Existing student","username":"existing"}');
   insert into auth.users values('22222222-2222-4222-8222-222222222222','234567@astanait.edu.kz',now(),' {"name":"Other student","username":"other"}');
   update public.aitu_profiles set major='Software Engineering',course=2 where username='existing';
   update public.aitu_profiles set major='Legacy custom major' where username='other';
   insert into public.aitu_posts(author_id,body) values('11111111-1111-4111-8111-111111111111','Keep this post');`);
  const migration=readFileSync(new URL('../supabase/migrations/20261022_academic_profiles.sql',import.meta.url),'utf8');
  await db.exec(migration);await db.exec(migration);
  const rows=(await db.query('select username,major,program_code,course,group_name from public.aitu_profile_cards order by username')).rows;
  assert.equal(rows[0].program_code,'6B06102');assert.equal(rows[0].course,2);assert.equal(rows[0].group_name,'');
  assert.equal(rows[1].major,'Legacy custom major');assert.equal(rows[1].program_code,null);
  assert.equal((await db.query('select body from public.aitu_posts')).rows[0].body,'Keep this post');
  assert.equal((await db.query('select student_code from aitu_private.student_accounts where user_id=$1',['11111111-1111-4111-8111-111111111111'])).rows[0].student_code,'001234');
 }finally{await db.close();}
});
