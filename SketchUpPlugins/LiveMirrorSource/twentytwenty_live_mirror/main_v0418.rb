# frozen_string_literal: true

require 'sketchup.rb'
require 'json'
require 'base64'

module TwentyTwenty
  module LiveMirror
    extend self

    EXTENSION_NAME = '20-20 Live Mirror'.freeze
    VERSION = '0.4.18'.freeze
    DICT = '2020_live_mirror_v04'.freeze
    MODEL_MIRROR = 'mirror'.freeze
    MODEL_LIVE = 'live'.freeze
    MODEL_QUALITY = 'quality'.freeze
    MODEL_SHADING = 'shading'.freeze
    MODEL_EDGES = 'edges'.freeze
    MODEL_SCENE_LIMIT = 'scene_limit'.freeze
    OVERLAY_ID = '2020_architekti.live_mirror.projected'.freeze
    MATERIAL_NAME = '2020_LIVE_MIRROR_NATIVE'.freeze

    LEGACY_DICT = '2020_live_mirror_v03'.freeze
    LEGACY_WORLD_FLAG = 'is_mirror_world'.freeze
    LEGACY_PORTAL_FLAG = 'is_portal_mask'.freeze
    LEGACY_MODEL_FACE_IDS = 'mirror_face_ids'.freeze

    DEFAULT_QUALITY = 2048
    QUALITY_LEVELS = [512, 768, 1024, 1536, 2048, 3072, 4096].freeze
    DEFAULT_TRIANGLE_LIMIT = 600_000
    TRIANGLE_LIMITS = [180_000, 350_000, 600_000, 900_000, 1_500_000].freeze
    MAX_EDGE_SEGMENTS = 600_000
    MAX_RECURSION = 32
    CAMERA_DEBOUNCE = 0.12
    SCENE_CHUNK_SIZE = 350_000
    REFLECTION_CULL_EXPANSION = 4.0
    REFLECTION_CULL_EPSILON = 5.0.mm
    DENSE_FACE_THRESHOLD = 4
    DENSE_OBJECT_THRESHOLD = 600
    ADAPTIVE_HARD_OVERSHOOT = 1.30
    OVERLAY_EPSILON = 3.0.mm
    CLIP_EPSILON = 1.5.mm
    BACKING_MAX_DISTANCE = 150.mm
    BACKING_PARALLEL_DOT = 0.965
    BACKING_MIN_COVERAGE = 0.30

    @renderer = nil
    @renderer_ready = false
    @scene_ready = false
    @scene_sending = false
    @scene_stats = nil
    @overlay = nil
    @view_observer = nil
    @observed_view = nil
    @refresh_timer = nil
    @render_token = 0
    @last_applied_token = 0
    @last_error = nil
    @toolbar = nil
    @last_frame_bytes = 0
    @last_frame_token = 0
    @last_frame_data_url = nil
    @last_frame_size = 0
    @renderer_max_size = 0
    @raw_preview = nil
    @native_material_applied = false
    @last_scene_json_bytes = 0
    @scene_cull_fallback = false

    class MirrorViewObserver < Sketchup::ViewObserver
      def onViewChanged(view)
        TwentyTwenty::LiveMirror.on_view_changed(view)
      end
    end

    class MirrorOverlay < Sketchup::Overlay
      def initialize
        super(OVERLAY_ID, '20-20 Projected Mirror', description: 'Projected planar mirror texture rendered by the 20-20 Live Mirror offscreen renderer.')
        @mirror = nil
        @texture_id = nil
        @texture_view = nil
      end

      def set_mirror(record)
        @mirror = record
      end

      def texture_loaded?
        !@texture_id.nil?
      end

      def texture_id
        @texture_id
      end

      def clear_texture
        if @texture_id && @texture_view
          begin
            @texture_view.release_texture(@texture_id)
          rescue StandardError
            nil
          end
        end
        @texture_id = nil
        @texture_view = nil
      end

      def update_image(view, image_rep)
        clear_texture
        @texture_id = view.load_texture(image_rep)
        @texture_view = view
        self.enabled = true unless enabled?
        view.invalidate
      rescue StandardError => error
        TwentyTwenty::LiveMirror.report_error('Overlay texture load failed', error, false)
      end

      def start
        Sketchup.active_model.active_view.invalidate rescue nil
        nil
      end

      def stop(*_args)
        clear_texture
      end

      def getExtents
        bb = Geom::BoundingBox.new
        bb.add(Sketchup.active_model.bounds)
        if @mirror && @mirror[:triangles]
          @mirror[:triangles].each { |tri| tri.each { |p| bb.add(p) } }
        end
        bb
      end

      def draw(view)
        return unless @mirror && @texture_id

        # v0.4.8: bypass SketchUp's 3D textured overlay path completely.
        # The WebGL reflection itself is already correct (Raw Reflection Frame),
        # so project the mirror rectangle into screen space and draw the texture
        # there. We subdivide the rectangle into a grid so perspective distortion
        # is approximated very closely even when the mirror is viewed obliquely.
        p00 = @mirror[:p00]
        p10 = @mirror[:p10]
        p01 = @mirror[:p01]

        xvec = p10 - p00
        yvec = p01 - p00
        return if xvec.length < 1.0e-9 || yvec.length < 1.0e-9

        # Adapt tessellation to mirror aspect ratio, while staying lightweight.
        aspect = xvec.length.to_f / [yvec.length.to_f, 1.0e-9].max
        if aspect >= 1.0
          cols = 40
          rows = [[(40.0 / aspect).round, 8].max, 40].min
        else
          rows = 40
          cols = [[(40.0 * aspect).round, 8].max, 40].min
        end

        points = []
        uvs = []

        # Bilinear point on the mirror rectangle. Because p00/p10/p01 describe
        # a planar rectangle, this is exact in model space. screen_coords then
        # gives SketchUp 2026 logical screen coordinates expected by draw2d.
        point_at = lambda do |u, v|
          Geom::Point3d.new(
            p00.x.to_f + xvec.x.to_f * u + yvec.x.to_f * v,
            p00.y.to_f + xvec.y.to_f * u + yvec.y.to_f * v,
            p00.z.to_f + xvec.z.to_f * u + yvec.z.to_f * v
          )
        end

        rows.times do |iy|
          v0 = iy.to_f / rows
          v1 = (iy + 1).to_f / rows
          cols.times do |ix|
            u0 = ix.to_f / cols
            u1 = (ix + 1).to_f / cols

            w00 = point_at.call(u0, v0)
            w10 = point_at.call(u1, v0)
            w11 = point_at.call(u1, v1)
            w01 = point_at.call(u0, v1)

            s00 = view.screen_coords(w00)
            s10 = view.screen_coords(w10)
            s11 = view.screen_coords(w11)
            s01 = view.screen_coords(w01)
            next unless s00 && s10 && s11 && s01

            # Use GL_QUADS because this is the canonical textured View API path.
            # IMPORTANT: no U flip here. The raw reflection frame is already the
            # exact image the user wants to see, so map it 1:1 onto the mirror.
            points.concat([s00, s10, s11, s01])
            uvs.concat([
              Geom::Vector3d.new(u0, v0, 0.0),
              Geom::Vector3d.new(u1, v0, 0.0),
              Geom::Vector3d.new(u1, v1, 0.0),
              Geom::Vector3d.new(u0, v1, 0.0)
            ])
          end
        end

        return if points.empty?
        view.drawing_color = Sketchup::Color.new(255, 255, 255, 255)
        view.draw2d(GL_QUADS, points, texture: @texture_id, uvs: uvs)
      rescue StandardError => error
        TwentyTwenty::LiveMirror.report_error('Overlay draw failed', error, false)
      end
    end

    def model
      Sketchup.active_model
    end

    def quality(m = model)
      q = m.get_attribute(DICT, MODEL_QUALITY, DEFAULT_QUALITY).to_i
      QUALITY_LEVELS.include?(q) ? q : DEFAULT_QUALITY
    end

    def live_enabled?(m = model)
      m.get_attribute(DICT, MODEL_LIVE, true) == true
    end


    def shading_enabled?(m = model)
      m.get_attribute(DICT, MODEL_SHADING, true) == true
    end

    def edges_enabled?(m = model)
      m.get_attribute(DICT, MODEL_EDGES, true) == true
    end

    def triangle_limit(m = model)
      value = m.get_attribute(DICT, MODEL_SCENE_LIMIT, DEFAULT_TRIANGLE_LIMIT).to_i
      TRIANGLE_LIMITS.include?(value) ? value : DEFAULT_TRIANGLE_LIMIT
    end

    def set_triangle_limit(value)
      value = value.to_i
      return unless TRIANGLE_LIMITS.include?(value)
      model.set_attribute(DICT, MODEL_SCENE_LIMIT, value)
      rebuild_renderer_scene(false) if load_mirror_record
      UI.messagebox("20-20 Live Mirror: limit scény nastaven na #{value.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1 ').reverse} trojúhelníků.")
    rescue StandardError => error
      report_error('Scene limit change failed', error)
    end

    def toggle_shading
      enabled = !shading_enabled?
      model.set_attribute(DICT, MODEL_SHADING, enabled)
      request_render
      UI.messagebox("Mirror shading: #{enabled ? 'ON' : 'OFF'}")
    end

    def toggle_edges
      enabled = !edges_enabled?
      model.set_attribute(DICT, MODEL_EDGES, enabled)
      request_render
      UI.messagebox("Mirror edges: #{enabled ? 'ON' : 'OFF'}")
    end

    def install_overlay(m = model)
      if @overlay && @overlay.valid?
        begin
          @overlay.enabled = true unless @overlay.enabled?
        rescue StandardError
          nil
        end
        record = load_mirror_record(m)
        @overlay.set_mirror(record) if record
        m.active_view.invalidate rescue nil
        return @overlay
      end

      # Overlays are disabled by default when added. v0.4.0/0.4.1 forgot to
      # explicitly enable ours, which meant the renderer could be READY and
      # produce frames while SketchUp never called Overlay#draw. Remove any
      # stale instance with our id, then add and enable a fresh overlay.
      begin
        stale = nil
        m.overlays.each { |ov| stale = ov if ov.overlay_id == OVERLAY_ID }
        m.overlays.remove(stale) if stale
      rescue StandardError
        nil
      end

      @overlay = MirrorOverlay.new
      added = m.overlays.add(@overlay)
      raise 'Could not register the mirror overlay.' unless added
      @overlay.enabled = true
      record = load_mirror_record(m)
      @overlay.set_mirror(record) if record
      m.active_view.invalidate rescue nil
      @overlay
    rescue StandardError => error
      report_error('Overlay setup failed', error)
      nil
    end

    def attach_view_observer
      view = model.active_view
      return if @observed_view == view && @view_observer
      begin
        @observed_view.remove_observer(@view_observer) if @observed_view && @view_observer
      rescue StandardError
        nil
      end
      @view_observer ||= MirrorViewObserver.new
      view.add_observer(@view_observer)
      @observed_view = view
    end

    def on_view_changed(_view)
      return unless live_enabled?
      return unless load_mirror_record
      return unless @scene_ready
      UI.stop_timer(@refresh_timer) if @refresh_timer
      @refresh_timer = UI.start_timer(live_debounce_seconds, false) do
        @refresh_timer = nil
        request_render
      end
    rescue StandardError
      @refresh_timer = nil
    end


    def live_debounce_seconds
      case quality
      when 0..1024 then CAMERA_DEBOUNCE
      when 1025..1536 then 0.25
      when 1537..2048 then 0.40
      when 2049..3072 then 0.70
      else 1.00
      end
    end

    def make_mirror_from_selection
      face = model.selection.grep(Sketchup::Face).first
      unless face
        UI.messagebox('Select one mirror face, then run Make Projected Mirror.')
        return
      end

      cleanup_legacy_v03
      record = build_mirror_record(face, model.edit_transform)
      raise 'The selected face could not be converted into a valid planar mirror.' unless record

      model.start_operation('Create Projected Mirror', true)
      save_mirror_record(record)
      model.set_attribute(DICT, MODEL_LIVE, true)
      model.commit_operation

      remove_overlay_pipeline
      model.selection.clear
      attach_view_observer
      ensure_renderer
      rebuild_renderer_scene(true)
    rescue StandardError => error
      model.abort_operation rescue nil
      report_error('Create mirror failed', error)
    end

    def remove_mirror
      record = load_mirror_record
      unless record
        UI.messagebox('No v0.4 projected mirror exists in this model.')
        return
      end
      model.start_operation('Remove Projected Mirror', true)
      restore_original_mirror_material(record)
      model.delete_attribute(DICT, MODEL_MIRROR)
      model.commit_operation
      remove_overlay_pipeline
      @native_material_applied = false
    @last_scene_json_bytes = 0
    @scene_cull_fallback = false
      @scene_ready = false
      model.active_view.invalidate
    rescue StandardError => error
      report_error('Remove mirror failed', error)
    end

    def build_mirror_record(face, transform)
      mesh = face.mesh(7)
      return nil unless mesh && mesh.count_points >= 3

      world_outer = face.outer_loop.vertices.map { |v| transform * v.position }
      return nil if world_outer.length < 3
      plane_point = world_outer.first

      # v0.4.12: derive the mirror plane from the ACTUAL transformed polygon.
      # Transforming Face#normal directly is wrong under non-uniform scaling
      # (normals require inverse-transpose math). In scaled/nested architectural
      # components that made the virtual eye reflect across a slightly wrong
      # plane, shifting the whole mirror image. Computing the normal from the
      # transformed vertices is affine-safe and matches the visible face.
      normal = polygon_normal_from_points(world_outer)
      return nil unless normal

      # Freeze the reflective/front side at creation time. This avoids relying
      # on SketchUp's arbitrary front/back face orientation when clipping the
      # renderer scene.
      creation_eye = model.active_view.camera.eye
      normal = normal.reverse if (creation_eye - plane_point).dot(normal) < 0.0

      # Pick the longest actual edge as the local horizontal reference. This is
      # numerically more stable than blindly using the first edge (which can be
      # tiny on imported / segmented geometry).
      xaxis = nil
      best_length = 0.0
      count = world_outer.length
      count.times do |i|
        edge = world_outer[(i + 1) % count] - world_outer[i]
        next unless edge.length > best_length && edge.length > 1.0e-8
        best_length = edge.length
        xaxis = edge.normalize
      end
      return nil unless xaxis
      yaxis = normal.cross(xaxis)
      return nil if yaxis.length < 1.0e-8
      yaxis.normalize!

      xs = []
      ys = []
      world_outer.each do |p|
        d = p - plane_point
        xs << d.dot(xaxis)
        ys << d.dot(yaxis)
      end
      xmin, xmax = xs.minmax
      ymin, ymax = ys.minmax
      return nil if (xmax-xmin).abs < 1.0e-8 || (ymax-ymin).abs < 1.0e-8

      p00 = plane_point.offset(xaxis, xmin).offset(yaxis, ymin)
      p10 = plane_point.offset(xaxis, xmax).offset(yaxis, ymin)
      p01 = plane_point.offset(xaxis, xmin).offset(yaxis, ymax)

      triangles = []
      uv_triangles = []
      mesh.polygons.each do |poly|
        indices = poly.map { |i| i.abs }
        next if indices.length < 3
        base = indices[0]
        (1...(indices.length-1)).each do |i|
          ids = [base, indices[i], indices[i+1]]
          pts = ids.map { |idx| transform * mesh.point_at(idx) }
          uvs = pts.map do |p|
            d = p - p00
            [d.dot(xaxis)/(xmax-xmin), d.dot(yaxis)/(ymax-ymin)]
          end
          triangles << pts
          uv_triangles << uvs
        end
      end
      return nil if triangles.empty?

      {
        face_pid: face.persistent_id,
        plane_point: plane_point,
        normal: normal,
        p00: p00,
        p10: p10,
        p01: p01,
        triangles: triangles,
        uv_triangles: uv_triangles,
        transform: transform.to_a,
        original_front_material: face.material ? face.material.name : '',
        original_back_material: face.back_material ? face.back_material.name : ''
      }
    end

    def save_mirror_record(record, m = model)
      hash = {
        'face_pid' => record[:face_pid],
        'plane_point' => point_to_a(record[:plane_point]),
        'normal' => vector_to_a(record[:normal]),
        'p00' => point_to_a(record[:p00]),
        'p10' => point_to_a(record[:p10]),
        'p01' => point_to_a(record[:p01]),
        'triangles' => record[:triangles].map { |tri| tri.map { |p| point_to_a(p) } },
        'uv_triangles' => record[:uv_triangles],
        'transform' => record[:transform],
        'original_front_material' => record[:original_front_material].to_s,
        'original_back_material' => record[:original_back_material].to_s
      }
      m.set_attribute(DICT, MODEL_MIRROR, JSON.generate(hash))
    end

    def load_mirror_record(m = model)
      json = m.get_attribute(DICT, MODEL_MIRROR, nil)
      return nil unless json.is_a?(String) && !json.empty?
      h = JSON.parse(json)
      {
        face_pid: h['face_pid'].to_i,
        plane_point: point_from_a(h['plane_point']),
        normal: vector_from_a(h['normal']),
        p00: point_from_a(h['p00']),
        p10: point_from_a(h['p10']),
        p01: point_from_a(h['p01']),
        triangles: Array(h['triangles']).map { |tri| tri.map { |p| point_from_a(p) } },
        uv_triangles: h['uv_triangles'],
        transform: h['transform'],
        original_front_material: h['original_front_material'].to_s,
        original_back_material: h['original_back_material'].to_s
      }
    rescue StandardError
      nil
    end

    def ensure_renderer
      return @renderer if @renderer
      html = File.join(__dir__, 'renderer_v0418.html')
      options = {
        dialog_title: '20-20 Mirror Renderer',
        preferences_key: '2020_live_mirror_renderer_v0418',
        scrollable: false,
        resizable: false,
        width: 40,
        height: 40,
        left: -10_000,
        top: -10_000,
        min_width: 40,
        min_height: 40,
        max_width: 40,
        max_height: 40,
        style: UI::HtmlDialog::STYLE_UTILITY
      }
      @renderer = UI::HtmlDialog.new(options)
      @renderer.set_file(html)

      @renderer.add_action_callback('renderer_ready') do |_ctx|
        @renderer_ready = true
        rebuild_renderer_scene(false) if load_mirror_record
      end

      @renderer.add_action_callback('scene_loaded') do |_ctx, triangles, truncated|
        @scene_ready = true
        @scene_sending = false
        @scene_stats ||= {}
        @scene_stats[:triangles] = triangles.to_i
        @scene_stats[:truncated] = truncated == true
        request_render
      end

      @renderer.add_action_callback('mirror_frame') do |_ctx, token, data_url, actual_size, renderer_max|
        @last_frame_size = actual_size.to_i if actual_size
        @renderer_max_size = renderer_max.to_i if renderer_max
        apply_renderer_frame(token.to_i, data_url.to_s)
      end

      @renderer.add_action_callback('renderer_error') do |_ctx, message|
        @last_error = message.to_s
        puts "[#{EXTENSION_NAME}] renderer: #{@last_error}"
      end

      @renderer.show
      begin
        @renderer.set_position(-10_000, -10_000)
        @renderer.set_size(40, 40)
      rescue StandardError
        nil
      end
      @renderer
    end

    def rebuild_renderer_scene(show_message = false)
      record = load_mirror_record
      unless record
        UI.messagebox('Create a projected mirror first.') if show_message
        return
      end
      ensure_renderer
      unless @renderer_ready
        UI.start_timer(0.25, false) { rebuild_renderer_scene(show_message) if @renderer_ready }
        return
      end
      return if @scene_sending

      scene, stats = build_scene_payload(record)
      json = JSON.generate(scene)
      @last_scene_json_bytes = json.bytesize
      stats[:json_bytes] = @last_scene_json_bytes
      @scene_stats = stats
      @scene_ready = false
      @scene_sending = true
      send_scene_json(json)
      if show_message
        note = if stats[:adaptive_decimated].to_i > 0
                 "\nAdaptive LOD simplified #{stats[:adaptive_decimated]} dense triangles while keeping low-poly architecture complete."
               elsif stats[:truncated]
                 "\nScene reached the adaptive hard safety cap. Increase Scene Detail if needed."
               else
                 ''
               end
        UI.messagebox("#{EXTENSION_NAME} v#{VERSION}\n\nProjected mirror created.\nRenderer scene: #{stats[:triangles]} triangles.#{note}\n\nThe SketchUp camera is NEVER modified by v0.4. Orbit/Pan/Zoom normally.")
      end
    rescue StandardError => error
      @scene_sending = false
      report_error('Scene rebuild failed', error)
    end

    def send_scene_json(json)
      chunks = []
      offset = 0
      while offset < json.length
        chunks << json.byteslice(offset, SCENE_CHUNK_SIZE)
        offset += SCENE_CHUNK_SIZE
      end
      chunks = ['{}'] if chunks.empty?
      @renderer.execute_script("window.beginSceneTransfer(#{chunks.length});")
      chunks.each_with_index do |chunk, index|
        @renderer.execute_script("window.addSceneChunk(#{index}, #{chunk.to_json});")
      end
    end

    def build_scene_payload(record)
      # v0.4.16 accuracy mode: complex real-world models were still losing
      # valid reflected geometry because the mirror-aperture frustum culler was
      # too aggressive in some view/model combinations. Prefer correctness here:
      # keep only the mirror-plane rejection and nested bounds-behind-mirror
      # pre-cull, but disable the reflection-cone culler for scene transfer.
      # This preserves more geometry in the mirror at the cost of a heavier
      # payload, which is the right tradeoff when the mirror exists but omits
      # objects that should clearly be visible.
      working_record = record.dup
      working_record[:cull_planes] = nil
      working_record[:edge_color] = reflection_edge_color
      count_cache = {}

      # v0.4.17 adaptive LOD. First estimate how much of the model sits on the
      # reflective side of the mirror. Low-poly architectural faces are kept in
      # full. Only dense faces are sampled when the scene exceeds the selected
      # budget, so the triangle limit no longer means "everything after the
      # first 600k triangles disappears".
      estimate = estimate_scene_complexity(
        model.entities,
        Geom::Transformation.new,
        {},
        0,
        working_record,
        count_cache
      )
      simple_est = estimate[:simple].to_i
      dense_est = estimate[:dense].to_i
      budget = triangle_limit.to_i
      dense_budget = [budget - simple_est, 0].max
      dense_ratio = if dense_est > 0
                      [[dense_budget.to_f / dense_est.to_f, 0.0].max, 1.0].min
                    else
                      1.0
                    end
      working_record[:dense_keep_ratio] = dense_ratio
      working_record[:estimated_simple_triangles] = simple_est
      working_record[:estimated_dense_triangles] = dense_est
      working_record[:adaptive_hard_limit] = [(budget * ADAPTIVE_HARD_OVERSHOOT).round, budget + 100_000].max

      opaque = []
      transparent = []
      edges = []
      stats = {
        triangles: 0,
        transparent: 0,
        edges: 0,
        truncated: false,
        edges_truncated: false,
        culled_groups: 0,
        culled_faces: 0,
        culled_edges: 0,
        frustum_culling: !working_record[:cull_planes].nil?,
        estimated_simple_triangles: simple_est,
        estimated_dense_triangles: dense_est,
        dense_keep_ratio: dense_ratio,
        adaptive_decimated: 0
      }
      collect_entities(
        model.entities,
        Geom::Transformation.new,
        nil,
        {},
        0,
        working_record,
        opaque,
        transparent,
        edges,
        stats,
        1.0,
        count_cache
      )

      # Fail-safe: if the conservative view culler somehow rejected the whole
      # model, retry using only the mirror-plane cull. This costs more memory but
      # avoids a silent blank mirror in unusual transformed/nested models.
      if stats[:triangles].zero? && working_record[:cull_planes]
        opaque.clear
        transparent.clear
        edges.clear
        retry_record = working_record.dup
        retry_record[:cull_planes] = nil
        stats = {
          triangles: 0,
          transparent: 0,
          edges: 0,
          truncated: false,
          edges_truncated: false,
          culled_groups: 0,
          culled_faces: 0,
          culled_edges: 0,
          frustum_culling: false,
          cull_fallback: true
        }
        collect_entities(
          model.entities,
          Geom::Transformation.new,
          nil,
          {},
          0,
          retry_record,
          opaque,
          transparent,
          edges,
          stats,
          1.0,
          count_cache
        )
      end

      bg = background_color
      edge_color = working_record[:edge_color]
      bb = model.bounds
      scene = {
        opaque: opaque,
        transparent: transparent,
        edges: edges,
        edgeColor: edge_color,
        bounds: { min: point_to_a(bb.min), max: point_to_a(bb.max) },
        background: [bg.red/255.0, bg.green/255.0, bg.blue/255.0, 1.0],
        triangles: stats[:triangles],
        edgeSegments: stats[:edges],
        truncated: stats[:truncated],
        edgesTruncated: stats[:edges_truncated]
      }
      [scene, stats]
    end

    def estimate_scene_complexity(entities, transform, stack, depth, record, count_cache = {})
      result = { simple: 0, dense: 0 }
      return result if depth > MAX_RECURSION

      entities.each do |entity|
        next unless entity.valid?
        next if entity.respond_to?(:hidden?) && entity.hidden?
        next if entity.respond_to?(:layer) && entity.layer && !entity.layer.visible?

        case entity
        when Sketchup::Face
          next if entity.persistent_id == record[:face_pid]
          next if mirror_backing_face?(entity, transform, record)
          tri_count = face_triangle_count(entity)
          if tri_count <= DENSE_FACE_THRESHOLD
            result[:simple] += tri_count
          else
            result[:dense] += tri_count
          end
        when Sketchup::Group
          child_transform = transform * entity.transformation
          local_bounds = begin
            if entity.respond_to?(:local_bounds)
              entity.local_bounds
            elsif entity.respond_to?(:definition) && entity.definition
              entity.definition.bounds
            end
          rescue StandardError
            nil
          end
          next if local_bounds && !bounds_may_reflect?(local_bounds, child_transform, record)
          total = subtree_triangle_count(entity, {}, count_cache)
          if total > DENSE_OBJECT_THRESHOLD
            result[:dense] += total
          else
            result[:simple] += total
          end
        when Sketchup::ComponentInstance
          definition = entity.definition
          key = definition.object_id
          next if stack[key]
          child_transform = transform * entity.transformation
          next if definition.bounds && !bounds_may_reflect?(definition.bounds, child_transform, record)
          total = subtree_triangle_count(entity, stack, count_cache)
          if total > DENSE_OBJECT_THRESHOLD
            result[:dense] += total
          else
            result[:simple] += total
          end
        end
      end
      result
    rescue StandardError
      result || { simple: 0, dense: 0 }
    end

    def face_triangle_count(face)
      mesh = face.mesh(7) rescue nil
      return 0 unless mesh
      tri_count = 0
      mesh.polygons.each do |poly|
        indices = poly.map { |i| i.abs }
        tri_count += [indices.length - 2, 0].max
      end
      tri_count
    rescue StandardError
      0
    end

    def subtree_triangle_count(entity, stack = {}, cache = {}, depth = 0)
      return 0 if depth > MAX_RECURSION
      case entity
      when Sketchup::Face
        return face_triangle_count(entity)
      when Sketchup::Group
        key = [:group, entity.persistent_id]
        return cache[key] if cache.key?(key)
        sum = 0
        entity.entities.each do |child|
          next unless child.valid?
          next if child.respond_to?(:hidden?) && child.hidden?
          next if child.respond_to?(:layer) && child.layer && !child.layer.visible?
          sum += subtree_triangle_count(child, stack, cache, depth + 1)
        end
        cache[key] = sum
        return sum
      when Sketchup::ComponentInstance
        definition = entity.definition
        key = [:definition, definition.object_id]
        return cache[key] if cache.key?(key)
        return 0 if stack[key]
        stack[key] = true
        sum = 0
        definition.entities.each do |child|
          next unless child.valid?
          next if child.respond_to?(:hidden?) && child.hidden?
          next if child.respond_to?(:layer) && child.layer && !child.layer.visible?
          sum += subtree_triangle_count(child, stack, cache, depth + 1)
        end
        stack.delete(key)
        cache[key] = sum
        return sum
      else
        return 0
      end
    rescue StandardError
      0
    end

    def evenly_sample_triangles(triangles, desired)
      count = triangles.length
      return triangles if desired >= count
      return [] if desired <= 0 || count.zero?
      picked = []
      desired.times do |i|
        index = (((i + 0.5) * count) / desired.to_f).floor
        index = count - 1 if index >= count
        picked << triangles[index]
      end
      picked
    end

    def collect_entities(entities, transform, inherited_material, stack, depth, record, opaque, transparent, edges, stats, sample_ratio = 1.0, count_cache = {})
      return if depth > MAX_RECURSION || stats[:truncated]
      entities.each do |entity|
        break if stats[:truncated]
        next unless entity.valid?
        next if entity.respond_to?(:hidden?) && entity.hidden?
        next if entity.respond_to?(:layer) && entity.layer && !entity.layer.visible?

        case entity
        when Sketchup::Face
          next if entity.persistent_id == record[:face_pid]
          emit_face(entity, transform, inherited_material, record, opaque, transparent, stats, sample_ratio)
        when Sketchup::Edge
          emit_edge(entity, transform, record, edges, stats)
        when Sketchup::Group
          child_transform = transform * entity.transformation
          local_bounds = begin
            if entity.respond_to?(:local_bounds)
              entity.local_bounds
            elsif entity.respond_to?(:definition) && entity.definition
              entity.definition.bounds
            else
              nil
            end
          rescue StandardError
            nil
          end
          if local_bounds && !bounds_may_reflect?(local_bounds, child_transform, record)
            stats[:culled_groups] += 1
            next
          end
          mat = entity.material || inherited_material
          object_ratio = sample_ratio
          if sample_ratio >= 0.9999
            object_triangles = subtree_triangle_count(entity, {}, count_cache)
            if object_triangles > DENSE_OBJECT_THRESHOLD
              object_ratio = [record[:dense_keep_ratio].to_f, 1.0].min
            end
          end
          collect_entities(entity.entities, child_transform, mat, stack, depth + 1, record, opaque, transparent, edges, stats, object_ratio, count_cache)
        when Sketchup::ComponentInstance
          definition = entity.definition
          key = definition.object_id
          next if stack[key]
          child_transform = transform * entity.transformation
          if definition.bounds && !bounds_may_reflect?(definition.bounds, child_transform, record)
            stats[:culled_groups] += 1
            next
          end
          mat = entity.material || inherited_material
          object_ratio = sample_ratio
          if sample_ratio >= 0.9999
            object_triangles = subtree_triangle_count(entity, stack, count_cache)
            if object_triangles > DENSE_OBJECT_THRESHOLD
              object_ratio = [record[:dense_keep_ratio].to_f, 1.0].min
            end
          end
          stack[key] = true
          collect_entities(definition.entities, child_transform, mat, stack, depth + 1, record, opaque, transparent, edges, stats, object_ratio, count_cache)
          stack.delete(key)
        end
      end
    end

    def bounds_may_reflect?(bounds, parent_transform, record)
      points = (0..7).map { |i| parent_transform * bounds.corner(i) }
      # Always reject geometry wholly behind the physical mirror plane.
      plane_ok = points.any? do |p|
        signed_distance(p, record[:plane_point], record[:normal]) >= -CLIP_EPSILON.to_f
      end
      return false unless plane_ok

      planes = record[:cull_planes]
      return true unless planes && !planes.empty?
      points_may_intersect_cull_volume?(points, planes)
    rescue StandardError
      true
    end

    def reflection_cull_planes(record, real_eye)
      p00 = record[:p00]
      p10 = record[:p10]
      p01 = record[:p01]
      xvec = p10 - p00
      yvec = p01 - p00
      return nil if xvec.length < 1.0e-8 || yvec.length < 1.0e-8

      p11 = p10.offset(yvec)
      center = Geom::Point3d.new(
        (p00.x + p10.x + p01.x + p11.x) / 4.0,
        (p00.y + p10.y + p01.y + p11.y) / 4.0,
        (p00.z + p10.z + p01.z + p11.z) / 4.0
      )

      visible_normal = (real_eye - record[:plane_point]).dot(record[:normal]) >= 0.0 ? record[:normal] : record[:normal].reverse
      virtual_eye = reflect_point_about_plane(real_eye, record[:plane_point], visible_normal)

      # Expand around mirror center so orbit/pan can move substantially without
      # requiring the scene to be rebuilt on every mouse movement.
      factor = REFLECTION_CULL_EXPANSION.to_f
      corners = [p00, p10, p11, p01].map do |p|
        Geom::Point3d.new(
          center.x + (p.x - center.x) * factor,
          center.y + (p.y - center.y) * factor,
          center.z + (p.z - center.z) * factor
        )
      end

      # A point well in front of the mirror centre is guaranteed to be inside
      # the desired reflection volume and is used to orient all side planes.
      test_point = center.offset(visible_normal, [xvec.length, yvec.length, 1.0].max * 2.0)
      planes = []
      4.times do |i|
        a = corners[i]
        b = corners[(i + 1) % 4]
        n = (a - virtual_eye).cross(b - virtual_eye)
        next if n.length < 1.0e-9
        n.normalize!
        n.reverse! if (test_point - virtual_eye).dot(n) < 0.0
        planes << [virtual_eye, n]
      end
      planes
    rescue StandardError
      nil
    end

    def points_may_intersect_cull_volume?(points, planes)
      planes.each do |origin, normal|
        # If every corner lies clearly outside one side plane, the whole bounds
        # is outside that half-space and cannot intersect the reflection cone.
        outside = points.all? { |p| (p - origin).dot(normal) < -REFLECTION_CULL_EPSILON.to_f }
        return false if outside
      end
      true
    end

    def triangle_may_reflect?(points, record)
      planes = record[:cull_planes]
      return true unless planes && !planes.empty?
      points_may_intersect_cull_volume?(points, planes)
    end

    def reflect_point_about_plane(point, plane_point, normal)
      d = (point - plane_point).dot(normal)
      Geom::Point3d.new(
        point.x - 2.0 * d * normal.x,
        point.y - 2.0 * d * normal.y,
        point.z - 2.0 * d * normal.z
      )
    end

    def emit_face(face, transform, inherited_material, record, opaque, transparent, stats, sample_ratio = 1.0)
      # A mirror mounted on a wall often has a second wall/cover face essentially
      # coplanar with the mirror. In the private renderer that face would be the
      # first thing hit by every reflected ray and the mirror would appear as a
      # red/white wall instead of a reflection. Suppress only large, nearly
      # parallel faces close to the mirror plane that substantially cover the
      # mirror aperture. This changes only the offscreen render; model geometry
      # is never hidden or modified.
      return if mirror_backing_face?(face, transform, record)

      mesh = face.mesh(7)
      return unless mesh
      material = face.material || inherited_material
      rgba = material_rgba(material)
      normal = world_face_normal(face, transform) || face.normal
      normal = normal.normalize if normal.length > 1.0e-9
      rgb = [rgba[0], rgba[1], rgba[2]]
      alpha = rgba[3]
      target = alpha < 0.985 ? transparent : opaque

      candidate_triangles = []
      mesh.polygons.each do |poly|
        indices = poly.map { |i| i.abs }
        next if indices.length < 3
        p0 = transform * mesh.point_at(indices[0])
        (1...(indices.length - 1)).each do |i|
          pts = [p0, transform * mesh.point_at(indices[i]), transform * mesh.point_at(indices[i+1])]
          distances = pts.map { |p| signed_distance(p, record[:plane_point], record[:normal]) }
          next if distances.all? { |d| d < -CLIP_EPSILON.to_f }
          unless triangle_may_reflect?(pts, record)
            stats[:culled_faces] += 1
            next
          end
          candidate_triangles << pts
        end
      end

      face_count = candidate_triangles.length
      return if face_count.zero?
      selected = candidate_triangles
      ratio = sample_ratio.to_f
      if ratio >= 0.9999 && face_count > DENSE_FACE_THRESHOLD
        ratio = record[:dense_keep_ratio].to_f
      end
      if ratio < 0.9999
        desired = [(face_count * ratio).round, 1].max
        desired = [desired, face_count].min
        selected = evenly_sample_triangles(candidate_triangles, desired)
        stats[:adaptive_decimated] += (face_count - selected.length)
      end

      hard_limit = record[:adaptive_hard_limit].to_i
      selected.each do |pts|
        break if hard_limit > 0 && stats[:triangles] >= hard_limit
        pts.each do |p|
          target.concat([
            p.x.to_f, p.y.to_f, p.z.to_f,
            rgb[0], rgb[1], rgb[2], alpha,
            normal.x.to_f, normal.y.to_f, normal.z.to_f
          ])
        end
        stats[:triangles] += 1
        stats[:transparent] += 1 if alpha < 0.985
      end
      stats[:truncated] = true if hard_limit > 0 && stats[:triangles] >= hard_limit
    end

    def emit_edge(edge, transform, record, edges, stats)
      return if stats[:edges_truncated]
      return if edge.soft? || edge.smooth?

      a = transform * edge.start.position
      b = transform * edge.end.position
      da = signed_distance(a, record[:plane_point], record[:normal])
      db = signed_distance(b, record[:plane_point], record[:normal])
      return if da < -CLIP_EPSILON.to_f && db < -CLIP_EPSILON.to_f
      unless triangle_may_reflect?([a, b], record)
        stats[:culled_edges] += 1
        return
      end

      c = record[:edge_color] || reflection_edge_color
      # Same interleaved format as face vertices: xyz + rgba + normal.
      # The edge color is dark, so the lighting term does not materially alter it.
      [a, b].each do |p|
        edges.concat([
          p.x.to_f, p.y.to_f, p.z.to_f,
          c[0], c[1], c[2], c[3],
          0.0, 0.0, 1.0
        ])
      end
      stats[:edges] += 1
      stats[:edges_truncated] = true if stats[:edges] >= MAX_EDGE_SEGMENTS
    rescue StandardError
      nil
    end

    def reflection_edge_color
      color = model.rendering_options['EdgeColor'] rescue nil
      color ||= Sketchup::Color.new(25, 25, 25)
      [color.red / 255.0, color.green / 255.0, color.blue / 255.0, 0.92]
    rescue StandardError
      [0.08, 0.08, 0.08, 0.92]
    end

    def mirror_backing_face?(face, transform, record)
      world_normal = world_face_normal(face, transform)
      return false unless world_normal
      return false if world_normal.dot(record[:normal]).abs < BACKING_PARALLEL_DOT

      points = face.outer_loop.vertices.map { |vertex| transform * vertex.position }
      return false if points.length < 3

      distances = points.map { |point| signed_distance(point, record[:plane_point], record[:normal]) }
      average_distance = distances.sum / distances.length.to_f
      return false if average_distance.abs > BACKING_MAX_DISTANCE.to_f

      xaxis = record[:p10] - record[:p00]
      yaxis = record[:p01] - record[:p00]
      mirror_width = xaxis.length.to_f
      mirror_height = yaxis.length.to_f
      return false if mirror_width < 1.0e-8 || mirror_height < 1.0e-8
      xaxis.normalize!
      yaxis.normalize!

      xs = []
      ys = []
      points.each do |point|
        delta = point - record[:p00]
        xs << delta.dot(xaxis)
        ys << delta.dot(yaxis)
      end
      fx0, fx1 = xs.minmax
      fy0, fy1 = ys.minmax
      overlap_x = [[fx1, mirror_width].min - [fx0, 0.0].max, 0.0].max
      overlap_y = [[fy1, mirror_height].min - [fy0, 0.0].max, 0.0].max
      mirror_area = mirror_width * mirror_height
      return false if mirror_area <= 1.0e-8

      coverage = (overlap_x * overlap_y) / mirror_area
      coverage >= BACKING_MIN_COVERAGE
    rescue StandardError
      false
    end

    def material_rgba(material)
      if material
        c = material.color
        a = material.alpha.to_f
        [c.red/255.0, c.green/255.0, c.blue/255.0, [[a, 0.04].max, 1.0].min]
      else
        c = model.rendering_options['FaceFrontColor'] rescue Sketchup::Color.new(230,230,230)
        [c.red/255.0, c.green/255.0, c.blue/255.0, 1.0]
      end
    rescue StandardError
      [0.85, 0.85, 0.85, 1.0]
    end

    def background_color
      model.rendering_options['BackgroundColor']
    rescue StandardError
      Sketchup::Color.new(200, 200, 200)
    end

    def request_render
      record = load_mirror_record
      return unless record && @renderer_ready && @scene_ready

      view = model.active_view
      camera = view.camera
      eye = camera.eye
      normal = record[:normal]
      visible = (eye - record[:plane_point]).dot(normal) >= 0.0 ? normal : normal.reverse

      # v0.4.6 renders the exact mirror aperture instead of rendering a full
      # camera frame and trying to paste/crop it afterwards. The user's eye is
      # reflected behind the mirror, then the mirror's own four corners define
      # an asymmetric off-axis frustum. The resulting PNG is therefore already
      # the exact image that belongs on the mirror surface.
      mirror_w = (record[:p10] - record[:p00]).length.to_f
      mirror_h = (record[:p01] - record[:p00]).length.to_f
      mirror_aspect = mirror_h > 1.0e-8 ? mirror_w / mirror_h : 1.0
      mirror_aspect = 1.0 unless mirror_aspect.finite? && mirror_aspect > 1.0e-6
      p11 = record[:p10].offset(record[:p01] - record[:p00])

      @render_token += 1
      payload = {
        token: @render_token,
        size: quality,
        eye: point_to_a(eye),
        planePoint: point_to_a(record[:plane_point]),
        visibleNormal: vector_to_a(visible),
        p00: point_to_a(record[:p00]),
        p10: point_to_a(record[:p10]),
        p01: point_to_a(record[:p01]),
        p11: point_to_a(p11),
        mirrorAspect: mirror_aspect,
        clipEps: CLIP_EPSILON.to_f,
        shading: shading_enabled?,
        showEdges: edges_enabled?
      }
      @renderer.execute_script("window.renderMirror(#{JSON.generate(payload)});")
    rescue StandardError => error
      report_error('Render request failed', error, false)
    end

    def apply_renderer_frame(token, data_url)
      return if token < @last_applied_token
      prefix = 'data:image/png;base64,'
      return unless data_url.start_with?(prefix)
      bytes = Base64.decode64(data_url[prefix.length..])
      @last_frame_bytes = bytes.bytesize
      @last_frame_token = token
      @last_frame_data_url = data_url
      path = File.join(Sketchup.temp_dir, "2020_mirror_native_v0413_#{Process.pid}.png")
      File.binwrite(path, bytes)

      record = load_mirror_record
      raise 'Mirror record is missing.' unless record
      apply_native_face_texture(record, path)

      @last_applied_token = token
    rescue StandardError => error
      report_error('Rendered frame import failed', error, false)
    ensure
      begin
        File.delete(path) if path && File.exist?(path)
      rescue StandardError
        nil
      end
    end

    # v0.4.9 deliberately bypasses SketchUp Overlay textured drawing. The WebGL
    # renderer already produces the correct mirror frame; this method turns that
    # frame into a normal SketchUp material texture and pins one complete texture
    # tile to the four corners of the original mirror face. This uses SketchUp's
    # native material pipeline instead of View#draw / View#draw2d.
    def apply_native_face_texture(record, image_path)
      remove_overlay_pipeline
      face = model.find_entity_by_persistent_id(record[:face_pid].to_i)
      raise 'The original mirror Face could not be found.' unless face.is_a?(Sketchup::Face) && face.valid?

      material = model.materials[MATERIAL_NAME] || model.materials.add(MATERIAL_NAME)
      material.color = Sketchup::Color.new(255, 255, 255)
      material.alpha = 1.0
      material.texture = Sketchup::ImageRep.new(image_path)

      mapping = native_material_mapping(face, record)
      raise 'Could not build native mirror UV mapping. Re-select the mirror face and run Make Projected Mirror once.' unless mapping

      face.material = material
      face.back_material = material
      front_ok = face.position_material(material, mapping, true)
      back_ok = face.position_material(material, mapping, false)
      raise 'SketchUp rejected the native material mapping.' unless front_ok || back_ok

      @native_material_applied = true
      model.active_view.invalidate
    end

    def native_material_mapping(face, record)
      # New v0.4.9 records contain the exact edit-context transform used when the
      # mirror was created, so the world-space render aperture can be converted
      # back to the Face's own local coordinates without approximation.
      p00 = record[:p00]
      p10 = record[:p10]
      p01 = record[:p01]
      p11 = Geom::Point3d.new(
        p10.x.to_f + (p01.x.to_f - p00.x.to_f),
        p10.y.to_f + (p01.y.to_f - p00.y.to_f),
        p10.z.to_f + (p01.z.to_f - p00.z.to_f)
      )

      tr_array = record[:transform]
      if tr_array.is_a?(Array) && tr_array.length == 16
        inverse = Geom::Transformation.new(tr_array).inverse
        corners = [p00, p10, p11, p01].map { |p| p.transform(inverse) }
      else
        # Compatibility fallback for a mirror created by 0.4.0-0.4.8. This is
        # reliable for top-level / rigidly transformed faces. For nested mirrors
        # the user can simply re-run Make Projected Mirror once under v0.4.9.
        corners = local_face_rectangle(face)
        return nil unless corners
      end

      # v0.4.11: do not rotate the framebuffer; mirror it left/right.
      # The raw frame is upright, but the final face material needs a pure
      # horizontal flip to behave like a mirror.
      # Mapping: p00->(1,0), p10->(0,0), p11->(0,1), p01->(1,1).
      uvs = [
        Geom::Point3d.new(1.0, 0.0, 0.0),
        Geom::Point3d.new(0.0, 0.0, 0.0),
        Geom::Point3d.new(0.0, 1.0, 0.0),
        Geom::Point3d.new(1.0, 1.0, 0.0)
      ]
      corners.zip(uvs).flatten
    rescue StandardError
      nil
    end

    def local_face_rectangle(face)
      points = face.outer_loop.vertices.map(&:position)
      return nil if points.length < 3
      origin = points.first
      normal = face.normal.clone
      return nil if normal.length < 1.0e-9
      normal.normalize!

      xaxis = nil
      points[1..].each do |point|
        edge = point - origin
        if edge.length > 1.0e-8
          xaxis = edge.normalize
          break
        end
      end
      return nil unless xaxis
      yaxis = normal.cross(xaxis)
      return nil if yaxis.length < 1.0e-9
      yaxis.normalize!

      xs = []
      ys = []
      points.each do |point|
        delta = point - origin
        xs << delta.dot(xaxis)
        ys << delta.dot(yaxis)
      end
      xmin, xmax = xs.minmax
      ymin, ymax = ys.minmax
      return nil if (xmax - xmin).abs < 1.0e-9 || (ymax - ymin).abs < 1.0e-9
      [
        origin.offset(xaxis, xmin).offset(yaxis, ymin),
        origin.offset(xaxis, xmax).offset(yaxis, ymin),
        origin.offset(xaxis, xmax).offset(yaxis, ymax),
        origin.offset(xaxis, xmin).offset(yaxis, ymax)
      ]
    end

    def remove_overlay_pipeline
      begin
        if @overlay && @overlay.valid?
          @overlay.clear_texture if @overlay.respond_to?(:clear_texture)
          model.overlays.remove(@overlay)
        end
      rescue StandardError
        nil
      end
      @overlay = nil
      begin
        stale = nil
        model.overlays.each { |ov| stale = ov if ov.overlay_id == OVERLAY_ID }
        model.overlays.remove(stale) if stale
      rescue StandardError
        nil
      end
    end

    def restore_original_mirror_material(record)
      face = model.find_entity_by_persistent_id(record[:face_pid].to_i)
      return unless face.is_a?(Sketchup::Face) && face.valid?
      front = record[:original_front_material].to_s
      back = record[:original_back_material].to_s
      face.material = front.empty? ? nil : model.materials[front]
      face.back_material = back.empty? ? nil : model.materials[back]
    rescue StandardError
      nil
    end

    def show_raw_reflection_frame
      unless @last_frame_data_url && !@last_frame_data_url.empty?
        UI.messagebox('No raw reflection frame has been received yet. Use Refresh Reflection Now first.')
        return
      end

      @raw_preview ||= UI::HtmlDialog.new(
        dialog_title: '20-20 Raw Reflection Frame',
        preferences_key: '2020_live_mirror_raw_frame_v049',
        scrollable: false,
        resizable: true,
        width: 760,
        height: 760,
        min_width: 360,
        min_height: 360,
        style: UI::HtmlDialog::STYLE_DIALOG
      )

      escaped = @last_frame_data_url.to_json
      html = <<~HTML
        <!doctype html>
        <html><head><meta charset="utf-8"><title>Raw Reflection</title>
        <style>
          html,body{margin:0;width:100%;height:100%;background:#1a1a1a;color:#eee;font-family:Arial,sans-serif;overflow:hidden}
          #wrap{width:100%;height:100%;display:flex;flex-direction:column}
          #head{padding:10px 14px;font-size:13px;background:#252525;box-sizing:border-box}
          #imgwrap{flex:1;min-height:0;display:flex;align-items:center;justify-content:center;padding:12px;box-sizing:border-box}
          img{max-width:100%;max-height:100%;object-fit:contain;image-rendering:auto;box-shadow:0 0 0 1px #555}
        </style></head>
        <body><div id="wrap"><div id="head">Exact WebGL output before SketchUp Overlay mapping — frame #{@last_frame_token}, #{@last_frame_bytes} bytes</div><div id="imgwrap"><img id="f"></div></div>
        <script>document.getElementById('f').src=#{escaped};</script></body></html>
      HTML
      @raw_preview.set_html(html)
      @raw_preview.show
      @raw_preview.bring_to_front
    rescue StandardError => error
      report_error('Raw reflection preview failed', error)
    end

    def refresh_now
      record = load_mirror_record
      unless record
        UI.messagebox('Create a projected mirror first.')
        return
      end
      ensure_renderer
      if @scene_ready
        request_render
      else
        rebuild_renderer_scene(false)
      end
    end

    def toggle_live
      enabled = !live_enabled?
      model.start_operation('Toggle Projected Mirror Live Updates', true)
      model.set_attribute(DICT, MODEL_LIVE, enabled)
      model.commit_operation
      attach_view_observer if enabled
      request_render if enabled
      UI.messagebox("Projected mirror live updates: #{enabled ? 'ON' : 'OFF'}")
    end

    def set_quality(q)
      q = q.to_i
      return unless QUALITY_LEVELS.include?(q)
      model.start_operation('Set Mirror Quality', true)
      model.set_attribute(DICT, MODEL_QUALITY, q)
      model.commit_operation
      request_render
    end

    def cleanup_legacy_v03
      ids = model.get_attribute(LEGACY_DICT, LEGACY_MODEL_FACE_IDS, [])
      ids = [ids] unless ids.is_a?(Array)
      model.start_operation('Clean Legacy Mirror 0.3', true)
      ids.each do |pid|
        face = model.find_entity_by_persistent_id(pid.to_i)
        next unless face.is_a?(Sketchup::Face) && face.valid?
        portal_ids = face.get_attribute(LEGACY_DICT, 'portal_face_ids', [])
        portal_states = face.get_attribute(LEGACY_DICT, 'portal_original_hidden', [])
        portal_ids = [portal_ids] unless portal_ids.is_a?(Array)
        portal_states = [portal_states] unless portal_states.is_a?(Array)
        portal_ids.each_with_index do |bid, i|
          blocker = model.find_entity_by_persistent_id(bid.to_i)
          blocker.hidden = portal_states[i] == true if blocker.is_a?(Sketchup::Face) && blocker.valid?
        end
        face.hidden = face.get_attribute(LEGACY_DICT, 'original_hidden', false) == true
        face.delete_attribute(LEGACY_DICT)
      end
      model.entities.to_a.each do |entity|
        next unless entity.respond_to?(:get_attribute)
        is_world = entity.get_attribute(LEGACY_DICT, LEGACY_WORLD_FLAG, false) == true
        is_portal = entity.get_attribute(LEGACY_DICT, LEGACY_PORTAL_FLAG, false) == true
        entity.erase! if entity.valid? && (is_world || is_portal)
      end
      model.delete_attribute(LEGACY_DICT, LEGACY_MODEL_FACE_IDS)
      model.commit_operation
    rescue StandardError => error
      model.abort_operation rescue nil
      puts "[#{EXTENSION_NAME}] Legacy cleanup warning: #{error.class}: #{error.message}"
    end

    def signed_distance(point, plane_point, normal)
      (point - plane_point).dot(normal)
    end

    def polygon_normal_from_points(points)
      return nil unless points && points.length >= 3
      origin = points[0]
      (1...(points.length - 1)).each do |i|
        a = points[i] - origin
        b = points[i + 1] - origin
        n = a.cross(b)
        next if n.length < 1.0e-9
        n.normalize!
        return n
      end
      nil
    rescue StandardError
      nil
    end

    def world_face_normal(face, transform)
      points = face.outer_loop.vertices.map { |vertex| transform * vertex.position }
      polygon_normal_from_points(points)
    rescue StandardError
      nil
    end

    # Kept for compatibility with older helper calls, but v0.4.12 mirror and
    # scene plane logic no longer relies on this under non-uniform scaling.
    def transformed_normal(normal, transform)
      n = normal.transform(transform)
      return nil if n.length < 1.0e-9
      n.normalize
    rescue StandardError
      nil
    end

    def point_to_a(point)
      [point.x.to_f, point.y.to_f, point.z.to_f]
    end

    def vector_to_a(vector)
      [vector.x.to_f, vector.y.to_f, vector.z.to_f]
    end

    def point_from_a(a)
      Geom::Point3d.new(a[0].to_f, a[1].to_f, a[2].to_f)
    end

    def vector_from_a(a)
      v = Geom::Vector3d.new(a[0].to_f, a[1].to_f, a[2].to_f)
      v.normalize! if v.length > 1.0e-9
      v
    end

    def diagnostics
      record = load_mirror_record
      renderer_state = @renderer_ready ? 'READY' : 'NOT READY'
      scene_state = @scene_ready ? 'READY' : (@scene_sending ? 'SENDING' : 'NOT READY')
      stats = @scene_stats || {}
      lines = [
        "#{EXTENSION_NAME} v#{VERSION}",
        '',
        "Engine: #{__FILE__}",
        "Mirror: #{record ? 'YES' : 'NO'}",
        "Renderer: #{renderer_state}",
        "Scene: #{scene_state}",
        "Triangles: #{stats[:triangles] || 0}",
        "Transparent triangles: #{stats[:transparent] || 0}",
        "Edge segments: #{stats[:edges] || 0}",
        "Shading: #{shading_enabled? ? 'ON' : 'OFF'}",
        "Edges: #{edges_enabled? ? 'ON' : 'OFF'}",
        "Scene truncated: #{stats[:truncated] ? 'YES' : 'NO'}",
        "Requested quality: #{quality}px",
        "Actual frame size: #{@last_frame_size || 0}px",
        "Renderer max size: #{@renderer_max_size || 0}px",
        "Live updates: #{live_enabled? ? 'ON' : 'OFF'}",
        "Native face material: #{@native_material_applied ? 'APPLIED (horizontal mirror remap)' : 'WAITING'}",
        "Overlay pipeline: DISABLED",
        "Last frame token: #{@last_frame_token || 0}",
        "Last frame PNG: #{@last_frame_bytes || 0} bytes",
        '',
        'Camera writes: NONE.',
        'Mirrored model geometry: NONE.',
        'Reflection source: private WebGL renderer -> native Face material texture.',
        'Final display path: Material#texture= + Face#position_material (Overlay bypassed, horizontal mirror remap).',
        'Mirror plane: derived from transformed polygon vertices (non-uniform-scale safe).',
        'Nested scene bounds pre-culling: ON (world-space safe; only groups fully behind mirror are skipped).',
        "Triangle scene budget: #{triangle_limit}",
        "Estimated simple triangles (kept whole): #{stats[:estimated_simple_triangles] || 0}",
        "Estimated dense triangles: #{stats[:estimated_dense_triangles] || 0}",
        "Dense LOD keep ratio: #{((stats[:dense_keep_ratio] || 1.0) * 100.0).round(1)}%",
        "Dense object threshold: #{DENSE_OBJECT_THRESHOLD} triangles per group/component subtree",
        "Adaptive triangles omitted: #{stats[:adaptive_decimated] || 0}",
        "Scene transfer: #{((@last_scene_json_bytes || 0) / 1_048_576.0).round(1)} MB JSON",
        "Reflection frustum culling: #{stats[:frustum_culling] ? 'ON' : 'OFF (accuracy mode)'}#{stats[:frustum_culling] ? " (#{REFLECTION_CULL_EXPANSION}x aperture)" : ""}",
        "Culled groups/components: #{stats[:culled_groups] || 0}",
        "Culled face triangles: #{stats[:culled_faces] || 0}",
        "Culled edges: #{stats[:culled_edges] || 0}",
        "Backing suppression: <= #{BACKING_MAX_DISTANCE.to_mm.round(1)} mm, coverage >= #{(BACKING_MIN_COVERAGE * 100).round}%",
        'Projection mode: MIRROR-APERTURE OFF-AXIS (exact planar reflection window).',
        'Native UV mapping: one complete 0..1 texture tile pinned to mirror rectangle.',
        'Raw frame orientation: mapped 1:1 (no extra Overlay modulation).',
        'Reflection render style: directional face shading + visible hard edges.'
      ]
      lines << "\nLast renderer error:\n#{@last_error}" if @last_error && !@last_error.empty?
      UI.messagebox(lines.join("\n"))
    end

    def report_error(title, error, popup = true)
      trace = error.backtrace ? error.backtrace.first(8).join("\n") : ''
      message = "#{EXTENSION_NAME} #{title}:\n#{error.class}: #{error.message}\n\n#{trace}"
      puts message
      UI.messagebox(message) if popup
    end

    def install_ui
      submenu = UI.menu('Extensions').add_submenu(EXTENSION_NAME)
      submenu.add_item('Make Projected Mirror from Selected Face') { make_mirror_from_selection }
      submenu.add_item('Refresh Reflection Now') { refresh_now }
      submenu.add_item('Show Raw Reflection Frame') { show_raw_reflection_frame }
      submenu.add_item('Rebuild Renderer Scene') { rebuild_renderer_scene(true) }
      submenu.add_item('Live Updates ON/OFF') { toggle_live }
      submenu.add_item('Shading ON/OFF') { toggle_shading }
      submenu.add_item('Edges ON/OFF') { toggle_edges }
      quality_menu = submenu.add_submenu('Reflection Quality')
      QUALITY_LEVELS.each do |q|
        label = case q
                when 2048 then '2048px (2K)'
                when 3072 then '3072px (Ultra)'
                when 4096 then '4096px (4K / Very Heavy)'
                else "#{q}px"
                end
        quality_menu.add_item(label) { set_quality(q) }
      end
      detail_menu = submenu.add_submenu('Scene Detail / Triangle Limit')
      TRIANGLE_LIMITS.each do |limit|
        label = case limit
                when 180_000 then '180k (Low / old limit)'
                when 350_000 then '350k (Medium)'
                when 600_000 then '600k (High - default)'
                when 900_000 then '900k (Max / heavy)'
                else limit.to_s
                end
        detail_menu.add_item(label) { set_triangle_limit(limit) }
      end
      submenu.add_separator
      submenu.add_item('Diagnostics') { diagnostics }
      submenu.add_item('Remove Projected Mirror') { remove_mirror }
      submenu.add_item('Clean Legacy v0.3 Artifacts') { cleanup_legacy_v03; model.active_view.invalidate }
      submenu.add_separator
      submenu.add_item('About v0.4.14') do
        UI.messagebox(
          "#{EXTENSION_NAME} v#{VERSION}\n\n" \
          "This engine does not move the SketchUp camera and does not create mirrored room geometry. It renders a reflected virtual view in a private WebGL renderer and applies the resulting image directly as a native SketchUp material on the selected mirror face. v0.4.18 improves adaptive scene LOD for complex models. High-poly groups and components are now recognized as whole objects, so dense models like furniture, fixtures or decorations are sampled object-wide instead of disappearing because each tiny face looked 'simple'. Low-poly architectural geometry is still kept complete.\n\n" \
          "v0.4.6 fixes the mapping stage: the private renderer now uses an exact asymmetric off-axis frustum through the selected mirror aperture, so the PNG corresponds 1:1 to the mirror surface. Overlay triangle winding is corrected toward the viewer and the texture U axis is flipped to match the virtual camera viewing the back side of the mirror. High-resolution modes up to 4096px remain available. SketchUp material image textures are not yet reproduced inside the private renderer."
        )
      end

      @toolbar = UI::Toolbar.new(EXTENSION_NAME)
      icon_dir = File.join(__dir__, 'icons')

      add_toolbar_command = lambda do |title, icon_name, tooltip, status, &block|
        cmd = UI::Command.new(title, &block)
        icon_path = File.join(icon_dir, "#{icon_name}.png")
        cmd.small_icon = icon_path if File.exist?(icon_path)
        cmd.large_icon = icon_path if File.exist?(icon_path)
        cmd.tooltip = tooltip
        cmd.status_bar_text = status
        @toolbar.add_item(cmd)
        cmd
      end

      make_cmd = add_toolbar_command.call(
        'Vytvořit zrcadlo', 'mirror_make',
        'Vytvořit zrcadlo z vybrané plochy',
        'Vybranou plochu nastaví jako živé 20-20 zrcadlo bez pohybu SketchUp kamery.'
      ) { make_mirror_from_selection }

      refresh_cmd = add_toolbar_command.call(
        'Obnovit odraz', 'mirror_refresh',
        'Obnovit odraz teď',
        'Okamžitě znovu vyrenderuje aktuální odraz.'
      ) { refresh_now }

      raw_cmd = add_toolbar_command.call(
        'Surový render', 'mirror_raw',
        'Zobrazit surový render odrazu',
        'Ukáže přesný obrázek vytvořený WebGL rendererem před aplikací na zrcadlo.'
      ) { show_raw_reflection_frame }

      rebuild_cmd = add_toolbar_command.call(
        'Načíst scénu', 'mirror_rebuild',
        'Znovu načíst scénu z modelu',
        'Znovu načte geometrii modelu do rendereru; použij po větších změnách modelu.'
      ) { rebuild_renderer_scene(true) }

      live_cmd = add_toolbar_command.call(
        'Živé aktualizace', 'mirror_live',
        'Živé aktualizace odrazu zapnout / vypnout',
        'Zapíná nebo vypíná automatické přepočítávání odrazu při pohybu kamery.'
      ) { toggle_live }
      live_cmd.set_validation_proc { live_enabled? ? MF_CHECKED : MF_UNCHECKED }

      shading_cmd = add_toolbar_command.call(
        'Stínování', 'mirror_shading',
        'Stínování v odrazu zapnout / vypnout',
        'Zapíná nebo vypíná směrové stínování ploch v odrazu.'
      ) { toggle_shading }
      shading_cmd.set_validation_proc { shading_enabled? ? MF_CHECKED : MF_UNCHECKED }

      edges_cmd = add_toolbar_command.call(
        'Hrany', 'mirror_edges',
        'Hrany v odrazu zapnout / vypnout',
        'Zapíná nebo vypíná tvrdé SketchUp hrany v odrazu.'
      ) { toggle_edges }
      edges_cmd.set_validation_proc { edges_enabled? ? MF_CHECKED : MF_UNCHECKED }

      diag_cmd = add_toolbar_command.call(
        'Diagnostika', 'mirror_diag',
        'Diagnostika Live Mirror',
        'Zobrazí stav rendereru, velikost scény, kvalitu a případné limity.'
      ) { diagnostics }

      remove_cmd = add_toolbar_command.call(
        'Odstranit zrcadlo', 'mirror_remove',
        'Odstranit živé zrcadlo',
        'Odstraní Live Mirror a vrátí původní materiál plochy.'
      ) { remove_mirror }

      @toolbar.restore

      install_overlay
      attach_view_observer
      ensure_renderer if load_mirror_record
    end

    unless file_loaded?(__FILE__)
      install_ui
      file_loaded(__FILE__)
    end
  end
end
