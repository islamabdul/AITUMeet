/* AITU bachelor catalogue, checked 2026-10-22: https://astanait.edu.kz/ru/bachelor
   Group prefixes are app abbreviations approved by the project owner, not an official registry.
   EE, IT, DNE and DL follow the owner's exact mappings. Academic year: 2026/27. */
window.AituAcademics = (() => {
 const academicYear=2026, defaultProgram='6B07102';
 const schools=[
  {id:'software',names:['Школа программной инженерии','School of Software Engineering','Бағдарламалық инженерия мектебі']},
  {id:'ai-data',names:['Школа искусственного интеллекта и науки о данных','School of Artificial Intelligence and Data Science','Жасанды интеллект және деректер ғылымы мектебі']},
  {id:'cybersecurity',names:['Школа кибербезопасности','School of Cybersecurity','Киберқауіпсіздік мектебі']},
  {id:'intelligent',names:['Школа интеллектуальных систем','School of Intelligent Systems','Зияткерлік жүйелер мектебі']},
  {id:'creative',names:['Школа креативных индустрий','School of Creative Industries','Креативті индустриялар мектебі']},
  {id:'digital-government',names:['Школа цифрового государственного управления','School of Digital Public Administration','Цифрлық мемлекеттік басқару мектебі']},
  {id:'general',names:['Школа общеобразовательных дисциплин','School of General Education Disciplines','Жалпы білім беру пәндері мектебі']}
 ];
 const programs=[
  {code:'6B06102',school:'software',name:'Software Engineering',prefix:'SE'},
  {code:'6B06101',school:'ai-data',name:'Computer Science',prefix:'IT'},
  {code:'6B06103',school:'ai-data',name:'Big Data Analysis',prefix:'BDA'},
  {code:'6B06107',school:'ai-data',name:'Mathematical and Computational Science',prefix:'MCS'},
  {code:'6B06301',school:'cybersecurity',name:'Cybersecurity',prefix:'CYB'},
  {code:'6B06302',school:'cybersecurity',name:'Smart Security Technologies',prefix:'SST'},
  {code:'6B07101',school:'intelligent',name:'Industrial Internet of Things',prefix:'IIOT'},
  {code:'6B07102',school:'intelligent',name:'Electronic Engineering',prefix:'EE'},
  {code:'6B06202',school:'intelligent',name:'Smart Technologies',prefix:'ST'},
  {code:'6B07103',school:'intelligent',name:'Digital Technologies in Nuclear Power Engineering',prefix:'DNE'},
  {code:'6B06105',school:'creative',name:'Media Technologies',prefix:'MT'},
  {code:'6B03201',school:'creative',name:'Digital Journalism',prefix:'DJ'},
  {code:'6B04104',school:'digital-government',name:'Digital Public Administration',prefix:'DPA'},
  {code:'6B04201',school:'digital-government',name:'Digital Jurisprudence',prefix:'DL'},
  {code:'6B04103',school:'digital-government',name:'AI Business',prefix:'AIB'},
  {code:'6B04101',school:'digital-government',name:'IT Management',prefix:'ITM'},
  {code:'6B04102',school:'digital-government',name:'IT Entrepreneurship',prefix:'ITE'}
 ];
 const program=code=>programs.find(p=>p.code===code);
 const schoolName=(id,language='ru')=>schools.find(s=>s.id===id)?.names[['ru','en','kk'].indexOf(language)]||'';
 function groupPrefix(code=defaultProgram,course=1){const p=program(code);return p&&[1,2,3].includes(Number(course))?`${p.prefix}-${String(academicYear-Number(course)+1).slice(-2)}`:'';}
 function groupName(code,course,number=''){const prefix=groupPrefix(code,course);return prefix?prefix+(/^[0-9]{2}$/.test(number)?number:'xx'):'';}
 function normalize(data){
  if(!program(data.program_code))throw {code:'programInvalid'};
  if(![1,2,3].includes(Number(data.course)))throw {code:'courseInvalid'};
  const group_number=String(data.group_number??'').trim();
  if(!/^[0-9]{2}$/.test(group_number))throw {code:'groupInvalid'};
  return {program_code:data.program_code,course:Number(data.course),group_number};
 }
 return {academicYear,defaultProgram,schools,programs,program,schoolName,groupPrefix,groupName,normalize};
})();
