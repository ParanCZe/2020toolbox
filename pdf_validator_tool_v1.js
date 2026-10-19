// 20-20 TOOLBOX · PDF Validator · local bridge: veraPDF + qualified eIDAS
(function(){
  'use strict';
  const API='http://127.0.0.1:8094';
  const files=[], results=new Map(), expanded=new Set();
  let dssPoll=null;
  let token='',ready=false,busy=false;
  const css=document.createElement('style');
  css.textContent='#tool-pdfvalidator .pv-drop{border:1px dashed #a1a1aa;border-radius:10px;background:#fafafa;min-height:100px;padding:24px;text-align:center;cursor:pointer;display:flex;flex-direction:column;justify-content:center;gap:6px}'
    +'#tool-pdfvalidator .pv-drop.over{background:#fefcd6}#tool-pdfvalidator .pv-actions{display:flex;gap:9px;align-items:center;flex-wrap:wrap;margin:12px 0}'
    +'#tool-pdfvalidator .pv-actions button{border:1px solid #d4d4d8;background:#fff;border-radius:7px;padding:9px 12px;cursor:pointer}'
    +'#tool-pdfvalidator .pv-actions button:disabled{opacity:.5;cursor:not-allowed}#tool-pdfvalidator #pv-start{background:#18181b;color:#fff}'
    +'#tool-pdfvalidator .pv-note{padding:12px;background:#fafafa;border:1px solid #ddd;border-radius:8px;font-size:12px;margin:12px 0;line-height:1.6}'
    +'#tool-pdfvalidator .pv-table-wrap{overflow-x:auto;border:1px solid #e4e4e7;border-radius:9px}#tool-pdfvalidator table{border-collapse:collapse;width:100%;min-width:720px;font-size:11px}'
    +'#tool-pdfvalidator th,#tool-pdfvalidator td{text-align:left;padding:11px;border-bottom:1px solid #eee}#tool-pdfvalidator th{background:#fafafa;color:#71717a}'
    +'#tool-pdfvalidator .pv-tag{display:inline-block;padding:4px 6px;border-radius:5px;background:#f1f1f3;white-space:nowrap}'
    +'#tool-pdfvalidator .pv-tag.valid{color:#086b3d;background:#ddf7e7}#tool-pdfvalidator .pv-tag.invalid{color:#ac2020;background:#ffe0e0}'
    +'#tool-pdfvalidator .pv-tag.unverified{color:#8a5900;background:#fff1d0}'
    +'#tool-pdfvalidator .pv-error{background:#fff0ea;border:1px solid #f0b6a2;border-radius:8px;padding:12px;white-space:pre-wrap;overflow-wrap:anywhere;color:#852b12;margin:8px 0;font-size:12px}'
    +'#tool-pdfvalidator .pv-tag.consistent{background:#e4f6ec;color:#15603c}#tool-pdfvalidator .pv-tag.warning{background:#fff1d0;color:#8a5900}#tool-pdfvalidator .pv-tag.conflict{background:#ffe0e0;color:#ac2020}'
    +'#tool-pdfvalidator .pv-detailcell{padding:15px!important;background:#f8fafc}#tool-pdfvalidator .pv-detail{display:grid;gap:13px}'
    +'#tool-pdfvalidator .pv-summary{font-size:13px;font-weight:650}#tool-pdfvalidator .pv-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(205px,1fr));gap:9px}'
    +'#tool-pdfvalidator .pv-card{background:#fff;border:1px solid #e3e5e9;border-radius:10px;padding:12px;min-width:0}'
    +'#tool-pdfvalidator .pv-card b{display:block;margin-bottom:8px;font-size:12px}#tool-pdfvalidator .pv-fact{display:flex;justify-content:space-between;gap:10px;padding:4px 0;font-size:12px;align-items:baseline}'
    +'#tool-pdfvalidator .pv-fact span:first-child{color:#71717a}#tool-pdfvalidator .pv-fact strong{font-weight:650;text-align:right;overflow-wrap:anywhere}'
    +'#tool-pdfvalidator .pv-explain{font-size:12px;color:#52525b;line-height:1.55}#tool-pdfvalidator .pv-messages{margin:4px 0 0;padding-left:20px;font-size:12px;line-height:1.7}'
    +'#tool-pdfvalidator .pv-note-list{font-size:12px;line-height:1.65}#tool-pdfvalidator .pv-file{max-width:265px;overflow-wrap:anywhere}';
  document.head.appendChild(css);
  const host=document.getElementById('tool-3dprint')?.parentElement||document.querySelector('.card');
  if(!host)return;
  const view=document.createElement('div');
  view.id='tool-pdfvalidator';view.className='tool-view';
  view.innerHTML='<button class="back-btn" onclick="closeTool()">← Zpět do menu</button>'
    +'<h1>PDF Validator</h1><p class="muted">Lokální nezávislá kontrola PDF/A-3b, elektronických podpisů a kvalifikovaných časových razítek.</p>'
    +'<div id="pv-health" class="pv-note">Kontroluji lokální validační engine…</div>'
    +'<div class="pv-actions"><button id="pv-install-dss" type="button">Nainstalovat EU DSS (cca 630 MB)</button><span id="pv-install-note" class="muted"></span></div>'
    +'<div id="pv-drop" class="pv-drop" tabindex="0" role="button"><strong>Přetáhni PDF nebo klikni pro výběr</strong><small>PDF soubory zůstávají na tomto počítači.</small></div>'
    +'<input id="pv-input" type="file" accept=".pdf,application/pdf" multiple hidden>'
    +'<div class="pv-actions"><button id="pv-start">Spustit kontrolu</button><button id="pv-clear">Vyčistit</button><button id="pv-refresh">Stav validátoru</button><span id="pv-progress"></span></div>'
    +'<div id="pv-error" class="pv-error" role="alert" hidden></div>'
    +'<div class="pv-table-wrap"><table><thead><tr><th>Soubor</th><th>PDF/A-3b</th><th>Kryptografie</th><th>QES</th><th>QTSA</th><th>Podklady PDF</th><th>Výsledek</th></tr></thead><tbody id="pv-results"></tbody></table></div>'
    +'<p class="pv-note">PDF/A-3b ověřuje lokální veraPDF; QES a QTSA přímo lokální evropský engine EU DSS 6.5. PDF se neodesílá na vzdálený validační server. EU DSS může stahovat veřejné evropské důvěryhodné seznamy a OCSP/CRL. '
    +'<a target="_blank" rel="noopener noreferrer" href="https://ec.europa.eu/digital-building-blocks/DSS/webapp-demo/validation">Oficiální online EU DSS ↗</a> (nahrání PDF na externí server).</p>';
  host.appendChild(view);
  const $=id=>document.getElementById(id);
  const names={
    pdfa:{valid:'VYHOVUJE',invalid:'NEVYHOVUJE'},
    crypto:{valid:'PLATNÁ',invalid:'NEPLATNÁ'},
    signature:{valid:'QES OK',invalid:'NEPLATNÝ'},
    timestamp:{valid:'QTSA OK',invalid:'NEPLATNÉ'}
  };
  function label(value,key){return names[key][value]||'NEOVĚŘENO';}
  function tag(value,key){const s=document.createElement('span');s.className='pv-tag '+(value||'unverified');s.textContent=label(value,key);return s;}
  const evidenceStates={consistent:'BEZ ROZPORU',warning:'PROVĚŘIT',conflict:'NESOULAD',unverified:'NEZJIŠTĚNO'};
  function evidenceName(data){return evidenceStates[data?.consistency?.status]||'NEZJIŠTĚNO';}
  function fact(parent,key,value){
    const row=document.createElement('div');row.className='pv-fact';
    const left=document.createElement('span');left.textContent=key;
    const right=document.createElement('strong');right.textContent=String(value);
    row.append(left,right);parent.appendChild(row);
  }
  function card(parent,title){
    const box=document.createElement('div');box.className='pv-card';
    const name=document.createElement('b');name.textContent=title;
    box.appendChild(name);parent.appendChild(box);return box;
  }
  function detailView(parent,file,data){
    const wrap=document.createElement('div');wrap.className='pv-detail';
    const headline=document.createElement('div');headline.className='pv-summary';
    const state=data?.consistency?.status||'unverified';
    headline.textContent=state==='conflict'?'Nesoulad mezi dílčími kontrolami — prohlédni poznámky.':
      state==='warning'?'Technická kontrola dokončena; některé podklady vyžadují pozornost.':
      state==='consistent'?'Technický obsah a výsledky se vzájemně nevylučují.':
      'Technickou kontrolu se nepodařilo dokončit.';
    wrap.appendChild(headline);
    const grid=document.createElement('div');grid.className='pv-grid';
    const a=card(grid,'Nezávislé ověření');
    fact(a,'PDF/A-3b',label(data.pdfa,'pdfa'));
    fact(a,'Kryptografická integrita',label(data.crypto,'crypto'));
    fact(a,'Kvalifikovaný podpis (QES)',label(data.signature,'signature'));
    fact(a,'Kvalifikované razítko (QTSA)',label(data.timestamp,'timestamp'));
    const ev=data.structure||{},sigs=ev.signatures||[],dss=ev.pdf_dss||{};
    const doc=card(grid,'Podklady dlouhodobé validace');
    fact(doc,'PDF /DSS',ev.status==='inspected'?(dss.present?'ANO':'NE'):'NEZJIŠTĚNO');
    fact(doc,'OCSP v /DSS',ev.status==='inspected'?dss.ocsp||0:'—');
    fact(doc,'CRL v /DSS',ev.status==='inspected'?dss.crl||0:'—');
    fact(doc,'Certifikáty v /DSS',ev.status==='inspected'?dss.certificates||0:'—');
    if(!sigs.length){
      const sigbox=card(grid,'Elektronické podpisy');
      fact(sigbox,'Nalezená pole',ev.status==='inspected'?'0':'NEZJIŠTĚNO');
    }else{
      sigs.forEach((sign,i)=>{
        const b=card(grid,'Podpis '+(i+1)+(sign.field?' · '+sign.field:''));
        fact(b,'Formát PDF /SubFilter',sign.subfilter||'nezjištěno');
        fact(b,'Pokrývá celý soubor',sign.covers_whole_file===true?'ANO':sign.covers_whole_file===false?'NE / starší revize':'NEZJIŠTĚNO');
        fact(b,'Certifikáty v CMS',sign.cms_readable?sign.certificates_in_cms:'NEZJIŠTĚNO');
        fact(b,'Podpisová RFC3161 razítka',sign.cms_readable?sign.timestamp_tokens_in_cms:'NEZJIŠTĚNO');
        fact(b,'OCSP/CRL ve vnitřních atributech CMS',sign.cms_readable?(sign.revocation_values_in_cms?'PŘÍTOMNÉ':'NENALEZENÉ'):'NEZJIŠTĚNO');
      });
    }
    wrap.appendChild(grid);
    const desc=document.createElement('p');desc.className='pv-explain';
    desc.textContent='Přítomnost certifikátů, OCSP/CRL nebo razítka v PDF sama o sobě nepotvrzuje jejich platnost ani profil PAdES-LT. Právní kvalifikaci a důvěryhodnost posuzuje EU DSS. Chybějící podklady mohou být dostupné online.';
    wrap.appendChild(desc);
    const notes=[...(data.consistency?.messages||[]),...(ev.messages||[]),...(data.messages||[])].filter(Boolean);
    if(notes.length){
      const noteBox=document.createElement('div');noteBox.className='pv-card';
      const heading=document.createElement('b');heading.textContent='Závěry a upozornění';noteBox.appendChild(heading);
      const list=document.createElement('ul');list.className='pv-messages';
      for(const item of notes.slice(0,20)){const li=document.createElement('li');li.textContent=String(item);list.appendChild(li);}
      noteBox.appendChild(list);wrap.appendChild(noteBox);
    }
    const sha=document.createElement('p');sha.className='pv-explain';
    sha.textContent='SHA-256 PDF: '+(data.sha256||'neuvedeno')+' · Výsledek platí jen pro tento konkrétní soubor.';
    wrap.appendChild(sha);parent.appendChild(wrap);
  }
  function reportText(f,data){
    const struct=data.structure||{},dss=struct.pdf_dss||{},signs=struct.signatures||[];
    let text='20-20 PDF Validator\nSoubor: '+f.name+'\nSHA-256: '+(data.sha256||'')
      +'\nPDF/A-3b: '+label(data.pdfa,'pdfa')
      +'\nKryptografická integrita: '+label(data.crypto,'crypto')
      +'\nKvalifikovaný podpis: '+label(data.signature,'signature')
      +'\nKvalifikované TSA: '+label(data.timestamp,'timestamp')
      +'\nShoda dílčích výsledků: '+evidenceName(data)
      +'\n\nPŘÍTOMNÉ VALIDAČNÍ PODKLADY (nikoliv ověření platnosti)'
      +'\nPDF /DSS: '+(dss.present?'ANO':'NE / neověřeno')
      +'\n/DSS OCSP: '+(dss.ocsp||0)+' · CRL: '+(dss.crl||0)+' · certifikáty: '+(dss.certificates||0);
    signs.forEach((s,i)=>{text+='\nPodpis '+(i+1)+': '+(s.field||'bez názvu')+' · '+(s.subfilter||'neznámý formát')
      +' · celý PDF: '+String(s.covers_whole_file)
      +' · certifikáty CMS: '+s.certificates_in_cms
      +' · časová razítka CMS: '+s.timestamp_tokens_in_cms
      +' · OCSP/CRL atributy CMS: '+String(s.revocation_values_in_cms);});
    text+='\n\nPOZNÁMKY\n'+[...(data.consistency?.messages||[]),...(struct.messages||[]),...(data.messages||[])].join('\n');
    return text+'\n\n'+(data.report||'');
  }
  function render(){
    const body=$('pv-results');body.replaceChildren();
    if(!files.length){const tr=body.insertRow(),td=tr.insertCell();td.colSpan=7;td.textContent='Žádné PDF zatím nebylo vybráno.';}
    files.forEach(file=>{
      const data=results.get(file)||{};
      const row=body.insertRow(),td=row.insertCell();
      td.className='pv-file';td.textContent=file.name;
      for(const key of ['pdfa','crypto','signature','timestamp'])row.insertCell().appendChild(tag(data[key],key));
      const evidence=row.insertCell(),ev=document.createElement('span'),state=data.consistency?.status||'unverified';
      ev.className='pv-tag '+state;ev.textContent=evidenceName(data);evidence.appendChild(ev);
      const actions=row.insertCell();
      const more=document.createElement('button');more.type='button';more.textContent=expanded.has(file)?'Skrýt detail ↑':'Detail ↓';
      more.disabled=!results.has(file);more.addEventListener('click',()=>{if(expanded.has(file))expanded.delete(file);else expanded.add(file);render();});
      actions.appendChild(more);
      const button=document.createElement('button');button.type='button';button.textContent='TXT';button.disabled=!results.has(file);
      button.addEventListener('click',()=>{
        const u=URL.createObjectURL(new Blob([reportText(file,results.get(file))],{type:'text/plain;charset=utf-8'}));
        const a=document.createElement('a');a.href=u;a.download=file.name.replace(/\.pdf$/i,'')+'_validace.txt';a.click();
        setTimeout(()=>URL.revokeObjectURL(u),1000);
      });
      actions.appendChild(button);
      if(expanded.has(file)&&results.has(file)){
        const extra=body.insertRow();const cell=extra.insertCell();cell.colSpan=7;cell.className='pv-detailcell';
        detailView(cell,file,data);
      }
    });
    $('pv-start').disabled=busy||!ready||files.length===0;
    $('pv-clear').disabled=busy;
  }
  function add(incoming){
    if(busy)return;
    for(const f of incoming||[]){
      if(files.length>=35)break;
      if(!/\.pdf$/i.test(f.name)||f.size>150*1024*1024)continue;
      if(!files.some(x=>x.name===f.name&&x.size===f.size&&x.lastModified===f.lastModified))files.push(f);
    }render();
  }
  $('pv-drop').onclick=()=>$('pv-input').click();
  $('pv-drop').onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();$('pv-input').click();}};
  $('pv-input').onchange=e=>{add(e.target.files);e.target.value='';};
  for(const event of ['dragenter','dragover'])$('pv-drop').addEventListener(event,e=>{e.preventDefault();$('pv-drop').classList.add('over');});
  for(const event of ['dragleave','drop'])$('pv-drop').addEventListener(event,e=>{e.preventDefault();$('pv-drop').classList.remove('over');});
  $('pv-drop').addEventListener('drop',e=>add(e.dataTransfer.files));
  $('pv-clear').onclick=()=>{files.length=0;results.clear();expanded.clear();$('pv-error').hidden=true;$('pv-error').textContent='';render();};
  async function session(){
    if(token)return token;
    const r=await fetch(API+'/session',{cache:'no-store'}),j=await r.json();
    if(!r.ok||!j.ok||!j.token)throw Error(j.error||'Bridge nevydal session');
    token=j.token;return token;
  }
  async function health(){
    try{
      const r=await fetch(API+'/status',{cache:'no-store'}),j=await r.json();
      if(!r.ok||!j.features?.local_eu_dss_validator)throw Error('Vyžadován aktualizovaný AuthorizationBridge 2.3.0.');
      const t=await session();
      const s=await fetch(API+'/validator-status',{headers:{'X-20-20-Session':t},cache:'no-store'}),d=await s.json();
      if(!s.ok||!d.ok)throw Error(d.error||'Nelze načíst stav');
      ready=!!d.verapdf_ready;
      $('pv-health').textContent='AuthorizationBridge '+(d.bridge_version||'')+
        ' · veraPDF: '+(d.verapdf_ready?'připraveno':'chybí')+
        ' · EU DSS 6.5 (QES/QTSA): '+(d.dss_ready?'nainstalováno':d.dss_installing?'probíhá instalace':'není nainstalováno')+
        (ready?' · Kontrola PDF/A je připravená.':' · Nainstaluj veraPDF.');
      $('pv-install-dss').hidden=!!d.dss_installed;
      $('pv-install-dss').disabled=!!d.dss_installing;
      $('pv-install-note').textContent=d.dss_install_error||(
        d.dss_installing?'Stahuji a rozbaluji oficiální instalační balíček…':
        d.dss_ready?'EU DSS se při první kontrole automaticky spustí.':''
      );
      if(d.dss_installing && !dssPoll)dssPoll=setInterval(health,8000);
      if(!d.dss_installing && dssPoll){clearInterval(dssPoll);dssPoll=null;}
    }catch(e){token='';ready=false;$('pv-health').textContent='Validátor zatím není připraven: '+(e?.message||e)+'. Spusť instalátor nové verze AuthorizationBridge.';}
    render();
  }
  $('pv-install-dss').onclick=async()=>{
    const consent=confirm('Stáhnout přibližně 630 MB oficiálního EU DSS 6.5 do tohoto PC?\nDSS bude běžet jen lokálně (127.0.0.1).');
    if(!consent)return;
    $('pv-install-dss').disabled=true;
    $('pv-install-note').textContent='Spouštím instalaci EU DSS…';
    try {
      const t=await session();
      const response=await fetch(API+'/install-eu-dss',{
        method:'POST',headers:{'X-20-20-Session':t}
      });
      const j=await response.json();
      if(!response.ok||!j.ok)throw Error(j.error||'Instalaci nelze spustit.');
      if(!dssPoll)dssPoll=setInterval(health,8000);
      await health();
    }catch(e){
      $('pv-install-note').textContent='Instalace selhala: '+String(e?.message||e);
      $('pv-install-dss').disabled=false;
    }
  };
  $('pv-refresh').onclick=health;
  $('pv-start').onclick=async()=>{
    if(busy||!ready)return;
    busy=true;$('pv-error').hidden=true;$('pv-error').textContent='';render();
    for(let i=0;i<files.length;i++){
      const f=files[i];$('pv-progress').textContent='Kontroluji '+(i+1)+'/'+files.length+': '+f.name;
      try{
        const t=await session(),data=new FormData();data.append('file',f,f.name);
        const ac=new AbortController(),timer=setTimeout(()=>ac.abort(),580000);
        let response;
        try{response=await fetch(API+'/validate-pdf',{method:'POST',body:data,headers:{'X-20-20-Session':t},signal:ac.signal});}
        finally{clearTimeout(timer);}
        const j=await response.json();
        if(!response.ok||!j.ok){
          const description=[j.error||'Lokální kontrola selhala.',j.detail].filter(Boolean).join(' — ');
          throw Error('HTTP '+response.status+': '+description);
        }
        results.set(f,j.result);
        if(['pdfa','crypto','signature','timestamp'].every(k=>j.result?.[k]!=='valid'&&j.result?.[k]!=='invalid')){
          const details=(j.result?.messages||[]).filter(Boolean).slice(0,6).join(' | ');
          const reason=f.name+': '+(details||'Všechny dílčí kontroly vrátily NEOVĚŘENO. Stáhni TXT report.');
          $('pv-error').hidden=false;
          $('pv-error').textContent+=reason+'\n';
        }
      }catch(e){
        const message=String(e?.message||e);
        const reason=f.name+': '+message;
        results.set(f,{pdfa:'unverified',crypto:'unverified',signature:'unverified',timestamp:'unverified',messages:[reason],report:'Kontrola se vůbec nedokončila. Jde o chybu programu nebo komunikace, nikoliv potvrzenou neplatnost podpisu.\n'+reason});
        $('pv-error').hidden=false;
        $('pv-error').textContent+=reason+'\n';
      }render();
    }
    busy=false;render();$('pv-progress').textContent='Dokončeno: '+files.length+' souborů.';
  };
  window.toolboxRegisterPDFValidator?.(()=>window.openTool?.('pdfvalidator'));
  health();
})();