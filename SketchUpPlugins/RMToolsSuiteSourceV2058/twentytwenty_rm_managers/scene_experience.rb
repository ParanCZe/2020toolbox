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
          '<section class="rm-map-area"><div class="rm-map-title">PŮDORYS · KAMERY</div>' \
          '<div class="rm-map-help">Skutečný řez SketchUpu ve výšce 2 m. Přejetím na kameru zobrazíš její záběr.</div>' \
          '<div id="rmMiniMap" class="rm-mini-map"></div><button class="rm-map-refresh" onclick="Manager.act({kind:\'rebuild_plan\'})">↻ Obnovit půdorys</button></section><div id="tree"></div></aside>')
        original.sub('</body>', "<script>\n#{js}\n</script></body>")
      end

      def show(which)
        dialog = super
        if which == :scenes && !Floorplan.cached_data(Sketchup.active_model)
          UI.start_timer(0.7, false) do
            model = Sketchup.active_model
            begin
              Floorplan.build(model) do |ok, error|
                notify(:scenes, ok ? 'Půdorys byl vygenerován.' : "Automatický půdorys: #{error}")
                refresh(:scenes)
              end
            rescue StandardError => e
              notify(:scenes, "Půdorys: #{e.message}")
            end
          end
        end
        dialog
      end

      def scene_data
        result = super
        model = Sketchup.active_model
        result[:floorplan] = Floorplan.cached_data(model)
        ground = model.bounds.valid? ? model.bounds.min.z : 0.to_l
        result[:scenes].each_with_index do |entry, index|
          entry[:height_1800] = (model.pages.to_a[index].camera.eye.z - ground - 1800.mm).abs < 50.mm
        end
        result[:scenes].each_with_index do |data, index|
          page = model.pages.to_a[index]
          cam = page.camera
          data[:eye] = [cam.eye.x.to_f, cam.eye.y.to_f]
          data[:direction] = [cam.direction.x.to_f, cam.direction.y.to_f]
          data[:preview] = SceneVisuals.preview_base64(model, page)
        end
        result
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
                    {name: page.name, preview: SceneVisuals.preview_base64(model, page)})
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
        page.update(scene_options)
        page.set_attribute(SCENE_DICT, 'ratio', ratio || ratio_name(model.active_view.camera))
        rm_schedule_thumbnail(model, page)
      end

      def scene_action(d)
        model = Sketchup.active_model
        kind = d['kind']
        name = d['name'].to_s
        page = page_by_name(name)
        view = model.active_view
        case kind
        when 'refresh'
          super
        when 'rebuild_plan'
          Floorplan.build(model) do |ok, error|
            notify(:scenes, ok ? 'Půdorys byl aktualizován.' : "Půdorys se nepodařilo vytvořit: #{error}")
            refresh(:scenes)
          end
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
        when 'update_view'
          target = page || model.pages.selected_page
          raise 'Nejdříve vyber scénu ze seznamu.' unless target
          # Save ONLY eye, target and up from the visible viewport.
          # Keep focal length and frame ratio from the target's saved camera.
          # Explicitly avoid activating the saved page first, which would
          # overwrite the new user-adjusted view.
          saved = target.camera
          current = view.camera
          preserved_focal = focal_35(saved)
          preserved_ratio = saved.aspect_ratio
          model.start_operation('RM aktualizovat polohu záběru', true)
          begin
            replacement_camera = Sketchup::Camera.new(current.eye, current.target, current.up)
            replacement_camera.perspective = saved.perspective?
            if saved.perspective? && preserved_focal
              set_focal_35(replacement_camera, preserved_focal)
            end
            replacement_camera.aspect_ratio = preserved_ratio
            view.camera = replacement_camera
            view.invalidate
            rm_save_scene(model, target, ratio_name(saved))
            model.commit_operation
            notify(:scenes, "Poloha scény #{target.name} aktualizována. Ohnisko a poměr zůstaly zachované.")
            refresh(:scenes)
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
          # Keep existing version's correct scene flags, undo semantics and
          # capture of current view rather than replacing it with saved camera.
          super
          target = kind == 'create' ? page_by_name(name.strip) : page
          rm_schedule_thumbnail(model, target) if target
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
