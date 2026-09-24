# frozen_string_literal: true

require 'json'
require 'securerandom'

module TwentyTwenty
  module ModelLibrary
    extend self

    VERSION = '0.2.0'.freeze
    DICT = 'twentytwenty_model_library'.freeze
    DIALOG_PREF = 'twentytwenty_model_library_v020'.freeze

    ASSETS = {
      'switch_single' => {
        name: 'Vypínač', category: 'Elektro', icon: '▣', placement: 'wall',
        width_mm: 80.0, height_mm: 80.0, depth_mm: 12.0,
        axis_height_mm: 1050.0, horizontal_offset_mm: 150.0,
        modules: [:switch]
      },
      'switch_double' => {
        name: 'Dvojvypínač', category: 'Elektro', icon: '▦', placement: 'wall',
        width_mm: 80.0, height_mm: 80.0, depth_mm: 12.0,
        axis_height_mm: 1050.0, horizontal_offset_mm: 150.0,
        modules: [:switch_double]
      },
      'socket_single' => {
        name: 'Zásuvka', category: 'Elektro', icon: '◉', placement: 'wall',
        width_mm: 80.0, height_mm: 80.0, depth_mm: 12.0,
        axis_height_mm: 300.0, horizontal_offset_mm: 150.0,
        modules: [:socket]
      },
      'socket_double' => {
        name: 'Dvojzásuvka', category: 'Elektro', icon: '◉◉', placement: 'wall',
        width_mm: 151.0, height_mm: 80.0, depth_mm: 12.0,
        axis_height_mm: 300.0, horizontal_offset_mm: 150.0,
        modules: [:socket, :socket]
      },
      'socket_switch' => {
        name: 'Zásuvka + vypínač', category: 'Elektro', icon: '◉▣', placement: 'wall',
        width_mm: 151.0, height_mm: 80.0, depth_mm: 12.0,
        axis_height_mm: 1050.0, horizontal_offset_mm: 150.0,
        modules: [:socket, :switch]
      },

      'tree_deciduous' => {
        name: 'Listnatý strom 2D', category: 'Vegetace', icon: '♣', placement: 'billboard',
        width_mm: 3600.0, height_mm: 6200.0, color: [86, 128, 72],
        scale_min: 0.90, scale_max: 1.10, shape: :tree_round
      },
      'tree_conifer' => {
        name: 'Jehličnan 2D', category: 'Vegetace', icon: '▲', placement: 'billboard',
        width_mm: 3000.0, height_mm: 7000.0, color: [55, 104, 67],
        scale_min: 0.90, scale_max: 1.10, shape: :tree_conifer
      },
      'shrub_round' => {
        name: 'Keř 2D', category: 'Vegetace', icon: '●', placement: 'billboard',
        width_mm: 1800.0, height_mm: 1200.0, color: [77, 122, 66],
        scale_min: 0.85, scale_max: 1.15, shape: :shrub
      },
      'tall_grass' => {
        name: 'Vysoká tráva 2D', category: 'Vegetace', icon: '≋', placement: 'billboard',
        width_mm: 1300.0, height_mm: 1100.0, color: [111, 137, 70],
        scale_min: 0.85, scale_max: 1.20, shape: :grass
      },

      'window_wall' => {
        name: 'Parametrické okno', category: 'Okna', icon: '▢', placement: 'hosted',
        host: 'wall', object_kind: 'window',
        width_mm: 1200.0, height_mm: 1200.0, sill_mm: 900.0,
        frame_mm: 80.0, depth_mm: 110.0
      },
      'roof_window' => {
        name: 'Střešní okno · VELUX-ready', category: 'Okna', icon: '◇', placement: 'hosted',
        host: 'roof', object_kind: 'roof_window',
        width_mm: 780.0, height_mm: 1180.0, sill_mm: 0.0,
        frame_mm: 70.0, depth_mm: 90.0,
        presets: ['550x780','660x1180','780x1180','780x1400','1140x1180']
      },
      'door_single' => {
        name: 'Jednokřídlé dveře', category: 'Dveře', icon: '▯', placement: 'hosted',
        host: 'wall', object_kind: 'door',
        width_mm: 900.0, height_mm: 2100.0, sill_mm: 0.0,
        frame_mm: 80.0, depth_mm: 120.0
      },
      'door_double' => {
        name: 'Dvoukřídlé dveře', category: 'Dveře', icon: '▯▯', placement: 'hosted',
        host: 'wall', object_kind: 'door_double',
        width_mm: 1600.0, height_mm: 2100.0, sill_mm: 0.0,
        frame_mm: 80.0, depth_mm: 120.0
      }
    }.freeze

    def init
      return if @loaded
      @loaded = true
      create_commands
      create_menu
      create_toolbar
    end

    def create_commands
      @cmd_open = UI::Command.new('20-20 Model Library') { show_dialog }
      @cmd_open.tooltip = '20-20 Model Library – 2D vegetace, elektro a parametrické stavební objekty'
      @cmd_open.status_bar_text = 'Otevře knihovnu 20-20 s parametrickými okny/dveřmi a automatickým cut-opening.'
      icon = File.join(__dir__, 'icons', 'library.png')
      if File.exist?(icon)
        @cmd_open.small_icon = icon
        @cmd_open.large_icon = icon
      end
    end

    def create_menu
      UI.menu('Extensions').add_item(@cmd_open)
      UI.menu('Tools').add_item(@cmd_open)
    end

    def create_toolbar
      @toolbar = UI::Toolbar.new('20-20 Model Library')
      @toolbar.add_item(@cmd_open)
      @toolbar.restore
    rescue StandardError
      nil
    end

    def show_dialog
      @dialog = build_dialog if @dialog.nil?
      @dialog.show
      @dialog.bring_to_front
    rescue StandardError
      @dialog = nil
      retry
    end

    def build_dialog
      dlg = UI::HtmlDialog.new(
        dialog_title: "20-20 Model Library v#{VERSION}",
        preferences_key: DIALOG_PREF,
        scrollable: true,
        resizable: true,
        width: 840,
        height: 740,
        min_width: 680,
        min_height: 560,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      dlg.set_html(dialog_html)
      dlg.add_action_callback('place_asset') { |_ctx, payload| place_asset_from_dialog(payload) }
      dlg.add_action_callback('update_selected') { |_ctx, payload| update_selected_from_dialog(payload) }
      dlg.add_action_callback('close_dialog') do |_ctx|
        @dialog = nil if @dialog.equal?(dlg)
        dlg.close
      end
      dlg.set_on_closed { @dialog = nil if @dialog.equal?(dlg) }
      dlg
    end

    def serializable_assets
      ASSETS.transform_values do |v|
        v.each_with_object({}) do |(k, value), memo|
          next if k == :modules
          memo[k] = value.is_a?(Symbol) ? value.to_s : value
        end
      end
    end

    def dialog_html
      assets_json = JSON.generate(serializable_assets)
      <<~HTML
        <!doctype html>
        <html lang="cs"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        :root{--bg:#f5f5f5;--card:#fff;--line:#dedede;--text:#171717;--muted:#737373;--yellow:#f7f197}
        *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:13px system-ui,Segoe UI,sans-serif}
        .head{background:var(--yellow);border-bottom:1px solid #dad36d;padding:14px 18px;display:flex;justify-content:space-between;align-items:center}
        .head b{font-size:17px}.wrap{padding:16px}.tabs{display:flex;gap:8px;margin-bottom:14px;flex-wrap:wrap}
        .tab{border:1px solid var(--line);background:#fff;border-radius:8px;padding:8px 11px;cursor:pointer}.tab.active{background:#171717;color:#fff;border-color:#171717}
        .grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}
        .asset{border:1px solid var(--line);background:#fff;border-radius:12px;padding:13px;text-align:left;cursor:pointer;min-height:104px}
        .asset:hover{border-color:#aaa}.asset.active{outline:2px solid #171717}.ico{font-size:26px;height:34px}.name{font-weight:700;margin-top:6px}.meta{font-size:11px;color:var(--muted);margin-top:4px}
        .panel{margin-top:14px;border:1px solid var(--line);background:#fff;border-radius:12px;padding:14px}.panel h3{margin:0 0 10px;font-size:14px}
        .row{display:grid;grid-template-columns:1fr 1fr;gap:10px}.field{display:flex;flex-direction:column;gap:5px;margin-bottom:9px}.field label{font-size:11px;color:#555}
        .field input,.field select{border:1px solid var(--line);border-radius:7px;padding:8px;background:#fff;width:100%}
        .help{font-size:11px;color:var(--muted);line-height:1.45;padding:10px;background:#fafafa;border-radius:8px;margin-top:5px}
        .actions{display:flex;gap:8px;margin-top:13px;flex-wrap:wrap}.primary{background:#171717;color:#fff;border:1px solid #171717;border-radius:8px;padding:9px 13px;cursor:pointer}
        .secondary{background:#fff;border:1px solid var(--line);border-radius:8px;padding:9px 13px;cursor:pointer}.hidden{display:none}
        .beta{font-size:10px;border:1px solid #d4cc5d;border-radius:999px;padding:2px 6px;margin-left:6px;background:#fffce0}
        @media(max-width:720px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}.row{grid-template-columns:1fr}}
        </style></head><body>
        <div class="head"><div><b>20-20 MODEL LIBRARY <span class="beta">PARAMETRIC BETA</span></b><div style="font-size:11px;margin-top:2px">elektro · 2D vegetace · okna · dveře</div></div><button class="secondary" onclick="sketchup.close_dialog()">Zavřít</button></div>
        <div class="wrap">
          <div class="tabs">
            <button class="tab active" data-cat="Elektro">Elektro</button>
            <button class="tab" data-cat="Vegetace">Vegetace</button>
            <button class="tab" data-cat="Okna">Okna</button>
            <button class="tab" data-cat="Dveře">Dveře</button>
          </div>
          <div id="grid" class="grid"></div>

          <div id="panel" class="panel hidden">
            <h3 id="selectedName">Vybraný objekt</h3>

            <div id="wallFields" class="hidden">
              <div class="row">
                <div class="field"><label>Horizontální odsazení od referenčního bodu [mm]</label><input id="hoff" type="number" step="1"></div>
                <div class="field"><label>Osová výška [mm]</label><input id="axis" type="number" step="1"></div>
              </div>
              <div class="row">
                <div class="field"><label>Odsazení od stěny [mm]</label><input id="depthOffset" type="number" step="1" value="0"></div>
                <div class="field"><label>Směr</label><select id="dir"><option value="right">doprava</option><option value="left">doleva</option></select></div>
              </div>
              <div class="help">Elektro zůstává stejné jako dřív: nejdřív stěna, potom referenční bod.</div>
            </div>

            <div id="plantFields" class="hidden">
              <div class="row">
                <div class="field"><label>Měřítko min. [%]</label><input id="scaleMin" type="number" value="90"></div>
                <div class="field"><label>Měřítko max. [%]</label><input id="scaleMax" type="number" value="110"></div>
              </div>
              <div class="help">Vegetace je nyní čistý 2D billboard/cutout a automaticky se natáčí ke kameře. Žádné 3D koruny ani kužely.</div>
            </div>

            <div id="hostedFields" class="hidden">
              <div id="presetWrap" class="field hidden"><label>Rychlá velikost</label><select id="preset" onchange="applyPreset()"></select></div>
              <div class="row">
                <div class="field"><label>Šířka [mm]</label><input id="objWidth" type="number" min="100" step="10"></div>
                <div class="field"><label>Výška [mm]</label><input id="objHeight" type="number" min="100" step="10"></div>
              </div>
              <div class="row">
                <div id="sillWrap" class="field"><label>Výška parapetu / odsazení od reference [mm]</label><input id="objSill" type="number" min="0" step="10"></div>
                <div class="field"><label>Šířka rámu [mm]</label><input id="objFrame" type="number" min="20" step="5"></div>
              </div>
              <div class="field"><label>Hloubka rámu [mm]</label><input id="objDepth" type="number" min="20" step="5"></div>
              <div id="hostedHelp" class="help"></div>
              <div class="help"><b>Parametrické:</b> objekt se uloží s vlastními parametry. Vyber už vložený 20-20 objekt, nastav nové hodnoty a klikni na „Použít na vybraný“.</div>
            </div>

            <div class="actions">
              <button class="primary" onclick="place()">Vložit do modelu</button>
              <button id="updateBtn" class="secondary hidden" onclick="updateSelected()">Použít na vybraný objekt</button>
            </div>
          </div>
        </div>

        <script>
        const assets=#{assets_json};
        let cat='Elektro',selected=null;
        const grid=document.getElementById('grid');

        document.querySelectorAll('.tab').forEach(function(b){
          b.onclick=function(){
            document.querySelectorAll('.tab').forEach(function(x){x.classList.remove('active')});
            b.classList.add('active');cat=b.dataset.cat;selected=null;render();document.getElementById('panel').classList.add('hidden');
          };
        });

        function placementLabel(a){
          if(a.placement==='wall') return 'na stěnu';
          if(a.placement==='billboard') return '2D cutout';
          if(a.host==='roof') return 'do střechy · parametrické';
          return 'do stěny · parametrické';
        }

        function render(){
          grid.innerHTML='';
          Object.entries(assets).filter(function(pair){return pair[1].category===cat}).forEach(function(pair){
            const id=pair[0],a=pair[1],el=document.createElement('button');
            el.className='asset'+(selected===id?' active':'');
            el.innerHTML='<div class="ico">'+a.icon+'</div><div class="name">'+a.name+'</div><div class="meta">'+placementLabel(a)+'</div>';
            el.onclick=function(){selectAsset(id)};
            grid.appendChild(el);
          });
        }

        function selectAsset(id){
          selected=id;const a=assets[id];render();
          document.getElementById('panel').classList.remove('hidden');
          document.getElementById('selectedName').textContent=a.name;
          const isWall=a.placement==='wall',isPlant=a.placement==='billboard',isHosted=a.placement==='hosted';
          document.getElementById('wallFields').classList.toggle('hidden',!isWall);
          document.getElementById('plantFields').classList.toggle('hidden',!isPlant);
          document.getElementById('hostedFields').classList.toggle('hidden',!isHosted);
          document.getElementById('updateBtn').classList.toggle('hidden',!isHosted);

          if(isWall){
            document.getElementById('hoff').value=a.horizontal_offset_mm||0;
            document.getElementById('axis').value=a.axis_height_mm||0;
            document.getElementById('depthOffset').value=0;
          }
          if(isPlant){
            document.getElementById('scaleMin').value=Math.round((a.scale_min||1)*100);
            document.getElementById('scaleMax').value=Math.round((a.scale_max||1)*100);
          }
          if(isHosted){
            document.getElementById('objWidth').value=a.width_mm||900;
            document.getElementById('objHeight').value=a.height_mm||1200;
            document.getElementById('objSill').value=a.sill_mm||0;
            document.getElementById('objFrame').value=a.frame_mm||70;
            document.getElementById('objDepth').value=a.depth_mm||100;
            document.getElementById('sillWrap').classList.toggle('hidden',a.host==='roof');
            const p=document.getElementById('preset'),pw=document.getElementById('presetWrap');
            p.innerHTML='';
            if(a.presets&&a.presets.length){
              pw.classList.remove('hidden');
              a.presets.forEach(function(v){const o=document.createElement('option');o.value=v;o.textContent=v.replace('x',' × ')+' mm';p.appendChild(o)});
              const current=String(a.width_mm)+'x'+String(a.height_mm);if(a.presets.includes(current))p.value=current;
            }else{pw.classList.add('hidden')}
            document.getElementById('hostedHelp').textContent=
              a.host==='roof'
              ? 'Klikni na šikmou střešní plochu v místě středu okna. Objekt se přilepí ke střeše a použije SketchUp Cut Opening.'
              : '1) Klikni na stěnu. 2) Klikni na referenční bod u podlahy pod středem objektu. Plugin dopočítá výšku a vloží objekt s Cut Opening.';
          }
        }

        function applyPreset(){
          const v=document.getElementById('preset').value.split('x');if(v.length!==2)return;
          document.getElementById('objWidth').value=parseFloat(v[0])||780;
          document.getElementById('objHeight').value=parseFloat(v[1])||1180;
        }

        function payload(){
          if(!selected)return null;const a=assets[selected],p={id:selected};
          if(a.placement==='wall'){
            p.horizontal_offset_mm=parseFloat(document.getElementById('hoff').value)||0;
            p.axis_height_mm=parseFloat(document.getElementById('axis').value)||0;
            p.depth_offset_mm=parseFloat(document.getElementById('depthOffset').value)||0;
            p.direction=document.getElementById('dir').value;
          }else if(a.placement==='billboard'){
            p.scale_min=(parseFloat(document.getElementById('scaleMin').value)||100)/100;
            p.scale_max=(parseFloat(document.getElementById('scaleMax').value)||100)/100;
          }else{
            p.width_mm=parseFloat(document.getElementById('objWidth').value)||a.width_mm;
            p.height_mm=parseFloat(document.getElementById('objHeight').value)||a.height_mm;
            p.sill_mm=parseFloat(document.getElementById('objSill').value)||0;
            p.frame_mm=parseFloat(document.getElementById('objFrame').value)||a.frame_mm;
            p.depth_mm=parseFloat(document.getElementById('objDepth').value)||a.depth_mm;
          }
          return p;
        }

        function place(){const p=payload();if(p)sketchup.place_asset(JSON.stringify(p))}
        function updateSelected(){const p=payload();if(p)sketchup.update_selected(JSON.stringify(p))}
        render();
        </script></body></html>
      HTML
    end

    def place_asset_from_dialog(payload)
      data = JSON.parse(payload.to_s)
      asset = ASSETS[data['id']]
      return UI.messagebox('Neznámý model.') unless asset

      old_dialog = @dialog
      @dialog = nil
      old_dialog.close if old_dialog

      case asset[:placement]
      when 'wall'
        Sketchup.active_model.select_tool(WallPlacementTool.new(data['id'], asset, data))
      when 'billboard'
        Sketchup.active_model.select_tool(GroundPlacementTool.new(data['id'], asset, data))
      when 'hosted'
        Sketchup.active_model.select_tool(HostedPlacementTool.new(data['id'], asset, normalize_hosted_params(asset, data)))
      end
    rescue StandardError => e
      UI.messagebox("Model Library: #{e.class}: #{e.message}")
    end

    def update_selected_from_dialog(payload)
      data = JSON.parse(payload.to_s)
      asset_id = data['id'].to_s
      asset = ASSETS[asset_id]
      return UI.messagebox('Tento typ objektu není parametrický.') unless asset && asset[:placement] == 'hosted'

      model = Sketchup.active_model
      inst = model.selection.grep(Sketchup::ComponentInstance).find { |x| x.get_attribute(DICT, 'parametric', false) }
      return UI.messagebox('Vyber jeden parametrický 20-20 objekt v modelu.') unless inst
      return UI.messagebox('Vybraný objekt je jiný typ. V knihovně otevři jeho odpovídající položku.') unless inst.get_attribute(DICT, 'asset_id').to_s == asset_id

      params = normalize_hosted_params(asset, data)
      model.start_operation('20-20 upravit parametrický objekt', true)

      inst.make_unique if inst.definition.instances.length > 1
      entities = inst.definition.entities
      entities.erase_entities(entities.to_a) unless entities.empty?
      build_hosted_geometry(entities, asset, params)
      configure_hosted_behavior(inst.definition, asset)

      ref = array_to_point(inst.get_attribute(DICT, 'reference_point'))
      x_axis = array_to_vector(inst.get_attribute(DICT, 'x_axis'))
      y_axis = array_to_vector(inst.get_attribute(DICT, 'y_axis'))
      normal = array_to_vector(inst.get_attribute(DICT, 'normal'))
      if ref && x_axis && y_axis && normal
        origin = hosted_origin(ref, y_axis, asset, params)
        inst.transformation = Geom::Transformation.axes(origin, x_axis, y_axis, normal)
      end

      store_parametric_attributes(inst, asset_id, asset, params)
      model.commit_operation
      model.active_view.invalidate
      UI.messagebox('Parametrický objekt aktualizován.')
    rescue StandardError => e
      model.abort_operation rescue nil
      UI.messagebox("Úprava objektu selhala: #{e.class}: #{e.message}")
    end

    def normalize_hosted_params(asset, data)
      {
        width_mm: [[data.fetch('width_mm', asset[:width_mm]).to_f, 100.0].max, 10000.0].min,
        height_mm: [[data.fetch('height_mm', asset[:height_mm]).to_f, 100.0].max, 10000.0].min,
        sill_mm: [data.fetch('sill_mm', asset[:sill_mm] || 0).to_f, 0.0].max,
        frame_mm: [[data.fetch('frame_mm', asset[:frame_mm] || 70).to_f, 20.0].max, 400.0].min,
        depth_mm: [[data.fetch('depth_mm', asset[:depth_mm] || 100).to_f, 20.0].max, 1000.0].min
      }
    end

    def mm(value)
      value.to_f.mm
    end

    def point_to_array(point)
      [point.x.to_f, point.y.to_f, point.z.to_f]
    end

    def vector_to_array(vector)
      [vector.x.to_f, vector.y.to_f, vector.z.to_f]
    end

    def array_to_point(value)
      return nil unless value.respond_to?(:length) && value.length == 3
      Geom::Point3d.new(value[0].to_f, value[1].to_f, value[2].to_f)
    end

    def array_to_vector(value)
      return nil unless value.respond_to?(:length) && value.length == 3
      v = Geom::Vector3d.new(value[0].to_f, value[1].to_f, value[2].to_f)
      return nil if v.length < 1e-9
      v.normalize!
      v
    end

    def definition_for(asset_id, asset)
      model = Sketchup.active_model
      name = "20-20_LIB_#{asset_id}_v020"
      found = model.definitions[name]
      return found if found

      definition = model.definitions.add(name)
      build_asset_geometry(definition.entities, asset)

      if asset[:placement] == 'billboard'
        definition.behavior.always_face_camera = true
        definition.behavior.shadows_face_sun = true
      end

      definition.set_attribute(DICT, 'asset_id', asset_id)
      definition.set_attribute(DICT, 'placement', asset[:placement])
      definition
    end

    def build_asset_geometry(entities, asset)
      case asset[:placement]
      when 'wall'
        build_wall_asset(entities, asset)
      when 'billboard'
        build_billboard(entities, asset)
      end
    end

    def material(name, color, alpha = 1.0)
      mats = Sketchup.active_model.materials
      mat = mats[name] || mats.add(name)
      mat.color = Sketchup::Color.new(*color)
      mat.alpha = alpha
      mat
    end

    def build_wall_asset(entities, asset)
      w = mm(asset[:width_mm]); h = mm(asset[:height_mm]); d = mm(asset[:depth_mm])
      x0 = -w / 2.0; z0 = -h / 2.0
      face = entities.add_face([x0,0,z0],[x0+w,0,z0],[x0+w,0,z0+h],[x0,0,z0+h])
      face.reverse! if face.normal.y < 0
      face.pushpull(d)
      body_mat = material('20-20 Elektro White', [238,238,235])
      entities.grep(Sketchup::Face).each { |f| f.material = body_mat }

      modules = asset[:modules]
      spacing = 71.mm
      start_x = -((modules.length - 1) * spacing) / 2.0
      modules.each_with_index do |kind, i|
        cx = start_x + i * spacing
        case kind
        when :socket
          add_socket_symbol(entities, cx, d + 0.5.mm, 0)
        when :switch
          add_switch_symbol(entities, cx, d + 0.5.mm, 0, false)
        when :switch_double
          add_switch_symbol(entities, cx, d + 0.5.mm, 0, true)
        end
      end
    end

    def add_socket_symbol(entities, cx, y, cz)
      r = 21.mm
      circle = entities.add_circle([cx,y,cz], [0,1,0], r, 32)
      f = entities.add_face(circle)
      f.material = material('20-20 Elektro Insert', [60,60,60]) if f
      2.times do |i|
        dx = i.zero? ? -7.mm : 7.mm
        c = entities.add_circle([cx+dx,y+0.3.mm,cz], [0,1,0], 2.0.mm, 12)
        hf = entities.add_face(c)
        hf.material = Sketchup::Color.new(15,15,15) if hf
      end
    end

    def add_switch_symbol(entities, cx, y, cz, double)
      ww = 42.mm; hh = 42.mm
      if double
        [-11.mm,11.mm].each do |dx|
          f = entities.add_face([cx+dx-9.mm,y,cz-hh/2],[cx+dx+9.mm,y,cz-hh/2],[cx+dx+9.mm,y,cz+hh/2],[cx+dx-9.mm,y,cz+hh/2])
          f.material = Sketchup::Color.new(205,205,202) if f
        end
      else
        f = entities.add_face([cx-ww/2,y,cz-hh/2],[cx+ww/2,y,cz-hh/2],[cx+ww/2,y,cz+hh/2],[cx-ww/2,y,cz+hh/2])
        f.material = Sketchup::Color.new(205,205,202) if f
      end
    end

    def build_billboard(entities, asset)
      w = mm(asset[:width_mm]); h = mm(asset[:height_mm])
      points = billboard_points(asset[:shape], w, h)
      face = entities.add_face(points)
      return unless face
      mat = material("20-20 Vegetace #{asset[:shape]}", asset[:color], 0.92)
      face.material = mat
      face.back_material = mat
      face.edges.each { |edge| edge.soft = true; edge.smooth = true }
    end

    def billboard_points(shape, w, h)
      x = w / 2.0
      case shape
      when :tree_round
        [
          [-x*0.10,0,0],[-x*0.11,0,h*0.28],[-x*0.48,0,h*0.38],[-x*0.80,0,h*0.55],
          [-x*0.65,0,h*0.78],[-x*0.30,0,h*0.94],[0,0,h],[x*0.34,0,h*0.92],
          [x*0.70,0,h*0.76],[x*0.82,0,h*0.54],[x*0.52,0,h*0.37],[x*0.11,0,h*0.28],[x*0.10,0,0]
        ]
      when :tree_conifer
        [
          [-x*0.10,0,0],[-x*0.10,0,h*0.17],[-x*0.70,0,h*0.30],[-x*0.38,0,h*0.42],
          [-x*0.82,0,h*0.47],[-x*0.42,0,h*0.60],[-x*0.67,0,h*0.66],[-x*0.27,0,h*0.78],
          [0,0,h],[x*0.27,0,h*0.78],[x*0.67,0,h*0.66],[x*0.42,0,h*0.60],
          [x*0.82,0,h*0.47],[x*0.38,0,h*0.42],[x*0.70,0,h*0.30],[x*0.10,0,h*0.17],[x*0.10,0,0]
        ]
      when :shrub
        [
          [-x,0,0],[-x*0.94,0,h*0.38],[-x*0.72,0,h*0.75],[-x*0.42,0,h*0.92],
          [0,0,h],[x*0.46,0,h*0.90],[x*0.78,0,h*0.68],[x,0,h*0.28],[x*0.92,0,0]
        ]
      else
        [
          [-x,0,0],[-x*0.88,0,h*0.55],[-x*0.68,0,h*0.15],[-x*0.52,0,h],
          [-x*0.34,0,h*0.18],[-x*0.12,0,h*0.78],[0,0,h*0.22],[x*0.18,0,h*0.93],
          [x*0.34,0,h*0.20],[x*0.55,0,h],[x*0.70,0,h*0.18],[x*0.90,0,h*0.62],[x,0,0]
        ]
      end.map { |p| Geom::Point3d.new(*p) }
    end

    def hosted_definition(asset_id, asset, params)
      model = Sketchup.active_model
      definition = model.definitions.add("20-20_PARAM_#{asset_id}_#{SecureRandom.hex(4)}")
      build_hosted_geometry(definition.entities, asset, params)
      configure_hosted_behavior(definition, asset)
      definition.set_attribute(DICT, 'asset_id', asset_id)
      definition.set_attribute(DICT, 'parametric', true)
      definition
    end

    def configure_hosted_behavior(definition, asset)
      behavior = definition.behavior
      behavior.is2d = true
      behavior.cuts_opening = true
      behavior.snapto = asset[:host] == 'roof' ? SnapTo_Sloped : SnapTo_Vertical
    end

    def build_hosted_geometry(entities, asset, params)
      w = mm(params[:width_mm]); h = mm(params[:height_mm]); f = mm(params[:frame_mm]); d = mm(params[:depth_mm])
      f = [f, [w,h].min * 0.35].min
      frame_mat = material('20-20 Param Frame', [224,224,220])
      dark_mat = material('20-20 Param Dark', [62,65,66])
      glass_mat = material('20-20 Param Glass', [150,185,198], 0.45)

      # Local convention for hosted objects:
      # X = horizontal in host plane, Y = vertical/up-slope in host plane, Z = out of host.
      x0 = -w/2.0; x1 = w/2.0; y0 = -h/2.0; y1 = h/2.0

      case asset[:object_kind]
      when 'door', 'door_double'
        box(entities, x0, y0, 0, x0+f, y1, d, frame_mat)
        box(entities, x1-f, y0, 0, x1, y1, d, frame_mat)
        box(entities, x0, y1-f, 0, x1, y1, d, frame_mat)
        leaf_depth = [d*0.25, 20.mm].max
        leaf = box(entities, x0+f, y0+f*0.15, d*0.35, x1-f, y1-f, d*0.35+leaf_depth, dark_mat)
        if asset[:object_kind] == 'door_double'
          entities.add_line([0,y0, d+1.mm], [0,y1-f, d+1.mm])
        end
        add_cut_loop(entities, x0, y0, x1, y1)
      else
        box(entities, x0, y0, 0, x0+f, y1, d, frame_mat)
        box(entities, x1-f, y0, 0, x1, y1, d, frame_mat)
        box(entities, x0+f, y0, 0, x1-f, y0+f, d, frame_mat)
        box(entities, x0+f, y1-f, 0, x1-f, y1, d, frame_mat)
        glass = entities.add_face([x0+f,y0+f,d*0.42],[x1-f,y0+f,d*0.42],[x1-f,y1-f,d*0.42],[x0+f,y1-f,d*0.42])
        if glass
          glass.material = glass_mat
          glass.back_material = glass_mat
        end
        add_cut_loop(entities, x0, y0, x1, y1)
      end
    end

    def add_cut_loop(entities, x0, y0, x1, y1)
      pts = [[x0,y0,0],[x1,y0,0],[x1,y1,0],[x0,y1,0],[x0,y0,0]]
      edges = entities.add_edges(pts)
      Array(edges).each { |edge| edge.hidden = true rescue nil }
    end

    def box(entities, x0, y0, z0, x1, y1, z1, mat)
      return if x1 <= x0 || y1 <= y0 || z1 <= z0
      face = entities.add_face([x0,y0,z0],[x1,y0,z0],[x1,y1,z0],[x0,y1,z0])
      return unless face
      face.reverse! if face.normal.z < 0
      face.pushpull(z1-z0)
      connected = face.all_connected.grep(Sketchup::Face)
      connected.each { |f| f.material = mat }
      face
    end

    def hosted_origin(reference, y_axis, asset, params)
      return reference if asset[:host] == 'roof'
      offset = if %w[door door_double].include?(asset[:object_kind])
                 params[:height_mm].to_f / 2.0
               else
                 params[:sill_mm].to_f + params[:height_mm].to_f / 2.0
               end
      reference.offset(y_axis, mm(offset))
    end

    def host_axes(face, reference, host)
      normal = face.normal.clone
      normal.normalize!
      eye_vec = Sketchup.active_model.active_view.camera.eye - reference
      normal.reverse! if normal.dot(eye_vec) < 0

      if host == 'wall'
        y_axis = Z_AXIS.clone
        x_axis = y_axis.cross(normal)
        return nil if x_axis.length < 1e-6
        x_axis.normalize!
        [x_axis, y_axis, normal]
      else
        x_axis = Z_AXIS.cross(normal)
        x_axis = X_AXIS.clone if x_axis.length < 1e-6
        x_axis.normalize!
        y_axis = normal.cross(x_axis)
        y_axis.normalize!
        [x_axis, y_axis, normal]
      end
    end

    def valid_host_face?(face, host)
      return false unless face
      n = face.normal.clone
      n.normalize!
      z = n.dot(Z_AXIS).abs
      host == 'wall' ? z < 0.20 : z >= 0.15
    end

    def store_parametric_attributes(inst, asset_id, asset, params, reference = nil, axes = nil, face = nil)
      inst.set_attribute(DICT, 'parametric', true)
      inst.set_attribute(DICT, 'asset_id', asset_id)
      inst.set_attribute(DICT, 'host', asset[:host])
      inst.set_attribute(DICT, 'object_kind', asset[:object_kind])
      params.each { |k,v| inst.set_attribute(DICT, k.to_s, v.to_f) }
      if reference && axes
        inst.set_attribute(DICT, 'reference_point', point_to_array(reference))
        inst.set_attribute(DICT, 'x_axis', vector_to_array(axes[0]))
        inst.set_attribute(DICT, 'y_axis', vector_to_array(axes[1]))
        inst.set_attribute(DICT, 'normal', vector_to_array(axes[2]))
      end
      inst.set_attribute(DICT, 'host_face_pid', face.persistent_id) if face && face.respond_to?(:persistent_id)
    end

    class WallPlacementTool
      def initialize(asset_id, asset, options)
        @asset_id, @asset, @options = asset_id, asset, options
        @state = 0
        @ip = Sketchup::InputPoint.new
        @face = nil
      end
      def activate
        Sketchup.status_text = '20-20 Model Library: klikni na cílovou stěnu.'
      end
      def onMouseMove(_flags,x,y,view); @ip.pick(view,x,y); view.invalidate; end
      def draw(view); @ip.draw(view) if @ip.valid?; end
      def onLButtonDown(_flags,x,y,view)
        @ip.pick(view,x,y)
        return unless @ip.valid?
        if @state == 0
          @face = @ip.face
          unless @face
            UI.beep; Sketchup.status_text='Musíš kliknout na plochu stěny.'; return
          end
          n = @face.normal
          if n.parallel?(Z_AXIS)
            UI.messagebox('Vybraná plocha vypadá jako podlaha/strop. Pro elektro vyber svislou stěnu.'); return
          end
          @state = 1
          Sketchup.status_text = 'Teď klikni na referenční bod na stejné stěně.'
        else
          place(@ip.position)
          Sketchup.active_model.select_tool(nil)
          TwentyTwenty::ModelLibrary.show_dialog
        end
      end
      def onCancel(_reason,_view); Sketchup.active_model.select_tool(nil); TwentyTwenty::ModelLibrary.show_dialog; end
      def place(ref)
        model = Sketchup.active_model
        model.start_operation('20-20 vložit elektro', true)
        n = @face.normal.clone; n.normalize!
        eye_vec = model.active_view.camera.eye - ref
        n.reverse! if n.dot(eye_vec) < 0
        z = Z_AXIS.clone
        horizontal = z.cross(n)
        horizontal = X_AXIS.clone if horizontal.length < 1e-6
        horizontal.normalize!
        sign = @options['direction'] == 'left' ? -1.0 : 1.0
        pos = ref.offset(horizontal, TwentyTwenty::ModelLibrary.mm(@options['horizontal_offset_mm']) * sign)
        pos = pos.offset(z, TwentyTwenty::ModelLibrary.mm(@options['axis_height_mm']))
        pos = pos.offset(n, TwentyTwenty::ModelLibrary.mm(@options['depth_offset_mm']))
        tr = Geom::Transformation.axes(pos, horizontal, n, z)
        definition = TwentyTwenty::ModelLibrary.definition_for(@asset_id, @asset)
        inst = model.active_entities.add_instance(definition, tr)
        inst.set_attribute(DICT, 'asset_id', @asset_id)
        model.commit_operation
      rescue StandardError => e
        model.abort_operation rescue nil
        UI.messagebox("Umístění selhalo: #{e.class}: #{e.message}")
      end
    end

    class GroundPlacementTool
      def initialize(asset_id, asset, options)
        @asset_id,@asset,@options=asset_id,asset,options
        @ip=Sketchup::InputPoint.new
      end
      def activate
        Sketchup.status_text='20-20 Model Library: klikni na terén / podlahu. Vegetace = 2D cutout.'
      end
      def onMouseMove(_flags,x,y,view); @ip.pick(view,x,y); view.invalidate; end
      def draw(view); @ip.draw(view) if @ip.valid?; end
      def onLButtonDown(_flags,x,y,view)
        @ip.pick(view,x,y); return unless @ip.valid?
        place(@ip.position)
        Sketchup.active_model.select_tool(nil)
        TwentyTwenty::ModelLibrary.show_dialog
      end
      def onCancel(_reason,_view); Sketchup.active_model.select_tool(nil); TwentyTwenty::ModelLibrary.show_dialog; end
      def place(point)
        model=Sketchup.active_model
        model.start_operation('20-20 vložit 2D vegetaci',true)
        tr=Geom::Transformation.translation(point)
        min=@options['scale_min'].to_f;max=@options['scale_max'].to_f
        min=@asset[:scale_min].to_f if min<=0
        max=@asset[:scale_max].to_f if max<=0
        max=min if max<min
        s=min+rand*(max-min)
        tr=tr*Geom::Transformation.scaling(ORIGIN,s)
        definition=TwentyTwenty::ModelLibrary.definition_for(@asset_id,@asset)
        inst=model.active_entities.add_instance(definition,tr)
        inst.set_attribute(DICT,'asset_id',@asset_id)
        inst.set_attribute(DICT,'billboard',true)
        model.commit_operation
      rescue StandardError=>e
        model.abort_operation rescue nil
        UI.messagebox("Umístění selhalo: #{e.class}: #{e.message}")
      end
    end

    class HostedPlacementTool
      def initialize(asset_id, asset, params)
        @asset_id, @asset, @params = asset_id, asset, params
        @state = 0
        @ip = Sketchup::InputPoint.new
        @face = nil
        @reference = nil
      end

      def activate
        if @asset[:host] == 'roof'
          Sketchup.status_text = '20-20: klikni na střešní plochu v místě středu okna.'
        else
          Sketchup.status_text = '20-20: klikni na cílovou stěnu.'
        end
      end

      def onMouseMove(_flags,x,y,view); @ip.pick(view,x,y); view.invalidate; end
      def draw(view); @ip.draw(view) if @ip.valid?; end

      def onLButtonDown(_flags,x,y,view)
        @ip.pick(view,x,y)
        return unless @ip.valid?

        if @state == 0
          @face = @ip.face
          unless TwentyTwenty::ModelLibrary.valid_host_face?(@face, @asset[:host])
            UI.beep
            UI.messagebox(@asset[:host] == 'roof' ? 'Vyber střešní / šikmou plochu.' : 'Vyber svislou stěnu.')
            return
          end

          if @asset[:host] == 'roof'
            @reference = @ip.position
            place
            finish
          else
            @state = 1
            Sketchup.status_text = 'Teď klikni na referenční bod u podlahy pod středem objektu.'
          end
        else
          @reference = @ip.position
          place
          finish
        end
      end

      def finish
        Sketchup.active_model.select_tool(nil)
        TwentyTwenty::ModelLibrary.show_dialog
      end

      def onCancel(_reason,_view); finish; end

      def place
        model = Sketchup.active_model
        axes = TwentyTwenty::ModelLibrary.host_axes(@face, @reference, @asset[:host])
        return UI.messagebox('Nepodařilo se určit osy hostitelské plochy.') unless axes

        origin = TwentyTwenty::ModelLibrary.hosted_origin(@reference, axes[1], @asset, @params)
        tr = Geom::Transformation.axes(origin, axes[0], axes[1], axes[2])

        model.start_operation('20-20 vložit parametrický objekt', true)
        definition = TwentyTwenty::ModelLibrary.hosted_definition(@asset_id, @asset, @params)
        inst = model.active_entities.add_instance(definition, tr)

        glued = false
        begin
          inst.glued_to = @face
          glued = true
        rescue StandardError
          glued = false
        end

        TwentyTwenty::ModelLibrary.store_parametric_attributes(inst, @asset_id, @asset, @params, @reference, axes, @face)
        inst.set_attribute(DICT, 'opening_mode', glued ? 'SketchUp Cut Opening' : 'visual_only')
        model.commit_operation
        model.active_view.invalidate

        unless glued
          UI.messagebox('Objekt byl vložen, ale SketchUp ho nedovolil přilepit k této ploše. Automatické vyříznutí otvoru proto na této konkrétní ploše neproběhlo.')
        end
      rescue StandardError => e
        model.abort_operation rescue nil
        UI.messagebox("Vložení parametrického objektu selhalo: #{e.class}: #{e.message}")
      end
    end
  end
end

TwentyTwenty::ModelLibrary.init
