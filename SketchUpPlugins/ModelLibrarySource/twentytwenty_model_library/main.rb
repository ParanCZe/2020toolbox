# frozen_string_literal: true

require 'json'

module TwentyTwenty
  module ModelLibrary
    extend self

    VERSION = '0.1.1'.freeze
    DICT = 'twentytwenty_model_library'.freeze
    DIALOG_PREF = 'twentytwenty_model_library_v011'.freeze

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
        name: 'Listnatý strom', category: 'Stromy', icon: '♣', placement: 'ground',
        width_mm: 3200.0, height_mm: 6000.0, depth_mm: 3200.0,
        random_rotation: true, random_scale_min: 0.9, random_scale_max: 1.1,
        modules: [:tree_deciduous]
      },
      'tree_conifer' => {
        name: 'Jehličnan', category: 'Stromy', icon: '▲', placement: 'ground',
        width_mm: 2600.0, height_mm: 6500.0, depth_mm: 2600.0,
        random_rotation: true, random_scale_min: 0.9, random_scale_max: 1.1,
        modules: [:tree_conifer]
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
      @cmd_open.tooltip = '20-20 Model Library – chytrá knihovna modelů'
      @cmd_open.status_bar_text = 'Otevře knihovnu modelů a nástroje pro chytré umístění.'
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
      # HtmlDialog objects cannot be reused reliably after close. Always rebuild
      # when the previous dialog has been destroyed.
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
        width: 760,
        height: 680,
        min_width: 620,
        min_height: 520,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      dlg.set_html(dialog_html)
      dlg.add_action_callback('place_asset') { |_ctx, payload| place_asset_from_dialog(payload) }
      dlg.add_action_callback('close_dialog') do |_ctx|
        @dialog = nil if @dialog.equal?(dlg)
        dlg.close
      end
      dlg.set_on_closed { @dialog = nil if @dialog.equal?(dlg) }
      dlg
    end

    def dialog_html
      assets_json = JSON.generate(ASSETS.transform_values { |v| v.reject { |k,_| k == :modules } })
      <<~HTML
        <!doctype html>
        <html lang="cs"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        :root{--bg:#f5f5f5;--card:#fff;--line:#dedede;--text:#171717;--muted:#737373;--yellow:#f7f197}
        *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:13px system-ui,Segoe UI,sans-serif}.head{background:var(--yellow);border-bottom:1px solid #dad36d;padding:14px 18px;display:flex;justify-content:space-between;align-items:center}.head b{font-size:17px}.wrap{padding:16px}.tabs{display:flex;gap:8px;margin-bottom:14px}.tab{border:1px solid var(--line);background:#fff;border-radius:8px;padding:8px 11px;cursor:pointer}.tab.active{background:#171717;color:#fff;border-color:#171717}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}.asset{border:1px solid var(--line);background:#fff;border-radius:12px;padding:13px;text-align:left;cursor:pointer;min-height:104px}.asset:hover{border-color:#aaa}.asset.active{outline:2px solid #171717}.ico{font-size:26px;height:34px}.name{font-weight:700;margin-top:6px}.meta{font-size:11px;color:var(--muted);margin-top:4px}.panel{margin-top:14px;border:1px solid var(--line);background:#fff;border-radius:12px;padding:14px}.panel h3{margin:0 0 10px;font-size:14px}.row{display:grid;grid-template-columns:1fr 1fr;gap:10px}.field{display:flex;flex-direction:column;gap:5px;margin-bottom:9px}.field label{font-size:11px;color:#555}.field input,.field select{border:1px solid var(--line);border-radius:7px;padding:8px;background:#fff}.help{font-size:11px;color:var(--muted);line-height:1.45;padding:10px;background:#fafafa;border-radius:8px;margin-top:5px}.actions{display:flex;gap:8px;margin-top:13px}.primary{background:#171717;color:#fff;border:1px solid #171717;border-radius:8px;padding:9px 13px;cursor:pointer}.secondary{background:#fff;border:1px solid var(--line);border-radius:8px;padding:9px 13px;cursor:pointer}.hidden{display:none}@media(max-width:680px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}.row{grid-template-columns:1fr}}
        </style></head><body>
        <div class="head"><div><b>20-20 MODEL LIBRARY</b><div style="font-size:11px;margin-top:2px">chytré vkládání podle typu objektu</div></div><button class="secondary" onclick="sketchup.close_dialog()">Zavřít</button></div>
        <div class="wrap">
          <div class="tabs"><button class="tab active" data-cat="Elektro">Elektro</button><button class="tab" data-cat="Stromy">Stromy</button></div>
          <div id="grid" class="grid"></div>
          <div id="panel" class="panel hidden">
            <h3 id="selectedName">Vybraný model</h3>
            <div id="wallFields">
              <div class="row"><div class="field"><label>Horizontální odsazení od referenčního bodu [mm]</label><input id="hoff" type="number" step="1"></div><div class="field"><label>Osová výška nad referenčním bodem [mm]</label><input id="axis" type="number" step="1"></div></div>
              <div class="row"><div class="field"><label>Odsazení od stěny [mm]</label><input id="depth" type="number" step="1" value="0"></div><div class="field"><label>Směr horizontálního odsazení</label><select id="dir"><option value="right">doprava</option><option value="left">doleva</option></select></div></div>
              <div class="help">Po kliknutí na Vložit: 1) klikni na cílovou stěnu, 2) klikni na referenční bod na stěně (typicky roh, hranu dveří nebo bod u podlahy). Plugin vezme tento bod jako výchozí a přičte horizontální odsazení + osovou výšku.</div>
            </div>
            <div id="groundFields" class="hidden">
              <div class="row"><div class="field"><label><input id="randRot" type="checkbox" checked> náhodná rotace</label></div><div class="field"><label>Náhodné měřítko [%]</label><div style="display:flex;gap:6px"><input id="scaleMin" type="number" value="90" style="width:50%"><input id="scaleMax" type="number" value="110" style="width:50%"></div></div></div>
              <div class="help">Klikni na terén. Vkládací bod je přesně střed základny kmene. Strom zůstane svisle podle světové osy Z.</div>
            </div>
            <div class="actions"><button class="primary" onclick="place()">Vložit do modelu</button></div>
          </div>
        </div>
        <script>
        const assets=#{assets_json};let cat='Elektro',selected=null;
        const grid=document.getElementById('grid');
        document.querySelectorAll('.tab').forEach(b=>b.onclick=()=>{document.querySelectorAll('.tab').forEach(x=>x.classList.remove('active'));b.classList.add('active');cat=b.dataset.cat;selected=null;render();document.getElementById('panel').classList.add('hidden')});
        function render(){grid.innerHTML='';Object.entries(assets).filter(([id,a])=>a.category===cat).forEach(([id,a])=>{const el=document.createElement('button');el.className='asset'+(selected===id?' active':'');el.innerHTML=`<div class="ico">${a.icon}</div><div class="name">${a.name}</div><div class="meta">${a.placement==='wall'?'na stěnu':'na terén'}</div>`;el.onclick=()=>selectAsset(id);grid.appendChild(el)})}
        function selectAsset(id){selected=id;const a=assets[id];render();document.getElementById('panel').classList.remove('hidden');document.getElementById('selectedName').textContent=a.name;const wall=a.placement==='wall';document.getElementById('wallFields').classList.toggle('hidden',!wall);document.getElementById('groundFields').classList.toggle('hidden',wall);if(wall){document.getElementById('hoff').value=a.horizontal_offset_mm||0;document.getElementById('axis').value=a.axis_height_mm||0;document.getElementById('depth').value=0}else{document.getElementById('randRot').checked=a.random_rotation!==false;document.getElementById('scaleMin').value=Math.round((a.random_scale_min||1)*100);document.getElementById('scaleMax').value=Math.round((a.random_scale_max||1)*100)}}
        function place(){if(!selected)return;const a=assets[selected];const payload={id:selected};if(a.placement==='wall'){payload.horizontal_offset_mm=parseFloat(document.getElementById('hoff').value)||0;payload.axis_height_mm=parseFloat(document.getElementById('axis').value)||0;payload.depth_offset_mm=parseFloat(document.getElementById('depth').value)||0;payload.direction=document.getElementById('dir').value}else{payload.random_rotation=document.getElementById('randRot').checked;payload.scale_min=(parseFloat(document.getElementById('scaleMin').value)||100)/100;payload.scale_max=(parseFloat(document.getElementById('scaleMax').value)||100)/100}sketchup.place_asset(JSON.stringify(payload))}
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
      if asset[:placement] == 'wall'
        Sketchup.active_model.select_tool(WallPlacementTool.new(data['id'], asset, data))
      else
        Sketchup.active_model.select_tool(GroundPlacementTool.new(data['id'], asset, data))
      end
    rescue StandardError => e
      UI.messagebox("Model Library: #{e.class}: #{e.message}")
    end

    def mm(value)
      value.to_f.mm
    end

    def definition_for(asset_id, asset)
      model = Sketchup.active_model
      name = "20-20_LIB_#{asset_id}_v010"
      found = model.definitions[name]
      return found if found
      definition = model.definitions.add(name)
      build_asset_geometry(definition.entities, asset)
      definition.set_attribute(DICT, 'asset_id', asset_id)
      definition.set_attribute(DICT, 'placement', asset[:placement])
      definition
    end

    def build_asset_geometry(entities, asset)
      if asset[:placement] == 'wall'
        build_wall_asset(entities, asset)
      elsif asset[:modules].include?(:tree_conifer)
        build_conifer(entities, asset)
      else
        build_deciduous_tree(entities, asset)
      end
    end

    def build_wall_asset(entities, asset)
      w = mm(asset[:width_mm]); h = mm(asset[:height_mm]); d = mm(asset[:depth_mm])
      # Local convention: X = horizontal, Y = away from wall, Z = vertical. Origin = visual center on wall plane.
      x0 = -w / 2.0; z0 = -h / 2.0
      face = entities.add_face([x0,0,z0],[x0+w,0,z0],[x0+w,0,z0+h],[x0,0,z0+h])
      face.reverse! if face.normal.y < 0
      face.pushpull(d)
      body_mat = Sketchup.active_model.materials['20-20 Elektro White'] || Sketchup.active_model.materials.add('20-20 Elektro White')
      body_mat.color = Sketchup::Color.new(238,238,235)
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
      if f
        mat = Sketchup.active_model.materials['20-20 Elektro Insert'] || Sketchup.active_model.materials.add('20-20 Elektro Insert')
        mat.color = Sketchup::Color.new(60,60,60)
        f.material = mat
      end
      2.times do |i|
        dx = (i.zero? ? -7.mm : 7.mm)
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

    def build_deciduous_tree(entities, asset)
      h = mm(asset[:height_mm]); crown = mm(asset[:width_mm]); trunk_h = h * 0.38; trunk_r = [crown * 0.055, 120.mm].max
      trunk_mat = Sketchup.active_model.materials['20-20 Tree Trunk'] || Sketchup.active_model.materials.add('20-20 Tree Trunk'); trunk_mat.color = Sketchup::Color.new(111,82,56)
      leaf_mat = Sketchup.active_model.materials['20-20 Tree Leaves'] || Sketchup.active_model.materials.add('20-20 Tree Leaves'); leaf_mat.color = Sketchup::Color.new(89,132,72)
      circ = entities.add_circle([0,0,0],[0,0,1],trunk_r,16); f=entities.add_face(circ); f.material=trunk_mat if f; f.pushpull(trunk_h) if f
      centers = [[0,0,trunk_h + crown*0.22],[crown*0.18,0,trunk_h+crown*0.13],[-crown*0.17,crown*0.08,trunk_h+crown*0.15],[0,-crown*0.15,trunk_h+crown*0.19]]
      centers.each_with_index do |c,i|
        r = crown * (i.zero? ? 0.34 : 0.27)
        add_icosphereish(entities, c, r, leaf_mat)
      end
    end

    def build_conifer(entities, asset)
      h = mm(asset[:height_mm]); crown = mm(asset[:width_mm]); trunk_r = [crown * 0.04, 90.mm].max
      trunk_mat = Sketchup.active_model.materials['20-20 Tree Trunk'] || Sketchup.active_model.materials.add('20-20 Tree Trunk'); trunk_mat.color = Sketchup::Color.new(111,82,56)
      leaf_mat = Sketchup.active_model.materials['20-20 Conifer'] || Sketchup.active_model.materials.add('20-20 Conifer'); leaf_mat.color = Sketchup::Color.new(52,105,67)
      circ=entities.add_circle([0,0,0],[0,0,1],trunk_r,14); f=entities.add_face(circ); f.material=trunk_mat if f; f.pushpull(h*0.2) if f
      [[0.18,0.42],[0.34,0.34],[0.50,0.27],[0.65,0.19]].each do |zfrac,rfrac|
        z = h*zfrac; r = crown*rfrac
        base = entities.add_circle([0,0,z],[0,0,1],r,20)
        bf = entities.add_face(base); next unless bf
        apex = [0,0,[z+h*0.33,h*0.98].min]
        pts = base.map(&:start).map(&:position)
        bf.erase!
        pts.each_with_index do |p,idx|
          q=pts[(idx+1)%pts.length]
          tf=entities.add_face(p,q,apex); tf.material=leaf_mat if tf
        end
      end
    end

    def add_icosphereish(entities, center, r, mat)
      cx,cy,cz=center
      rings = [
        [cz-r*0.75, r*0.55],
        [cz-r*0.25, r*0.92],
        [cz+r*0.25, r],
        [cz+r*0.70, r*0.52]
      ]
      ring_pts = rings.map do |z,rr|
        (0...16).map { |i| a=2*Math::PI*i/16.0; Geom::Point3d.new(cx+Math.cos(a)*rr,cy+Math.sin(a)*rr,z) }
      end
      bottom=Geom::Point3d.new(cx,cy,cz-r); top=Geom::Point3d.new(cx,cy,cz+r)
      ring_pts[0].each_with_index { |p,i| f=entities.add_face(bottom,p,ring_pts[0][(i+1)%16]); f.material=mat if f }
      (0...ring_pts.length-1).each do |ri|
        16.times do |i|
          a=ring_pts[ri][i]; b=ring_pts[ri][(i+1)%16]; c=ring_pts[ri+1][(i+1)%16]; d=ring_pts[ri+1][i]
          f=entities.add_face(a,b,c,d); f.material=mat if f
        end
      end
      ring_pts[-1].each_with_index { |p,i| f=entities.add_face(p,top,ring_pts[-1][(i+1)%16]); f.material=mat if f }
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
      def onMouseMove(_flags,x,y,view)
        @ip.pick(view,x,y); view.invalidate
      end
      def draw(view)
        @ip.draw(view) if @ip.valid?
      end
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
          Sketchup.status_text = 'Teď klikni na referenční bod na stejné stěně (roh / hrana dveří / bod u podlahy).'
        else
          ref = @ip.position
          place(ref)
          Sketchup.active_model.select_tool(nil)
          TwentyTwenty::ModelLibrary.show_dialog
        end
      end
      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
        TwentyTwenty::ModelLibrary.show_dialog
      end
      def place(ref)
        model = Sketchup.active_model
        model.start_operation('20-20 vložit elektro', true)
        n = @face.normal.clone
        n.normalize!
        # Ensure normal points toward current camera where possible, so device is on visible side.
        eye_vec = model.active_view.camera.eye - ref
        n.reverse! if n.dot(eye_vec) < 0
        z = Z_AXIS.clone
        horizontal = z.cross(n)
        if horizontal.length < 1e-6
          horizontal = X_AXIS.clone
        else
          horizontal.normalize!
        end
        sign = @options['direction'] == 'left' ? -1.0 : 1.0
        pos = ref.offset(horizontal, TwentyTwenty::ModelLibrary.mm(@options['horizontal_offset_mm']) * sign)
        pos = pos.offset(z, TwentyTwenty::ModelLibrary.mm(@options['axis_height_mm']))
        pos = pos.offset(n, TwentyTwenty::ModelLibrary.mm(@options['depth_offset_mm']))
        # Local X -> horizontal, local Y -> face normal, local Z -> world Z.
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
        Sketchup.status_text='20-20 Model Library: klikni na terén / podlahu. Bod = střed základny objektu.'
      end
      def onMouseMove(_flags,x,y,view);@ip.pick(view,x,y);view.invalidate;end
      def draw(view);@ip.draw(view) if @ip.valid?;end
      def onLButtonDown(_flags,x,y,view)
        @ip.pick(view,x,y);return unless @ip.valid?;place(@ip.position);Sketchup.active_model.select_tool(nil);TwentyTwenty::ModelLibrary.show_dialog
      end
      def onCancel(_reason,_view);Sketchup.active_model.select_tool(nil);TwentyTwenty::ModelLibrary.show_dialog;end
      def place(point)
        model=Sketchup.active_model;model.start_operation('20-20 vložit objekt',true)
        tr=Geom::Transformation.translation(point)
        if @options['random_rotation']
          a=rand*Math::PI*2.0;tr=tr*Geom::Transformation.rotation(ORIGIN,Z_AXIS,a)
        end
        min=@options['scale_min'].to_f;max=@options['scale_max'].to_f;min=1.0 if min<=0;max=min if max<min
        s=min+rand*(max-min);tr=tr*Geom::Transformation.scaling(ORIGIN,s)
        definition=TwentyTwenty::ModelLibrary.definition_for(@asset_id,@asset)
        inst=model.active_entities.add_instance(definition,tr);inst.set_attribute(DICT,'asset_id',@asset_id)
        model.commit_operation
      rescue StandardError=>e
        model.abort_operation rescue nil;UI.messagebox("Umístění selhalo: #{e.class}: #{e.message}")
      end
    end
  end
end

TwentyTwenty::ModelLibrary.init
