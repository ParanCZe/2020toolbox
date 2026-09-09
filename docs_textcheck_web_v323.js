(()=>{
  const APP_VERSION='V3.23';
  const webState={old:null,new:null};
  const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));

  function forceVersion(){const el=document.getElementById('app-version');if(el)el.textContent=APP_VERSION;}
  function cleanUrl(v){try{const u=new URL(String(v||'').trim());if(!/^https?:$/.test(u.protocol))return'';return u.href}catch(e){return''}}
  function htmlToText(html){
    const doc=new DOMParser().parseFromString(String(html||''),'text/html');
    doc.querySelectorAll('script,style,noscript,svg,canvas,nav,footer,header,form,aside').forEach(x=>x.remove());
    const main=doc.querySelector('main,article,[role="main"],#content,.content')||doc.body;
    return (main?.innerText||main?.textContent||'').replace(/\u00a0/g,' ').replace(/[ \t]+/g,' ').replace(/\n\s*\n\s*\n+/g,'\n\n').trim();
  }
  function markdownToText(md){
    return String(md||'')
      .replace(/^Title:.*$/gmi,'').replace(/^URL Source:.*$/gmi,'').replace(/^Published Time:.*$/gmi,'')
      .replace(/!\[[^\]]*\]\([^)]*\)/g,'').replace(/\[([^\]]+)\]\([^)]*\)/g,'$1')
      .replace(/^#{1,6}\s*/gm,'').replace(/^[-*+]\s+/gm,'').replace(/^>\s?/gm,'')
      .replace(/`{1,3}/g,'').replace(/\*\*/g,'').replace(/__/g,'')
      .replace(/[ \t]+/g,' ').replace(/\n{3,}/g,'\n\n').trim();
  }
  async function fetchPageText(url,status,label){
    status.textContent=`Načítám ${label} web…`;
    try{
      const r=await fetch(url,{mode:'cors',credentials:'omit',cache:'no-store'});
      if(r.ok){const ct=r.headers.get('content-type')||'';if(/text\/html|text\/plain|application\/xhtml/i.test(ct)){const t=await r.text(),txt=/html/i.test(ct)?htmlToText(t):t;if(txt.length>150)return{url,text:txt,method:'přímé načtení'};}}
    }catch(e){}
    status.textContent=`${label}: přímé načtení blokováno, používám textovou čtečku…`;
    const reader='https://r.jina.ai/http://'+url.replace(/^https?:\/\//i,'');
    const rr=await fetch(reader,{cache:'no-store'});
    if(!rr.ok)throw new Error(`${label}: stránku se nepodařilo načíst (${rr.status}).`);
    const raw=await rr.text(),txt=markdownToText(raw);
    if(txt.length<150)throw new Error(`${label}: stránka neobsahuje dost čitelného textu.`);
    return{url,text:txt,method:'textová čtečka'};
  }
  function splitSegments(text){
    const clean=String(text||'').replace(/\u00a0/g,' ').replace(/[ \t]+/g,' ').replace(/\n{3,}/g,'\n\n').trim();
    let chunks=clean.split(/\n\s*\n|(?<=[.!?;:])\s+(?=[A-ZÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ0-9§])/).map(x=>x.trim()).filter(x=>x.length>=55);
    const out=[];for(let c of chunks){if(c.length<=700){out.push({page:'web',text:c});continue;}const ss=c.split(/(?<=[.!?;])\s+/);let b='';for(const s of ss){if((b+' '+s).length>650&&b.length>80){out.push({page:'web',text:b.trim()});b=''}b+=(b?' ':'')+s}if(b.length>55)out.push({page:'web',text:b.trim()});}return out;
  }
  function normalize(s){return String(s||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9%°²³.,/+\- ]+/g,' ').replace(/\s+/g,' ').trim()}
  const STOP=new Set('a i ale nebo ani ze se je jsou byl byla bylo byly byt do od na v ve z ze s u o k ke pro pri podle jako ktery ktera ktere jejich jeho jeji tento tato toto mezi nad pod pred po bez take pak kde kdy co jak zda jiz jen aby nez tim teto tohoto tech ty'.split(' '));
  function toks(s){return [...new Set(normalize(s).split(' ').filter(w=>w.length>2&&!STOP.has(w)))]}
  function sim(a,b){const A=new Set(toks(a)),B=new Set(toks(b));if(!A.size||!B.size)return 0;let h=0;for(const x of A)if(B.has(x))h++;return h/Math.max(A.size,B.size)}
  function vals(s){const rx=/(\d+(?:[.,]\d+)?)\s*(mm|cm|dm|m|km|m2|m²|m3|m³|%|°|kn|n|mpa|kpa|pa|lx|db|h|min|s|kg|t)?/gi,o=[];let m;while((m=rx.exec(String(s||''))))o.push(m[1].replace(',','.')+(m[2]?' '+m[2].toLowerCase():''));return o}
  function valDiff(a,b){return vals(a).join('|')!==vals(b).join('|')&&(vals(a).length||vals(b).length)}
  function best(seg,list){let b=null;for(const c of list){const s=sim(seg.text,c.text);if(!b||s>b.score)b={seg:c,score:s}}return b}
  function compare(a,b){
    const out=[],used=new Set();for(const o of a){const m=best(o,b);if(!m||m.score<.34){out.push({old:o,new:null,score:m?.score||0,type:'ODSTRANĚNO',prio:3});continue}used.add(m.seg);let type='';if(valDiff(o.text,m.seg.text)&&m.score>=.38)type='ZMĚNA HODNOTY';else if(m.score>=.88)type='SHODNÝ / PŘESUNUTÝ TEXT';else if(m.score>=.5)type='ZMĚNA FORMULACE';else type='SLABÁ SHODA';if(type!=='SHODNÝ / PŘESUNUTÝ TEXT'||valDiff(o.text,m.seg.text))out.push({old:o,new:m.seg,score:m.score,type,prio:type==='ZMĚNA HODNOTY'?5:type==='ZMĚNA FORMULACE'?4:2});}
    for(const n of b){if(used.has(n))continue;const m=best(n,a);if(!m||m.score<.34)out.push({old:null,new:n,score:m?.score||0,type:'NOVĚ PŘIDÁNO',prio:3});}
    return out.sort((x,y)=>y.prio-x.prio||y.score-x.score).slice(0,400);
  }
  function renderWebResults(results){
    const host=document.getElementById('textcheck-results');if(!host)return;window.__textcheckWebResults=results;
    if(!results.length){host.innerHTML='<div class="docs-empty">Nebyly nalezeny významné rozdíly.</div>';return}
    const counts={};results.forEach(r=>counts[r.type]=(counts[r.type]||0)+1);
    host.innerHTML=`<div class="textcheck-summary">${Object.entries(counts).map(([k,v])=>`<span><b>${v}</b> ${esc(k)}</span>`).join('')}</div>`+results.map((r,i)=>`<article class="textcheck-card ${r.type==='ZMĚNA HODNOTY'?'error':/ZMĚNA|ODSTRAN|PŘIDÁNO/.test(r.type)?'warn':'ok'}" id="webcheck-${i}"><div class="textcheck-head"><span class="textcheck-type">${esc(r.type)}</span><span>podobnost ${Math.round((r.score||0)*100)} %</span></div><div class="textcheck-pages"><b>Stará:</b> web &nbsp;→&nbsp; <b>Nová:</b> web</div><div class="textcheck-cols"><div><b>STARÝ TEXT</b><p>${esc(r.old?.text||'—')}</p></div><div><b>NOVÝ TEXT</b><p>${esc(r.new?.text||'—')}</p></div></div>${r.old&&r.new&&valDiff(r.old.text,r.new.text)?`<div class="textcheck-values"><b>Hodnoty:</b> ${esc(vals(r.old.text).join(', ')||'—')} → ${esc(vals(r.new.text).join(', ')||'—')}</div>`:''}<div class="textcheck-actions"><button class="back-btn" onclick="window.webTextcheckRecheck(${i})">Projít znovu tento výsledek</button><a class="back-btn" href="${esc(webState.old?.url||'#')}" target="_blank" rel="noopener">Otevřít starý zdroj ↗</a><a class="back-btn" href="${esc(webState.new?.url||'#')}" target="_blank" rel="noopener">Otevřít nový zdroj ↗</a></div></article>`).join('');
  }
  window.webTextcheckRecheck=i=>{const r=window.__textcheckWebResults?.[i];if(!r||!webState.old||!webState.new)return;if(r.old){const m=best(r.old,splitSegments(webState.new.text));if(m){r.new=m.seg;r.score=m.score;r.type=valDiff(r.old.text,r.new.text)&&m.score>=.38?'ZMĚNA HODNOTY':m.score>=.5?'ZMĚNA FORMULACE':'SLABÁ SHODA';}}else if(r.new){const m=best(r.new,splitSegments(webState.old.text));if(m){r.old=m.seg;r.score=m.score;}}renderWebResults(window.__textcheckWebResults);setTimeout(()=>document.getElementById('webcheck-'+i)?.scrollIntoView({behavior:'smooth',block:'center'}),20)};
  async function runWeb(){
    const st=document.getElementById('textcheck-status'),btn=document.getElementById('textcheck-web-run'),u1=cleanUrl(document.getElementById('textcheck-old-url')?.value),u2=cleanUrl(document.getElementById('textcheck-new-url')?.value);if(!u1||!u2){st.textContent='Vlož platný starý i nový odkaz.';return}
    try{btn.disabled=true;webState.old=await fetchPageText(u1,st,'starý zdroj');webState.new=await fetchPageText(u2,st,'nový zdroj');st.textContent='Porovnávám text z webových stránek…';const a=splitSegments(webState.old.text),b=splitSegments(webState.new.text),res=compare(a,b);renderWebResults(res);st.textContent=`Hotovo. Starý zdroj: ${a.length} textových úseků (${webState.old.method}) · nový zdroj: ${b.length} úseků (${webState.new.method}) · ${res.length} nálezů.`;}catch(e){st.textContent='Chyba: '+(e.message||e)}finally{btn.disabled=false}
  }
  function inject(){
    const sec=document.getElementById('docs-textcheck');if(!sec||document.getElementById('textcheck-web-box'))return;
    const files=sec.querySelector('.textcheck-files');if(!files)return;
    const or=document.createElement('div');or.id='textcheck-web-box';or.innerHTML=`<div class="textcheck-or"><span>NEBO POROVNAT PŘÍMO WEBOVÉ STRÁNKY</span></div><div class="textcheck-web-grid"><label><b>STARÝ ODKAZ</b><input id="textcheck-old-url" type="url" placeholder="https://…"></label><label><b>NOVÝ ODKAZ</b><input id="textcheck-new-url" type="url" placeholder="https://…"></label></div><div class="row"><button class="action" id="textcheck-web-run">Načíst odkazy a porovnat</button></div><div class="docs-note">Webový režim nejdřív zkusí stránku načíst přímo. Pokud web blokuje přístup z prohlížeče, použije textovou čtečku. Funguje na běžných veřejných HTML stránkách; stránky za přihlášením nebo s blokací robotů nemusí jít načíst.</div>`;
    files.parentNode.insertBefore(or,files.nextSibling);document.getElementById('textcheck-web-run').onclick=runWeb;
  }
  function css(){if(document.getElementById('textcheck-web-v323-style'))return;const s=document.createElement('style');s.id='textcheck-web-v323-style';s.textContent=`#tool-docs .textcheck-or{display:flex;align-items:center;gap:10px;margin:16px 0 10px;color:var(--muted);font-size:9px;letter-spacing:.45px}.textcheck-or:before,.textcheck-or:after{content:"";height:1px;background:var(--border);flex:1}.textcheck-web-grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:10px}.textcheck-web-grid label{border:1px solid var(--border);border-radius:9px;background:#fafafa;padding:12px;display:flex;flex-direction:column;gap:8px}.textcheck-web-grid label b{font:normal 12px 'Antarctican Mono',monospace}.textcheck-web-grid input{width:100%}.textcheck-actions a.back-btn{text-decoration:none;display:inline-flex;align-items:center}@media(max-width:700px){.textcheck-web-grid{grid-template-columns:1fr}}`;document.head.appendChild(s)}
  function init(){forceVersion();css();inject();setTimeout(()=>{forceVersion();inject()},400);setTimeout(forceVersion,1600)}
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();