# frozen_string_literal: true
require 'json'
require 'base64'
require 'digest/sha1'
require 'fileutils'

module TwentyTwenty
  module RMManagers
    module Floorplan
      extend self
      def cache_dir(model)
        root = if Sketchup.platform == :platform_win
                 ENV['LOCALAPPDATA'] || ENV['APPDATA'] || Sketchup.temp_dir
               else
                 File.expand_path('~/Library/Caches')
               end
        key = Digest::SHA1.hexdigest(model.path.to_s.empty? ? model.guid.to_s : File.expand_path(model.path))
        path = File.join(root, '20-20', 'RMTools', 'Plans', key)
        FileUtils.mkdir_p(path)
        path
      end
      def raster_file(model); File.join(cache_dir(model), 'section-2m.png'); end
      def meta_file(model); File.join(cache_dir(model), 'section-2m.json'); end
      def cached_data(model)
        image = raster_file(model)
        meta = meta_file(model)
        return nil unless File.file?(image) && File.file?(meta)
        m = JSON.parse(File.read(meta))
        return nil unless m['width'].to_i > 0 && m['height'].to_i > 0
        stat = File.stat(image)
        @cache ||= {}
        slot = @cache[image]
        if !slot || slot[:size] != stat.size || slot[:mtime] != stat.mtime.to_f
          @cache[image] = {size:stat.size, mtime:stat.mtime.to_f,
                           src:'data:image/png;base64,'+Base64.strict_encode64(File.binread(image))}
        end
        {image:@cache[image][:src], rect:m['rect'], width:m['width'],height:m['height'],
         cut_z:m['cut_z'], generated_at:m['generated_at']}
      rescue StandardError => e
        puts "[RM PLAN] Cache: #{e.class}: #{e.message}"
        nil
      end

      def build(model, &on_complete)
        @jobs ||= {}
        key = model.object_id
        return if @jobs[key]
        view = model.active_view
        bounds = model.bounds
        raise 'Model je prázdný; půdorys nelze vytvořit.' unless bounds.valid?
        raise 'Zavři editaci komponenty před vytvořením půdorysu.' if model.active_path && !model.active_path.empty?
        # Rendering the REAL SketchUp viewport with a temporary active section
        # yields actual wall cuts, furniture, floors and materials, unlike
        # manually intersecting face edges.
        camera_before = view.camera
        current_section = model.entities.active_section_plane
        rendering = model.rendering_options
        flags = {}
        %w[DisplaySectionCuts DisplaySectionPlanes SectionCutFilled].each do |name|
          begin
            flags[name] = rendering[name]
          rescue StandardError
            # Some SketchUp releases do not support every rendering key.
          end
        end
        z = bounds.min.z + 2000.mm
        dx = [bounds.max.x - bounds.min.x, 3000.mm].max
        dy = [bounds.max.y - bounds.min.y, 3000.mm].max
        cx = (bounds.max.x + bounds.min.x) / 2
        cy = (bounds.max.y + bounds.min.y) / 2
        size = [dx,dy].max
        job = {model:model, view:view, camera:camera_before, original_section:current_section,
               rendering:rendering, flags:flags, finished:false, callback:on_complete}
        @jobs[key] = job
        model.start_operation('RM dočasný půdorysný řez', true)
        begin
          section = model.entities.add_section_plane(Geom::Point3d.new(cx,cy,z), Geom::Vector3d.new(0,0,-1))
          section.name = 'RM TEMP FLOORPLAN (not saved)' if section.respond_to?(:name=)
          section.activate
          section.hidden = true
          rendering['DisplaySectionCuts'] = true
          rendering['DisplaySectionPlanes'] = false
          # Let SketchUp preserve user's desired lineweights and filled sections.
          top = Sketchup::Camera.new(Geom::Point3d.new(cx,cy,z+size*3),
                                    Geom::Point3d.new(cx,cy,z),
                                    Geom::Vector3d.new(0,1,0))
          top.perspective = false
          view.camera = top
          # Fit XY only: building height must not shrink a top-down plan.
          flat_bounds = Geom::BoundingBox.new
          flat_bounds.add(Geom::Point3d.new(bounds.min.x,bounds.min.y,z))
          flat_bounds.add(Geom::Point3d.new(bounds.max.x,bounds.max.y,z+10.mm))
          view.zoom(flat_bounds)
          view.invalidate
          # Screen positions and pixels MUST use the same viewport dimensions.
          # Screenshot is deferred one repaint; the viewport is restored in ensure.
          UI.start_timer(0.25,false) do
            begin
              raise 'Aktivní model se během generování změnil.' unless Sketchup.active_model.equal?(model)
              vpw = [view.vpwidth.to_i, 1].max
              vph = [view.vpheight.to_i, 1].max
              # Capture normalized placement using the exact camera at render.
              center = Geom::Point3d.new(cx,cy,z)
              ex = Geom::Point3d.new(cx+1000.mm,cy,z)
              ey = Geom::Point3d.new(cx,cy+1000.mm,z)
              c = view.screen_coords(center)
              x = view.screen_coords(ex)
              y = view.screen_coords(ey)
              # World => fractional screenshot coordinates. Valid for all
              # camera markers independently of the min/max of model bounds.
              rect = {
                'origin'=>[c.x.to_f/vpw,c.y.to_f/vph],
                'xaxis'=>[(x.x-c.x).to_f/vpw,(x.y-c.y).to_f/vph],
                'yaxis'=>[(y.x-c.x).to_f/vpw,(y.y-c.y).to_f/vph],
                'world_center'=>[cx.to_f,cy.to_f],
                'world_unit'=>1000.mm.to_f
              }
              image = raster_file(model)
              ok = view.write_image(filename:image,width:vpw,height:vph,antialias:false)
              raise 'SketchUp nevytvořil obrázek půdorysu.' unless ok && File.file?(image)
              File.write(meta_file(model), JSON.generate({rect:rect,width:vpw,height:vph,
                cut_z:z.to_f,generated_at:Time.now.to_i}))
              @cache.delete(image) if @cache
              job[:finished] = true
            rescue StandardError => e
              puts "[RM PLAN] Generation: #{e.class}: #{e.message}\n#{e.backtrace&.first(4)&.join("\n")}"
              job[:error] = e.message
            ensure
              restore(job)
            end
          end
        rescue StandardError
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
            job[:view].camera = job[:camera]
            job[:view].invalidate
            job[:original_section].activate if job[:original_section] && job[:original_section].valid?
          end
        rescue StandardError => e
          puts "[RM PLAN] Camera restoration: #{e.message}"
        ensure
          begin model.abort_operation rescue nil end
          job[:flags].each { |k,v| begin job[:rendering][k]=v unless v.nil? rescue nil end }
          @jobs.delete(model.object_id) if @jobs
          job[:callback].call(job[:finished],job[:error]) if job[:callback]
        end
      end
    end
  end
end
