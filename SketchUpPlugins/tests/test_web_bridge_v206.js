// Run after patch_web_bridge_v206.py. Mocks a browser, network and native URL handler.
const fs=require('node:fs');
const vm=require('node:vm');
const assert=require('node:assert/strict');

const page=fs.readFileSync('index.html','utf8');
function section(start,end){
  const a=page.indexOf(start);
  assert(a!==-1,'Missing '+start);
  const b=page.indexOf(end,a);
  assert(b>a,'Missing '+end);
  return page.slice(a,b);
}
const runtime=section('let suBridgeActiveUrl=null;','function cmpVer(');
const installation=section('async function refreshSuPluginVersions(){','let suToastTimer=null');
let mode='off';
let launched=0;
let installed=0;
const network=[];
const display={'suplugin-state-demo':{className:'',textContent:''}};
const doc={
  body:{appendChild(){}},
  createElement(tag){
    assert.equal(tag,'a');
    return {
      style:{},href:'',remove(){},
      click(){launched++;mode='on';}
    };
  },
  getElementById(id){return display[id]||null;}
};

async function fetchStub(url,options={}){
  network.push(url);
  if(url.endsWith('/status')){
    const connected=mode==='on' && url.startsWith('http://127.0.0.1:8093');
    return {ok:connected,async json(){return {ok:connected,sketchup:'SketchUp 2026',installed:{},bridge_version:'3.5'}}};
  }
  if(url.includes('/install?file=demo.rbz')){
    assert.equal(mode,'on');
    assert.equal(options.method,'POST');
    installed++;
    return {ok:true,async json(){return {ok:true,sketchup:'SketchUp 2026',installed:{demo:'1.0'}}}};
  }
  throw Error('Unexpected network request: '+url);
}

const context={
  fetch:fetchStub,
  document:doc,
  Promise,AbortController,
  setTimeout,clearTimeout,
  console,
  SU_BRIDGE_URL:'http://127.0.0.1:8093',
  SU_BRIDGE_SCHEME:'twentytwentytoolboxv3://bridge',
  SU_PLUGIN_CATALOG:[{id:'demo',loader:'demo.rb'}],
  suPluginPayload(id,version){assert.equal(id,'demo');return {plugin:{id,name:'Demo plugin',loader:'demo.rb'},version:{file:'demo.rbz'}};},
  async suPluginBytes(){network.push('FETCH_SELECTED_RBZ');return {plugin:{name:'Demo plugin'},version:{file:'demo.rbz'},bytes:new Uint8Array([80,75])};},
  suPluginToast(){},
  applyInstalledVersions(){}
};
vm.createContext(context);
vm.runInContext(runtime+'\n'+installation+'\nfunction __bridgeUrl(){return suBridgeActiveUrl}',context);

(async()=>{
  await context.refreshSuPluginVersions();
  assert.equal(launched,0,'Opening plugin list must not automatically relaunch/download bridge');
  assert.equal(display['suplugin-state-demo'].textContent,'Bridge připraven ke spuštění');

  network.length=0;
  await context.installSuPlugin('demo','1.0');
  assert.equal(launched,1,'Button must open installed bridge protocol directly');
  assert.equal(installed,1);
  assert.equal(context.__bridgeUrl(),'http://127.0.0.1:8093');
  const statusIndex=network.findIndex(x=>x.endsWith('/status'));
  const rbzIndex=network.indexOf('FETCH_SELECTED_RBZ');
  const installIndex=network.findIndex(x=>x.includes('/install?file=demo.rbz'));
  assert(statusIndex>=0 && rbzIndex>statusIndex && installIndex>rbzIndex);
  assert(network.every(url=>!String(url).includes('bridge_v3.ps1')));
  console.log('PASS: web opens cached native Bridge; only selected plugin RBZ is downloaded afterwards');
  console.log('PASS: passive status does not restart/download Bridge on every page visit');
})().catch(error=>{console.error(error);process.exit(1)});
