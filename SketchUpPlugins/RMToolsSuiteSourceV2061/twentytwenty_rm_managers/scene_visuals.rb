# frozen_string_literal: true
require 'base64'
require 'fileutils'
require 'digest/sha1'

module TwentyTwenty
  module RMManagers
    module SceneVisuals
      extend self
      SECTION_LIMIT = 4000
      def preview_dir(model)
        # Each project has its own disk cache; snapshots need not be stored in SKP attributes.
        project = model.path.to_s.empty? ? model.guid.to_s : File.expand_path(model.path)
        platform_root = if Sketchup.platform == :platform_win
          ENV['LOCALAPPDATA'] || ENV['APPDATA'] || Sketchup.temp_dir
        else
          File.expand_path('~/Library/Caches')
        end
        root = File.join(platform_root, '20-20', 'RMTools', 'ScenePreviews', Digest::SHA1.hexdigest(project))
        FileUtils.mkdir_p(root)
        root
      end
      def page_key(page)
        id = TwentyTwenty::RMManagers.scene_id(page)
        Digest::SHA1.hexdigest(id)
      end
      def file_for(model, page)
        File.join(preview_dir(model), page_key(page) + '.png')
      end
      def preview_base64(model, page)
        file = file_for(model, page)
        return nil unless File.file?(file)
        stat = File.stat(file)
        @preview_cache ||= {}
        saved = @preview_cache[file]
        if saved && saved[0] == stat.size && saved[1] == stat.mtime.to_f
          return saved[2]
        end
        result = 'data:image/png;base64,' + Base64.strict_encode64(File.binread(file))
        @preview_cache[file] = [stat.size, stat.mtime.to_f, result]
        result
      rescue StandardError => e
        puts "[RM SCENES] Náhled nelze přečíst: #{e.message}"
        nil
      end
      def capture(model, page)
        file = file_for(model, page)
        # Call when current viewport displays the exact scene to be saved.
        # write_image is intentionally done AFTER applying the scene's changes.
        ratio = model.active_view.camera.aspect_ratio.to_f
        ratio = 16.0 / 9.0 if ratio <= 0
        height = [[(320.0 / ratio).round, 160].max, 550].min
        opts = {filename: file, width: 320, height: height, antialias: true}
        model.active_view.invalidate
        result = model.active_view.write_image(opts)
        raise 'SketchUp neuložil obrázek náhledu.' unless result && File.file?(file)
        @preview_cache.delete(file) if @preview_cache
        true
      rescue StandardError => e
        puts "[RM SCENES] Náhled #{page.name}: #{e.message}"
        false
      end
      def clear(model, page)
        file = file_for(model, page)
        File.delete(file) if File.file?(file)
        @preview_cache.delete(file) if @preview_cache
      rescue StandardError
        nil
      end

      def slice_segments(entities, transformation, z, segments, visited, depth, budget)
        return if depth > 5 || segments.length > SECTION_LIMIT
        entities.each do |entity|
          break if segments.length > SECTION_LIMIT || budget[0] <= 0
          budget[0] -= 1
          next unless entity.valid? && !(entity.respond_to?(:hidden?) && entity.hidden?)
          if entity.is_a?(Sketchup::Face)
            vertices = entity.outer_loop.vertices.map { |v| v.position.transform(transformation) }
            hits = []
            vertices.each_with_index do |a, i|
              b = vertices[(i + 1) % vertices.length]
              delta_a = a.z.to_f - z
              delta_b = b.z.to_f - z
              if delta_a.abs < 0.001 && delta_b.abs < 0.001
                segments << [a.x.to_f, a.y.to_f, b.x.to_f, b.y.to_f]
              elsif (delta_a < 0 && delta_b > 0) || (delta_a > 0 && delta_b < 0)
                t = -delta_a / (delta_b - delta_a)
                hits << [a.x.to_f + t*(b.x-a.x), a.y.to_f + t*(b.y-a.y)]
              elsif delta_a.abs < 0.001
                hits << [a.x.to_f, a.y.to_f]
              end
            end
            hits = hits.uniq
            # Pair intersections of outer loops. This represents a horizontal
            # planar section, not occlusion-rendered floor plan.
            hits.each_slice(2) do |pair|
              segments << [*pair[0], *pair[1]] if pair.length == 2
            end
          elsif entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
            next if visited.include?(entity.definition.object_id)
            slice_segments(entity.definition.entities, transformation * entity.transformation, z,
                           segments, visited + [entity.definition.object_id], depth + 1, budget)
          end
        end
      end
      def section_map(model)
        bb = model.bounds
        return {segments:[], bounds:[0,0,1,1], cut_z:0, truncated:false} unless bb.valid?
        z = bb.min.z.to_f + 2000.mm.to_f
        segments = []
        budget = [14000]
        begin
          slice_segments(model.entities, Geom::Transformation.new, z, segments, [], 0, budget)
        rescue StandardError => e
          puts "[RM SCENES] Půdorysný řez: #{e.message}"
        end
        # Use model bounds as a stable minimap coordinate system so dots do not jump.
        minx, miny, maxx, maxy = bb.min.x.to_f, bb.min.y.to_f, bb.max.x.to_f, bb.max.y.to_f
        dx = [maxx-minx, 10.0].max
        dy = [maxy-miny, 10.0].max
        pad = [dx, dy].max*0.08
        {segments:segments.first(SECTION_LIMIT).map { |r| r.map { |v| v.round(2) } },
         bounds:[minx-pad, miny-pad, maxx+pad, maxy+pad],
         cut_z:z.round(1), truncated:segments.length>SECTION_LIMIT || budget[0]<=0}
      end
    end
  end
end
