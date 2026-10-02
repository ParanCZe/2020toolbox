# frozen_string_literal: true
require File.join(__dir__, 'scene_visuals')

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
          '<section class="rm-map-area"><div class="rm-map-title">PŮDORYS · KAMERY</div>' \
          '<div class="rm-map-help">Řez 2 m nad nejnižším bodem modelu. Přejetím zobrazíš náhled; dvojklikem aktivuješ záběr.</div>' \
          '<div id="rmMiniMap" class="rm-mini-map"></div></section><div id="tree"></div></aside>')
        original.sub('</body>', "<script>\n#{js}\n</script></body>")
      end

      def scene_data
        result = super
        model = Sketchup.active_model
        # Recompute the section only when the model's top-level geometry or bounds
        # change, or when the user explicitly presses Obnovit.
        bounds = model.bounds
        fingerprint = [model.object_id, model.entities.length,
                       (bounds.valid? ? bounds.min.to_a + bounds.max.to_a : [])]
        if @rm_map_key != fingerprint
          @rm_map_section = SceneVisuals.section_map(model)
          @rm_map_key = fingerprint
        end
        result[:section] = @rm_map_section
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
          @rm_map_key = nil
          super
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
