# frozen_string_literal: true

require 'sketchup.rb'
require 'json'
require 'fileutils'
require 'time'

module TwentyTwenty
  module AIModelExporter
    extend self

    VERSION = '0.1.0'.freeze
    M_TO_IN = 39.37007874015748
    IN_TO_M = 0.0254

    def init
      return if @loaded
      @loaded = true
      create_command
      create_menu
      create_toolbar
    end

    def create_command
      @command = UI::Command.new('AI Model Pack · FBX + GLB') { export_package }
      @command.tooltip = '20-20 AI Model Exporter · FBX + GLB + scény/kamery/materialy'
      @command.status_bar_text = 'Exportuje celý model pro AI workflow včetně metadat scén, kamer, tagů, hierarchie a materiálů.'
      icon = File.join(__dir__, 'icons', 'model_export.svg')
      if File.file?(icon)
        @command.small_icon = icon
        @command.large_icon = icon
      end
    end

    def create_menu
      root = UI.menu('Extensions').add_submenu('20-20 AI Model Exporter')
      root.add_item(@command)
    end

    def create_toolbar
      @toolbar = UI::Toolbar.new('20-20 AI Model Export')
      @toolbar.add_item(@command)
      @toolbar.restore
    rescue StandardError
      nil
    end

    def export_package
      model = Sketchup.active_model
      base_dir = model.path.to_s.empty? ? Dir.home : File.dirname(model.path)
      target_root = UI.select_directory(
        title: 'Vyber složku pro AI model package',
        directory: base_dir
      )
      return unless target_root

      base = safe_name(model)
      package_dir = unique_package_dir(target_root, "#{base}_AI_MODEL")
      FileUtils.mkdir_p(package_dir)

      fbx_path = File.join(package_dir, "#{base}.fbx")
      glb_path = File.join(package_dir, "#{base}.glb")

      progress('Exportuji FBX…')
      export_fbx(model, fbx_path)

      progress('Exportuji GLB…')
      glb_ok = export_glb(model, glb_path)

      progress('Zapisuji scény, kamery a strukturu…')
      payload = build_manifest(model, base, fbx_path, glb_ok ? glb_path : nil)
      File.write(
        File.join(package_dir, '20-20_model_manifest.json'),
        JSON.pretty_generate(payload)
      )

      File.write(
        File.join(package_dir, 'README_AI_IMPORT.txt'),
        readme_text(base, glb_ok)
      )

      progress('')
      files = ["#{base}.fbx"]
      files << "#{base}.glb" if glb_ok
      files << '20-20_model_manifest.json'
      files << 'README_AI_IMPORT.txt'

      UI.messagebox(
        "AI model package hotový.\n\n"         "#{package_dir}\n\n"         "#{files.join("\n")}\n\n"         "GLB = lehký model pro AI / realtime.\n"         "FBX = kompatibilní plný 3D export.\n"         "Manifest drží SketchUp scény, kamery, tagy, hierarchii a materiálová metadata."
      )
    rescue StandardError => e
      progress('')
      UI.messagebox(
        "AI Model Export selhal:\n#{e.class}: #{e.message}\n\n"         "Pokud selhal FBX kvůli konkrétní textuře, zkontroluj materiály bez platné obrazové přípony."
      )
    end

    def export_fbx(model, path)
      options = {
        units: 'm',
        triangulated_faces: true,
        doublesided_faces: true,
        texture_maps: true,
        separate_disconnected_faces: false,
        swap_yz: false,
        selectionset_only: false,
        show_summary: false
      }
      ok = model.export(path, options)
      raise 'SketchUp FBX exporter nevrátil platný soubor.' unless ok && File.file?(path) && File.size(path) > 0
      true
    end

    def export_glb(model, path)
      return false if Sketchup.version.to_i < 24
      ok = model.export(path, false)
      ok && File.file?(path) && File.size(path) > 0
    rescue ArgumentError, RuntimeError
      false
    end

    def build_manifest(model, base, fbx_path, glb_path)
      {
        schema: '20-20-ai-model-package',
        schema_version: 1,
        exporter: {
          name: '20-20 AI Model Exporter',
          version: VERSION,
          exported_at_utc: Time.now.utc.iso8601,
          sketchup_version: Sketchup.version.to_s
        },
        model: model_metadata(model, base),
        coordinate_system: {
          source: 'SketchUp',
          x_axis: 'X',
          y_axis: 'Y',
          z_axis: 'Z up',
          manifest_units: 'meters',
          fbx_units: 'meters',
          glb_units: 'meters'
        },
        files: {
          fbx: File.basename(fbx_path),
          glb: glb_path ? File.basename(glb_path) : nil
        },
        scenes: scene_metadata(model),
        tags: tag_metadata(model),
        materials: material_metadata(model),
        hierarchy: hierarchy_metadata(model),
        statistics: geometry_statistics(model)
      }
    end

    def model_metadata(model, base)
      bounds = model.bounds
      units = model.options['UnitsOptions'] rescue nil
      {
        name: base,
        title: model.title.to_s,
        source_skp: model.path.to_s.empty? ? nil : model.path.to_s,
        guid: (model.guid rescue nil),
        description: (model.description.to_s rescue ''),
        bounds_m: bounds_hash(bounds),
        units: units ? {
          length_unit: safe_option(units, 'LengthUnit'),
          length_format: safe_option(units, 'LengthFormat'),
          length_precision: safe_option(units, 'LengthPrecision'),
          suppress_units_display: safe_option(units, 'SuppressUnitsDisplay')
        } : {},
        georeferenced: (model.georeferenced? rescue false),
        attributes: attribute_dictionaries_hash(model)
      }
    end

    def scene_metadata(model)
      model.pages.each_with_index.map do |page, index|
        camera = page.camera
        {
          index: index,
          name: page.name.to_s,
          label: (page.label.to_s rescue page.name.to_s),
          description: (page.description.to_s rescue ''),
          include_in_animation: (page.include_in_animation? rescue true),
          delay_time_s: (page.delay_time.to_f rescue nil),
          transition_time_s: (page.transition_time.to_f rescue nil),
          use_camera: (page.use_camera? rescue true),
          use_tag_visibility: (page.use_hidden_layers? rescue false),
          use_hidden_geometry: (page.use_hidden_geometry? rescue false),
          use_hidden_objects: (page.use_hidden_objects? rescue false),
          use_section_planes: (page.use_section_planes? rescue false),
          camera: camera_hash(camera),
          axes: axes_hash((page.axes rescue nil)),
          visible_tags: scene_visible_tags(model, page),
          hidden_top_level_entities: scene_hidden_entities(page),
          active_section_planes: scene_section_planes(page),
          style: scene_style(page)
        }
      end
    end

    def camera_hash(camera)
      return nil unless camera
      data = {
        eye_m: point_m(camera.eye),
        target_m: point_m(camera.target),
        up: vector(camera.up),
        direction: vector(camera.direction),
        xaxis: vector(camera.xaxis),
        yaxis: vector(camera.yaxis),
        zaxis: vector(camera.zaxis),
        perspective: (camera.perspective? rescue true),
        two_point_perspective: (camera.is_2d? rescue false),
        fov_deg: (camera.fov.to_f rescue nil),
        aspect_ratio: (camera.aspect_ratio.to_f rescue 0.0),
        image_width: (camera.image_width.to_f rescue nil),
        description: (camera.description.to_s rescue '')
      }
      data[:height_m] = camera.height.to_f * IN_TO_M if !data[:perspective] && camera.respond_to?(:height)
      data
    end

    def axes_hash(axes)
      return nil unless axes
      {
        origin_m: point_m(axes.origin),
        xaxis: vector(axes.xaxis),
        yaxis: vector(axes.yaxis),
        zaxis: vector(axes.zaxis)
      }
    rescue StandardError
      nil
    end

    def scene_visible_tags(model, page)
      model.layers.map do |layer|
        {
          name: layer.display_name.to_s,
          internal_name: layer.name.to_s,
          visible: layer_visible_in_page?(layer, page)
        }
      end
    end

    def layer_visible_in_page?(layer, page)
      return layer.visible? unless page.use_hidden_layers?
      hidden_by_default = (layer.page_behavior & LAYER_HIDDEN_BY_DEFAULT) == LAYER_HIDDEN_BY_DEFAULT
      page.layers.include?(layer) == hidden_by_default
    rescue StandardError
      layer.visible? rescue true
    end

    def scene_hidden_entities(page)
      Array(page.hidden_entities).map do |entity|
        {
          persistent_id: (entity.persistent_id rescue nil),
          entity_id: (entity.entityID rescue nil),
          type: entity.typename.to_s,
          name: entity_name(entity)
        }
      end
    rescue StandardError
      []
    end

    def scene_section_planes(page)
      Array(page.active_section_planes).map do |plane|
        {
          persistent_id: (plane.persistent_id rescue nil),
          name: entity_name(plane),
          symbol: (plane.symbol.to_s rescue nil),
          plane: (plane.get_plane.map(&:to_f) rescue nil)
        }
      end
    rescue StandardError
      []
    end

    def scene_style(page)
      style = page.style rescue nil
      return nil unless style
      {
        name: (style.display_name.to_s rescue style.name.to_s),
        description: (style.description.to_s rescue '')
      }
    rescue StandardError
      nil
    end

    def tag_metadata(model)
      model.layers.map do |layer|
        folder = layer.folder rescue nil
        {
          name: layer.display_name.to_s,
          internal_name: layer.name.to_s,
          visible_now: (layer.visible? rescue true),
          folder: folder_path(folder),
          color: color_hash((layer.color rescue nil))
        }
      end
    end

    def folder_path(folder)
      parts = []
      seen = {}
      while folder && !seen[folder.object_id]
        seen[folder.object_id] = true
        parts.unshift(folder.name.to_s)
        folder = folder.folder rescue nil
      end
      parts
    rescue StandardError
      []
    end

    def material_metadata(model)
      model.materials.map do |material|
        texture = material.texture rescue nil
        entry = {
          name: material.display_name.to_s,
          internal_name: material.name.to_s,
          color: color_hash((material.color rescue nil)),
          alpha: (material.alpha.to_f rescue 1.0),
          material_type: (material.materialType.to_i rescue nil),
          texture: texture_hash(texture),
          pbr: pbr_material_hash(material),
          attributes: attribute_dictionaries_hash(material)
        }
        entry
      end
    end

    def pbr_material_hash(material)
      data = {}
      if material.respond_to?(:workflow)
        data[:workflow] = material.workflow rescue nil
      end
      if material.respond_to?(:metalness_enabled?)
        data[:metalness_enabled] = material.metalness_enabled? rescue nil
        data[:metallic_factor] = material.metallic_factor.to_f rescue nil
        data[:metallic_texture] = texture_hash((material.metallic_texture rescue nil))
      end
      if material.respond_to?(:roughness_enabled?)
        data[:roughness_enabled] = material.roughness_enabled? rescue nil
        data[:roughness_factor] = material.roughness_factor.to_f rescue nil
        data[:roughness_texture] = texture_hash((material.roughness_texture rescue nil))
      end
      if material.respond_to?(:normal_enabled?)
        data[:normal_enabled] = material.normal_enabled? rescue nil
        data[:normal_scale] = material.normal_scale.to_f rescue nil
        data[:normal_style] = material.normal_style rescue nil
        data[:normal_texture] = texture_hash((material.normal_texture rescue nil))
      end
      if material.respond_to?(:ao_enabled?)
        data[:ao_enabled] = material.ao_enabled? rescue nil
        data[:ao_strength] = material.ao_strength.to_f rescue nil
        data[:ao_texture] = texture_hash((material.ao_texture rescue nil))
      end
      data
    end

    def texture_hash(texture)
      return nil unless texture
      {
        filename: (texture.filename.to_s rescue ''),
        width_m: (texture.width.to_f * IN_TO_M rescue nil),
        height_m: (texture.height.to_f * IN_TO_M rescue nil),
        image_width_px: (texture.image_width.to_i rescue nil),
        image_height_px: (texture.image_height.to_i rescue nil)
      }
    end

    def hierarchy_metadata(model)
      model.entities.map { |entity| hierarchy_entity(entity, Geom::Transformation.new, 0) }.compact
    end

    def hierarchy_entity(entity, parent_transform, depth)
      return nil if depth > 64
      common = {
        type: entity.typename.to_s,
        persistent_id: (entity.persistent_id rescue nil),
        entity_id: (entity.entityID rescue nil),
        name: entity_name(entity),
        tag: (entity.layer.display_name.to_s rescue nil),
        hidden: (entity.hidden? rescue false),
        material: material_name((entity.material rescue nil))
      }

      case entity
      when Sketchup::Group
        tr = parent_transform * entity.transformation
        common.merge(
          transformation: transformation_hash(tr),
          bounds_m: transformed_bounds_hash(entity.bounds, parent_transform),
          children: entity.entities.map { |child| hierarchy_entity(child, tr, depth + 1) }.compact
        )
      when Sketchup::ComponentInstance
        tr = parent_transform * entity.transformation
        definition = entity.definition
        common.merge(
          definition_name: definition.name.to_s,
          definition_guid: (definition.guid.to_s rescue nil),
          transformation: transformation_hash(tr),
          bounds_m: transformed_bounds_hash(entity.bounds, parent_transform),
          children: definition.entities.map { |child| hierarchy_entity(child, tr, depth + 1) }.compact
        )
      when Sketchup::Face
        common.merge(
          front_material: material_name(entity.material),
          back_material: material_name(entity.back_material),
          area_m2: entity.area.to_f * IN_TO_M * IN_TO_M
        )
      when Sketchup::Edge
        common.merge(length_m: entity.length.to_f * IN_TO_M)
      else
        common
      end
    rescue StandardError
      common || nil
    end

    def geometry_statistics(model)
      definitions = model.definitions.reject { |d| d.image? rescue false }
      {
        root_entities: model.entities.length,
        faces_total: model.number_faces,
        materials: model.materials.length,
        tags: model.layers.length,
        scenes: model.pages.length,
        component_definitions: definitions.length,
        component_instances: count_instances(model.entities),
        groups: count_groups(model.entities)
      }
    end

    def count_instances(entities, seen = {})
      total = 0
      entities.each do |entity|
        if entity.is_a?(Sketchup::ComponentInstance) && !entity.is_a?(Sketchup::Group)
          total += 1
          definition = entity.definition
          next if seen[definition.object_id]
          seen[definition.object_id] = true
          total += count_instances(definition.entities, seen)
        elsif entity.is_a?(Sketchup::Group)
          total += count_instances(entity.entities, seen)
        end
      end
      total
    rescue StandardError
      total
    end

    def count_groups(entities, seen = {})
      total = 0
      entities.each do |entity|
        if entity.is_a?(Sketchup::Group)
          total += 1
          total += count_groups(entity.entities, seen)
        elsif entity.is_a?(Sketchup::ComponentInstance)
          definition = entity.definition
          next if seen[definition.object_id]
          seen[definition.object_id] = true
          total += count_groups(definition.entities, seen)
        end
      end
      total
    rescue StandardError
      total
    end

    def transformation_hash(transform)
      arr = transform.to_a.map(&:to_f)
      meters = arr.dup
      [12, 13, 14].each { |index| meters[index] *= IN_TO_M }
      {
        matrix_sketchup_inches: arr,
        matrix_meters: meters,
        origin_m: point_m(transform.origin),
        xaxis: vector(transform.xaxis),
        yaxis: vector(transform.yaxis),
        zaxis: vector(transform.zaxis)
      }
    end

    def transformed_bounds_hash(bounds, parent_transform)
      points = (0..7).map { |i| bounds.corner(i).transform(parent_transform) }
      xs = points.map(&:x)
      ys = points.map(&:y)
      zs = points.map(&:z)
      {
        min: [xs.min * IN_TO_M, ys.min * IN_TO_M, zs.min * IN_TO_M],
        max: [xs.max * IN_TO_M, ys.max * IN_TO_M, zs.max * IN_TO_M]
      }
    rescue StandardError
      bounds_hash(bounds)
    end

    def bounds_hash(bounds)
      {
        min: point_m(bounds.min),
        max: point_m(bounds.max),
        center: point_m(bounds.center),
        width: bounds.width.to_f * IN_TO_M,
        height: bounds.height.to_f * IN_TO_M,
        depth: bounds.depth.to_f * IN_TO_M
      }
    rescue StandardError
      nil
    end

    def point_m(point)
      [point.x.to_f * IN_TO_M, point.y.to_f * IN_TO_M, point.z.to_f * IN_TO_M]
    end

    def vector(value)
      [value.x.to_f, value.y.to_f, value.z.to_f]
    end

    def color_hash(color)
      return nil unless color
      {
        r: color.red.to_i,
        g: color.green.to_i,
        b: color.blue.to_i,
        a: (color.alpha.to_i rescue 255)
      }
    end

    def material_name(material)
      material ? material.display_name.to_s : nil
    rescue StandardError
      nil
    end

    def entity_name(entity)
      if entity.respond_to?(:name) && !entity.name.to_s.empty?
        entity.name.to_s
      elsif entity.respond_to?(:definition) && entity.definition && !entity.definition.name.to_s.empty?
        entity.definition.name.to_s
      else
        ''
      end
    rescue StandardError
      ''
    end

    def attribute_dictionaries_hash(object)
      dictionaries = object.attribute_dictionaries rescue nil
      return {} unless dictionaries
      dictionaries.each_with_object({}) do |dict, output|
        next if dict.name.to_s.start_with?('_')
        values = {}
        dict.each_pair do |key, value|
          safe = json_safe(value)
          values[key.to_s] = safe unless safe == :__unsupported__
        end
        output[dict.name.to_s] = values unless values.empty?
      end
    rescue StandardError
      {}
    end

    def json_safe(value, depth = 0)
      return :__unsupported__ if depth > 5
      case value
      when NilClass, TrueClass, FalseClass, String, Integer, Float
        value
      when Length
        value.to_f * IN_TO_M
      when Geom::Point3d
        point_m(value)
      when Geom::Vector3d
        vector(value)
      when Array
        value.map { |item| json_safe(item, depth + 1) }.reject { |item| item == :__unsupported__ }
      when Hash
        value.each_with_object({}) do |(key, item), output|
          safe = json_safe(item, depth + 1)
          output[key.to_s] = safe unless safe == :__unsupported__
        end
      else
        value.to_s
      end
    rescue StandardError
      :__unsupported__
    end

    def safe_option(provider, key)
      provider[key]
    rescue StandardError
      nil
    end

    def readme_text(base, glb_ok)
      <<~TXT
        20-20 AI MODEL PACKAGE
        ======================

        #{base}.fbx
        - Compatibility export.
        - Geometry is triangulated.
        - Materials and texture maps are included by SketchUp's FBX exporter.
        - Units: meters.

        #{glb_ok ? "#{base}.glb" : '(GLB nebyl v této verzi SketchUpu dostupný)'}
        - Recommended lightweight/realtime/AI model format.
        - Single binary file.
        - SketchUp 2024+ GLB exporter supports modern material data.

        20-20_model_manifest.json
        - SketchUp scenes and camera positions.
        - Camera eye / target / up / FOV.
        - Scene tag visibility and section planes.
        - Full model tag list.
        - Material and texture metadata, including PBR fields where available.
        - Group/component hierarchy and world transforms.
        - Model bounds and basic statistics.

        IMPORTANT
        =========
        FBX and GLB are interchange formats and do not reliably preserve every SketchUp
        scene-tab property in a way every target application understands. The manifest
        is the authoritative source for reconstructing SketchUp scenes/cameras/tags in
        the receiving AI application.

        Recommended importer behavior:
        1. Prefer GLB for fast loading; use FBX as compatibility fallback.
        2. Read 20-20_model_manifest.json.
        3. Recreate cameras from scenes[].camera.
        4. Recreate scene visibility using scenes[].visible_tags.
        5. Keep original object/component names from the 3D file and hierarchy manifest.
      TXT
    end

    def safe_name(model)
      value = File.basename(model.path.to_s, '.*')
      value = model.title.to_s if value.empty?
      value = 'sketchup_model' if value.empty?
      value.gsub(/[^0-9A-Za-z._-]+/, '_')[0, 96]
    end

    def unique_package_dir(parent, name)
      path = File.join(parent, name)
      return path unless File.exist?(path)
      stamp = Time.now.strftime('%Y%m%d_%H%M%S')
      File.join(parent, "#{name}_#{stamp}")
    end

    def progress(text)
      Sketchup.status_text = text.to_s
    rescue StandardError
      nil
    end
  end
end

TwentyTwenty::AIModelExporter.init
