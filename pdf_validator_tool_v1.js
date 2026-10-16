// 20-20 TOOLBOX · PDF Validator · local bridge: veraPDF + qualified eIDAS
(function(){
  'use strict';
  const API='http://127.0.0.1:8094';
  const files=[], results=new Map();
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
    +'#tool-pdfvalidator .pv-tag.unverified{color:#8a5900;background:#fff1d0}';
  document.head.appendChild(css);
  const host=document.getElementById('tool-3dprint')?.parentElement||document.querySelector('.card');
  if(!host)return;
  const view=document.createElement('div');
  view.id='tool-pdfvalidator';view.className='tool-view';
  view.innerHTML='<button class="back-btn" onclick="closeTool()">← Zpět do menu</button>'
    +'<h1>PDF Validator</h1><p class="muted">Lokální nezávislá kontrola PDF/A-3b, elektronických podpisů a kvalifikovaných časových razítek.</p>'
    +'<div id="pv-health" class="pv-note">Kontroluji lokální validační engine…</div>'
    +'<div id="pv-drop" class="pv-drop" tabindex="0" role="button"><strong>Přetáhni PDF nebo klikni pro výběr</strong><small>PDF soubory zůstávají na tomto počítači.</small></div>'
    +'<input id="pv-input" type="file" accept=".pdf,application/pdf" multiple hidden>'
    +'<div class="pv-actions"><button id="pv-start">Spustit kontrolu</button><button id="pv-clear">Vyčistit</button><button id="pv-refresh">Stav validátoru</button><span id="pv-progress"></span></div>'
    +'<div class="pv-table-wrap"><table><thead><tr><th>Soubor</th><th>PDF/A-3b</th><th>Kryptografie</th><th>QES</th><th>QTSA</th><th>Report</th></tr></thead><tbody id="pv-results"></tbody></table></div>'
    +'<p class="pv-note">Zelená PDF/A znamená skutečnou kontrolu veraPDF. Pokud nelze stáhnout nebo ověřit český důvěryhodný seznam (např. HTTP 406), je eIDAS stav NEOVĚŘENO, ne „neplatné“. '
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
  function reportText(f,data){
    return '20-20 PDF Validator\nSoubor: '+f.name+'\nSHA-256: '+(data.sha256||'')+'\nPDF/A: '+label(data.pdfa,'pdfa')
      +'\nKryptografická integrita: '+label(data.crypto,'crypto')+'\nKvalifikovaný podpis: '+label(data.signature,'signature')
      +'\nKvalifikované TSA: '+label(data.timestamp,'timestamp')+'\n\n'+(data.messages||[]).join('\n')+'\n\n'+(data.report||'');
  }
  function render(){
    const body=$('pv-results');body.replaceChildren();
    if(!files.length){const tr=body.insertRow(),td=tr.insertCell();td.colSpan=6;td.textContent='Žádné PDF zatím nebylo vybráno.';}
    files.forEach(file=>{
      const data=results.get(file)||{};
      const row=body.insertRow(),td=row.insertCell();
      td.textContent=file.name;td.style.overflowWrap='anywhere';
      for(const key of ['pdfa','crypto','signature','timestamp'])row.insertCell().appendChild(tag(data[key],key));
      const button=document.createElement('button');button.type='button';button.textContent='TXT';button.disabled=!results.has(file);button.title=(data.messages||[]).join('; ');
      button.addEventListener('click',()=>{
        const u=URL.createObjectURL(new Blob([reportText(file,results.get(file))],{type:'text/plain;charset=utf-8'}));
        const a=document.createElement('a');a.href=u;a.download=file.name.replace(/\.pdf$/i,'')+'_validace.txt';a.click();
        setTimeout(()=>URL.revokeObjectURL(u),1000);
      });
      row.insertCell().appendChild(button);
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
  $('pv-clear').onclick=()=>{files.length=0;results.clear();render();};
  async function session(){
    if(token)return token;
    const r=await fetch(API+'/session',{cache:'no-store'}),j=await r.json();
    if(!r.ok||!j.ok||!j.token)throw Error(j.error||'Bridge nevydal session');
    token=j.token;return token;
  }
  async function health(){
    try{
      const r=await fetch(API+'/status',{cache:'no-store'}),j=await r.json();
      if(!r.ok||!j.features?.integrated_pdf_validator)throw Error('Vyžadován aktualizovaný AuthorizationBridge 2.2.0.');
      const t=await session();
      const s=await fetch(API+'/validator-status',{headers:{'X-20-20-Session':t},cache:'no-store'}),d=await s.json();
      if(!s.ok||!d.ok)throw Error(d.error||'Nelze načíst stav');
      ready=!!(d.verapdf_ready&&d.eidas_ready&&d.tsa_ready);
      $('pv-health').textContent='AuthorizationBridge '+(d.bridge_version||'')+' · veraPDF: '+(d.verapdf_ready?'připraveno':'chybí')
        +' · eIDAS: '+(d.eidas_ready?'připraveno':'chybí')+' · QTSA: '+(d.tsa_ready?'připraveno':'chybí')+(ready?' · Připraveno.':' · Aktualizuj lokální Bridge nebo PDF Validator.');
    }catch(e){token='';ready=false;$('pv-health').textContent='Validátor zatím není připraven: '+(e?.message||e)+'. Spusť instalátor nové verze AuthorizationBridge.';}
    render();
  }
  $('pv-refresh').onclick=health;
  $('pv-start').onclick=async()=>{
    if(busy||!ready)return;
    busy=true;render();
    for(let i=0;i<files.length;i++){
      const f=files[i];$('pv-progress').textContent='Kontroluji '+(i+1)+'/'+files.length+': '+f.name;
      try{
        const t=await session(),data=new FormData();data.append('file',f,f.name);
        const ac=new AbortController(),timer=setTimeout(()=>ac.abort(),580000);
        let response;
        try{response=await fetch(API+'/validate-pdf',{method:'POST',body:data,headers:{'X-20-20-Session':t},signal:ac.signal});}
        finally{clearTimeout(timer);}
        const j=await response.json();
        if(!response.ok||!j.ok)throw Error(j.error||'Lokální kontrola selhala.');
        results.set(f,j.result);
      }catch(e){
        results.set(f,{pdfa:'unverified',crypto:'unverified',signature:'unverified',timestamp:'unverified',messages:[String(e?.message||e)],report:''});
      }render();
    }
    busy=false;render();$('pv-progress').textContent='Dokončeno: '+files.length+' souborů.';
  };
  window.toolboxRegisterPDFValidator?.(()=>window.openTool?.('pdfvalidator'));
  health();
})();