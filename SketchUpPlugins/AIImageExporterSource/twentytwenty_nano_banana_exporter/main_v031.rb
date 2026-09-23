# frozen_string_literal: true

require 'json'

module TwentyTwenty
  module NanoBananaExporter
    extend self

    VERSION = '0.3.1'.freeze
    FRAME_ASPECT = (16.0 / 9.0).freeze
    FRAME_EPSILON = 0.0001

    EXPORTS = {
      '4K' => [3840, 2160],
      '6K' => [6144, 3456],
      '8K' => [7680, 4320]
    }.freeze

    STANDARD_ICONS = {
      '4K' => 'export_4k.svg',
      '6K' => 'export_6k.svg',
      '8K' => 'export_8k.svg'
    }.freeze

    AI_ICONS = {
      '4K' => 'export_ai_4k.svg',
      '6K' => 'export_ai_6k.svg',
      '8K' => 'export_ai_8k.svg'
    }.freeze

    PASS_RENDER_KEYS = %w[
      RenderMode Texture EdgeDisplayMode EdgeColorMode DrawSilhouettes SilhouetteWidth
      DrawDepthQue DrawLineEnds ExtendLines JitterEdges DrawBackEdges DrawHidden
      DrawHiddenGeometry DrawHiddenObjects DisplayColorByLayer DisplayFog FogColor
      FogStartDist FogEndDist FogUseBkColor BackgroundColor FaceFrontColor FaceBackColor
      ForegroundColor DrawGround DrawHorizon DisplayWatermarks DisplayText DisplayDims
      DisplaySketchAxes DisplayInstanceAxes DisplaySectionPlanes ModelTransparency
      MaterialTransparency AmbientOcclusion
    ].freeze

    def init
      return if @loaded
      @loaded = true
      create_commands
      create_menu
      create_toolbar
    end

    def icon_path(name)
      File.join(__dir__, 'icons', name)
    end

    def setup_icon(command, filename)
      path = icon_path(filename)
      return unless File.file?(path)
      command.small_icon = path
      command.large_icon = path
    rescue StandardError
      nil
    end

    def create_commands
      @standard_commands = {}
      @ai_commands = {}

      @frame_command = UI::Command.new('16:9 Frame') { toggle_16x9_frame }
      @frame_command.tooltip = '16:9 FRAME – zapnout / vypnout hranici exportu'
      @frame_command.status_bar_text = 'Zobrazí nativní 16:9 kamerový výřez SketchUpu. Šedá oblast je mimo výsledný export.'
      setup_icon(@frame_command, 'frame_16x9.svg')

      EXPORTS.each do |label, dims|
        width, height = dims

        standard = UI::Command.new("Standard #{label}") { export_current_view(label) }
        standard.tooltip = "Standard export #{label} 16:9 – #{width} × #{height}"
        standard.status_bar_text = "Exportuje aktuální pohled jako jeden PNG #{width} × #{height} px."
        setup_icon(standard, STANDARD_ICONS[label])
        @standard_commands[label] = standard

        ai = UI::Command.new("AI #{label} · RGB + Z + Lines") { export_ai_pack(label) }
        ai.tooltip = "AI export #{label} – RGB + Z-depth + Lines + camera JSON"
        ai.status_bar_text = "Exportuje RGB, aproximovaný Z-depth pass, čárový pass a metadata kamery v #{width} × #{height} px."
        setup_icon(ai, AI_ICONS[label])
        @ai_commands[label] = ai
      end
    end

    def create_menu
      root = UI.menu('Extensions').add_submenu('20-20 AI Image Exporter')
      root.add_item(@frame_command)
      root.add_separator
      standard = root.add_submenu('Standard export')
      EXPORTS.keys.each { |label| standard.add_item(@standard_commands[label]) }
      ai = root.add_submenu('AI export · RGB + Z + Lines')
      EXPORTS.keys.each { |label| ai.add_item(@ai_commands[label]) }
    end

    def create_toolbar
      @toolbar = UI::Toolbar.new('20-20 AI Export')
      @toolbar.add_item(@frame_command)
      @toolbar.add_separator
      EXPORTS.keys.each { |label| @toolbar.add_item(@standard_commands[label]) }
      @toolbar.add_separator
      EXPORTS.keys.each { |label| @toolbar.add_item(@ai_commands[label]) }
      @toolbar.restore
    rescue StandardError
      nil
    end

    def export_current_view(label)
      width, height = EXPORTS.fetch(label)
      model = Sketchup.active_model
      view = model.active_view
      scene = current_scene_name(model)
      default_dir = default_export_dir(model)
      default_name = "#{scene}_#{label}_16x9.png"

      path = UI.savepanel("Standard export #{label} 16:9", default_dir, default_name)
      return unless path
      path = ensure_png(path)

      write_png(view, path, width, height)
      UI.messagebox("Export hotový.\n\nStandard #{label} 16:9\n#{width} × #{height} px\n\n#{path}")
    rescue StandardError => e
      export_error(label, e)
    end

    def export_ai_pack(label)
      width, height = EXPORTS.fetch(label)
      model = Sketchup.active_model
      view = model.active_view
      scene = current_scene_name(model)
      default_dir = default_export_dir(model)
      default_name = "#{scene}_#{label}_AI_RGB.png"

      rgb_path = UI.savepanel("AI export #{label} · RGB + Z + Lines", default_dir, default_name)
      return unless rgb_path
      rgb_path = ensure_png(rgb_path)
      base = rgb_path.sub(/(?:_RGB)?\.png\z/i, '')
      rgb_path = "#{base}_RGB.png"
      depth_path = "#{base}_DEPTH.png"
      lines_path = "#{base}_LINES.png"
      meta_path = "#{base}_CAMERA.json"

      render_snapshot = snapshot_rendering_options(model)
      shadow_snapshot = snapshot_shadow_info(model)

      begin
        write_png(view, rgb_path, width, height)

        apply_depth_style(model)
        view.refresh
        write_png(view, depth_path, width, height)

        apply_line_style(model)
        view.refresh
        write_png(view, lines_path, width, height)
      ensure
        restore_rendering_options(model, render_snapshot)
        restore_shadow_info(model, shadow_snapshot)
        view.refresh rescue nil
      end

      write_camera_metadata(model, meta_path, label, width, height, rgb_path, depth_path, lines_path)

      UI.messagebox(
        "AI export hotový.\n\n" \
        "#{label} · #{width} × #{height} px\n\n" \
        "RGB   #{File.basename(rgb_path)}\n" \
        "Z     #{File.basename(depth_path)}\n" \
        "LINES #{File.basename(lines_path)}\n" \
        "META  #{File.basename(meta_path)}\n\n" \
        "Z pass je depth/fog mapa podle vzdálenosti od aktuální kamery."
      )
    rescue StandardError => e
      export_error(label, e, 'AI')
    end

    def frame_active?(camera = Sketchup.active_model.active_view.camera)
      (camera.aspect_ratio.to_f - FRAME_ASPECT).abs <= FRAME_EPSILON
    rescue StandardError
      false
    end

    def toggle_16x9_frame
      view = Sketchup.active_model.active_view
      camera = view.camera

      if frame_active?(camera)
        restore_ratio = @frame_previous_aspect
        camera.aspect_ratio = restore_ratio.nil? ? 0.0 : restore_ratio.to_f
        @frame_previous_aspect = nil
      else
        @frame_previous_aspect = camera.aspect_ratio.to_f
        camera.aspect_ratio = FRAME_ASPECT
      end

      view.invalidate
      view.refresh
      true
    rescue StandardError => e
      UI.messagebox("16:9 FRAME se nepodařilo přepnout:\n#{e.class}: #{e.message}")
      false
    end

    def with_16x9_export_frame(view)
      camera = view.camera
      original_ratio = camera.aspect_ratio.to_f
      changed = (original_ratio - FRAME_ASPECT).abs > FRAME_EPSILON

      if changed
        camera.aspect_ratio = FRAME_ASPECT
        view.refresh
      end

      yield
    ensure
      if changed
        begin
          camera.aspect_ratio = original_ratio
          view.refresh
        rescue StandardError
          nil
        end
      end
    end

    def write_png(view, path, width, height)
      options = {
        filename: path,
        width: width,
        height: height,
        antialias: true,
        compression: 1.0,
        transparent: false
      }

      ok = nil
      with_16x9_export_frame(view) do
        ok = view.write_image(options)
      end

      raise "SketchUp export selhal: #{File.basename(path)}" unless ok && File.file?(path) && File.size(path) > 0
      true
    end

    def snapshot_rendering_options(model)
      ro = model.rendering_options
      snapshot = {}
      PASS_RENDER_KEYS.each do |key|
        begin
          snapshot[key] = ro[key] if ro.keys.include?(key)
        rescue StandardError
          nil
        end
      end
      snapshot
    end

    def restore_rendering_options(model, snapshot)
      ro = model.rendering_options
      snapshot.each do |key, value|
        begin
          ro[key] = value
        rescue StandardError
          nil
        end
      end
    end

    def snapshot_shadow_info(model)
      info = model.shadow_info
      keys = %w[DisplayShadows DisplayOnGround Light]
      keys.each_with_object({}) do |key, memo|
        begin
          memo[key] = info[key]
        rescue StandardError
          nil
        end
      end
    rescue StandardError
      {}
    end

    def restore_shadow_info(model, snapshot)
      info = model.shadow_info
      snapshot.each do |key, value|
        begin
          info[key] = value
        rescue StandardError
          nil
        end
      end
    rescue StandardError
      nil
    end

    def set_render(ro, key, value)
      return unless ro.keys.include?(key)
      ro[key] = value
    rescue StandardError
      nil
    end

    def set_clean_common_style(model)
      ro = model.rendering_options
      {
        'Texture' => false,
        'DisplayColorByLayer' => false,
        'DrawBackEdges' => false,
        'DrawHidden' => false,
        'DrawHiddenGeometry' => false,
        'DrawHiddenObjects' => false,
        'DrawGround' => false,
        'DrawHorizon' => false,
        'DisplayWatermarks' => false,
        'DisplayText' => false,
        'DisplayDims' => false,
        'DisplaySketchAxes' => false,
        'DisplayInstanceAxes' => false,
        'DisplaySectionPlanes' => false,
        'ModelTransparency' => false,
        'MaterialTransparency' => false,
        'AmbientOcclusion' => false,
        'JitterEdges' => false,
        'ExtendLines' => false,
        'DrawLineEnds' => false,
        'DrawDepthQue' => false
      }.each { |key, value| set_render(ro, key, value) }

      begin
        model.shadow_info['DisplayShadows'] = false
      rescue StandardError
        nil
      end
    end

    def apply_depth_style(model)
      set_clean_common_style(model)
      ro = model.rendering_options
      black = Sketchup::Color.new(0, 0, 0)
      white = Sketchup::Color.new(255, 255, 255)

      set_render(ro, 'RenderMode', 5)
      set_render(ro, 'EdgeDisplayMode', 0)
      set_render(ro, 'DrawSilhouettes', false)
      set_render(ro, 'FaceFrontColor', white)
      set_render(ro, 'FaceBackColor', white)
      set_render(ro, 'ForegroundColor', white)
      set_render(ro, 'BackgroundColor', black)
      set_render(ro, 'FogColor', black)
      set_render(ro, 'FogUseBkColor', false)

      near_dist, far_dist = depth_range(model)
      set_render(ro, 'FogStartDist', near_dist)
      set_render(ro, 'FogEndDist', far_dist)
      set_render(ro, 'DisplayFog', true)
    end

    def apply_line_style(model)
      set_clean_common_style(model)
      ro = model.rendering_options
      black = Sketchup::Color.new(0, 0, 0)
      white = Sketchup::Color.new(255, 255, 255)

      set_render(ro, 'DisplayFog', false)
      set_render(ro, 'RenderMode', 1)
      set_render(ro, 'Texture', false)
      set_render(ro, 'BackgroundColor', white)
      set_render(ro, 'FaceFrontColor', white)
      set_render(ro, 'FaceBackColor', white)
      set_render(ro, 'ForegroundColor', black)
      set_render(ro, 'EdgeColorMode', 1)
      set_render(ro, 'EdgeDisplayMode', 1)
      set_render(ro, 'DrawSilhouettes', true)
      set_render(ro, 'SilhouetteWidth', 2)
    end

    def depth_range(model)
      camera = model.active_view.camera
      eye = camera.eye
      direction = camera.direction.clone
      direction.normalize!
      bounds = model.bounds

      depths = (0..7).map do |index|
        point = bounds.corner(index)
        vector = point - eye
        vector.dot(direction)
      end.select { |value| value.finite? && value > 0.001 }

      return [1.0, 1000.0] if depths.empty?
      near_dist = depths.min
      far_dist = depths.max
      span = [far_dist - near_dist, 1.0].max
      near_dist = [near_dist - span * 0.03, 0.001].max
      far_dist += span * 0.03
      [near_dist, far_dist]
    rescue StandardError
      [1.0, 1000.0]
    end

    def write_camera_metadata(model, path, label, width, height, rgb_path, depth_path, lines_path)
      camera = model.active_view.camera
      eye = camera.eye
      target = camera.target
      up = camera.up
      near_dist, far_dist = depth_range(model)

      payload = {
        exporter: '20-20 AI Image Exporter',
        version: VERSION,
        mode: 'AI RGB + Z + Lines',
        resolution: label,
        width_px: width,
        height_px: height,
        aspect_ratio: '16:9',
        perspective: camera.perspective?,
        fov_deg: (camera.fov rescue nil),
        camera: {
          eye: [eye.x.to_f, eye.y.to_f, eye.z.to_f],
          target: [target.x.to_f, target.y.to_f, target.z.to_f],
          up: [up.x.to_f, up.y.to_f, up.z.to_f]
        },
        depth: {
          method: 'SketchUp fog depth approximation',
          near_in: near_dist.to_f,
          far_in: far_dist.to_f,
          encoding: 'near=white, far=black'
        },
        files: {
          rgb: File.basename(rgb_path),
          depth: File.basename(depth_path),
          lines: File.basename(lines_path)
        }
      }
      File.write(path, JSON.pretty_generate(payload))
    end

    def current_scene_name(model)
      scene = model.pages.selected_page ? model.pages.selected_page.name.to_s : 'view'
      scene = 'view' if scene.empty?
      sanitize_filename(scene)
    end

    def default_export_dir(model)
      model.path.to_s.empty? ? Dir.home : File.dirname(model.path)
    end

    def ensure_png(path)
      path = path.to_s
      path += '.png' unless File.extname(path).downcase == '.png'
      path
    end

    def export_error(label, error, mode = 'Standard')
      UI.messagebox(
        "#{mode} export #{label} 16:9 selhal:\n" \
        "#{error.class}: #{error.message}\n\n" \
        "U 8K může být problém limit grafiky / paměti. Zkus případně 6K."
      )
    end

    def sanitize_filename(value)
      value.to_s.strip.gsub(/[\\\/:*?\"<>|]/, '_').gsub(/\s+/, '_')
    end
  end
end

TwentyTwenty::NanoBananaExporter.init
