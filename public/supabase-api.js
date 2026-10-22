/* All application records live in Supabase. This adapter has no local database fallback. */
window.AituAPI = (() => {
 const config=window.AITU_CONFIG||{}, signed=new Map();
 let client=null;
 const fail=code=>{throw Object.assign(new Error(code),{code});};
 function configured(){return /^https:\/\/[^/]+\/?$/.test(config.supabaseUrl||'')&&!!config.supabasePublishableKey;}
 function connection(){
  if(!configured())fail('setupRequired');
  const key=config.supabasePublishableKey;
  if(key.startsWith('sb_secret_'))fail('unsafeKey');
  try{if(JSON.parse(atob(key.split('.')[1]||'')).role==='service_role')fail('unsafeKey');}catch(e){if(e.code)throw e;}
  if(!client)client=window.supabase.createClient(config.supabaseUrl,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
  return client;
 }
 function unwrap({data,error}){
  if(error){
   const message=(error.message||'').toLowerCase();
   const code=error.code==='23505'?'usernameTaken':message.includes('invalid login credentials')?'wrongCredentials':message.includes('email not confirmed')?'authSetupRequired':message.includes('rate limit')||error.status===429?'tooManyAttempts':message.includes('password')?'passwordInvalid':message.includes('failed to fetch')||message.includes('network')?'networkError':error.code==='PGRST116'?'notFound':'requestFailed';
   fail(code);
  }return data;
 }
 async function identity(){const {user}=unwrap(await connection().auth.getUser());if(!user)fail('signInRequired');return user;}
 async function media(paths){
  const unique=[...new Set(paths.filter(Boolean))], missing=unique.filter(p=>!signed.has(p)||signed.get(p).expires<Date.now());
  if(missing.length){const result=unwrap(await connection().storage.from(config.storageBucket||'aitu-media').createSignedUrls(missing,3600));for(const row of result||[])if(row.signedUrl)signed.set(row.path,{url:row.signedUrl,expires:Date.now()+3000000});}
  return p=>signed.get(p)?.url||'';
 }
 async function profiles(rows){const url=await media(rows.flatMap(p=>[p.avatar_path,p.cover_path]));return rows.map(p=>({...p,avatar:url(p.avatar_path),cover:url(p.cover_path)}));}
 async function profile(username){const row=unwrap(await connection().from('aitu_profile_cards').select('*').eq('username',username).single());return (await profiles([row]))[0];}
 async function current(){
  if(!configured())return null;
  const session=unwrap(await connection().auth.getSession());if(!session.session)return null;
  const user=await identity();
  const row=unwrap(await connection().from('aitu_profile_cards').select('*').eq('id',user.id).single());
  return (await profiles([row]))[0];
 }
 async function signUp({email,password,name,username,...study}){
  const academic=window.AituAcademics.normalize(study);
  email=email.trim().toLowerCase();username=username.trim().replace(/^@/,'').toLowerCase();
  if(!/^[0-9]{6}@astanait\.edu\.kz$/.test(email))fail('emailInvalid');
  if(!/^[a-z][a-z0-9_]{2,23}$/.test(username))fail('usernameInvalid');
  if(password.length<8||password.length>128)fail('passwordInvalid');
  const {data,error}=await connection().auth.signUp({email,password,options:{data:{name:name.trim(),username,...academic}}});
  if(error){if(error.code==='23505'||/username|duplicate/i.test(error.message))fail('usernameTaken');if(/rate limit/i.test(error.message))fail('tooManyAttempts');fail('signupFailed');}
  if(!data.session)fail('authSetupRequired');
  return {user:await current()};
 }
 async function signIn({email,password}){unwrap(await connection().auth.signInWithPassword({email:email.trim().toLowerCase(),password}));return current();}
 async function signOut(){unwrap(await connection().auth.signOut({scope:'local'}));signed.clear();}
 async function search(q=''){
  let query=connection().from('aitu_profile_cards').select('*').order('created_at',{ascending:false}).limit(60);
  const needle=q.replace(/^@/,'').replace(/[^\p{L}\p{N}_ -]/gu,'').slice(0,60);
  if(needle)query=query.or(`name.ilike.*${needle}*,username.ilike.*${needle}*,major.ilike.*${needle}*,group_name.ilike.*${needle}*`);
  return profiles(unwrap(await query)||[]);
 }
 async function updateProfile(d){const u=await identity();const username=d.username.trim().replace(/^@/,'').toLowerCase();if(!/^[a-z][a-z0-9_]{2,23}$/.test(username))fail('usernameInvalid');unwrap(await connection().from('aitu_profiles').update({username,name:d.name.trim(),bio:d.bio,...window.AituAcademics.normalize(d),interests:d.interests,avatar_path:d.avatar_path,cover_path:d.cover_path}).eq('id',u.id));return current();}
 async function upload(file){
  if(!file||!file.size||file.size>2097152)fail('imageSize');
  const b=new Uint8Array(await file.slice(0,12).arrayBuffer());
  const ext=b[0]===137&&b[1]===80&&b[2]===78&&b[3]===71?'png':b[0]===255&&b[1]===216&&b[2]===255?'jpg':String.fromCharCode(...b.slice(0,4))==='RIFF'&&String.fromCharCode(...b.slice(8,12))==='WEBP'?'webp':null;
  if(!ext)fail('imageType');const u=await identity(),path=u.id+'/'+crypto.randomUUID()+'.'+ext;
  unwrap(await connection().storage.from(config.storageBucket||'aitu-media').upload(path,file,{contentType:ext==='jpg'?'image/jpeg':'image/'+ext,upsert:false}));
  const get=await media([path]);return {path,url:get(path)};
 }
 async function feed({username,tag,saved,following,before,id}={}){
  let query=connection().from('aitu_feed').select('*').order('created_at',{ascending:false}).order('id',{ascending:false}).limit(30);
  if(id)query=query.eq('id',id);if(username)query=query.eq('username',username);if(tag)query=query.eq('tag',tag);if(saved)query=query.eq('saved',true);
  if(before)query=query.or(`created_at.lt.${before.created_at},and(created_at.eq.${before.created_at},id.lt.${before.id})`);
  if(following){const u=await identity(),links=unwrap(await connection().from('aitu_follows').select('following_id').eq('follower_id',u.id));query=query.in('author_id',[u.id,...links.map(x=>x.following_id)]);}
  const rows=unwrap(await query)||[],url=await media(rows.flatMap(x=>[x.image_path,x.avatar_path]));
  return rows.map(x=>({...x,image:url(x.image_path),avatar:url(x.avatar_path)}));
 }
 async function publish({body,tag,image_path=''}){const u=await identity();return unwrap(await connection().from('aitu_posts').insert({author_id:u.id,body:body.trim(),tag,image_path}).select('id').single());}
 async function removePost(id){unwrap(await connection().from('aitu_posts').delete().eq('id',id));}
 async function toggle(kind,id){const u=await identity(),table=kind==='like'?'aitu_likes':'aitu_bookmarks';const old=unwrap(await connection().from(table).select('post_id').eq('user_id',u.id).eq('post_id',id).maybeSingle());unwrap(old?await connection().from(table).delete().eq('user_id',u.id).eq('post_id',id):await connection().from(table).insert({user_id:u.id,post_id:id}));return !old;}
 async function follow(username){const u=await identity(),target=await profile(username);if(u.id===target.id)fail('ownProfile');const old=unwrap(await connection().from('aitu_follows').select('following_id').eq('follower_id',u.id).eq('following_id',target.id).maybeSingle());unwrap(old?await connection().from('aitu_follows').delete().eq('follower_id',u.id).eq('following_id',target.id):await connection().from('aitu_follows').insert({follower_id:u.id,following_id:target.id}));return !old;}
 async function comments(postId){const rows=unwrap(await connection().from('aitu_comments').select('id,body,created_at,author:aitu_profiles(username,name,avatar_path)').eq('post_id',postId).order('created_at').limit(200));const url=await media(rows.map(x=>x.author.avatar_path));return rows.map(x=>({...x,...x.author,avatar:url(x.author.avatar_path)}));}
 async function comment(postId,body){const u=await identity();unwrap(await connection().from('aitu_comments').insert({author_id:u.id,post_id:postId,body:body.trim()}));}
 async function messages(username){const u=await identity(),other=await profile(username);const rows=unwrap(await connection().from('aitu_messages').select('*').or(`and(sender_id.eq.${u.id},recipient_id.eq.${other.id}),and(sender_id.eq.${other.id},recipient_id.eq.${u.id})`).order('created_at',{ascending:false}).limit(100));unwrap(await connection().from('aitu_messages').update({read_at:new Date().toISOString()}).eq('recipient_id',u.id).eq('sender_id',other.id).is('read_at',null));return {user:other,messages:rows.reverse()};}
 async function send(username,body){const u=await identity(),other=await profile(username);unwrap(await connection().from('aitu_messages').insert({sender_id:u.id,recipient_id:other.id,body:body.trim()}));}
 async function chats(){const u=await identity(),rows=unwrap(await connection().from('aitu_messages').select('*').or(`sender_id.eq.${u.id},recipient_id.eq.${u.id}`).order('created_at',{ascending:false}).limit(300));const grouped=new Map();for(const m of rows){const id=m.sender_id===u.id?m.recipient_id:m.sender_id;if(!grouped.has(id))grouped.set(id,{last_message:m.body,unread:0});if(m.recipient_id===u.id&&!m.read_at)grouped.get(id).unread++;}if(!grouped.size)return [];const people=await profiles(unwrap(await connection().from('aitu_profiles').select('*').in('id',[...grouped.keys()])));return [...grouped].map(([id,meta])=>({...people.find(p=>p.id===id),...meta})).filter(x=>x.username);}
 async function notifications(){const u=await identity();const messages=unwrap(await connection().from('aitu_messages').select('body,created_at,author:aitu_profiles!aitu_messages_sender_id_fkey(username,name,avatar_path)').eq('recipient_id',u.id).is('read_at',null).order('created_at',{ascending:false}).limit(20));const own=unwrap(await connection().from('aitu_posts').select('id').eq('author_id',u.id));const comments=own.length?unwrap(await connection().from('aitu_comments').select('body,created_at,post_id,author:aitu_profiles(username,name,avatar_path)').in('post_id',own.map(p=>p.id)).neq('author_id',u.id).order('created_at',{ascending:false}).limit(20)):[];const rows=[...messages.map(n=>({...n,type:'message'})),...comments.map(n=>({...n,type:'comment'}))].sort((a,b)=>b.created_at.localeCompare(a.created_at));const url=await media(rows.map(x=>x.author.avatar_path));return rows.map(n=>({...n,...n.author,avatar:url(n.author.avatar_path)}));}
 async function password(old,next){const u=await identity();unwrap(await connection().auth.signInWithPassword({email:u.email,password:old}));unwrap(await connection().auth.updateUser({password:next}));unwrap(await connection().auth.signOut({scope:'global'}));}
 return {configured,current,profile,signUp,signIn,signOut,search,updateProfile,upload,feed,publish,removePost,toggle,follow,comments,comment,messages,send,chats,notifications,password};
})();
