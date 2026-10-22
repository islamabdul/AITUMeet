import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const root=new URL('../',import.meta.url);
const file=name=>readFileSync(new URL(name,root),'utf8');
function environment(){const memory=new Map();return {window:{},document:{documentElement:{lang:'ru',dataset:{}}},localStorage:{getItem:k=>memory.get(k),setItem:(k,v)=>memory.set(k,v)},Intl,Date};}
test('all translations have Russian, English and Kazakh text',()=>{
 const env=environment();vm.runInNewContext(file('public/i18n.js'),env);
 const {strings}=env.window.AituI18n;assert.ok(Object.keys(strings).length>150);
 for(const [key,value]of Object.entries(strings)){assert.equal(value.length,3,key);for(const text of value)assert.ok(typeof text==='string'&&text.length,key);const tokens=s=>[...s.matchAll(/\{(\w+)\}/g)].map(x=>x[1]).sort().join(',');assert.equal(tokens(value[0]),tokens(value[1]),key);assert.equal(tokens(value[0]),tokens(value[2]),key);}
 for(const match of file('public/app.js').matchAll(/\bt\('([^']+)'/g))assert.ok(strings[match[1]],match[1]);
});
test('theme and language persist, invalid preference values are contained',()=>{
 const env=environment();env.localStorage.setItem('aitu.theme','light');env.localStorage.setItem('aitu.language','kk');vm.runInNewContext(file('public/preferences.js'),env);assert.equal(env.document.documentElement.lang,'kk');assert.equal(env.document.documentElement.dataset.theme,'light');
 vm.runInNewContext(file('public/i18n.js'),env);env.window.AituI18n.set('en');assert.equal(env.localStorage.getItem('aitu.language'),'en');assert.equal(env.window.AituI18n.t('login'),'Sign in');env.window.AituI18n.set('invalid');assert.equal(env.document.documentElement.lang,'en');
});
test('there are no demo profiles, demo posts, barcode output or local database imports',()=>{
 const code=file('public/app.js'),server=file('server.mjs');assert.doesNotMatch(code,/samplePeople|samplePosts|demo1|barcode|student_code|STUDENT ID/);assert.doesNotMatch(server,/node:sqlite|DatabaseSync|local\/runtime/);
 const adapter=file('public/supabase-api.js');assert.doesNotMatch(adapter,/student_code|aitu_private|local\/api|fetch\(['"]api\//);assert.match(adapter,/name\.ilike/);assert.match(adapter,/username\.ilike/);assert.doesNotMatch(adapter,/id\.ilike/);
});
test('unconfigured Supabase stays empty and reports an explicit setup error',async()=>{
 const env={window:{AITU_CONFIG:{supabaseUrl:'',supabasePublishableKey:''}},Map,Set};vm.runInNewContext(file('public/supabase-api.js'),env);assert.equal(env.window.AituAPI.configured(),false);assert.equal(await env.window.AituAPI.current(),null);await assert.rejects(env.window.AituAPI.search(),e=>e.code==='setupRequired');
});
test('browser adapter refuses privileged Supabase keys',async()=>{
 const env={window:{AITU_CONFIG:{supabaseUrl:'https://test.supabase.co',supabasePublishableKey:'sb_secret_test'}},Map,Set};vm.runInNewContext(file('public/supabase-api.js'),env);await assert.rejects(env.window.AituAPI.search(),e=>e.code==='unsafeKey');
});
