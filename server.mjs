// Static website server only. Auth, records and uploads live in Supabase.
import http from 'node:http';
import path from 'node:path';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const root=path.join(path.dirname(fileURLToPath(import.meta.url)),'public');
const port=Number(process.env.PORT||3000),host=process.env.HOST||'127.0.0.1';
const key=process.env.SUPABASE_PUBLISHABLE_KEY||'';
let secret=key.startsWith('sb_secret_');
try{secret ||= JSON.parse(Buffer.from(key.split('.')[1]||'','base64url').toString()).role==='service_role';}catch{}
if(secret)throw new Error('Use a Supabase PUBLIC publishable/anon key, never a secret or service_role key.');
const types={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.png':'image/png','.jpg':'image/jpeg','.webp':'image/webp','.svg':'image/svg+xml','.woff2':'font/woff2'};
const server=http.createServer(async(req,res)=>{
 try{
  if(!['GET','HEAD'].includes(req.method)){res.writeHead(405,{'Allow':'GET, HEAD'});res.end();return;}
  const url=new URL(req.url,'http://localhost');
  const headers={'X-Content-Type-Options':'nosniff','Referrer-Policy':'strict-origin-when-cross-origin','Cache-Control':'no-cache'};
  if(url.pathname==='/config.js'&&process.env.SUPABASE_URL){const config={supabaseUrl:process.env.SUPABASE_URL,supabasePublishableKey:key,storageBucket:'aitu-media'};res.writeHead(200,{...headers,'Content-Type':types['.js']});res.end(req.method==='HEAD'?undefined:'window.AITU_CONFIG = Object.freeze('+JSON.stringify(config)+');');return;}
  const file=path.resolve(root,'.'+decodeURIComponent(url.pathname==='/'?'/index.html':url.pathname));
  if(!file.startsWith(root+path.sep)){res.writeHead(403);res.end();return;}
  const content=await readFile(file);res.writeHead(200,{...headers,'Content-Type':types[path.extname(file)]||'application/octet-stream'});res.end(req.method==='HEAD'?undefined:content);
 }catch(e){res.writeHead(e.code==='ENOENT'||e.code==='EISDIR'?404:500,{'Content-Type':'text/plain; charset=utf-8'});res.end('Not found');}
});
server.listen(port,host,()=>console.log(`AITUMeet: http://${host}:${port}\nStatic server. No local database. Ctrl+C to stop.`));
