// Preferences only. Profiles, posts and messages are never stored locally.
(() => {
 const read=(key,fallback)=>{try{return localStorage.getItem(key)||fallback;}catch{return fallback;}};
 const language=read('aitu.language','ru'), theme=read('aitu.theme','dark');
 document.documentElement.lang=['ru','en','kk'].includes(language)?language:'ru';
 document.documentElement.dataset.theme=theme==='light'?'light':'dark';
})();
