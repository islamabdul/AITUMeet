// Standalone server: requires only Node.js 22.13+, no npm packages.
import http from 'node:http';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import * as api from './local/api.mjs';
const root=path.dirname(fileURLToPath(import.meta.url)),staticRoot=path.join(root,'public'),port=Number(process.env.PORT||3000);
const types={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.png':'image/png','.svg':'image/svg+xml','.jpg':'image/jpeg','.webp':'image/webp'};
let queue=Promise.resolve();
async function handle(req,res){try{
 const url=new URL(req.url,`http://${req.headers.host||'127.0.0.1:'+port}`);
 if(url.pathname.startsWith('/api/')){
  if(!api[req.method]){res.writeHead(405);res.end();return;}
  const parts=[];let length=0;
  for await(const chunk of req){length+=chunk.length;if(length>2300000){res.writeHead(413,{'Content-Type':'application/json'});res.end(JSON.stringify({error:'Запрос слишком большой.'}));return;}parts.push(chunk);}
  const headers=new Headers();for(const [k,v]of Object.entries(req.headers))if(v)headers.set(k,Array.isArray(v)?v.join(', '):v);
  const request=new Request(url,{method:req.method,headers,...(!['GET','HEAD'].includes(req.method)?{body:Buffer.concat(parts)}:{})});
  const response=await api[req.method](request);res.writeHead(response.status,Object.fromEntries(response.headers));res.end(Buffer.from(await response.arrayBuffer()));return;
 }
 if(!['GET','HEAD'].includes(req.method)){res.writeHead(405);res.end();return;}
 const relative=decodeURIComponent(url.pathname==='/'?'/index.html':url.pathname),file=path.resolve(staticRoot,'.'+relative);
 if(!file.startsWith(staticRoot+path.sep)){res.writeHead(403);res.end();return;}
 const bytes=await readFile(file);res.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream','X-Content-Type-Options':'nosniff','Cache-Control':'no-cache'});res.end(req.method==='HEAD'?undefined:bytes);
}catch(error){res.writeHead(error.code==='ENOENT'?404:500,{'Content-Type':'text/plain; charset=utf-8'});res.end(error.code==='ENOENT'?'Не найдено':'Ошибка сервера');console.error(error.message);}}
// Serial requests prevent asynchronous crypto from interleaving SQLite transactions.
const server=http.createServer((req,res)=>{queue=queue.then(()=>handle(req,res)).catch(e=>console.error(e.message));});
server.listen(port,'127.0.0.1',()=>console.log(`AITUMeet is ready: http://127.0.0.1:${port}\nData is stored in ./data. Press Ctrl+C to stop.`));
