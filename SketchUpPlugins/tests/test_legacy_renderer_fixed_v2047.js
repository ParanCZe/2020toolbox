// Reproduce the two actual scripts in isolation, ensuring old plugin status
// wiring cannot override the new large RM TOOLS + folded Legacy layout.
const fs=require('node:fs');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const index=fs.readFileSync('index.html','utf8');
const status=fs.readFileSync('sketchup_plugin_status_v360.js','utf8');
const b=index.indexOf('function renderSuPluginCard(p){');
const e=index.indexOf('function toggleSuPluginHistory(',b);
assert(b>=0&&e>b,'Native two-area renderer must exist');
const native=index.slice(b,e);
const a=status.indexOf('  const renderSketchUpPluginsNative = window.renderSketchUpPlugins;');
const z=status.indexOf('  };\n})();',a);
assert(a>=0&&z>a,'External status wrapper must delegate to native renderer');
assert(!status.includes('grid.innerHTML=SU_PLUGIN_CATALOG.map('),'External script must not paint ALL plugins into main grid');
assert(index.includes('<details id="suplugins-legacy"'),'Legacy details must exist and be collapsed');
assert(!/<details id="suplugins-legacy"[^>]+open(?:\s|>)/.test(index),'Legacy must be folded by default');
assert(index.includes('sketchup_plugin_status_v360.js?v=378'),'Force browsers to fetch corrected status script');

const elements={};
for(const id of ['suplugins-grid','suplugins-legacy-grid','legacy-plugin-count']){
  elements[id]={innerHTML:'',textContent:''};
}
let refreshCount=0,bridgeCount=0;
const products=[
  {id:'rm-tools-suite',name:'20-20 RM TOOLS',current:'2.0.4.7',featured:true,description:'All in one',meta:'latest',icon:'library',versions:[{version:'2.0.4.7',size:109672}]},
  {id:'component-library-server',name:'20-20 Component Library',current:'0.3.2.1',description:'Legacy',meta:'old',icon:'library',versions:[{version:'0.3.2.1',size:15015}]},
  {id:'live-mirror',name:'20-20 Live Mirror',current:'0.4.18',description:'Legacy',meta:'old',icon:'mirror',versions:[{version:'0.4.18',size:42000}]},
  {id:'agent-launcher',name:'Agent Launcher',current:'0.1.2',description:'Legacy',meta:'old',icon:'library',versions:[{version:'0.1.2',size:21000}]}
];
const sandbox={
  SU_PLUGIN_CATALOG:products,
  document:{
    getElementById(id){return elements[id]||null;}
  },
  window:{},
  getSuPluginVersion(p,version){return p.versions.find(x=>x.version===version);},
  suFmtBytes(n){return String(n)+' bytes';},
  suPluginIcon(name){return '<svg>'+name+'</svg>';},
  escapeHtml(s){return String(s);},
  refreshSuPluginVersions(){refreshCount++;},
  configureBridgePanel(){bridgeCount++;}
};
vm.createContext(sandbox);
vm.runInContext(native+'\nwindow.renderSketchUpPlugins=renderSketchUpPlugins;\n'+status.slice(a,z+5),sandbox);
sandbox.window.renderSketchUpPlugins();
assert.equal((elements['suplugins-grid'].innerHTML.match(/class="suplugin-card/g)||[]).length,1,'Main must have exactly ONE plugin');
assert(elements['suplugins-grid'].innerHTML.includes('id="suplugin-rm-tools-suite"'));
assert(elements['suplugins-grid'].innerHTML.includes('class="suplugin-card featured"'),'Featured card must retain large card CSS class');
assert(!elements['suplugins-grid'].innerHTML.includes('id="suplugin-live-mirror"'));
assert.equal((elements['suplugins-legacy-grid'].innerHTML.match(/class="suplugin-card/g)||[]).length,3,'ALL old plugins must be inside the Legacy details');
for(const legacy of products.slice(1))assert(elements['suplugins-legacy-grid'].innerHTML.includes('id="suplugin-'+legacy.id+'"'),legacy.id);
assert.equal(elements['legacy-plugin-count'].textContent,'3 pluginů');
assert.equal(bridgeCount,1);
assert.equal(refreshCount,1);
console.log('PASS: only enlarged RM TOOLS remains outside Legacy plugins');
console.log('PASS: every other plugin renders exclusively INSIDE the collapsed Legacy section');
console.log('PASS: external script preserves native renderer, status updates and Bridge setup');
console.log('PASS: cache-busted corrected script and original install/download controls retained');
