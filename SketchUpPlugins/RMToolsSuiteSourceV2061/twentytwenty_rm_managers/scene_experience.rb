# frozen_string_literal: true
require File.join(__dir__, 'scene_visuals')
require File.join(__dir__, 'floorplan')

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
          '<section class="rm-scene-sets"><label for="rmSetName">SADY SCÉN</label>' \
          '<div class="rm-create-row"><input id="rmSetName" aria-label="Název sady scén" placeholder="Varianta A"/>' \
          '<button id="rmSaveSet" type="button">Uložit sadu</button></div>' \
          '<div class="rm-create-row"><select id="rmSetSelect" aria-label="Uložené sady scén"></select>' \
          '<button class="primary" id="rmApplySet" type="button">Použít</button><button id="rmDeleteSet" type="button">Smazat</button></div></section>' \
          '<section class="rm-map-area"><div class="rm-map-title">PŮDORYS · KAMERY</div>' \
          '<div class="rm-map-help">Přejetím zobrazíš záběr. Podrž kameru 1,5 s a pak ji přetáhni na nové místo.</div>' \
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
        result[:scene_sets] = scene_sets(model).map { |set| {'name'=>set['name'].to_s,'count'=>Array(set['scenes']).length} }
        ground = model.bounds.valid? ? model.bounds.min.z : 0.to_l
        pages = model.pages.to_a
        result[:scenes].each_with_index do |data, index|
          page = pages[index]
          next unless page
          cam = page.camera
          data[:height_1800] = (cam.eye.z - ground - 1800.mm).abs < 50.mm
          data[:eye] = [cam.eye.x.to_f, cam.eye.y.to_f]
          data[:direction] = [cam.direction.x.to_f, cam.direction.y.to_f]
          up = cam.respond_to?(:up) ? cam.up : nil
          data[:up] = up ? [up.x.to_f, up.y.to_f] : [0.0, 1.0]
          data[:preview] = SceneVisuals.preview_base64(model, page)
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
          'ratio'=>page.get_attribute(SCENE_DICT,'ratio','').to_s
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
            set_aspect_ratio_fixed(cam, row['aspect_ratio'].to_f) if row['aspect_ratio']
            page.use_camera = true if page.respond_to?(:use_camera=)
            page.set_attribute(SCENE_DICT,'ratio',row['ratio'].to_s)
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
        # Selecting the page applies its camera. Reassigning page.camera back
        # into View#camera is redundant and can trigger a second camera solve.
        view.invalidate
      ensure
        opts['ShowTransition'] = previous if opts && !previous.nil?
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
            page.use_camera = true if page.respond_to?(:use_camera=)
            if model.pages.selected_page == page
              active = view.camera
              active.set(eye, target, active.up)
              view.invalidate
            end
            model.commit_operation
          rescue StandardError
            model.abort_operation
            raise
          end
          SceneVisuals.clear(model,page)
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
            set_aspect_ratio_fixed(camera, ratio == 'off' ? 0.0 : RATIOS.fetch(ratio))
          else
            ground = model.bounds.valid? ? model.bounds.min.z : 0.to_l
            height = ground + 1800.mm
            shift = height - camera.eye.z
            camera.set(Geom::Point3d.new(camera.eye.x,camera.eye.y,height),
                       Geom::Point3d.new(camera.target.x,camera.target.y,camera.target.z+shift),camera.up)
          end
          # Lens, frame and height setters mutate the active Camera in place.
          # Reassigning it to View#camera can make SketchUp recalculate/dolly it.
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
            set_aspect_ratio_fixed(saved, keep_ratio)
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
            set_aspect_ratio_fixed(camera, RATIOS.fetch(chosen))
          end
          # Keep the same active Camera object; focal/ratio edits are in-place.
          view.invalidate
          rm_save_scene(model, page)
          refresh(:scenes)
        when 'lens'
          camera = view.camera
          set_focal_35(camera, d['mm'])
          view.invalidate
          js(:scenes, 'currentState', camera_info(camera))
        when 'frame'
          chosen = d['ratio'].to_s
          raise 'Neplatný poměr stran.' unless RATIOS.key?(chosen) || chosen == 'off'
          camera = view.camera
          set_aspect_ratio_fixed(camera, chosen == 'off' ? 0.0 : RATIOS.fetch(chosen))
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
