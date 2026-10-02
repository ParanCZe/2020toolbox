# frozen_string_literal: true
require 'sketchup.rb'
require 'json'
require 'cgi'

module TwentyTwenty
  module RMManagers
    extend self
    VERSION = '0.1.0'.freeze
    def html_escape(v); CGI.escapeHTML(v.to_s); end
    def show(which)
      @dialogs ||= {}
      if (dlg = @dialogs[which])
        dlg.show
        refresh(which)
        return dlg
      end
      dlg = UI::HtmlDialog.new(dialog_title: "20-20 RM #{which == :tags ? 'TAG' : 'SCENE'} MANAGER",
        preferences_key: "2020-rm-#{which}-manager", scrollable: true, resizable: true,
        width: 1000, height: 740, min_width: 650, min_height: 490,
        style: UI::HtmlDialog::STYLE_DIALOG)
      @dialogs[which] = dlg
      dlg.add_action_callback('ready') { |_ctx| refresh(which) }
      dlg.add_action_callback('action') do |_ctx, raw|
        begin
          data = JSON.parse(raw.to_s)
          which == :tags ? tag_action(data) : scene_action(data)
        rescue StandardError => e
          notify(which, "#{e.class}: #{e.message}")
        end
      end
      dlg.add_action_callback('back') do |_ctx|
        dlg.close
        TwentyTwenty::RMToolsSuite.show
      end
      dlg.set_on_closed { @dialogs.delete(which) }
      dlg.set_html(html(which))
      dlg.show
      dlg
    end
    def js(which, fn, data)
      dlg = @dialogs && @dialogs[which]
      dlg.execute_script("window.Manager && Manager.#{fn}(#{JSON.generate(data)});") if dlg
    end
    def notify(which, message); js(which, 'notice', message); end
    def refresh(which)
      js(which, 'receive', which == :tags ? tag_data : scene_data)
    end

    def nested_members(entities, path, output, seen = {})
      entities.each do |ent|
        next unless ent.valid?
        next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
        key = ent.respond_to?(:persistent_id) ? ent.persistent_id : ent.entityID
        output << {
          id: key, name: (ent.name.to_s.empty? ? (ent.respond_to?(:definition) ? ent.definition.name : 'Group') : ent.name),
          definition: ent.respond_to?(:definition) ? ent.definition.name : 'Group',
          tag: ent.layer.name, hidden: ent.hidden?, path: path,
          materials: component_materials(ent), kind: ent.is_a?(Sketchup::Group) ? 'Group' : 'Component'
        }
        definition = ent.respond_to?(:definition) ? ent.definition : nil
        # Prevent circular definitions and extremely deep imported structures.
        next unless definition && path.length < 8
        next if seen[definition.object_id]
        nested_members(definition.entities, path + [key], output, seen.merge(definition.object_id => true))
      end
    end
    def component_materials(ent)
      names = []
      names << ent.material.name if ent.respond_to?(:material) && ent.material
      defn = ent.respond_to?(:definition) ? ent.definition : nil
      if defn
        defn.entities.each do |child|
          names << child.material.name if child.respond_to?(:material) && child.material
          names << child.back_material.name if child.respond_to?(:back_material) && child.back_material
        end
      end
      names.compact.uniq.first(30)
    end
    def object_cache
      model = Sketchup.active_model
      objects = []
      nested_members(model.entities, [], objects)
      @model_key = model.object_id
      @objects = objects
      objects
    end
    def folders(parent)
      parent.respond_to?(:folders) ? parent.folders.map { |f|
        {name: f.name, id: "folder:#{f.name}", visible: (f.respond_to?(:visible?) ? f.visible? : true),
         children: folders(f), tags: f.respond_to?(:layers) ? f.layers.map { |l| tag_item(l) } : []}
      } : []
    end
    def tag_item(layer)
      {name: layer.name, id: "tag:#{layer.name}", visible: layer.visible?}
    end
    def tag_data
      m = Sketchup.active_model
      members = object_cache
      all_folders = folders(m.layers)
      grouped = members.group_by { |x| x[:tag] }
      roots = m.layers.to_a.select { |l| !l.respond_to?(:folder) || l.folder.nil? }.map { |l| tag_item(l) }
      {folders: all_folders, root_tags: roots, objects: grouped, count: members.length}
    end
    def find_entity(id)
      model = Sketchup.active_model
      raise 'Otevři model před výběrem.' unless model
      obj = model.respond_to?(:find_entity_by_persistent_id) ? model.find_entity_by_persistent_id(id.to_i) : nil
      raise 'Objekt už v modelu neexistuje. Obnov seznam.' unless obj && obj.valid?
      obj
    end
    def folder_by_name(name, collection = Sketchup.active_model.layers)
      collection.respond_to?(:folders) ? collection.folders.find { |f| f.name == name } : nil
    end
    def tag_action(d)
      m = Sketchup.active_model
      case d['kind']
      when 'refresh'
      when 'visibility'
        if d['target'] == 'object'
          ent = find_entity(d['id'])
          m.start_operation('RM Object visibility', true)
          begin ent.hidden = !d['visible']; m.commit_operation
          rescue StandardError; m.abort_operation; raise; end
        elsif d['target'] == 'tag'
          layer = m.layers[d['id'].to_s]
          raise 'Tag nebyl nalezen.' unless layer
          layer.visible = !!d['visible']
        elsif d['target'] == 'folder'
          folder = folder_by_name(d['id'])
          raise 'Složka nebyla nalezena.' unless folder
          set_folder_visibility(folder, !!d['visible'])
        end
      when 'select', 'zoom'
        ent = find_entity(d['id'])
        # In edit contexts SketchUp cannot directly select a nested definition
        # member unless that context is open. Indicate this instead of choosing
        # a different object with the same name.
        parent = ent.parent
        if parent != m.active_entities
          notify(:tags, 'Vnořený objekt: otevři jeho nadřazenou komponentu a pak ho označ.')
        else
          m.selection.clear
          m.selection.add(ent)
          m.active_view.zoom(ent) if d['kind'] == 'zoom'
        end
      when 'replace'
        ent = find_entity(d['id'])
        raise 'Nahrazovat lze komponenty (ne skupiny).' unless ent.is_a?(Sketchup::ComponentInstance)
        @replacement = {model: m, id: ent.persistent_id, all: !!d['all']}
        require File.expand_path('../dvacet20_component_library/main', __dir__)
        install_library_replace_hook
        @dialogs[:tags].hide if @dialogs && @dialogs[:tags]
        Dvacet20::ComponentLibrary.show_dialog
        notify(:tags, 'V Model Library vyber model kliknutím na tlačítko vložení.')
        return
      else
        raise "Neznámá operace."
      end
      refresh(:tags)
    end
    def set_folder_visibility(folder, state)
      if folder.respond_to?(:visible=)
        folder.visible = state
      else
        folder.layers.each { |l| l.visible = state } if folder.respond_to?(:layers)
        folder.folders.each { |f| set_folder_visibility(f, state) } if folder.respond_to?(:folders)
      end
    end
    def install_library_replace_hook
      return if @library_hook
      owner = self
      patch = Module.new do
        define_method(:insert_component) do |path, dialog = @dialog|
          if owner.replacement_pending?
            owner.replace_from_library(path)
            dialog.execute_script('window.ComponentLibrary && ComponentLibrary.insertDone(' +
              JSON.generate(path) + ', true);') if dialog
          else
            super(path, dialog)
          end
        end
      end
      Dvacet20::ComponentLibrary.singleton_class.prepend(patch)
      @library_hook = true
    end
    def replacement_pending?
      !!@replacement
    end
    def replace_from_library(path)
      request = @replacement
      raise 'Nejdřív vyber komponentu v Tag Manageru.' unless request
      m = Sketchup.active_model
      raise 'V průběhu nahrazování se změnil model.' unless request[:model].equal?(m)
      root = File.expand_path(Dvacet20::ComponentLibrary.library_root)
      candidate = File.expand_path(path.to_s)
      raise 'Model musí pocházet z Model Library.' unless candidate.start_with?(root + File::SEPARATOR)
      raise 'Soubor SKP neexistuje.' unless File.file?(candidate) && File.extname(candidate).downcase == '.skp'
      old = find_entity(request[:id])
      raise 'Původní objekt už není komponenta.' unless old.is_a?(Sketchup::ComponentInstance)
      wrapper = m.definitions.load(candidate)
      roots = Dvacet20::ComponentLibrary.placement_roots(wrapper)
      raise 'Náhrada musí obsahovat právě jednu hlavní komponentu.' unless roots.length == 1
      data = roots.first
      definition = data[:definition]
      raise 'Neplatná definice modelu.' unless definition
      targets = request[:all] ? old.definition.instances.select(&:valid?) : [old]
      # Definition swap keeps each instance's transformation, tag, hidden state,
      # and instance-level metadata. No geometry deletion or placement click.
      m.start_operation('RM Replace Component', true)
      begin
        targets.each { |inst| inst.definition = definition }
        m.commit_operation
        @replacement = nil
        notify(:tags, "Nahrazeno komponent: #{targets.length}. Původní pozice a tag zachovány.")
        @dialogs[:tags].show if @dialogs && @dialogs[:tags]
        library_dialog = Dvacet20::ComponentLibrary.instance_variable_get(:@dialog)
        UI.start_timer(0.2, false) do
          library_dialog.close if library_dialog
          @dialogs[:tags].bring_to_front if @dialogs && @dialogs[:tags]
        end
        refresh(:tags)
      rescue StandardError
        m.abort_operation
        raise
      end
      true
    end

    def scene_data
      m = Sketchup.active_model
      selected = m.pages.selected_page
      {scenes: m.pages.map { |p|
        cam = p.camera
        {name: p.name, selected: p == selected,
         focal: (cam.respond_to?(:focal_length) ? cam.focal_length.to_f.round(1) : 0),
         ratio: p.get_attribute('20-20 RM SCENES', 'ratio', ''),
         perspective: cam.perspective?,
         shadows: p.respond_to?(:use_shadow_info?) ? p.use_shadow_info? : nil}
      }}
    end
    def page_by_name(name)
      Sketchup.active_model.pages.find { |p| p.name == name.to_s }
    end
    def scene_action(d)
      model = Sketchup.active_model
      name = d['name'].to_s
      page = page_by_name(name)
      case d['kind']
      when 'refresh'
      when 'activate'
        raise 'Scéna nenalezena.' unless page
        model.pages.selected_page = page
      when 'create'
        name = name.strip
        raise 'Zadej název scény.' if name.empty?
        raise 'Scéna s tímto názvem již existuje.' if page
        page = model.pages.add(name)
        page.update
      when 'update'
        raise 'Scéna nenalezena.' unless page
        # page.update captures current viewport; selecting the saved page first
        # would discard the user's current camera before updating.
        page.update
      when 'rename'
        raise 'Scéna nenalezena.' unless page
        next_name = d['new_name'].to_s.strip
        raise 'Neplatný nový název.' if next_name.empty? || page_by_name(next_name)
        page.name = next_name
      when 'delete'
        raise 'Scéna nenalezena.' unless page
        model.pages.erase(page)
      when 'camera'
        raise 'Scéna nenalezena.' unless page
        model.pages.selected_page = page
        camera = model.active_view.camera
        focal = d['focal'].to_f
        ratio = d['ratio'].to_s
        ratios = {'16:9'=>16.0/9, '4:3'=>4.0/3, '3:2'=>1.5, '1:1'=>1.0, '9:16'=>9.0/16}
        raise 'Neplatné ohnisko (10–200 mm).' unless focal.between?(10, 200)
        raise 'Neplatný poměr stran.' unless ratios.key?(ratio)
        camera.perspective = true unless camera.perspective?
        camera.focal_length = focal
        camera.aspect_ratio = ratios[ratio]
        page.set_attribute('20-20 RM SCENES', 'ratio', ratio)
        page.update
      else
        raise 'Neznámá operace scén.'
      end
      refresh(:scenes)
    end
    def html(which)
      is_tags = which == :tags
      <<~HTML
      <!doctype html><html lang="cs"><head><meta charset="utf-8">
      <style>
      :root{color-scheme:dark;--bg:#101215;--p:#191d23;--line:#343941;--muted:#9ca5af;--yellow:#ffd52a}
      *{box-sizing:border-box}body{margin:0;color:white;background:var(--bg);font:13px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
      header{display:flex;gap:16px;align-items:center;padding:17px 22px;border-bottom:1px solid var(--line)}
      h2{margin:0;font-size:18px}.small{color:var(--muted);font-size:11px}.back{background:var(--yellow);color:#151515;font-weight:800}
      button{cursor:pointer;border-radius:8px;border:1px solid var(--line);padding:8px 11px;color:#eee;background:#2b3037;font:inherit}
      button:hover{border-color:var(--yellow)}button.primary{background:var(--yellow);color:#111;font-weight:800}
      .layout{display:grid;grid-template-columns:minmax(280px,1fr) minmax(300px,1fr);min-height:calc(100vh - 75px)}
      aside,main{padding:18px;min-width:0}aside{border-right:1px solid var(--line)}
      input,select{background:#22272e;border:1px solid var(--line);color:white;border-radius:8px;padding:9px;width:100%}
      .entry{display:flex;gap:6px;align-items:center;min-height:33px;border-radius:6px;padding:2px 5px}
      .entry:hover,.entry.active{background:#313641}.entry span{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;cursor:pointer}
      .eye{border:0;padding:3px 7px;background:transparent;color:var(--yellow);font-size:16px}
      .children{margin-left:19px;border-left:1px solid #323944;padding-left:7px}
      .card{border:1px solid var(--line);background:var(--p);border-radius:12px;padding:15px;margin:10px 0}
      .line{display:flex;justify-content:space-between;gap:10px;border-bottom:1px solid #2a3038;padding:9px 0;overflow-wrap:anywhere}
      .line strong{text-align:right}.buttons{display:flex;gap:8px;flex-wrap:wrap;margin-top:12px}
      .note{margin-top:8px;font-size:11px;color:var(--muted);line-height:1.6}#message{color:var(--yellow);min-height:20px;padding:8px 0}
      @media(max-width:740px){.layout{grid-template-columns:1fr}aside{border-right:0;border-bottom:1px solid var(--line)}}
      </style></head><body>
      <header><button class="back" onclick="sketchup.back()">← RM TOOLS</button>
        <div><h2>#{is_tags ? 'TAG MANAGER' : 'SCENE MANAGER'}</h2><div class="small">20-20 · správa modelu pro render</div></div>
        <button onclick="Manager.act({kind:'refresh'})">↻ Obnovit</button></header>
      <div class="layout"><aside>
      <input id="search" placeholder="#{is_tags ? 'Hledat tag nebo komponentu…' : 'Hledat scénu…'}" oninput="Manager.draw()" />
      <div id="tree"></div></aside>
      <main><div id="details" class="card"><div class="small">Vyber položku vlevo.</div></div>
      <div id="message"></div></main></div>
      <script>
      (function(){
      const TAG_MODE = #{is_tags ? 'true' : 'false'};
      let data={}, selected=null, expanded={};
      const el=id=>document.getElementById(id);
      const esc=s=>String(s==null?'':s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
      const send=d=>sketchup.action(JSON.stringify(d));
      const eye=(target,id,visible)=>'<button class="eye" title="Viditelnost" onclick="event.stopPropagation();Manager.act({kind:\\'visibility\\',target:\\''+target+'\\',id:'+JSON.stringify(id)+',visible:'+(!visible)+'})">'+(visible?'◉':'○')+'</button>';
      const selectedObject=o=>{selected={type:'object',item:o};draw();send({kind:'select',id:o.id});};
      function objects(tag,query){
        const list=(data.objects||{})[tag]||[];
        return list.filter(o=>!query||((o.name+' '+o.definition).toLowerCase().includes(query)));
      }
      function folder(f,depth,query){
        const folderItems=[...(f.tags||[])], children=(f.children||[]);
        let content='';
        for(const sub of children)content+=folder(sub,depth+1,query);
        for(const t of folderItems)content+=tag(t,depth+1,query);
        if(query&&!f.name.toLowerCase().includes(query)&&!content)return '';
        const open=expanded[f.id]||!!query;
        return '<div class="entry" style="padding-left:'+depth*10+'px"><button onclick="Manager.toggle('+JSON.stringify(f.id)+')">'+(open?'▾':'▸')+'</button><span onclick="Manager.toggle('+JSON.stringify(f.id)+')">▣ '+esc(f.name)+'</span>'+eye('folder',f.name,f.visible)+'</div>'+(open?'<div class="children">'+content+'</div>':'');
      }
      function tag(t,depth,query){
        const rows=objects(t.name,query);
        if(query&&!t.name.toLowerCase().includes(query)&&!rows.length)return '';
        const open=expanded[t.id]||!!query;
        let out='<div class="entry" style="padding-left:'+depth*10+'px"><button onclick="Manager.toggle('+JSON.stringify(t.id)+')">'+(open?'▾':'▸')+'</button><span onclick="Manager.toggle('+JSON.stringify(t.id)+')">▤ '+esc(t.name)+' ('+((data.objects||{})[t.name]||[]).length+')</span>'+eye('tag',t.name,t.visible)+'</div>';
        if(open)out+='<div class="children">'+rows.map(o=>'<div class="entry '+(selected&&selected.type==='object'&&selected.item.id===o.id?'active':'')+'" style="padding-left:'+((depth+1)*8)+'px"><span onclick="Manager.pick('+o.id+')">⬡ '+esc(o.name||o.definition)+'</span>'+eye('object',o.id,!o.hidden)+'</div>').join('')+'</div>';
        return out;
      }
      function draw(){
        const q=el('search').value.trim().toLowerCase();
        if(TAG_MODE){
          el('tree').innerHTML=(data.folders||[]).map(f=>folder(f,0,q)).join('')+(data.root_tags||[]).map(t=>tag(t,0,q)).join('');
        } else {
          el('tree').innerHTML=(data.scenes||[]).filter(s=>s.name.toLowerCase().includes(q)).map(s=>
            '<div class="entry '+(s.selected?'active':'')+'"><span onclick="Manager.pickScene('+JSON.stringify(s.name)+')">◈ '+esc(s.name)+'</span></div>').join('');
        }
        details();
      }
      function line(k,v){return '<div class="line"><span class="small">'+esc(k)+'</span><strong>'+esc(v)+'</strong></div>';}
      function details(){
        const box=el('details');
        if(TAG_MODE){
          if(!selected||selected.type!=='object'){box.innerHTML='<h2>TAG MANAGER</h2><p class="note">Rozbal tag, vyber komponentu a zobraz její definici a materiály. Oko umožňuje vypínat jednotlivé objekty, tagy i složky.</p>';return;}
          const o=Object.values(data.objects||{}).flat().find(x=>x.id===selected.item.id);
          if(!o){selected=null;details();return;}selected.item=o;
          box.innerHTML='<h2>'+esc(o.name)+'</h2>'+line('Typ',o.kind)+line('Definice',o.definition)+line('Tag',o.tag)+
            line('Materiály',(o.materials||[]).join(', ')||'Žádné na první úrovni')+line('Vnořeno',o.path.length?'Ano':'Ne')+
            '<div class="buttons"><button onclick="Manager.act({kind:\\'select\\',id:'+o.id+'})">Označit v modelu</button>'+
            '<button onclick="Manager.act({kind:\\'zoom\\',id:'+o.id+'})">Zaměřit</button>'+
            (o.kind==='Component'?'<button class="primary" onclick="Manager.act({kind:\\'replace\\',id:'+o.id+',all:false})">Nahradit z Model Library</button>'+
            '<button onclick="Manager.act({kind:\\'replace\\',id:'+o.id+',all:true})">Nahradit všechny stejné</button>':'')+'</div>'+
            '<p class="note">Náhrada zachovává instanční transformaci a tag. Model musí obsahovat jednu hlavní komponentu.</p>';
        }else{
          if(!selected){box.innerHTML='<h2>SCENE MANAGER</h2><p class="note">Klikni na scénu vlevo nebo založ novou.</p><input id="newscene" placeholder="Název nové scény"/><div class="buttons"><button class="primary" onclick="Manager.act({kind:\\'create\\',name:document.getElementById(\\'newscene\\').value})">+ Vytvořit scénu</button></div>';return;}
          const s=(data.scenes||[]).find(x=>x.name===selected.item.name);
          if(!s){selected=null;details();return;}selected.item=s;
          box.innerHTML='<h2>'+esc(s.name)+'</h2>'+line('Ohnisko',s.focal+' mm')+line('Poměr stran',s.ratio||'Dle aktuální kamery')+
            line('Promítání',s.perspective?'Perspektiva':'Rovnoběžné')+
            '<div class="buttons"><button onclick="Manager.act({kind:\\'activate\\',name:'+JSON.stringify(s.name)+'})">Aktivovat</button>'+
            '<button onclick="Manager.act({kind:\\'update\\',name:'+JSON.stringify(s.name)+'})">Aktualizovat z aktuálního pohledu</button></div>'+
            '<div class="line"><span>Ohnisko</span><input id="focal" type="number" min="10" max="200" value="'+s.focal+'" /></div>'+
            '<div class="line"><span>Poměr stran</span><select id="ratio">'+['16:9','4:3','3:2','1:1','9:16'].map(r=>'<option '+(r===s.ratio?'selected':'')+'>'+r+'</option>').join('')+'</select></div>'+
            '<div class="buttons"><button class="primary" onclick="Manager.act({kind:\\'camera\\',name:'+JSON.stringify(s.name)+',focal:document.getElementById(\\'focal\\').value,ratio:document.getElementById(\\'ratio\\').value})">Uložit kameru</button></div>'+
            '<div class="line"><input id="rename" value="'+esc(s.name)+'"/><button onclick="Manager.act({kind:\\'rename\\',name:'+JSON.stringify(s.name)+',new_name:document.getElementById(\\'rename\\').value})">Přejmenovat</button></div>'+
            '<button onclick="if(confirm(\\'Smazat scénu?\\'))Manager.act({kind:\\'delete\\',name:'+JSON.stringify(s.name)+'})">Smazat scénu</button>'+
            '<hr/><input id="newscene" placeholder="Nová scéna"/><button onclick="Manager.act({kind:\\'create\\',name:document.getElementById(\\'newscene\\').value})">+ Vytvořit další</button>';
        }
      }
      window.Manager={
        receive(d){data=d;draw();},notice(s){el('message').textContent=s;},
        act(d){send(d);},
        toggle(id){expanded[id]=!expanded[id];draw();},
        pick(id){const o=Object.values(data.objects||{}).flat().find(x=>x.id===id);if(o)selectedObject(o);},
        pickScene(name){const s=(data.scenes||[]).find(x=>x.name===name);if(s){selected={type:'scene',item:s};draw();send({kind:'activate',name});}},
        draw
      };
      document.addEventListener('DOMContentLoaded',()=>sketchup.ready());
      })();
      </script></body></html>
      HTML
    end
  end
end