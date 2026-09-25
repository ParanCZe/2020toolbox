(function(){
  function byId(id){ return document.getElementById(id); }
  function esc(s){
    s = (s === null || typeof s === 'undefined') ? '' : String(s);
    return s.replace(/[&<>\"']/g,function(m){return {'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[m];});
  }
  function money(n){ n = Number(n || 0); return '$' + n.toFixed(6); }
  function addClass(el, cls){ if(el) el.className = cls; }
  function safeCall(name){
    try{
      if(window.sketchup && typeof window.sketchup[name] === 'function'){
        var args = Array.prototype.slice.call(arguments,1);
        window.sketchup[name].apply(window.sketchup,args);
        return true;
      }
    }catch(e){ showFatal('Bridge chyba: '+e.message); }
    return false;
  }
  function showFatal(t){
    var el=byId('summary');
    if(el) el.innerHTML='<div class="fatal">'+esc(t)+'</div>';
  }
  function boot(){
    var status=byId('bootState');
    if(status) status.textContent='UI OK';
    if(!safeCall('ready')){
      showFatal('UI se nacetlo, ale spojeni se SketchUp Ruby callbackem neni dostupne. Zavri a znovu otevri RM CHECK.');
    }
  }
  window.onerror=function(message,source,line,col,error){
    var txt='JavaScript chyba: '+String(message||'neznamy problem')+' (radek '+String(line||'?')+')';
    showFatal(txt);
    try{ safeCall('jsError',txt); }catch(_e){}
    return false;
  };

  window.RMCheck={
    data:null,
    esc:esc,
    money:money,
    render:function(data){
      try{
        this.data=data||{};
        var issues=data.issues||[];
        var sc=data.severity_counts||{};
        var ec=sc.error||0, wc=sc.warning||0, ic=sc.info||0, ok=0;
        var checks=data.checks||[];
        var i,x;
        for(i=0;i<checks.length;i++){ if(checks[i].status==='ok') ok++; }
        var rc=(data.repair_candidates && data.repair_candidates.length) ? data.repair_candidates.length : 0;
        byId('summary').innerHTML='<div class="summary"><div><div class="scene">SCENA</div><div class="title">'+esc(data.scene)+'</div><div class="meta">'+esc(data.model_name)+' · '+String(data.elapsed_ms||0)+' ms · max. vnoreni '+String(data.max_depth||0)+' · '+String(rc)+' opravnych kandidatu · <span id="bootState">Ruby OK</span></div></div><div class="counts"><span class="pill error">'+String(ec)+' chyb</span><span class="pill warning">'+String(wc)+' upozorneni</span><span class="pill info">'+String(ic)+' informaci</span><span class="pill ok">'+String(ok)+' OK</span></div></div>';
        var ch='';
        for(i=0;i<checks.length;i++){
          x=checks[i];
          ch+='<div class="check"><span class="dot '+esc(x.status)+'"></span><div>'+esc(x.label)+'</div><small>'+(x.count?String(x.count)+'×':'')+'</small></div>';
        }
        byId('checklist').innerHTML=ch || '<div class="empty">Checklist nema data.</div>';
        var ih='';
        if(issues.length){
          for(i=0;i<issues.length;i++){
            x=issues[i];
            ih+='<div class="issue '+esc(x.severity)+'"><div class="issue-title">'+esc(x.title)+(x.candidate_id?'<span class="candidate-mark">AI VOLBA</span>':'')+'</div><div class="issue-detail">'+esc(x.detail)+'</div>'+(x.action?'<div class="issue-action">→ '+esc(x.action)+'</div>':'')+'<div class="actions">'+(x.selectable?'<button onclick="sketchup.selectIssue(\''+esc(x.id)+'\')">Vybrat v modelu</button>':'')+(x.fix?'<button class="fix" onclick="sketchup.fixIssue(\''+esc(x.id)+'\')">Opravit</button>':'')+'</div></div>';
          }
        }else{
          ih='<div class="empty">Zadne nalezy. Model vypada podle automatickych kontrol v poradku.</div>';
        }
        byId('issues').innerHTML=ih;
        byId('issueMore').innerHTML=data.issue_truncated?'<div class="more-note">Zobrazeno prvnich '+String(issues.length)+' z '+String(data.issue_total)+' nalezu. Souhrnne pocty nahore obsahuji vsechny nalezy.</div>':'';
        var ai=byId('aiState');
        if(data.ai_connected){ ai.textContent=(data.ai_model||'AI')+' ON'; addClass(ai,'ai on'); }
        else { ai.textContent='AI OFF'; addClass(ai,'ai off'); }
        var u=data.ai_usage||{};
        byId('chatCost').textContent=data.ai_connected?'AI session: '+money(u.cost_usd||0):'';
      }catch(e){ showFatal('Vykresleni reportu selhalo: '+e.message); safeCall('jsError','render: '+e.message); }
    },
    quick:function(t){ var el=byId('chatinput'); el.value=t; el.focus(); },
    send:function(ev){
      if(ev && ev.preventDefault) ev.preventDefault();
      var el=byId('chatinput'),v=el.value.replace(/^\s+|\s+$/g,'');
      if(!v) return false;
      el.value='';
      safeCall('ask',v);
      return false;
    },
    chat:function(m){
      var log=byId('chatlog'),b=document.createElement('div');
      b.className='bubble '+(m.role||'assistant')+(m.error?' error':'')+(m.pending?' pending':'');
      b.textContent=m.text||'';
      b.setAttribute('data-pending',m.pending?'1':'0');
      log.appendChild(b); log.scrollTop=log.scrollHeight;
    },
    replacePending:function(m){
      var log=byId('chatlog'),all=log.querySelectorAll('[data-pending="1"]'),b=all.length?all[all.length-1]:null;
      if(!b){b=document.createElement('div');log.appendChild(b);}
      b.className='bubble assistant'+(m.error?' error':''); b.textContent=m.text||''; b.setAttribute('data-pending','0'); log.scrollTop=log.scrollHeight;
    },
    replacePendingRich:function(m){
      var log=byId('chatlog'),all=log.querySelectorAll('[data-pending="1"]'),b=all.length?all[all.length-1]:null,i;
      if(!b){b=document.createElement('div');log.appendChild(b);}
      b.className='bubble assistant rich'; b.setAttribute('data-pending','0'); b.innerHTML='';
      var ans=document.createElement('div');ans.className='answer';ans.textContent=m.answer||'';b.appendChild(ans);
      if(m.usage){var u=document.createElement('div');u.className='usage';u.textContent=(m.model||'AI')+' · '+String(m.usage.input_tokens||0)+' in / '+String(m.usage.output_tokens||0)+' out · dotaz '+money(m.usage.cost_usd)+' · session '+money(m.usage.session_cost_usd);b.appendChild(u);byId('chatCost').textContent='AI session: '+money(m.usage.session_cost_usd);}
      var plans=m.plans||[];
      if(plans.length){var holder=document.createElement('div');holder.className='plans';for(i=0;i<plans.length;i++)holder.appendChild(this.makePlan(plans[i],i));b.appendChild(holder);var foot=document.createElement('div');foot.className='plan-apply';foot.innerHTML='<button type="button">POTVRDIT A OPRAVIT</button>';foot.getElementsByTagName('button')[0].onclick=function(){window.RMCheck.applyPlans(b);};b.appendChild(foot);}
      log.scrollTop=log.scrollHeight;
    },
    makePlan:function(p,pi){
      var d=document.createElement('div'),h,cb,copy,t,ds,r,fs,i,f,row,lab,inp,op,dl,j,id;
      d.className='plan '+(p.risk||'confirm'); d.setAttribute('data-cid',p.candidate_id||''); d.setAttribute('data-risk',p.risk||'confirm');
      h=document.createElement('div');h.className='plan-head';cb=document.createElement('input');cb.type='checkbox';cb.className='plan-check';cb.checked=!!p.enabled;cb.disabled=p.risk==='manual';h.appendChild(cb);
      copy=document.createElement('div');copy.style.flex='1';t=document.createElement('div');t.className='plan-title';t.textContent=p.title||p.candidate_id||'';ds=document.createElement('div');ds.className='plan-desc';ds.textContent=p.description||'';copy.appendChild(t);copy.appendChild(ds);h.appendChild(copy);
      r=document.createElement('span');r.className='risk '+(p.risk||'confirm');r.textContent=p.risk==='safe'?'bezpecne':(p.risk==='manual'?'rucne':'potvrdit');h.appendChild(r);d.appendChild(h);
      var fields=p.fields||[];
      if(fields.length){fs=document.createElement('div');fs.className='plan-fields';for(i=0;i<fields.length;i++){f=fields[i];row=document.createElement('div');row.className='field';lab=document.createElement('label');lab.textContent=f.label||f.key||'';row.appendChild(lab);if(f.key==='mode' && f.options && f.options.length){inp=document.createElement('select');for(j=0;j<f.options.length;j++){op=document.createElement('option');op.value=f.options[j];op.textContent=f.options[j];if(f.options[j]===f.value)op.selected=true;inp.appendChild(op);}}else{inp=document.createElement('input');inp.type='text';inp.value=f.value||'';if(f.options && f.options.length){id='dl_'+String(pi)+'_'+String(i);inp.setAttribute('list',id);dl=document.createElement('datalist');dl.id=id;for(j=0;j<f.options.length;j++){op=document.createElement('option');op.value=f.options[j];dl.appendChild(op);}row.appendChild(dl);}}inp.setAttribute('data-key',f.key||'');row.appendChild(inp);fs.appendChild(row);}d.appendChild(fs);}
      return d;
    },
    applyPlans:function(scope){
      var nodes=scope.querySelectorAll('.plan'),actions=[],i,j,p,cb,inputs,values;
      for(i=0;i<nodes.length;i++){p=nodes[i];cb=p.querySelector('.plan-check');if(!cb || !cb.checked)continue;values={};inputs=p.querySelectorAll('[data-key]');for(j=0;j<inputs.length;j++)values[inputs[j].getAttribute('data-key')]=inputs[j].value;actions.push({candidate_id:p.getAttribute('data-cid'),enabled:true,values:values});}
      if(!actions.length){this.chat({role:'assistant',text:'Neni nic zaskrtnuto.'});return;}
      var btn=scope.querySelector('.plan-apply button');if(btn){btn.disabled=true;btn.textContent='OPRAVUJI…';}
      safeCall('applyPlan',JSON.stringify({actions:actions}));
    },
    planDone:function(m){this.chat({role:'assistant',text:(m.text||'Hotovo.')+'\n\nKontrola byla spustena znovu. Celou operaci lze vratit Ctrl+Z.'});if(m.report)this.render(m.report);},
    fatal:function(t){showFatal(t);},
    configureApiKey:function(){safeCall('configureApiKey');}
  };
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',boot,false); else setTimeout(boot,0);
})();