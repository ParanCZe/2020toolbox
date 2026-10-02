# frozen_string_literal: true
require 'json'
require 'base64'
require 'digest/sha1'
require 'fileutils'

module TwentyTwenty
  module RMManagers
    module Floorplan
      extend self
      # One initial camera gets a readable local plan, rather than model extents.
      CAMERA_PADDING = 15.m
      MIN_DIAMETER = 40.m

      def cache_dir(model)
        base = Sketchup.platform == :platform_win ?
          (ENV['LOCALAPPDATA'] || ENV['APPDATA'] || Sketchup.temp_dir) :
          File.expand_path('~/Library/Caches')
        identity = model.path.to_s.empty? ? model.guid.to_s : File.expand_path(model.path)
        dir = File.join(base, '20-20', 'RMTools', 'Plans', Digest::SHA1.hexdigest(identity))
        FileUtils.mkdir_p(dir)
        dir
      end
      def raster_file(model); File.join(cache_dir(model), 'floorplan-camera-region.png'); end
      def meta_file(model); File.join(cache_dir(model), 'floorplan-camera-region.json'); end
      def last_error(model)
        (@errors ||= {})[model.object_id]
      end
      def set_error(model, reason)
        (@errors ||= {})[model.object_id] = reason
      end
      def cameras(model)
        views = model.pages.to_a.map(&:camera)
        views = [model.active_view.camera] if views.empty?
        views.map(&:eye)
      end
      def camera_region(model)
        pts = cameras(model)
        # Include up to 15 m in front of each camera so the building being
        # photographed appears on the plan, even if the camera stands outside.
        views = model.pages.to_a.map(&:camera)
        views = [model.active_view.camera] if views.empty?
        focus = views.map do |camera|
          dir = camera.direction
          norm = Math.sqrt(dir.x.to_f**2 + dir.y.to_f**2)
          norm > 0.0001 ?
            [camera.eye.x + dir.x.to_f/norm*15.m, camera.eye.y + dir.y.to_f/norm*15.m] :
            [camera.eye.x, camera.eye.y]
        end
        xs = pts.map(&:x) + focus.map(&:first)
        ys = pts.map(&:y) + focus.map(&:last)
        # Fixed padding; irrelevant stray geometry never expands the map.
        xmin, xmax = xs.min - CAMERA_PADDING, xs.max + CAMERA_PADDING
        ymin, ymax = ys.min - CAMERA_PADDING, ys.max + CAMERA_PADDING
        midx, midy = (xmin + xmax)/2.0, (ymin + ymax)/2.0
        halfw = [(xmax - xmin)/2.0, MIN_DIAMETER/2.0].max
        halfh = [(ymax - ymin)/2.0, MIN_DIAMETER/2.0].max
        [midx-halfw, midy-halfh, midx+halfw, midy+halfh]
      end
      def cut_height(model)
        bb = model.bounds
        first = cameras(model).first
        # A remote discarded component can also poison the Z extents.
        if bb.valid? && (first.z - bb.min.z).abs < 15.m
          bb.min.z + 2.m
        else
          first.z + 0.2.m # camera assumed approximately 1.8 m above nearby ground
        end
      end
      def cached_data(model)
        image, metadata = raster_file(model), meta_file(model)
        return nil unless File.file?(image) && File.file?(metadata)
        info = JSON.parse(File.read(metadata))
        return nil unless info['rect'] && info['region'] && info['width'].to_i > 0
        stat = File.stat(image)
        @cache ||= {}
        entry = @cache[image]
        if !entry || entry[0] != stat.size || entry[1] != stat.mtime.to_f
          @cache[image] = [stat.size, stat.mtime.to_f,
            'data:image/png;base64,' + Base64.strict_encode64(File.binread(image))]
        end
        {image: @cache[image][2], rect: info['rect'], region: info['region'],
         width: info['width'], height: info['height'], cut_z: info['cut_z']}
      rescue StandardError => e
        set_error(model, "Mezipaměť půdorysu: #{e.message}")
        nil
      end
      def needs_rebuild?(model)
        data = cached_data(model)
        return true unless data
        region = data[:region]
        # Grow only after a camera leaves the currently rendered area.
        candidate = camera_region(model)
        # Don't regenerate after tiny edits. Each saved region already has 15 m
        # padding; expand only when a camera/gaze approaches the map boundary.
        candidate.each_with_index.any? do |edge,index|
          index < 2 ? edge < region[index]-5.m : edge > region[index]+5.m
        end
      end
      def build(model, &callback)
        @jobs ||= {}
        if @jobs.key?(model.object_id)
          set_error(model, 'Půdorys se už generuje. Chvíli počkej.')
          return false
        end
        view = model.active_view
        unless model.active_path.nil? || model.active_path.empty?
          raise 'Nejdřív ukonči editaci vnořené komponenty.'
        end
        region = camera_region(model)
        z = cut_height(model)
        cx, cy = (region[0]+region[2])/2.0, (region[1]+region[3])/2.0
        span = [region[2]-region[0],region[3]-region[1]].max
        original_camera = view.camera.clone
        old_section = (model.entities.active_section_plane rescue nil)
        options = model.rendering_options
        original_flags = {}
        %w[DisplaySectionCuts DisplaySectionPlanes].each do |key|
          begin original_flags[key] = options[key] rescue nil end
        end
        job = {model:model, camera:original_camera, section:old_section,
               options:options, flags:original_flags, callback:callback}
        @jobs[model.object_id] = job
        set_error(model, nil)
        begin
          plane = model.entities.add_section_plane(
            Geom::Point3d.new(cx,cy,z), Geom::Vector3d.new(0,0,-1))
          job[:temporary] = plane
          plane.activate
          options['DisplaySectionCuts'] = true
          options['DisplaySectionPlanes'] = false
          top = Sketchup::Camera.new(
            Geom::Point3d.new(cx,cy,z+span*2.5),
            Geom::Point3d.new(cx,cy,z), Geom::Vector3d.new(0,1,0))
          top.perspective = false
          view.camera = top
          # The two corners constrain the viewport to the CAMERA region only.
          box = Geom::BoundingBox.new
          box.add(Geom::Point3d.new(region[0],region[1],z))
          box.add(Geom::Point3d.new(region[2],region[3],z+1.mm))
          view.zoom(box)
          view.invalidate
          UI.start_timer(0.3,false) do
            begin
              raise 'Během generování se změnil aktivní model.' unless Sketchup.active_model.equal?(model)
              width = [view.vpwidth.to_i, 100].max
              height = [view.vpheight.to_i, 100].max
              center = Geom::Point3d.new(cx,cy,z)
              px = Geom::Point3d.new(cx+1.m,cy,z)
              py = Geom::Point3d.new(cx,cy+1.m,z)
              a,b,c = [center,px,py].map { |p| view.screen_coords(p) }
              rect = {'origin'=>[a.x.to_f/width,a.y.to_f/height],
                      'xaxis'=>[(b.x-a.x).to_f/width,(b.y-a.y).to_f/height],
                      'yaxis'=>[(c.x-a.x).to_f/width,(c.y-a.y).to_f/height],
                      'world_center'=>[cx.to_f,cy.to_f], 'world_unit'=>1.m.to_f}
              path = raster_file(model)
              ok = begin
                view.write_image(filename:path, width:width, height:height, antialias:false)
              rescue ArgumentError
                view.write_image(path)
              end
              raise 'SketchUp neuložil obrázek. Zkontroluj práva zápisu do místní složky.' unless ok && File.file?(path) && File.size(path)>0
              File.write(meta_file(model),JSON.generate({'rect'=>rect,'region'=>region.map(&:to_f),
                'cut_z'=>z.to_f,'width'=>width,'height'=>height}))
              @cache.delete(path) if @cache
              job[:success] = true
            rescue StandardError => e
              set_error(model,"#{e.class}: #{e.message}")
              puts "[RM FLOORPLAN] #{e.class}: #{e.message}\n#{e.backtrace&.first(6)&.join("\n")}"
            ensure
              restore(job)
            end
          end
        rescue StandardError => e
          set_error(model,"#{e.class}: #{e.message}")
          restore(job)
          raise
        end
        true
      end
      def restore(job)
        return if job[:restored]
        job[:restored] = true
        model = job[:model]
        begin
          if Sketchup.active_model.equal?(model)
            plane = job[:temporary]
            plane.erase! if plane && plane.valid?
            section = job[:section]
            section.activate if section && section.valid?
            model.active_view.camera = job[:camera]
            model.active_view.invalidate
          end
        rescue StandardError => e
          puts "[RM FLOORPLAN] Restore: #{e.message}"
        ensure
          job[:flags].each do |key,value|
            begin job[:options][key] = value unless value.nil? rescue nil end
          end
          @jobs.delete(model.object_id) if @jobs
          job[:callback].call(!!job[:success],last_error(model)) if job[:callback]
        end
      end
    end
  end
end
