(()=>{
  const ORT_URL='https://cdn.jsdelivr.net/npm/onnxruntime-web@1.22.0/dist/ort.min.js';
  const MODEL_URL='https://huggingface.co/bukuroo/RealESRGAN-ONNX/resolve/main/real-esrgan-x4plus-128.onnx?download=true';
  const GFPGAN_URL='https://huggingface.co/HowToSD/GFPGAN-ONNX/resolve/main/GFPGANv1.4.onnx?download=true';
  const MEDIAPIPE_URL='https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.32/vision_bundle.mjs';
  const MEDIAPIPE_WASM='https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.32/wasm';
  const FACE_DETECTOR_MODEL='https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/1/blaze_face_short_range.tflite';
  const OBJECT_DETECTOR_MODEL='https://storage.googleapis.com/mediapipe-models/object_detector/efficientdet_lite0/float16/1/efficientdet_lite0.tflite';
  const VOSR_BRIDGE_URL='http://127.0.0.1:8092';
  const GRADIO_CLIENT_URL='https://cdn.jsdelivr.net/npm/@gradio/client@2.7.0/dist/index.min.js';
  const INVSR_SPACE='OAOA/InvSR';
  const SUPIR_SPACES=['NotSky/supir-demo','Fabrice-TIERCELIN/SUPIR'];
  const AI_MODEL_CACHE='toolbox-ai-models-v1';
  const S={file:null,img:null,result:null,session:null,loadingModel:null,faceSession:null,loadingFaceModel:null,faceDetector:null,loadingFaceDetector:null,objectDetector:null,loadingObjectDetector:null,engine:'LOCAL',running:false,vosrOnline:false,vosrHealth:null,vosrQualitySupported:false,vosrTelemetryTimer:null,vosrRunStarted:0,vosrEtaSec:0,vosrRenderScale:0,vosrStopPending:false,gradioModule:null,cloudClients:{},cloudApi:{}};
  const $=s=>document.querySelector(s);
  const LOCAL_CORE={clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),clampByte:v=>Math.max(0,Math.min(255,Math.round(v))),tileStarts(size,tile=128,overlap=16){size=Math.max(1,Math.floor(size));if(size<=tile)return[0];const step=tile-overlap,out=[];for(let p=0;p<size-tile;p+=step)out.push(p);const last=size-tile;if(out[out.length-1]!==last)out.push(last);return out},outputScale:m=>m==='safe4'||m==='invsr4'||m==='ai4'||m==='vosr4'?4:m==='supirf'||m==='ai2'||m==='deblur2'||m==='vosr2'?2:1,sharpenAmount(v,m){const n=Math.max(0,Math.min(100,Number(v)||0))/100;return(m==='sharp'?0.35:0.18)+n*1.2},modeLabel:m=>({safe4:'SAFE UPSCALE 4× · REAL-ESRGAN',invsr4:'AI UPSCALE 4× · INVSR',supirf:'AI RESTORE FIDELITY · SUPIR v0F · ARCHVIZ',sharp:'SHARP FIX',clean:'CLEAN PHOTO',ai2:'AI UPSCALE 2× · LOCAL',ai4:'AI UPSCALE 4× · LOCAL',deblur2:'DEBLUR + AI 2×',vosr2:'VOSR 2.0 SCENE 2×',vosr4:'VOSR 2.0 SCENE 4×'})[m]||m};
  const core=()=>window.upscalerV359Core||LOCAL_CORE;

  function css(){if($('#upscaler-v359-style'))return;const s=document.createElement('style');s.id='upscaler-v359-style';s.textContent=`
    #tool-upscaler .ups-grid{display:grid;grid-template-columns:300px minmax(0,1fr) 280px;gap:16px;align-items:stretch;min-height:calc(100vh - 215px)}
    #tool-upscaler .ups-panel{border:1px solid var(--border);border-radius:10px;background:#fafafa;padding:16px;height:100%}
    #tool-upscaler .ups-panel h2{font:normal 13px 'Antarctican Mono',monospace;margin:0 0 10px}
    #tool-upscaler .ups-drop{border:2px dashed #cbd5e1;border-radius:9px;background:#fff;padding:26px 14px;text-align:center;cursor:pointer;transition:.15s}
    #tool-upscaler .ups-drop.over{background:#fffef3;border-color:#a1a1aa}
    #tool-upscaler .ups-drop b{display:block;margin-bottom:4px;font-size:13px}#tool-upscaler .ups-drop span{font-size:10px;color:var(--muted)}
    #tool-upscaler .ups-control{margin-top:12px}#tool-upscaler .ups-control>label{display:flex;justify-content:space-between;gap:8px;font-size:10px;color:var(--muted);margin-bottom:5px}
    #tool-upscaler .ups-control input[type=range],#tool-upscaler .ups-control select{width:100%}
    #tool-upscaler .ups-actions{display:grid;gap:7px;margin-top:14px}.ups-actions button{width:100%}
    #tool-upscaler .ups-check{display:flex;align-items:center;gap:8px;margin-top:12px;padding:9px 10px;border:1px solid var(--border);border-radius:7px;background:#fff;font-size:10px;color:var(--text)}#tool-upscaler .ups-check input{margin:0}
    #tool-upscaler .ups-preview{position:relative;min-height:calc(100vh - 250px);height:100%;background:#e4e4e7;border:1px solid var(--border);border-radius:10px;overflow:hidden;display:flex;align-items:center;justify-content:center}
    #tool-upscaler .ups-preview canvas{position:absolute;max-width:100%;max-height:100%;width:auto;height:auto;object-fit:contain;background:#fff;box-shadow:0 8px 24px rgba(0,0,0,.15)}
    #tool-upscaler #ups-after-wrap{position:absolute;inset:0;overflow:hidden;clip-path:inset(0 0 0 50%);display:flex;align-items:center;justify-content:center}
    #tool-upscaler #ups-before-wrap{position:absolute;inset:0;display:flex;align-items:center;justify-content:center}
    #tool-upscaler .ups-divider{position:absolute;top:0;bottom:0;left:50%;width:2px;background:#f7f197;box-shadow:0 0 0 1px rgba(0,0,0,.15);z-index:6;pointer-events:none}
    #tool-upscaler .ups-divider:after{content:'↔';position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:34px;height:34px;border-radius:50%;background:#f7f197;display:flex;align-items:center;justify-content:center;font-weight:700;color:#18181b;border:1px solid #a1a1aa}
    #tool-upscaler .ups-compare{margin-top:10px}#tool-upscaler .ups-compare input{width:100%}
    #tool-upscaler .ups-stat{display:flex;justify-content:space-between;gap:8px;padding:7px 0;border-bottom:1px dashed #d4d4d8;font-size:10px}.ups-stat b{text-align:right;font-weight:600}
    #tool-upscaler .ups-status{margin-top:12px;padding:10px;border-radius:7px;background:#fff;border:1px solid var(--border);font-size:10px;line-height:1.45;min-height:52px}
    #tool-upscaler .ups-badge{display:inline-flex;border:1px solid #d4d4d8;border-radius:999px;padding:2px 6px;font-size:8px;background:#f4f4f5;margin-left:6px}
    #tool-upscaler .ups-progress{height:7px;background:#e4e4e7;border-radius:4px;overflow:hidden;margin-top:8px}.ups-progress>i{display:block;height:100%;width:0;background:#18181b;transition:.15s}
    #tool-upscaler .ups-vosr-note{margin-top:10px;padding:9px 10px;border:1px solid #d4d4d8;border-radius:7px;background:#fffef3;font-size:9px;line-height:1.5;color:#52525b}#tool-upscaler .ups-vosr-note b{color:#18181b}
    #tool-upscaler .ups-bridge{margin-top:10px;padding:8px 9px;border:1px solid #d4d4d8;border-radius:7px;background:#fff;font-size:9px;line-height:1.4}.ups-bridge.ok{border-color:#86b98b;background:#f2fbf3}.ups-bridge.warn{border-color:#d8c76b;background:#fffdf0}.ups-bridge.bad{border-color:#d99a9a;background:#fff5f5}
    #tool-upscaler .ups-storage{margin-top:12px;padding-top:12px;border-top:1px dashed #d4d4d8}.ups-storage-title{font:normal 11px 'Antarctican Mono',monospace;margin-bottom:6px}.ups-storage p{font-size:9px;line-height:1.45;color:var(--muted);margin:0 0 8px}.ups-storage button{width:100%}
    #tool-upscaler .ups-storage-stats{display:grid;grid-template-columns:1fr auto;gap:4px 8px;margin:7px 0 9px;font-size:9px;line-height:1.35}#tool-upscaler .ups-storage-stats b{text-align:right}
    #tool-upscaler .ups-vosr-live{margin-top:10px;padding:10px;border:1px solid #d4d4d8;border-radius:8px;background:#fff}#tool-upscaler .ups-vosr-live[hidden]{display:none}
    #tool-upscaler .ups-live-title{font:normal 10px 'Antarctican Mono',monospace;margin-bottom:7px}
    #tool-upscaler .ups-live-grid{display:grid;grid-template-columns:1fr auto;gap:4px 8px;font-size:9px;line-height:1.35}#tool-upscaler .ups-live-grid b{text-align:right}
    #tool-upscaler .ups-stop{width:100%;margin-top:9px!important;color:#b91c1c!important;border-color:#efb4b4!important;background:#fff7f7!important}
    #tool-upscaler .ups-quality-hint{font-size:8.5px;line-height:1.4;margin-top:5px}
    body:has(#tool-upscaler.active) .wrap{max-width:none;padding:0 18px}body:has(#tool-upscaler.active) .wrap>.card{padding:18px}#tool-upscaler{width:100%;max-width:none;margin:0}#tool-upscaler .ups-grid>section:nth-child(2){min-width:0;display:flex;flex-direction:column}#tool-upscaler .ups-grid>section:nth-child(2) .ups-preview{flex:1}@media(max-width:1400px){#tool-upscaler .ups-grid{grid-template-columns:270px minmax(0,1fr) 245px}}@media(max-width:1050px){#tool-upscaler .ups-grid{grid-template-columns:1fr;min-height:auto}#tool-upscaler .ups-preview{min-height:560px}body:has(#tool-upscaler.active) .wrap{padding:0 12px}}
  `;document.head.appendChild(s)}

  function install(){css();
    const beta=document.querySelector('#menu-view .menu-app-row.beta');
    if(beta&&!$('#ups-menu-tile')){const d=document.createElement('div');d.id='ups-menu-tile';d.className='tile';d.innerHTML='<b>Upscaler <small class="menu-status">BETA</small></b><span>Safe Real-ESRGAN + InvSR + SUPIR Fidelity + volitelný VOSR 2.0</span>';d.onclick=()=>{window.openTool?.('upscaler');init()};beta.appendChild(d)}
    if(!$('#tool-upscaler')){const anchor=document.querySelector('.tool-view');if(!anchor)return;const v=document.createElement('div');v.id='tool-upscaler';v.className='tool-view';v.innerHTML=`
      <button class="back-btn" onclick="closeTool()">← Zpět do menu</button>
      <h1>Upscaler <small class="menu-status">BETA</small></h1>
      <div class="muted">Safe režimy běží lokálně v browseru přes Real-ESRGAN. InvSR a SUPIR Fidelity jsou volitelné online AI režimy přes veřejné Hugging Face GPU Spaces; VOSR 2.0 zůstává volitelný lokální GPU režim. U online režimů obrázek opouští počítač.</div>
      <div class="ups-grid">
        <section class="ups-panel"><h2>VSTUP A NASTAVENÍ</h2>
          <div id="ups-drop" class="ups-drop"><b>Přetáhni obrázek</b><span>PNG / JPG / WEBP nebo klikni</span><input id="ups-file" type="file" accept="image/png,image/jpeg,image/webp" hidden></div>
          <div class="ups-control"><label><span>Režim</span><span id="ups-mode-label"></span></label><select id="ups-mode"><option value="safe4">Safe Upscale 4× — Real-ESRGAN</option><option value="invsr4">AI Upscale 4× — InvSR</option><option value="supirf">AI Restore Fidelity — SUPIR v0F (Archviz Safe)</option><option value="ai2">Local AI Upscale 2×</option><option value="deblur2">Deblur + Local AI 2×</option><option value="sharp">Sharp Fix</option><option value="clean">Clean Photo</option><option value="vosr2">VOSR 2.0 Scene 2×</option><option value="vosr4">VOSR 2.0 Scene 4×</option></select></div>
          <div id="ups-cloud-note" class="ups-vosr-note" hidden></div>
          <div id="ups-vosr-note" class="ups-vosr-note" hidden><b>VOSR 2.0 · generativní rekonstrukce celé scény</b><br>Obnovuje objekty, lidi, hrany, materiály a textury v jednom passu.<br><br><b>Jak funguje:</b> VOSR běží lokálně na tvém PC přes NVIDIA CUDA bridge. Obrázek se nikam neodesílá a neopouští počítač.<br><b>Místo na disku:</b> po instalaci počítej přibližně <b>14–18 GB</b>. Během první instalace může dočasně potřebovat i <b>20+ GB</b> kvůli staženým balíčkům a cache. Modely se stahují jen jednou.<br><b>Požadavky:</b> NVIDIA GPU + lokální VOSR Bridge.<br><a class="back-btn" style="display:inline-flex;margin-top:7px;text-decoration:none" href="UpscaleBridge/install.bat?v=20260921quality130" download="20-20-TOOLBOX_VOSR_INSTALL.bat">↓ Stáhnout / aktualizovat VOSR Bridge</a></div>
          <div id="ups-vosr-quality-wrap" class="ups-control" hidden><label><span>VOSR kvalita</span><span id="ups-vosr-quality-label">QUALITY</span></label><select id="ups-vosr-quality"><option value="fast">Fast / Fidelity — 512 tile</option><option value="quality" selected>Quality — 768 tile</option><option value="max">Max Quality — 1024 tile</option></select><div id="ups-vosr-quality-hint" class="muted ups-quality-hint">Quality: větší kontext pro lidi, materiály a návaznost textur.</div></div>
          <div class="ups-control"><label><span>Ostrost</span><span id="ups-sharp-v">55</span></label><input id="ups-sharp" type="range" min="0" max="100" value="55"></div>
          <div class="ups-control"><label><span>Obnova detailu</span><span id="ups-detail-v">55</span></label><input id="ups-detail" type="range" min="0" max="100" value="55"></div>
          <div class="ups-control"><label><span>Odšumění</span><span id="ups-denoise-v">12</span></label><input id="ups-denoise" type="range" min="0" max="100" value="12"></div>
          <label class="ups-check"><input id="ups-generative" type="checkbox" checked><span>Generativní náhrada detailů</span></label>
          <label class="ups-check"><input id="ups-scene" type="checkbox" checked><span>AI rekonstrukce objektů a detailů</span></label>
          <div class="ups-control"><label><span>Síla rekonstrukce scény</span><span id="ups-scene-v">72</span></label><input id="ups-scene-strength" type="range" min="0" max="100" value="72"></div>
          <label class="ups-check"><input id="ups-face" type="checkbox" checked><span>AI rekonstrukce obličejů</span></label>
          <div class="ups-control"><label><span>Síla rekonstrukce obličejů</span><span id="ups-face-v">82</span></label><input id="ups-face-strength" type="range" min="0" max="100" value="82"></div>
          <div class="ups-actions"><button id="ups-run" class="action" disabled>Zpracovat</button><button id="ups-png" class="back-btn" disabled>Stáhnout PNG</button><button id="ups-jpg" class="back-btn" disabled>Stáhnout JPG</button></div>
        </section>
        <section><div id="ups-preview" class="ups-preview"><div id="ups-before-wrap"><canvas id="ups-before"></canvas></div><div id="ups-after-wrap"><canvas id="ups-after"></canvas></div><div id="ups-divider" class="ups-divider"></div></div><div class="ups-compare"><input id="ups-compare" type="range" min="0" max="100" value="50"></div></section>
        <aside class="ups-panel"><h2>STAV</h2><div class="ups-stat"><span>Soubor</span><b id="ups-name">—</b></div><div class="ups-stat"><span>Vstup</span><b id="ups-in">—</b></div><div class="ups-stat"><span>Výstup</span><b id="ups-out">—</b></div><div class="ups-stat"><span>Engine</span><b id="ups-engine">LOCAL</b></div><div class="ups-stat"><span>Čas</span><b id="ups-time">—</b></div><div id="ups-status" class="ups-status">Nahraj obrázek.</div><div class="ups-progress"><i id="ups-progress"></i></div><div id="ups-vosr-bridge" class="ups-bridge warn"><b>VOSR Bridge:</b> kontroluji…</div><div id="ups-vosr-live" class="ups-vosr-live" hidden><div class="ups-live-title">VOSR LIVE</div><div class="ups-live-grid"><span>GPU</span><b id="ups-vosr-gpu">—</b><span>Vytížení GPU</span><b id="ups-vosr-util">—</b><span>VRAM</span><b id="ups-vosr-vram">—</b><span>Teplota</span><b id="ups-vosr-temp">—</b><span>Kvalita</span><b id="ups-vosr-live-quality">—</b><span>Uplynulo</span><b id="ups-vosr-elapsed">—</b><span>ETA</span><b id="ups-vosr-eta">—</b></div><button type="button" class="back-btn ups-stop" id="ups-vosr-stop" disabled>■ STOP VOSR</button></div><div class="muted" style="font-size:9px;margin:10px 0 0"><b>Safe 4×:</b> Real-ESRGAN lokálně, bez odesílání obrázku. <b>InvSR / SUPIR:</b> zdarma přes veřejné Hugging Face GPU Space — může být fronta nebo denní limit a obrázek je odeslán externí službě. <b>VOSR 2.0:</b> volitelně lokálně; cca 14–18 GB (při instalaci dočasně 20+ GB).</div><div class="ups-storage"><div class="ups-storage-title">AI STORAGE / CLEANUP</div><p>Skutečné lokální místo zabrané Toolbox AI daty. VOSR hodnotu lze načíst, když běží Bridge.</p><div class="ups-storage-stats"><span>Browser AI cache</span><b id="ups-ai-storage-browser">měřím…</b><span>VOSR runtime + modely</span><b id="ups-ai-storage-vosr">měřím…</b><span>Celkem AI data</span><b id="ups-ai-storage-total">měřím…</b></div><button type="button" class="back-btn" id="ups-ai-clean" style="margin:0;color:#b91c1c">Smazat stažená AI data</button></div></aside>
      </div>`;anchor.parentNode.insertBefore(v,anchor)}
  }

  function init(){install();if($('#tool-upscaler')?.dataset.ready==='1')return;const root=$('#tool-upscaler');if(!root)return;root.dataset.ready='1';
    const file=$('#ups-file'),drop=$('#ups-drop'),mode=$('#ups-mode'),compare=$('#ups-compare');
    drop.onclick=()=>file.click();file.onchange=()=>file.files?.[0]&&loadFile(file.files[0]);
    ['dragenter','dragover'].forEach(t=>drop.addEventListener(t,e=>{e.preventDefault();drop.classList.add('over')}));['dragleave','drop'].forEach(t=>drop.addEventListener(t,e=>{e.preventDefault();drop.classList.remove('over')}));drop.addEventListener('drop',e=>e.dataTransfer.files?.[0]&&loadFile(e.dataTransfer.files[0]));
    for(const id of ['sharp','detail','denoise'])$('#ups-'+id).oninput=e=>$('#ups-'+id+'-v').textContent=e.target.value;
    $('#ups-scene-strength').oninput=e=>$('#ups-scene-v').textContent=e.target.value;
    $('#ups-face-strength').oninput=e=>$('#ups-face-v').textContent=e.target.value;
    const quality=$('#ups-vosr-quality');try{const saved=localStorage.getItem('toolbox-vosr-quality');if(saved&&['fast','quality','max'].includes(saved))quality.value=saved}catch(_){}
    quality.onchange=()=>{try{localStorage.setItem('toolbox-vosr-quality',quality.value)}catch(_){}syncVosrQualityUi()};
    mode.onchange=()=>{const m=mode.value;$('#ups-mode-label').textContent=core()?.modeLabel(m)||m;syncModeUi(m)};mode.onchange();syncVosrQualityUi();checkVosrBridge(true).then(()=>refreshAiStorage());
    compare.oninput=()=>{const v=Number(compare.value);$('#ups-after-wrap').style.clipPath=`inset(0 0 0 ${v}%)`;$('#ups-divider').style.left=v+'%'};compare.oninput();
    $('#ups-run').onclick=run;$('#ups-png').onclick=()=>save('image/png',1,'upscaled.png');$('#ups-jpg').onclick=()=>save('image/jpeg',.95,'upscaled.jpg');$('#ups-ai-clean').onclick=cleanupAiStorage;$('#ups-vosr-stop').onclick=stopVosrJob;
  }

  function isVosrMode(mode){return mode==='vosr2'||mode==='vosr4'}
  function isCloudMode(mode){return mode==='invsr4'||mode==='supirf'}
  function isFidelitySafeMode(mode){return mode==='safe4'||isCloudMode(mode)||isVosrMode(mode)}
  function versionAtLeast(v,min){const a=String(v||'0').split('.').map(x=>parseInt(x,10)||0),b=String(min||'0').split('.').map(x=>parseInt(x,10)||0);for(let i=0;i<Math.max(a.length,b.length);i++){const x=a[i]||0,y=b[i]||0;if(x>y)return true;if(x<y)return false}return true}
  function vosrQuality(){return $('#ups-vosr-quality')?.value||'quality'}
  function vosrQualityLabel(q){return({fast:'FAST / FIDELITY',quality:'QUALITY',max:'MAX QUALITY'})[q]||String(q||'').toUpperCase()}
  function syncVosrQualityUi(){
    const q=vosrQuality(),label=$('#ups-vosr-quality-label'),hint=$('#ups-vosr-quality-hint'),mode=$('#ups-mode')?.value;
    if(label)label.textContent=vosrQualityLabel(q);
    if(hint){
      if(!S.vosrQualitySupported&&S.vosrHealth)hint.textContent='Bridge '+(S.vosrHealth.version||'')+' je starší. Pro quality presety stáhni aktualizovaný VOSR Bridge.';
      else if(q==='fast')hint.textContent='Fast / Fidelity: 512 tile · nejnižší VRAM a nejbezpečnější běh.';
      else if(q==='quality')hint.textContent='Quality: 768 tile · větší kontext pro lidi, materiály a návaznost textur.';
      else hint.textContent=(mode==='vosr2'?'Max Quality: 1024 tile + interní 4× supersampling a výstup zpět na 2×.':'Max Quality: 1024 tile · maximum kontextu, vyšší VRAM nároky.');
    }
  }
  function formatBytesAi(n){n=Number(n)||0;if(n<=0)return'0 B';const u=['B','KB','MB','GB','TB'];let i=0;while(n>=1024&&i<u.length-1){n/=1024;i++}return(n>=100||i===0?n.toFixed(0):n>=10?n.toFixed(1):n.toFixed(2))+' '+u[i]}
  function formatDuration(sec){sec=Math.max(0,Math.round(Number(sec)||0));if(sec<60)return sec+' s';const m=Math.floor(sec/60),s=sec%60;return m+' min '+String(s).padStart(2,'0')+' s'}
  function vosrRenderScale(outputScale,q=vosrQuality()){return q==='max'&&Number(outputScale)===2?4:Number(outputScale)}
  function vosrRateKey(q,renderScale){return'toolbox-vosr-rate-v1-'+q+'-'+renderScale}
  function estimateVosrSeconds(src,outputScale,q=vosrQuality()){
    const rs=vosrRenderScale(outputScale,q),mp=Math.max(.1,src.width*src.height*rs*rs/1e6),fallback={fast:5.0,quality:5.6,max:6.3}[q]||5.6;
    let rate=fallback;try{const v=Number(localStorage.getItem(vosrRateKey(q,rs)));if(v>0&&v<120)rate=v}catch(_){}
    return Math.max(15,10+mp*rate)
  }
  function rememberVosrRate(src,outputScale,q,elapsed){
    const rs=vosrRenderScale(outputScale,q),mp=Math.max(.1,src.width*src.height*rs*rs/1e6),rate=Math.max(.2,Math.min(120,elapsed/mp));try{const k=vosrRateKey(q,rs),old=Number(localStorage.getItem(k));localStorage.setItem(k,String(old>0?old*.65+rate*.35:rate))}catch(_){}
  }
  function updateVosrClock(){
    if(!S.vosrRunStarted)return;const elapsed=(performance.now()-S.vosrRunStarted)/1000,eta=S.vosrEtaSec||0;
    const ee=$('#ups-vosr-elapsed'),et=$('#ups-vosr-eta');if(ee)ee.textContent=formatDuration(elapsed);if(et)et.textContent=eta?(elapsed<eta?'~ '+formatDuration(eta-elapsed):'dokončuje…'):'měřím…';
    if(S.running&&eta){const p=Math.min(90,22+68*Math.min(1,elapsed/eta));$('#ups-progress').style.width=p.toFixed(1)+'%'}
  }
  async function pollVosrTelemetry(){
    updateVosrClock();
    try{
      const ctrl=new AbortController(),tm=setTimeout(()=>ctrl.abort(),1400),r=await fetch(VOSR_BRIDGE_URL+'/telemetry',{cache:'no-store',signal:ctrl.signal});clearTimeout(tm);if(!r.ok)return;
      const t=await r.json();if(t.name)$('#ups-vosr-gpu').textContent=t.name;if(Number.isFinite(t.utilization_gpu))$('#ups-vosr-util').textContent=Math.round(t.utilization_gpu)+' %';
      if(Number.isFinite(t.memory_used_mb)&&Number.isFinite(t.memory_total_mb))$('#ups-vosr-vram').textContent=(t.memory_used_mb/1024).toFixed(1)+' / '+(t.memory_total_mb/1024).toFixed(1)+' GB';
      if(Number.isFinite(t.temperature_c))$('#ups-vosr-temp').textContent=Math.round(t.temperature_c)+' °C';
    }catch(_){}
  }
  function startVosrTelemetry(eta,q,renderScale){
    if(S.vosrTelemetryTimer)clearInterval(S.vosrTelemetryTimer);S.vosrEtaSec=eta;S.vosrRunStarted=performance.now();S.vosrRenderScale=renderScale;S.vosrStopPending=false;
    const box=$('#ups-vosr-live'),btn=$('#ups-vosr-stop');if(box)box.hidden=false;if(btn){btn.disabled=false;btn.textContent='■ STOP VOSR'}$('#ups-vosr-live-quality').textContent=vosrQualityLabel(q)+(renderScale!==core().outputScale($('#ups-mode').value)?' · '+renderScale+'×→'+core().outputScale($('#ups-mode').value)+'×':'');
    pollVosrTelemetry();S.vosrTelemetryTimer=setInterval(pollVosrTelemetry,1200)
  }
  function stopVosrTelemetry(){
    if(S.vosrTelemetryTimer){clearInterval(S.vosrTelemetryTimer);S.vosrTelemetryTimer=null}updateVosrClock();const btn=$('#ups-vosr-stop');if(btn){btn.disabled=true;btn.textContent=S.vosrStopPending?'Zastaveno / čekám…':'■ STOP VOSR'}
  }
  async function stopVosrJob(){
    if(!S.running||S.vosrStopPending)return;S.vosrStopPending=true;const btn=$('#ups-vosr-stop');if(btn){btn.disabled=true;btn.textContent='Zastavuju VOSR…'}status('Zastavuju VOSR proces…',Number.parseFloat($('#ups-progress')?.style.width)||0);
    try{const r=await fetch(VOSR_BRIDGE_URL+'/cancel',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});if(!r.ok)throw new Error('HTTP '+r.status)}catch(e){S.vosrStopPending=false;if(btn){btn.disabled=false;btn.textContent='■ STOP VOSR'}status('STOP se nepodařilo odeslat: '+e.message,0)}
  }
  async function browserAiCacheBytes(){
    if(!('caches' in window))return 0;let total=0;try{const cache=await caches.open(AI_MODEL_CACHE),keys=await cache.keys();for(const req of keys){const r=await cache.match(req);if(!r)continue;const h=Number(r.headers.get('content-length'));if(h>0){total+=h;continue}try{total+=(await r.clone().arrayBuffer()).byteLength}catch(_){}}}catch(_){}return total
  }
  async function refreshAiStorage(){
    const eb=$('#ups-ai-storage-browser'),ev=$('#ups-ai-storage-vosr'),et=$('#ups-ai-storage-total');if(eb)eb.textContent='měřím…';if(ev)ev.textContent='měřím…';if(et)et.textContent='měřím…';
    const browser=await browserAiCacheBytes();if(eb)eb.textContent=formatBytesAi(browser);let vosr=null;
    try{const ctrl=new AbortController(),tm=setTimeout(()=>ctrl.abort(),6000),r=await fetch(VOSR_BRIDGE_URL+'/storage',{cache:'no-store',signal:ctrl.signal});clearTimeout(tm);if(r.ok){const j=await r.json();vosr=Number(j.total_bytes)||0}}catch(_){}
    if(ev)ev.textContent=vosr==null?'— (Bridge offline)':formatBytesAi(vosr);if(et)et.textContent=vosr==null?formatBytesAi(browser):formatBytesAi(browser+vosr)
  }
  function syncModeUi(mode){
    const vosrOn=isVosrMode(mode),cloudOn=isCloudMode(mode),protectedOn=isFidelitySafeMode(mode),note=$('#ups-vosr-note'),cloudNote=$('#ups-cloud-note'),qualityWrap=$('#ups-vosr-quality-wrap');
    if(note)note.hidden=!vosrOn;if(qualityWrap)qualityWrap.hidden=!vosrOn;syncVosrQualityUi();
    if(cloudNote){
      cloudNote.hidden=!cloudOn;
      if(mode==='invsr4')cloudNote.innerHTML='<b>InvSR 4× · online / konzervativní AI</b><br>Oficiální OAOA/InvSR Space. Obrázek se odešle na veřejný Hugging Face ZeroGPU server a výsledek se vrátí přímo sem. Používáme 1-step režim a pevný seed pro konzistentnější výsledek. Služba může mít frontu nebo bezplatný denní limit.';
      else if(mode==='supirf')cloudNote.innerHTML='<b>SUPIR v0F · Archviz Fidelity / online</b><br>Režim v0-F je nastavený na vyšší věrnost originálu a konzervativní 2× obnovu. Toolbox zkusí dostupné veřejné SUPIR servery automaticky; pokud jsou všechny mimo provoz, použije jako bezpečný fallback InvSR. Obrázek se odešle na veřejný Hugging Face Space. Je pomalejší a může mít frontu nebo bezplatný denní limit; jde o research / non-commercial službu.';
    }
    for(const id of ['ups-generative','ups-scene','ups-scene-strength','ups-face','ups-face-strength']){
      const el=$('#'+id);if(el)el.disabled=protectedOn;
    }
    if(vosrOn)checkVosrBridge(false);
  }
  async function ensureGradioClient(){
    if(S.gradioModule)return S.gradioModule;
    status('Načítám cloud AI klienta…',4);
    try{S.gradioModule=await import(GRADIO_CLIENT_URL);return S.gradioModule}
    catch(e){throw new Error('Nepodařilo se načíst Gradio klienta. Zkontroluj internetové připojení.')}
  }
  async function getCloudClient(space){
    if(S.cloudClients[space])return S.cloudClients[space];
    const {Client}=await ensureGradioClient();
    status('Připojuju veřejný AI server…',7);
    const app=await Client.connect(space,{events:['data','status'],status_callback:s=>{if(s?.status==='sleeping')status('AI server se probouzí…',8)}});
    S.cloudClients[space]=app;return app;
  }
  async function resolveCloudEndpoint(app,needle,fallback){
    const cacheKey=(app.config?.space_id||'space')+':'+needle;if(S.cloudApi[cacheKey])return S.cloudApi[cacheKey];
    try{
      const info=await app.view_api(),named=info?.named_endpoints||{},keys=Object.keys(named);
      const exact=keys.find(k=>k.replace(/^\//,'').toLowerCase()===needle.toLowerCase());
      const partial=keys.find(k=>k.toLowerCase().includes(needle.toLowerCase()));
      S.cloudApi[cacheKey]=exact||partial||fallback;
    }catch(e){S.cloudApi[cacheKey]=fallback}
    return S.cloudApi[cacheKey];
  }
  function collectCloudImageUrls(value,out=[]){
    if(value==null)return out;
    if(typeof value==='string'){if(/^https?:\/\//i.test(value))out.push(value);return out}
    if(Array.isArray(value)){for(const v of value)collectCloudImageUrls(v,out);return out}
    if(typeof value==='object'){
      if(typeof value.url==='string'&&/^https?:\/\//i.test(value.url))out.push(value.url);
      for(const [k,v] of Object.entries(value))if(k!=='url'&&k!=='path')collectCloudImageUrls(v,out);
    }
    return out;
  }
  async function canvasFromCloudValue(value,preferLast=true){
    const urls=collectCloudImageUrls(value,[]);
    if(!urls.length)throw new Error('Cloud AI nevrátilo použitelný obrázek.');
    const url=preferLast?urls[urls.length-1]:urls[0],r=await fetch(url,{cache:'no-store'});
    if(!r.ok)throw new Error('Výsledek z cloud AI nejde stáhnout (HTTP '+r.status+').');
    const img=await imageFromBlob(await r.blob()),c=document.createElement('canvas');c.width=img.naturalWidth;c.height=img.naturalHeight;c.getContext('2d').drawImage(img,0,0);return c;
  }
  async function runInvsrCloud(src){
    const {handle_file}=await ensureGradioClient(),app=await getCloudClient(INVSR_SPACE),blob=await canvasToBlob(src);
    status('InvSR · odesílám obrázek na ZeroGPU…',12);
    let res;
    try{res=await app.predict('/predict',[handle_file(blob),1,128,12345])}
    catch(e){throw new Error('InvSR není právě dostupný nebo byl vyčerpán bezplatný GPU limit. '+(e?.message||e))}
    status('InvSR · stahuju 4× výsledek…',92);
    const out=await canvasFromCloudValue(res?.data?.[0]??res?.data??res,true);
    S.engine='InvSR 4× · HF ZeroGPU';$('#ups-engine').textContent=S.engine;return out;
  }
  async function runSupirOnSpace(space,src,blob,handle_file){
    status('SUPIR Fidelity · připojuju '+space+'…',8);
    const app=await getCloudClient(space);
    status('SUPIR Fidelity · načítám v0-F parametry…',10);
    const resetEp=await resolveCloudEndpoint(app,'load_and_reset','/load_and_reset');
    const stageEp=await resolveCloudEndpoint(app,'stage2_process','/stage2_process');
    const d=await app.predict(resetEp,['Fidelity']),defaults=d?.data;
    if(!Array.isArray(defaults)||defaults.length<14)throw new Error('Server nevrátil kompletní Fidelity nastavení.');
    const [edmSteps]=defaults;
    // Archviz-safe Fidelity preset. The public demo's default positive prompt is strongly
    // photographic and its negative prompt penalizes "3D render", which can cause
    // architecture to be re-imagined. Override those defaults and use SUPIR's
    // documented fidelity-oriented guidance values.
    const sCfg=4.0,sStage2=1.0,sStage1=-1.0,sChurn=5,sNoise=1.01;
    const aPrompt='high fidelity restoration, preserve original composition, preserve original architecture, preserve exact geometry, preserve window and door layout, preserve object positions, preserve people positions, preserve materials and colors, preserve original 3D render style, natural fine detail';
    const nPrompt='changed composition, altered architecture, warped geometry, bent straight lines, added windows, removed windows, added doors, removed doors, extra objects, missing objects, duplicated people, deformed people, distorted faces, changed signage, hallucinated text, artifacts';
    const colorFix='Wavelet',linearCfg=true,linearStage2=false,sptLinearCfg=1.0,sptLinearStage2=0.0,modelSelect='v0-F';
    status('SUPIR v0F · ARCHVIZ FIDELITY · čekám na GPU…',16);
    const payload=[
      handle_file(blob),0,null,'',aPrompt,nPrompt,1,1024,1,2,
      edmSteps,sStage1,sStage2,sCfg,false,12345,sChurn,sNoise,colorFix,
      'fp16','bf16',1.0,linearCfg,linearStage2,sptLinearCfg,sptLinearStage2,
      modelSelect,'png',180
    ];
    const res=await app.predict(stageEp,payload);
    status('SUPIR Fidelity · stahuju výsledek…',94);
    const out=await canvasFromCloudValue(res?.data?.[0]??res?.data??res,true);
    S.engine='SUPIR v0F · FIDELITY · '+space;$('#ups-engine').textContent=S.engine;return out;
  }
  async function runSupirFidelityCloud(src){
    const {handle_file}=await ensureGradioClient(),blob=await canvasToBlob(src);
    const errors=[];
    for(const space of SUPIR_SPACES){
      try{return await runSupirOnSpace(space,src,blob,handle_file)}
      catch(e){
        console.warn('SUPIR mirror failed',space,e);
        errors.push(space+': '+(e?.message||e));
        delete S.cloudClients[space];
        for(const k of Object.keys(S.cloudApi))if(k.includes(space))delete S.cloudApi[k];
      }
    }
    status('SUPIR servery jsou teď nedostupné · přepínám na InvSR 4×…',18);
    try{
      const out=await runInvsrCloud(src);
      S.engine='InvSR 4× · SUPIR FALLBACK';$('#ups-engine').textContent=S.engine;
      return out;
    }catch(e){
      throw new Error('SUPIR veřejné servery jsou nedostupné a selhal i InvSR fallback. '+errors.join(' | ')+' | InvSR: '+(e?.message||e));
    }
  }

  async function checkVosrBridge(silent=true){
    const badge=$('#ups-vosr-bridge'),ctrl=new AbortController(),tm=setTimeout(()=>ctrl.abort(),1800);
    try{
      const r=await fetch(VOSR_BRIDGE_URL+'/health',{cache:'no-store',signal:ctrl.signal});
      if(!r.ok)throw new Error('HTTP '+r.status);
      const h=await r.json();S.vosrHealth=h;S.vosrOnline=!!h.ready;S.vosrQualitySupported=versionAtLeast(h.version,'1.3.0');
      const qs=$('#ups-vosr-quality');if(qs)qs.disabled=!S.vosrQualitySupported;syncVosrQualityUi();
      if(badge){
        const bridgeState=h.ready?(S.vosrQualitySupported?'online · GPU připraveno':'online · aktualizuj Bridge pro Quality presety'):(!h.models_ready?'online · chybí modely':(!h.gpu_detected?'online · NVIDIA GPU nenalezena':'online · není připraveno'));
        badge.className='ups-bridge '+(h.ready?'ok':'warn');
        badge.innerHTML='<b>VOSR Bridge:</b> '+bridgeState;
      }
      if(!silent&&!h.ready){
        if(!h.models_ready)status('VOSR Bridge běží, ale modely nejsou nainstalované. Spusť UpscaleBridge\\\\setup.bat.',0);
        else if(!h.gpu_detected)status('VOSR Bridge běží, ale NVIDIA GPU nebyla nalezena.',0);
        else status('VOSR Bridge zatím není připravený.',0);
      }
      return h;
    }catch(e){
      S.vosrOnline=false;S.vosrHealth=null;
      if(badge){badge.className='ups-bridge bad';badge.innerHTML='<b>VOSR Bridge:</b> offline · spusť UpscaleBridge\\\\run_bridge.bat';}
      if(!silent)status('VOSR 2.0 potřebuje lokální bridge. Nejdřív spusť UpscaleBridge\\\\setup.bat a potom run_bridge.bat.',0);
      return null;
    }finally{clearTimeout(tm)}
  }
  function canvasToBlob(canvas,type='image/png',quality=1){return new Promise((res,rej)=>canvas.toBlob(b=>b?res(b):rej(new Error('Nepodařilo se připravit obrázek pro VOSR.')),type,quality))}
  function imageFromBlob(blob){return new Promise((res,rej)=>{const u=URL.createObjectURL(blob),i=new Image();i.onload=()=>{URL.revokeObjectURL(u);res(i)};i.onerror=()=>{URL.revokeObjectURL(u);rej(new Error('VOSR vrátil neplatný obrázek.'))};i.src=u})}
  async function runVosrBridge(src,scale){
    const h=await checkVosrBridge(true);
    if(!h||!h.ready)throw new Error('VOSR Bridge není připravený. Spusť UpscaleBridge\\setup.bat a run_bridge.bat');
    const q=S.vosrQualitySupported?vosrQuality():'fast',renderScale=vosrRenderScale(scale,q),eta=estimateVosrSeconds(src,scale,q),started=performance.now();
    status('VOSR 2.0 · připravuju obraz pro lokální GPU…',8);
    const blob=await canvasToBlob(src);
    status('VOSR 2.0 · '+vosrQualityLabel(q)+' · rekonstruuju scénu na GPU…',22);
    startVosrTelemetry(eta,q,renderScale);
    try{
      const r=await fetch(VOSR_BRIDGE_URL+'/upscale?scale='+encodeURIComponent(renderScale)+'&quality='+encodeURIComponent(q),{method:'POST',headers:{'Content-Type':'image/png'},body:blob});
      if(!r.ok){
        let msg='HTTP '+r.status;
        try{
          const j=await r.json();
          if(j?.error)msg=j.error;
          const detail=String(j?.detail||'').trim();
          if(detail){
            console.error('VOSR inference detail:',detail);
            const lines=detail.split(/\r?\n/).map(x=>x.trim()).filter(Boolean);
            msg+=' · '+lines.slice(-4).join(' | ');
          }
        }catch(e){}
        throw new Error(msg);
      }
      const out=await r.blob();status('VOSR 2.0 · načítám výsledek…',94);
      const img=await imageFromBlob(out),raw=document.createElement('canvas');raw.width=img.naturalWidth;raw.height=img.naturalHeight;raw.getContext('2d').drawImage(img,0,0);
      let result=raw;
      if(renderScale!==scale){status('VOSR Max Quality · supersampling → finální '+scale+'×…',97);result=resize(raw,Math.max(1,Math.round(src.width*scale)),Math.max(1,Math.round(src.height*scale)))}
      const elapsed=(performance.now()-started)/1000;rememberVosrRate(src,scale,q,elapsed);
      S.engine='VOSR 2.0 · '+vosrQualityLabel(q)+' · LOCAL CUDA';$('#ups-engine').textContent=S.engine;
      return result;
    }finally{stopVosrTelemetry()}
  }

  function status(t,p){$('#ups-status').textContent=t;if(Number.isFinite(p))$('#ups-progress').style.width=Math.max(0,Math.min(100,p))+'%'}
  function imageFromFile(f){return new Promise((res,rej)=>{const u=URL.createObjectURL(f),i=new Image();i.onload=()=>{URL.revokeObjectURL(u);res(i)};i.onerror=rej;i.src=u})}
  async function loadFile(f){if(!/^image\//.test(f.type)){status('Soubor není podporovaný obrázek.',0);return}try{const img=await imageFromFile(f);S.file=f;S.img=img;S.result=null;$('#ups-name').textContent=f.name;$('#ups-in').textContent=`${img.naturalWidth} × ${img.naturalHeight}`;$('#ups-out').textContent='—';$('#ups-run').disabled=false;$('#ups-png').disabled=true;$('#ups-jpg').disabled=true;drawPreview(img,$('#ups-before'));drawPreview(img,$('#ups-after'));status('Připraveno.',0)}catch(e){status('Obrázek se nepodařilo načíst: '+e.message,0)}}
  function drawPreview(src,target){const w=src.width||src.naturalWidth,h=src.height||src.naturalHeight;target.width=w;target.height=h;target.getContext('2d').drawImage(src,0,0,w,h)}
  function canvasOf(img){const c=document.createElement('canvas');c.width=img.naturalWidth;c.height=img.naturalHeight;c.getContext('2d').drawImage(img,0,0);return c}
  function resize(src,w,h){const c=document.createElement('canvas');c.width=w;c.height=h;const x=c.getContext('2d');x.imageSmoothingEnabled=true;x.imageSmoothingQuality='high';x.drawImage(src,0,0,w,h);return c}
  function blur(src,r){const c=document.createElement('canvas');c.width=src.width;c.height=src.height;const x=c.getContext('2d');x.filter=`blur(${r}px)`;x.drawImage(src,0,0);x.filter='none';return c}
  function unsharp(src,amount,radius){const b=blur(src,radius),a=src.getContext('2d').getImageData(0,0,src.width,src.height),bd=b.getContext('2d').getImageData(0,0,b.width,b.height).data,d=a.data,C=core();for(let i=0;i<d.length;i+=4)for(let k=0;k<3;k++)d[i+k]=C?C.clampByte(d[i+k]+amount*(d[i+k]-bd[i+k])):Math.max(0,Math.min(255,d[i+k]+amount*(d[i+k]-bd[i+k])));const c=document.createElement('canvas');c.width=src.width;c.height=src.height;c.getContext('2d').putImageData(a,0,0);return c}
  function denoise(src,strength){if(strength<=.01)return src;const b=blur(src,.65+strength*1.5),a=src.getContext('2d').getImageData(0,0,src.width,src.height),bd=b.getContext('2d').getImageData(0,0,b.width,b.height).data,d=a.data;const threshold=8+(1-strength)*22;for(let i=0;i<d.length;i+=4){const l0=.299*d[i]+.587*d[i+1]+.114*d[i+2],l1=.299*bd[i]+.587*bd[i+1]+.114*bd[i+2],edge=Math.abs(l0-l1),mix=strength*.42*Math.max(0,1-edge/threshold);for(let k=0;k<3;k++)d[i+k]=d[i+k]*(1-mix)+bd[i+k]*mix}const c=document.createElement('canvas');c.width=src.width;c.height=src.height;c.getContext('2d').putImageData(a,0,0);return c}
  function localEnhance(src,mode,sharp,detail,noise){let w=denoise(src,noise);const amt=(core()?.sharpenAmount(sharp*100,mode)||(.3+sharp));w=unsharp(w,amt,.75+detail*.9);if(mode==='sharp'||mode==='deblur2')w=unsharp(w,.18+detail*.45,1.7);return w}

  async function fetchAiModel(url,label){
    if(!('caches' in window))return url;
    try{
      const cache=await caches.open(AI_MODEL_CACHE);
      let r=await cache.match(url);
      if(!r){
        status('Stahuju '+label+'…',8);
        r=await fetch(url,{cache:'no-store'});
        if(!r.ok)throw new Error('HTTP '+r.status);
        await cache.put(url,r.clone());
      }
      return new Uint8Array(await r.arrayBuffer());
    }catch(e){
      console.warn('Toolbox AI cache fallback',e);
      return url;
    }
  }
  async function deleteMatchingIndexedDb(){
    if(!indexedDB?.databases)return 0;
    let n=0;
    try{
      const dbs=await indexedDB.databases();
      for(const d of dbs){
        const name=d?.name||'';
        if(!/upscal|onnx|ai[-_. ]?model|huggingface|transformers/i.test(name))continue;
        await new Promise(resolve=>{const q=indexedDB.deleteDatabase(name);q.onsuccess=q.onerror=q.onblocked=()=>resolve()});n++;
      }
    }catch(e){console.warn('IndexedDB cleanup',e)}
    return n;
  }
  function downloadCleanupFallback(){
    const a=document.createElement('a');a.href='UpscaleBridge/cleanup_ai.bat';a.download='20-20-TOOLBOX_AI_CLEANUP.bat';document.body.appendChild(a);a.click();a.remove();
  }
  async function cleanupAiStorage(){
    if(S.running)return alert('Nejdřív nech doběhnout aktuální upscale.');
    const ok=confirm('Smazat stažená AI data Toolboxu?\n\n• Real-ESRGAN / GFPGAN Toolbox cache\n• VOSR modely + Python runtime + knihovny (pokud jsou nainstalované)\n\nVOSR pak bude při dalším použití potřeba znovu nainstalovat.');
    if(!ok)return;
    status('Čistím AI data…',10);
    try{await S.session?.release?.()}catch(_){}
    try{await S.faceSession?.release?.()}catch(_){}
    S.session=null;S.faceSession=null;S.loadingModel=null;S.loadingFaceModel=null;
    let cacheDeleted=false,idbDeleted=0;
    try{if('caches' in window)cacheDeleted=await caches.delete(AI_MODEL_CACHE)}catch(e){console.warn('Cache cleanup',e)}
    idbDeleted=await deleteMatchingIndexedDb();
    for(let i=localStorage.length-1;i>=0;i--){const k=localStorage.key(i)||'';if(/toolbox\.(ai|upscal)|onnx|model.?cache/i.test(k))localStorage.removeItem(k)}
    let vosr='nenainstalován / bridge offline';
    try{
      const r=await fetch(VOSR_BRIDGE_URL+'/cleanup',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});
      if(r.ok){vosr='mazání spuštěno';S.vosrOnline=false;S.vosrHealth=null}
      else throw new Error('HTTP '+r.status);
    }catch(e){
      vosr='bridge offline — stáhl jsem cleanup skript';
      try{downloadCleanupFallback()}catch(_){}
    }
    const badge=$('#ups-vosr-bridge');if(badge){badge.className='ups-bridge warn';badge.innerHTML='<b>VOSR Bridge:</b> po cleanupu bude potřeba znovu nainstalovat';}
    const eb=$('#ups-ai-storage-browser'),ev=$('#ups-ai-storage-vosr'),et=$('#ups-ai-storage-total');if(eb)eb.textContent='0 B';if(ev)ev.textContent=vosr==='mazání spuštěno'?'mazání…':'—';if(et)et.textContent=vosr==='mazání spuštěno'?'mazání…':'0 B';
    status('AI cleanup: browser cache '+(cacheDeleted?'smazána':'vyčištěna / nebyla nalezena')+', IndexedDB '+idbDeleted+' · VOSR: '+vosr+'.',100);
  }

  async function ensureOrt(){if(window.ort)return;status('Načítám ONNX Runtime…',4);await new Promise((res,rej)=>{const s=document.createElement('script');s.src=ORT_URL;s.onload=res;s.onerror=()=>rej(new Error('Nepodařilo se načíst ONNX Runtime'));document.head.appendChild(s)});ort.env.wasm.wasmPaths='https://cdn.jsdelivr.net/npm/onnxruntime-web@1.22.0/dist/'}
  async function ensureSession(){if(S.session)return S.session;if(S.loadingModel)return S.loadingModel;S.loadingModel=(async()=>{await ensureOrt();const model=await fetchAiModel(MODEL_URL,'Real-ESRGAN model (~67 MB)');let sess;try{if(navigator.gpu){sess=await ort.InferenceSession.create(model,{executionProviders:['webgpu','wasm']});S.engine='AI · WebGPU'}}catch(e){console.warn('WebGPU Real-ESRGAN fallback',e)}if(!sess){sess=await ort.InferenceSession.create(model,{executionProviders:['wasm']});S.engine='AI · WASM'}S.session=sess;$('#ups-engine').textContent=S.engine;return sess})().finally(()=>S.loadingModel=null);return S.loadingModel}

  async function ensureObjectDetector(){if(S.objectDetector)return S.objectDetector;if(S.loadingObjectDetector)return S.loadingObjectDetector;S.loadingObjectDetector=(async()=>{status('Analyzuju objekty ve scéně…',86);const mp=await import(MEDIAPIPE_URL);const vision=await mp.FilesetResolver.forVisionTasks(MEDIAPIPE_WASM);S.objectDetector=await mp.ObjectDetector.createFromOptions(vision,{baseOptions:{modelAssetPath:OBJECT_DETECTOR_MODEL},runningMode:'IMAGE',scoreThreshold:.22,maxResults:30});return S.objectDetector})().finally(()=>S.loadingObjectDetector=null);return S.loadingObjectDetector}
  function cropRect(src,x,y,w,h,maxSide=224){const sx=Math.max(0,Math.floor(x)),sy=Math.max(0,Math.floor(y)),sw=Math.max(2,Math.min(src.width-sx,Math.ceil(w))),sh=Math.max(2,Math.min(src.height-sy,Math.ceil(h))),scale=Math.min(1,maxSide/Math.max(sw,sh)),c=document.createElement('canvas');c.width=Math.max(16,Math.round(sw*scale));c.height=Math.max(16,Math.round(sh*scale));const cx=c.getContext('2d');cx.imageSmoothingEnabled=true;cx.imageSmoothingQuality='high';cx.drawImage(src,sx,sy,sw,sh,0,0,c.width,c.height);return{canvas:c,x:sx,y:sy,w:sw,h:sh}}
  function compositeObject(dst,enhanced,box,strength,generative=true){const patch=document.createElement('canvas');patch.width=box.w;patch.height=box.h;const px=patch.getContext('2d');px.imageSmoothingEnabled=true;px.imageSmoothingQuality='high';px.drawImage(enhanced,0,0,patch.width,patch.height);const mask=document.createElement('canvas');mask.width=patch.width;mask.height=patch.height;const mx=mask.getContext('2d'),m=Math.max(3,Math.round(Math.min(patch.width,patch.height)*(generative?.08:.18))),g=mx.createLinearGradient(0,0,patch.width,0);mx.fillStyle='#fff';mx.fillRect(m,0,Math.max(1,patch.width-2*m),patch.height);const vg=mx.createLinearGradient(0,0,0,patch.height);vg.addColorStop(0,'rgba(255,255,255,0)');vg.addColorStop(m/patch.height,'rgba(255,255,255,1)');vg.addColorStop(1-m/patch.height,'rgba(255,255,255,1)');vg.addColorStop(1,'rgba(255,255,255,0)');mx.globalCompositeOperation='destination-in';mx.fillStyle=vg;mx.fillRect(0,0,patch.width,patch.height);mx.globalCompositeOperation='source-over';const lg=mx.createLinearGradient(0,0,patch.width,0);lg.addColorStop(0,'rgba(255,255,255,0)');lg.addColorStop(m/patch.width,'rgba(255,255,255,1)');lg.addColorStop(1-m/patch.width,'rgba(255,255,255,1)');lg.addColorStop(1,'rgba(255,255,255,0)');mx.globalCompositeOperation='destination-in';mx.fillStyle=lg;mx.fillRect(0,0,patch.width,patch.height);px.globalCompositeOperation='destination-in';px.drawImage(mask,0,0);px.globalCompositeOperation='source-over';const dx=dst.getContext('2d');dx.save();dx.globalAlpha=generative?Math.max(.88,Math.min(1,.94+strength*.06)):Math.max(.35,Math.min(.88,.45+strength*.4));dx.drawImage(patch,box.x,box.y);dx.restore()}
  function objectPriority(label,score,box,imgW,imgH){const hot=/sandwich|pizza|cake|donut|hot dog|bottle|cup|wine glass|fork|knife|spoon|bowl|banana|apple|orange|broccoli|carrot|book|cell phone|laptop|keyboard|mouse|tv|clock|vase|potted plant|chair|backpack|handbag/i.test(label||'');const area=(box.width*box.height)/(imgW*imgH);return score+(hot?.42:0)+(area<.03?.22:area<.09?.1:0)}
  async function restoreObjects(sourceForDetection,result,strength,generative=true){const detector=await ensureObjectDetector(),det=detector.detect(sourceForDetection),rx=result.width/sourceForDetection.width,ry=result.height/sourceForDetection.height;let items=(det?.detections||[]).map(d=>{const cat=d.categories?.[0]||{},b=d.boundingBox;return b?{label:cat.categoryName||cat.displayName||'objekt',score:Number(cat.score)||0,box:b}:null}).filter(Boolean).filter(o=>!/person/i.test(o.label)).filter(o=>o.box.width>=8&&o.box.height>=8).map(o=>({...o,priority:objectPriority(o.label,o.score,o.box,sourceForDetection.width,sourceForDetection.height)})).sort((a,b)=>b.priority-a.priority).slice(0,10);if(!items.length){status('Objektová analýza nenašla vhodné regiony.',90);return{count:0,labels:[]}}await ensureSession();let done=0;const labels=[];for(const o of items){const b=o.box,cx=(b.originX+b.width/2)*rx,cy=(b.originY+b.height/2)*ry,pad=1.42,w=Math.max(40,b.width*rx*pad),h=Math.max(40,b.height*ry*pad),x=cx-w/2,y=cy-h/2,cr=cropRect(result,x,y,w,h,208);if(cr.w<18||cr.h<18)continue;status(`Rekonstruuju objekt: ${o.label} (${done+1}/${items.length})`,88+5*(done/items.length));let hi=await aiX4(cr.canvas);hi=localEnhance(hi,'clean',generative?.32+.28*strength:.16+.18*strength,generative?.38+.34*strength:.18+.22*strength,0);if(generative)hi=localEnhance(hi,'sharp',.28+.24*strength,.42+.28*strength,0);const restored=resize(hi,cr.w,cr.h);compositeObject(result,restored,cr,strength,generative);done++;labels.push(o.label);await new Promise(r=>setTimeout(r,0))}return{count:done,labels:[...new Set(labels)]}}
  async function ensureFaceDetector(){if(S.faceDetector)return S.faceDetector;if(S.loadingFaceDetector)return S.loadingFaceDetector;S.loadingFaceDetector=(async()=>{status('Načítám detekci obličejů…',90);const mp=await import(MEDIAPIPE_URL);const vision=await mp.FilesetResolver.forVisionTasks(MEDIAPIPE_WASM);S.faceDetector=await mp.FaceDetector.createFromOptions(vision,{baseOptions:{modelAssetPath:FACE_DETECTOR_MODEL},runningMode:'IMAGE',minDetectionConfidence:.35,minSuppressionThreshold:.3});return S.faceDetector})().finally(()=>S.loadingFaceDetector=null);return S.loadingFaceDetector}
  async function ensureFaceSession(){if(S.faceSession)return S.faceSession;if(S.loadingFaceModel)return S.loadingFaceModel;S.loadingFaceModel=(async()=>{await ensureOrt();const model=await fetchAiModel(GFPGAN_URL,'GFPGAN model (~340 MB)');let sess;try{if(navigator.gpu)sess=await ort.InferenceSession.create(model,{executionProviders:['webgpu','wasm']})}catch(e){console.warn('GFPGAN WebGPU fallback',e)}if(!sess)sess=await ort.InferenceSession.create(model,{executionProviders:['wasm']});S.faceSession=sess;return sess})().finally(()=>S.loadingFaceModel=null);return S.loadingFaceModel}
  function faceTensorFromCanvas(c){const d=c.getContext('2d').getImageData(0,0,c.width,c.height).data,n=c.width*c.height,a=new Float32Array(n*3);for(let i=0;i<n;i++){a[i]=d[i*4]/127.5-1;a[n+i]=d[i*4+1]/127.5-1;a[n*2+i]=d[i*4+2]/127.5-1}return new ort.Tensor('float32',a,[1,3,c.height,c.width])}
  function faceCanvasFromTensor(t){const dims=t.dims,data=t.data,h=dims[dims.length-2],w=dims[dims.length-1],n=w*h,c=document.createElement('canvas'),x=c.getContext('2d'),im=x.createImageData(w,h),d=im.data,C=core();c.width=w;c.height=h;for(let i=0;i<n;i++){d[i*4]=C.clampByte((data[i]+1)*127.5);d[i*4+1]=C.clampByte((data[n+i]+1)*127.5);d[i*4+2]=C.clampByte((data[2*n+i]+1)*127.5);d[i*4+3]=255}x.putImageData(im,0,0);return c}
  function cropSquare(src,cx,cy,side,size=512){const c=document.createElement('canvas');c.width=size;c.height=size;const x=c.getContext('2d');x.imageSmoothingEnabled=true;x.imageSmoothingQuality='high';x.drawImage(src,cx-side/2,cy-side/2,side,side,0,0,size,size);return c}
  function compositeFace(dst,face,cx,cy,side,strength,generative=true){const patch=document.createElement('canvas');patch.width=Math.max(8,Math.round(side));patch.height=patch.width;const px=patch.getContext('2d');px.imageSmoothingEnabled=true;px.imageSmoothingQuality='high';px.drawImage(face,0,0,patch.width,patch.height);const g=px.createRadialGradient(patch.width/2,patch.height*.48,patch.width*(generative?.35:.26),patch.width/2,patch.height*.48,patch.width*(generative?.51:.55));g.addColorStop(0,'rgba(255,255,255,1)');g.addColorStop(generative?.78:.62,'rgba(255,255,255,1)');g.addColorStop(1,'rgba(255,255,255,0)');px.globalCompositeOperation='destination-in';px.fillStyle=g;px.fillRect(0,0,patch.width,patch.height);px.globalCompositeOperation='source-over';const dx=dst.getContext('2d');dx.save();dx.globalAlpha=generative?Math.max(.92,Math.min(1,.96+strength*.04)):Math.max(.45,Math.min(1,strength));dx.drawImage(patch,cx-side/2,cy-side/2,side,side);dx.restore()}
  async function restoreFaces(sourceForDetection,result,strength,generative=true){const detector=await ensureFaceDetector(),det=detector.detect(sourceForDetection),faces=(det?.detections||[]).map(d=>d.boundingBox).filter(Boolean).sort((a,b)=>b.width*b.height-a.width*a.height).slice(0,12);if(!faces.length){status('Obličeje nebyly nalezeny — dokončuju obraz bez face restore.',96);return 0}const sess=await ensureFaceSession(),rx=result.width/sourceForDetection.width,ry=result.height/sourceForDetection.height,input=sess.inputNames[0],output=sess.outputNames[0];let done=0;for(const b of faces){const w=b.width*rx,h=b.height*ry;if(Math.max(w,h)<14)continue;const cx=(b.originX+b.width/2)*rx,cy=(b.originY+b.height/2)*ry,side=Math.max(48,Math.max(w,h)*(generative?1.72:1.9)),crop=cropSquare(result,cx,cy,side,512),ten=faceTensorFromCanvas(crop),res=await sess.run({[input]:ten}),face=faceCanvasFromTensor(res[output]);compositeFace(result,face,cx,cy,side,strength,generative);done++;status(`Rekonstruuju obličeje: ${done}/${faces.length}`,92+6*done/faces.length);await new Promise(r=>setTimeout(r,0))}return done}

  function makeTile(src,x,y,tile){const c=document.createElement('canvas');c.width=tile;c.height=tile;const cx=c.getContext('2d');const sw=Math.min(tile,src.width-x),sh=Math.min(tile,src.height-y);cx.drawImage(src,x,y,sw,sh,0,0,sw,sh);if(sw<tile&&sw>0)cx.drawImage(c,sw-1,0,1,sh,sw,0,tile-sw,sh);if(sh<tile&&sh>0)cx.drawImage(c,0,sh-1,tile,1,0,sh,tile,tile-sh);return c}
  function tensorFromCanvas(c){const d=c.getContext('2d').getImageData(0,0,c.width,c.height).data,n=c.width*c.height,a=new Float32Array(n*3);for(let i=0;i<n;i++){a[i]=d[i*4]/255;a[n+i]=d[i*4+1]/255;a[n*2+i]=d[i*4+2]/255}return new ort.Tensor('float32',a,[1,3,c.height,c.width])}
  function canvasFromTensor(t){const dims=t.dims,data=t.data,h=dims[dims.length-2],w=dims[dims.length-1],n=w*h,c=document.createElement('canvas');c.width=w;c.height=h;const x=c.getContext('2d'),im=x.createImageData(w,h),d=im.data,C=core();for(let i=0;i<n;i++){d[i*4]=C.clampByte(data[i]*255);d[i*4+1]=C.clampByte(data[n+i]*255);d[i*4+2]=C.clampByte(data[2*n+i]*255);d[i*4+3]=255}x.putImageData(im,0,0);return c}
  async function aiX4(src){const sess=await ensureSession(),tile=128,overlap=16,C=core(),xs=C.tileStarts(src.width,tile,overlap),ys=C.tileStarts(src.height,tile,overlap),scale=4,out=document.createElement('canvas');out.width=src.width*scale;out.height=src.height*scale;const ox=out.getContext('2d'),input=sess.inputNames[0],output=sess.outputNames[0],total=xs.length*ys.length;let done=0;for(const y of ys)for(const x of xs){if(!S.running)throw new Error('Zpracování přerušeno');const tc=makeTile(src,x,y,tile),ten=tensorFromCanvas(tc),res=await sess.run({[input]:ten}),oc=canvasFromTensor(res[output]);const left=x===0?0:overlap/2,top=y===0?0:overlap/2,right=x===xs[xs.length-1]?0:overlap/2,bottom=y===ys[ys.length-1]?0:overlap/2,sw=(tile-left-right)*scale,sh=(tile-top-bottom)*scale;ox.drawImage(oc,left*scale,top*scale,sw,sh,(x+left)*scale,(y+top)*scale,sw,sh);done++;status(`AI rekonstrukce: ${done}/${total} dlaždic`,10+80*done/total);await new Promise(r=>setTimeout(r,0))}return out}

  async function run(){
    if(!S.img||S.running)return;
    S.running=true;$('#ups-run').disabled=true;$('#ups-png').disabled=true;$('#ups-jpg').disabled=true;$('#ups-mode').disabled=true;
    const t0=performance.now(),mode=$('#ups-mode').value,isVosr=isVosrMode(mode),isCloud=isCloudMode(mode),isProtected=isFidelitySafeMode(mode),sharp=Number($('#ups-sharp').value)/100,detail=Number($('#ups-detail').value)/100,noise=Number($('#ups-denoise').value)/100,generative=$('#ups-generative')?.checked!==false,sceneRestore=$('#ups-scene')?.checked,sceneStrength=Number($('#ups-scene-strength')?.value||72)/100,faceRestore=$('#ups-face')?.checked,faceStrength=Number($('#ups-face-strength')?.value||82)/100;
    if(isVosr&&$('#ups-vosr-quality'))$('#ups-vosr-quality').disabled=true;
    try{
      let src=canvasOf(S.img),scale=core().outputScale(mode),renderScale=isVosr?vosrRenderScale(scale,vosrQuality()):scale,pred=src.width*src.height*renderScale*renderScale,maxPx=isVosr?64000000:36000000;
      if(pred>maxPx){
        const f=Math.sqrt(maxPx/pred);src=resize(src,Math.max(128,Math.round(src.width*f)),Math.max(128,Math.round(src.height*f)));
        status('Velký obrázek: vstup byl bezpečně zmenšen kvůli paměti.',3);
      }
      let result;
      if(mode==='sharp'||mode==='clean'){
        status('Lokální rekonstrukce hran…',25);result=localEnhance(src,mode,sharp,detail,noise);S.engine='LOCAL · EDGE';$('#ups-engine').textContent=S.engine;
      }else if(mode==='safe4'){
        const prep=denoise(src,noise*.25);result=await aiX4(prep);
        if(result.width*result.height<16000000)result=localEnhance(result,'clean',sharp*.08,detail*.06,0);
        S.engine='Real-ESRGAN 4× · SAFE LOCAL';$('#ups-engine').textContent=S.engine;
      }else if(mode==='invsr4'){
        result=await runInvsrCloud(src);
      }else if(mode==='supirf'){
        result=await runSupirFidelityCloud(src);
      }else if(isVosr){
        result=await runVosrBridge(src,scale);
        if(result.width*result.height<24000000)result=localEnhance(result,'clean',sharp*.08,detail*.10,0);
      }else{
        let prep=src;if(mode==='deblur2')prep=localEnhance(prep,'deblur2',Math.min(1,sharp*.75),detail*.75,noise);else prep=denoise(prep,noise*.5);
        result=await aiX4(prep);if(scale===2)result=resize(result,Math.round(result.width/2),Math.round(result.height/2));
        if(result.width*result.height<16000000)result=localEnhance(result,'clean',sharp*.22,detail*.18,0);
      }
      let sceneInfo={count:0,labels:[]};
      if(!isProtected&&sceneRestore&&mode!=='sharp'&&mode!=='clean'){
        try{sceneInfo=await restoreObjects(src,result,sceneStrength,generative);if(sceneInfo.count){S.engine+=(S.engine.includes('SCENE')?'':' + SCENE AI');$('#ups-engine').textContent=S.engine}}
        catch(sceneErr){console.warn('Scene reconstruction failed',sceneErr);status('Základní upscale je hotový, scene reconstruction se nepodařila: '+sceneErr.message,94)}
      }
      let restored=0;
      if(!isProtected&&faceRestore){
        try{restored=await restoreFaces(src,result,faceStrength,generative);if(restored){S.engine+=(S.engine.includes('FACE')?'':' + FACE AI');$('#ups-engine').textContent=S.engine}}
        catch(faceErr){console.warn('Face restore failed',faceErr);status('Upscale je hotový, face restore se nepodařil: '+faceErr.message,98)}
      }
      S.result=result;const before=resize(src,result.width,result.height);drawPreview(before,$('#ups-before'));drawPreview(result,$('#ups-after'));
      $('#ups-out').textContent=`${result.width} × ${result.height}`;$('#ups-time').textContent=((performance.now()-t0)/1000).toFixed(1)+' s';$('#ups-png').disabled=false;$('#ups-jpg').disabled=false;
      const parts=[];if(mode==='safe4')parts.push('Safe Real-ESRGAN 4×');if(mode==='invsr4')parts.push('InvSR 4×');if(mode==='supirf')parts.push('SUPIR v0F Fidelity 2×');if(isVosr)parts.push('VOSR 2.0 · celá scéna');if(sceneInfo.count)parts.push(`${sceneInfo.count} objektů (${sceneInfo.labels.slice(0,5).join(', ')})`);if(restored)parts.push(`${restored} obličejů`);
      status(parts.length?`Hotovo · ${parts.join(' + ')}. Posuň slider a porovnej.`:'Hotovo. Posuň slider a porovnej originál s výsledkem.',100);
    }catch(e){
      console.error(e);status(((isVosr?'VOSR 2.0':isCloud?'Online AI':'AI režim')+' selhal: ')+e.message+(isVosr||isCloud?'':' . Zkus Safe Upscale 4×, Sharp Fix nebo Clean Photo.'),0);
    }finally{S.running=false;stopVosrTelemetry();$('#ups-run').disabled=!S.img;$('#ups-mode').disabled=false;if($('#ups-vosr-quality'))$('#ups-vosr-quality').disabled=!S.vosrQualitySupported}
  }
  function save(type,q,name){if(!S.result)return;S.result.toBlob(b=>{if(!b)return;const u=URL.createObjectURL(b),a=document.createElement('a');a.href=u;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(u),1000)},type,q)}

  window.initUpscalerApp=init;install();
})();