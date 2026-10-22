import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const env={window:{}};
vm.runInNewContext(readFileSync(new URL('../public/academics.js',import.meta.url),'utf8'),env);
const A=env.window.AituAcademics;
test('the AITU catalogue has 17 programmes and seven schools without inventing a general-education degree',()=>{
 assert.equal(A.programs.length,17);assert.equal(A.schools.length,7);
 assert.equal(new Set(A.programs.map(p=>p.code)).size,17);
 assert.equal(A.programs.filter(p=>p.school==='general').length,0);
 for(const p of A.programs){assert.ok(A.schools.some(s=>s.id===p.school));assert.match(p.code,/^6B[0-9]{5}$/);assert.ok(p.name);}
 assert.equal(A.program(A.defaultProgram).name,'Electronic Engineering');
});
test('group numbers preserve leading zeros and update their programme/year prefix',()=>{
 assert.equal(A.groupName(), 'EE-26xx');
 assert.equal(A.groupName('6B07102',1,'01'),'EE-2601');
 assert.equal(A.groupName('6B07102',2,'09'),'EE-2509');
 assert.equal(A.groupName('6B07102',3,'12'),'EE-2412');
 assert.equal(A.groupName('6B06102',1,'01'),'SE-2601');
 assert.equal(A.groupName('6B06101',1,'01'),'IT-2601');
 assert.equal(A.groupName('6B07103',2,'01'),'DNE-2501');
 assert.equal(A.groupName('6B04201',3,'01'),'DL-2401');
 assert.equal(A.groupName('6B07102',2),'EE-25xx');
 assert.equal(A.groupName('invalid',1,'01'),'');
 const result=A.normalize({program_code:'6B07102',course:'1',group_number:'01'});
 assert.equal(result.group_number,'01');assert.equal(result.course,1);
 for(const group_number of ['1','123','ab','０１','-1',''])assert.throws(()=>A.normalize({program_code:'6B07102',course:'1',group_number}),e=>e.code==='groupInvalid');
 assert.throws(()=>A.normalize({program_code:'invalid',course:1,group_number:'01'}),e=>e.code==='programInvalid');
 assert.throws(()=>A.normalize({program_code:'6B07102',course:4,group_number:'01'}),e=>e.code==='courseInvalid');
});
