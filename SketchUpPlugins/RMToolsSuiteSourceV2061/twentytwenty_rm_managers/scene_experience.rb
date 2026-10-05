# frozen_string_literal: true
require File.join(__dir__, 'scene_visuals')
require File.join(__dir__, 'floorplan')
require File.join(__dir__, 'street_view')

module TwentyTwenty
  module RMManagers
    module SceneExperience
      def html(which)
        original = super
        return original unless which == :scenes
        css = File.read(File.join(__dir__, 'scene_ui.css'), encoding: 'UTF-8')
        js = File.read(File.join(__dir__, 'scene_ui.js'), encoding: 'UTF-8')
        original = original.sub('</style>', css + "\n</style>")
        original = original.sub('<div id="tree"></div></aside>',
          '<section class="rm-scene-create"><label for="rmCreateName">NOVÁ SCÉNA</label>' \
          '<div class="rm-create-row"><input id="rmCreateName" aria-label="Název nové scény" placeholder="02 - EXTERIER - HLAVNI"/>' \
          '<button class="primary" id="rmCreateScene" type="button">+ Vytvořit scénu</button></div></section>' \
          '<section class="rm-map-area"><div class="rm-map-title">PŮDORYS · KAMERY</div>' \
          '<div class="rm-map-help">Geometrický řez +2 m, bez pohybu aktivní kamery. Přejetím zobrazíš záběr.</div>' \
          '<div id="rmMiniMap" class="rm-mini-map"></div><button class="rm-map-refresh" onclick="Manager.act({kind:\'rebuild_plan\'})">↻ Obnovit půdorys</button></section><div id="tree"></div></aside>')
        original.sub('</body>', "<script>\n#{js}\n</script></body>")
      end

      # Generate the vector plan independently. Opening Scene Manager never
      # touches SketchUp viewport or selected scene.
      def show(which)
        dialog = super
        if which == :scenes && Floorplan.needs_rebuild?(Sketchup.active_model)
          model = Sketchup.active_model
          UI.start_timer(0.2,false) do
            if Sketchup.active_model.equal?(model)
              ok,error = Floorplan.build(model)
              notify(:scenes,ok ? 'Půdorys připraven bez změny kamery.' : "Půdorys: #{error}")
              refresh(:scenes)
            end
          end
        end
        dialog
      end

      def scene_data
        result = super
        model = Sketchup.active_model
        result[:floorplan] = Floorplan.cached_data(model)
        result[:floorplan_error] = Floorplan.last_error(model)
        result[:street_api_key_set] = StreetView.configured?
        result[:scene_sets] = scene_sets(model).map { |set| {'name'=>set['name'].to_s,'count'=>Array(set['scenes']).length} }
        ground = model.bounds.valid? ? model.bounds.min.z : 0.to_l
        result[:scenes].each_with_index do |entry, index|
          entry[:height_1800] = (model.pages.to_a[index].camera.eye.z - ground - 1800.mm).abs < 50.mm
        end
        result[:scenes].each_with_index do |data, index|
          page = model.pages.to_a[index]
          cam = page.camera
          data[:eye] = [cam.eye.x.to_f, cam.eye.y.to_f]
          data[:direction] = [cam.direction.x.to_f, cam.direction.y.to_f]
          up = cam.respond_to?(:up) ? cam.up : nil
          data[:up] = up ? [up.x.to_f, up.y.to_f] : [0.0, 1.0]
          data[:preview] = SceneVisuals.preview_base64(model, page)
          data[:street_view] = StreetView.config(page)
        end
        result
      end

      SCENE_SET_DICT = '20-20 RM SCENE SETS'.freeze

      def scene_sets(model)
        return [] unless model.respond_to?(:get_attribute)
        raw = model.get_attribute(SCENE_SET_DICT, 'sets_json', '[]').to_s
        parsed = JSON.parse(raw)
        parsed.is_a?(Array) ? parsed : []
      rescue JSON::ParserError
        []
      end

      def write_scene_sets(model, sets)
        raise 'Model nepodporuje ukládání sad scén.' unless model.respond_to?(:set_attribute)
        model.set_attribute(SCENE_SET_DICT, 'sets_json', JSON.generate(sets))
      end

      def scene_set_snapshot(page)
        cam = page.camera
        {
          'name'=>page.name,
          'eye'=>[cam.eye.x.to_f,cam.eye.y.to_f,cam.eye.z.to_f],
          'target'=>[cam.target.x.to_f,cam.target.y.to_f,cam.target.z.to_f],
          'up'=>[cam.up.x.to_f,cam.up.y.to_f,cam.up.z.to_f],
          'perspective'=>cam.perspective?,
          'fov'=>cam.fov.to_f,
          'aspect_ratio'=>cam.aspect_ratio.to_f,
          'ratio'=>page.get_attribute(SCENE_DICT,'ratio','').to_s,
          'street_view'=>StreetView.config(page)
        }
      end

      def save_scene_set(model, name)
        clean = name.to_s.strip
        raise 'Zadej název sady scén.' if clean.empty?
        scenes = model.pages.to_a.map { |page| scene_set_snapshot(page) }
        raise 'V modelu není žádná scéna k uložení.' if scenes.empty?
        sets = scene_sets(model).reject { |set| set['name'].to_s.casecmp(clean).zero? }
        sets << {'name'=>clean,'scenes'=>scenes}
        write_scene_sets(model, sets)
        scenes.length
      end

      def restore_street_config(page, cfg)
        return unless cfg.is_a?(Hash)
        {
          'enabled'=>'enabled','source_url'=>'source_url','pano'=>'pano','location'=>'location',
          'heading'=>'heading','pitch'=>'pitch','fov'=>'fov','distance_m'=>'distance_m'
        }.each do |key, attr|
          value = cfg[key] || cfg[key.to_sym]
          page.set_attribute(StreetView::DICT, attr, value) unless value.nil?
        end
      end

      def apply_scene_set(model, name)
        set = scene_sets(model).find { |item| item['name'].to_s == name.to_s }
        raise 'Sada scén nebyla nalezena.' unless set
        rows = set['scenes']
        raise 'Sada neobsahuje žádné scény.' unless rows.is_a?(Array) && !rows.empty?
        model.start_operation('RM použít sadu scén', true)
        begin
          rows.each do |row|
            scene_name = row['name'].to_s
            next if scene_name.empty?
            page = page_by_name(scene_name) || model.pages.add(scene_name)
            cam = page.camera
            eye = Geom::Point3d.new(*row['eye'].map(&:to_f))
            target = Geom::Point3d.new(*row['target'].map(&:to_f))
            up = Geom::Vector3d.new(*row['up'].map(&:to_f))
            cam.set(eye,target,up)
            perspective = !!row['perspective']
            cam.perspective = perspective
            cam.fov = row['fov'].to_f if perspective && row['fov']
            cam.aspect_ratio = row['aspect_ratio'].to_f if row['aspect_ratio']
            page.use_camera = true
            page.set_attribute(SCENE_DICT,'ratio',row['ratio'].to_s)
            restore_street_config(page,row['street_view'])
            scene_id(page)
          end
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
        rows.length
      end

      # No visual scene-camera interpolation for RM button clicks.
      def rm_instant_scene(model, page)
        view = model.active_view
        opts = (model.options['PageOptions'] rescue nil)
        previous = nil
        begin
          previous = opts['ShowTransition'] if opts
          opts['ShowTransition'] = false if opts && !previous.nil?
        rescue StandardError
          opts = nil
        end
        model.pages.selected_page = page
        view.camera = page.camera
        view.invalidate
        rm_apply_street_view(model, page)
      ensure
        opts['ShowTransition'] = previous if opts && !previous.nil?
      end

      def rm_apply_street_view(model, page)
        if !StreetView.config(page)[:enabled]
          StreetView.clear(model)
          return
        end
        UI.start_timer(0.01, false) do
          begin
            if Sketchup.active_model.equal?(model) && model.pages.selected_page == page
              StreetView.apply(model, page)
              notify(:scenes, "Street View pozadí aktivní pro scénu #{page.name}.")
            end
          rescue StandardError => e
            StreetView.clear(model)
            notify(:scenes, "Street View: #{e.message}")
          end
        end
      end

      def rm_schedule_thumbnail(model, page)
        current = model.active_view.camera
        saved_eye = current.eye
        saved_dir = current.direction
        UI.start_timer(0.16, false) do
          begin
            if Sketchup.active_model.equal?(model)
              actual = model.active_view.camera
              if actual.eye.distance(saved_eye) < 0.01 &&
                 actual.direction.angle_between(saved_dir) < 0.0005
                if SceneVisuals.capture(model, page)
                  js(:scenes, 'updatePreview',
                    {id: scene_id(page), preview: SceneVisuals.preview_base64(model, page)})
                else
                  notify(:scenes, "Nepodařilo se vytvořit náhled scény #{page.name}.")
                end
              end
            end
          rescue StandardError => e
            puts "[RM SCENE] Náhled: #{e.class}: #{e.message}"
          end
        end
      end

      def rm_save_scene(model, page, ratio = nil)
        # Camera presets must not silently overwrite style, shadows or tag visibility.
        page.update(PAGE_USE_CAMERA)
        page.set_attribute(SCENE_DICT, 'ratio', ratio || ratio_name(model.active_view.camera))
        rm_schedule_thumbnail(model, page)
      end

      # Camera additions and viewpoint edits can expand the map automatically.
      # Defer past thumbnail capture so the two screenshot jobs never collide.
      def rm_plan_if_cameras_moved(model)
        return unless Floorplan.needs_rebuild?(model)
        UI.start_timer(0.4,false) do
          if Sketchup.active_model.equal?(model)
            ok,error = Floorplan.build(model)
            notify(:scenes,ok ? 'Mapa rozšířena podle kamer.' : "Mapa: #{error}")
            refresh(:scenes)
          end
        end
      end

      def scene_action(d)
        model = Sketchup.active_model
        kind = d['kind']
        name = d['name'].to_s
        page = page_from_action(d)
        view = model.active_view
        case kind
        when 'refresh'
          super
        when 'move_scene_marker'
          raise 'Scéna nebyla nalezena.' unless page
          x = Float(d['x'])
          y = Float(d['y'])
          raise 'Neplatná pozice kamery.' unless x.finite? && y.finite?
          cam = page.camera
          old_eye = cam.eye
          old_target = cam.target
          dx = x - old_eye.x.to_f
          dy = y - old_eye.y.to_f
          model.start_operation('RM přesun kamery na minimapě', true)
          begin
            eye = Geom::Point3d.new(x,y,old_eye.z)
            target = Geom::Point3d.new(old_target.x + dx,old_target.y + dy,old_target.z)
            cam.set(eye,target,cam.up)
            page.use_camera = true
            if model.pages.selected_page == page
              view.camera = cam
              view.invalidate
            end
            model.commit_operation
          rescue StandardError
            model.abort_operation
            raise
          end
          SceneVisuals.clear(model,page)
          rm_apply_street_view(model,page) if model.pages.selected_page == page
          refresh(:scenes)
          rm_plan_if_cameras_moved(model)
        when 'scene_set_save'
          count = save_scene_set(model,d['set_name'])
          notify(:scenes,"Sada #{d['set_name']} uložena (#{count} scén).")
          refresh(:scenes)
        when 'scene_set_apply'
          count = apply_scene_set(model,d['set_name'])
          notify(:scenes,"Sada #{d['set_name']} použita (#{count} scén).")
          refresh(:scenes)
          rm_plan_if_cameras_moved(model)
        when 'scene_set_delete'
          name_to_delete = d['set_name'].to_s
          sets = scene_sets(model)
          kept = sets.reject { |set| set['name'].to_s == name_to_delete }
          raise 'Sada scén nebyla nalezena.' if kept.length == sets.length
          write_scene_sets(model,kept)
          notify(:scenes,"Sada #{name_to_delete} smazána.")
          refresh(:scenes)
        when 'street_key'
          key = d['api_key'].to_s.strip
          raise 'API klíč je prázdný.' if key.empty?
          StreetView.api_key = key
          notify(:scenes, 'Google Maps API klíč uložen lokálně v nastavení SketchUpu.')
          refresh(:scenes)
        when 'street_open'
          raise 'Vyber scénu.' unless page
          cfg = StreetView.config(page)
          url = if cfg[:pano].to_s.empty? && cfg[:location].to_s.empty?
            'https://www.google.com/maps'
          else
            StreetView.maps_url(cfg)
          end
          UI.openURL(url)
        when 'street_apply'
          raise 'Vyber scénu.' unless page
          key = d['api_key'].to_s.strip
          StreetView.api_key = key unless key.empty?
          model.start_operation('RM Street View pozadí', true)
          begin
            StreetView.save_config(page, d)
            page.set_attribute(StreetView::DICT, 'enabled', true)
            model.commit_operation
          rescue StandardError
            model.abort_operation
            raise
          end
          rm_apply_street_view(model, page) if model.pages.selected_page == page
          refresh(:scenes)
        when 'street_toggle'
          raise 'Vyber scénu.' unless page
          enabled = !!d['enabled']
          if enabled
            cfg = StreetView.config(page)
            raise 'Nejdřív vlož Street View odkaz a klikni Použít.' if cfg[:pano].to_s.empty? && cfg[:location].to_s.empty?
          end
          page.set_attribute(StreetView::DICT, 'enabled', enabled)
          if model.pages.selected_page == page
            enabled ? rm_apply_street_view(model, page) : StreetView.clear(model)
          end
          refresh(:scenes)
        when 'street_remove'
          raise 'Vyber scénu.' unless page
          page.set_attribute(StreetView::DICT, 'enabled', false)
          StreetView.clear(model) if model.pages.selected_page == page
          refresh(:scenes)
        when 'rebuild_plan'
          notify(:scenes,'Počítám půdorys podle pozic kamer bez změny pohledu…')
          ok,error = Floorplan.build(model)
          notify(:scenes,ok ? 'Půdorys byl aktualizován.' : "Půdorys: #{error}")
          refresh(:scenes)
        when 'quick_lens', 'quick_ratio', 'quick_height'
          target = page || model.pages.selected_page
          raise 'Nejdříve vyber scénu ze seznamu.' unless target
          # Activate the saved scene only when the user edits ANOTHER scene.
          # Never reload the saved camera during subsequent preset clicks.
          rm_instant_scene(model, target) unless model.pages.selected_page == target
          camera = view.camera
          if kind == 'quick_lens'
            set_focal_35(camera, d['mm'])
          elsif kind == 'quick_ratio'
            ratio = d['ratio'].to_s
            raise 'Neplatný poměr stran.' unless RATIOS.key?(ratio) || ratio == 'off'
            camera.aspect_ratio = ratio == 'off' ? 0.0 : RATIOS.fetch(ratio)
          else
            ground = model.bounds.valid? ? model.bounds.min.z : 0.to_l
            height = ground + 1800.mm
            shift = height - camera.eye.z
            camera.set(Geom::Point3d.new(camera.eye.x,camera.eye.y,height),
                       Geom::Point3d.new(camera.target.x,camera.target.y,camera.target.z+shift),camera.up)
          end
          view.camera = camera
          view.invalidate
          rm_save_scene(model, target)
          # The refreshed thumbnail will arrive asynchronously when viewport repaints.
          refresh(:scenes)
        when 'quick_two_point'
          target = page || model.pages.selected_page
          raise 'Nejdříve vyber scénu ze seznamu.' unless target
          rm_instant_scene(model, target) unless model.pages.selected_page == target
          if view.camera.respond_to?(:is_2d?) && view.camera.is_2d?
            notify(:scenes, 'Dvoubodová perspektiva je už zapnutá.')
          else
            ok = Sketchup.send_action('viewTwoPointPerspective;')
            ok = Sketchup.send_action(10_627) if !ok && Sketchup.platform == :platform_win
            if ok
              UI.start_timer(0.4, false) do
                if Sketchup.active_model.equal?(model) && model.pages.selected_page == target
                  rm_save_scene(model, target)
                  refresh(:scenes)
                end
              end
            else
              notify(:scenes, 'Dvoubodovou perspektivu se nepodařilo zapnout.')
            end
          end
        when 'update_view'
          # A selected card is a stable scene ID. Do not silently update a
          # different active scene if that ID is missing or stale.
          raise 'Vyber scénu, kterou chceš aktualizovat.' unless page
          # Snapshot the current viewport camera directly into this exact
          # scene, without activating the page or assigning to view.camera.
          # Camera#set on a saved page can reorient the up vector / 2-point
          # state; SketchUp's PAGE_USE_CAMERA snapshot preserves the view.
          current = view.camera
          model.start_operation('RM aktualizovat polohu záběru', true)
          begin
            previous = page.camera
            keep_ratio = previous.aspect_ratio
            keep_fov = previous.fov if previous.perspective?
            keep_perspective = previous.perspective?
            ok = page.update(PAGE_USE_CAMERA)
            raise 'SketchUp neuložil aktuální pohled.' if ok == false
            saved = page.camera
            # Do not reset camera vectors after snapshot. Restore only the
            # stored lens and aspect (user-adjustable via the top presets).
            saved.perspective = keep_perspective if saved.perspective? != keep_perspective
            saved.fov = keep_fov if keep_perspective && keep_fov
            saved.aspect_ratio = keep_ratio
            page.use_camera = true
            model.commit_operation
            SceneVisuals.clear(model, page)
            notify(:scenes, "Poloha scény #{page.name} uložena. Ohnisko, poměr stran a pohled zůstaly beze změny; náhled se obnoví po aktivaci.")
            refresh(:scenes)
            rm_plan_if_cameras_moved(model)
          rescue StandardError
            model.abort_operation
            raise
          end
        when 'activate'
          raise 'Scéna nebyla nalezena.' unless page
          rm_instant_scene(model, page)
          rm_schedule_thumbnail(model, page) unless SceneVisuals.preview_base64(model, page)
          refresh(:scenes)
        when 'scene_ratio', 'scene_focal', 'camera'
          raise 'Scéna nebyla nalezena.' unless page
          # Avoid re-activating an already selected scene: this reset to the
          # previously SAVED camera made settings appear to need a second click.
          rm_instant_scene(model, page) unless model.pages.selected_page == page
          camera = view.camera
          if kind == 'scene_focal' || kind == 'camera'
            set_focal_35(camera, kind == 'camera' ? d['focal'] : d['focal'])
          end
          if kind == 'scene_ratio' || kind == 'camera'
            chosen = d['ratio'].to_s
            raise 'Neplatný poměr stran.' unless RATIOS.key?(chosen)
            camera.aspect_ratio = RATIOS.fetch(chosen)
          end
          view.camera = camera
          view.invalidate
          rm_save_scene(model, page)
          refresh(:scenes)
        when 'lens'
          camera = view.camera
          set_focal_35(camera, d['mm'])
          view.camera = camera
          view.invalidate
          js(:scenes, 'currentState', camera_info(camera))
        when 'frame'
          chosen = d['ratio'].to_s
          raise 'Neplatný poměr stran.' unless RATIOS.key?(chosen) || chosen == 'off'
          camera = view.camera
          camera.aspect_ratio = chosen == 'off' ? 0.0 : RATIOS.fetch(chosen)
          view.camera = camera
          view.invalidate
          js(:scenes, 'currentState', camera_info(camera))
        when 'create', 'update'
          super
          target = kind == 'create' ? page_by_name(name.strip) : page
          rm_schedule_thumbnail(model, target) if target
          rm_plan_if_cameras_moved(model)
        when 'delete'
          SceneVisuals.clear(model, page) if page
          super
        else
          super
        end
      end
    end
  end
end
