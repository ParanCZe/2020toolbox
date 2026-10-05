# frozen_string_literal: true
require 'base64'
require 'cgi'

module TwentyTwenty
  module RMManagers
    # Read-only floorplan. Never changes SketchUp's camera, selected scene,
    # section planes, rendering options, entity tags or active edit context.
    module Floorplan
      extend self
      MAX_VISITS = 18000
      MAX_FACES = 5500
      MAX_SEGMENTS = 8500
      CACHE_LIMIT = 4
      def touch_model_cache(model)
        key = model.object_id
        @cache_order ||= []
        @cache_order.delete(key)
        @cache_order << key
        while @cache_order.length > CACHE_LIMIT
          stale = @cache_order.shift
          @cache.delete(stale) if @cache
          @errors.delete(stale) if @errors
        end
        key
      end
      def last_error(model); (@errors ||= {})[model.object_id]; end
      def set_error(model, value); (@errors ||= {})[touch_model_cache(model)] = value; end
      def cameras(model)
        pages = model.pages.to_a
        pages.empty? ? [model.active_view.camera] : pages.map(&:camera)
      end
      def camera_region(model)
        cams = cameras(model)
        positions = cams.flat_map do |c|
          eye = c.eye
          dir = c.direction
          norm = Math.sqrt(dir.x.to_f**2 + dir.y.to_f**2)
          forward = norm > 0.0001 ? [eye.x + dir.x.to_f / norm * 15.m, eye.y + dir.y.to_f / norm * 15.m] : [eye.x, eye.y]
          [[eye.x,eye.y],forward]
        end
        xs, ys = positions.map(&:first), positions.map(&:last)
        centerx = (xs.min + xs.max) / 2.0
        centery = (ys.min + ys.max) / 2.0
        halfx = [(xs.max-xs.min)/2.0+12.m,20.m].max
        halfy = [(ys.max-ys.min)/2.0+12.m,20.m].max
        [centerx-halfx,centery-halfy,centerx+halfx,centery+halfy].map(&:to_f)
      end
      def cut_height(model)
        eye = cameras(model).first.eye
        bounds = model.bounds
        ground = bounds.valid? && (eye.z - bounds.min.z).abs < 15.m ? bounds.min.z : eye.z - 1.8.m
        (ground + 2.m).to_f
      end
      def cached_data(model)
        (@cache ||= {})[model.object_id]
      end
      def needs_rebuild?(model)
        cached = cached_data(model)
        return true unless cached
        old = cached[:region]
        incoming = camera_region(model)
        incoming.each_with_index.any? { |v,i| i<2 ? v<old[i]-4.m : v>old[i]+4.m }
      end
      def color(face)
        mat = face.material || face.back_material
        return '#e9e5db' unless mat
        c = mat.color
        format('#%02x%02x%02x',c.red,c.green,c.blue)
      rescue StandardError
        '#e9e5db'
      end
      def face_points(face, transform)
        face.outer_loop.vertices.map { |v| v.position.transform(transform) }
      end
      def overlapping?(bb, transform, region)
        corners = []
        [bb.min.x,bb.max.x].each do |x|
          [bb.min.y,bb.max.y].each do |y|
            [bb.min.z,bb.max.z].each do |z|
              p = Geom::Point3d.new(x,y,z).transform(transform)
              corners << p
            end
          end
        end
        minx,maxx = corners.map(&:x).minmax
        miny,maxy = corners.map(&:y).minmax
        !(maxx<region[0] || minx>region[2] || maxy<region[1] || miny>region[3])
      end
      def analyze(entities, transform, region, cut, result, stack, depth, budget)
        return if depth>7 || budget[0]<=0
        entities.each do |entity|
          break if budget[0]<=0 || result[:faces].length>=MAX_FACES || result[:cuts].length>=MAX_SEGMENTS
          budget[0]-=1
          next unless entity.valid?
          next if entity.respond_to?(:hidden?) && entity.hidden?
          next if entity.respond_to?(:layer) && entity.layer && !entity.layer.visible?
          if entity.is_a?(Sketchup::Face)
            next unless overlapping?(entity.bounds,transform,region)
            points = face_points(entity,transform)
            next if points.length<3
            heights=points.map(&:z)
            minz,maxz=heights.minmax
            # Top-facing floors and roofs below the cut give a recognizable plan,
            # drawn in Z order; walls are then outlined by true plane intersections.
            normal=entity.normal.transform(transform)
            if maxz<cut-1.mm && normal.z>0.35
              result[:faces] << [maxz,points.map { |p| [p.x.to_f,p.y.to_f] },color(entity)]
            elsif minz<=cut && maxz>=cut
              intersections=[]
              points.each_with_index do |p,i|
                q=points[(i+1)%points.length]
                da,db=p.z-cut,q.z-cut
                if da.abs<0.01 && db.abs<0.01
                  result[:cuts] << [[p.x.to_f,p.y.to_f],[q.x.to_f,q.y.to_f]]
                elsif da*db<0
                  t=-da.to_f/(db-da)
                  intersections << [p.x+t*(q.x-p.x),p.y+t*(q.y-p.y)]
                elsif da.abs<0.01
                  intersections << [p.x.to_f,p.y.to_f]
                end
              end
              intersections.uniq.each_slice(2) { |pair| result[:cuts] << pair if pair.length==2 }
            end
          elsif entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
            definition=entity.definition
            next if stack.include?(definition.object_id)
            next unless overlapping?(entity.bounds,transform,region)
            analyze(definition.entities,transform*entity.transformation,region,cut,
                    result,stack+[definition.object_id],depth+1,budget)
          end
        end
      end
      def build(model)
        raise 'Model není k dispozici.' unless model
        set_error(model,nil)
        region=camera_region(model)
        cut=cut_height(model)
        data={faces:[],cuts:[]}
        analyze(model.entities,Geom::Transformation.new,region,cut,data,[],0,[MAX_VISITS])
        # Fixed coordinate system: camera markers use same XY mapping as SVG.
        width=700.0
        height=700.0*(region[3]-region[1])/[region[2]-region[0],1].max
        height=[[height,270].max,1200].min
        scale=[(width-24)/(region[2]-region[0]),(height-24)/(region[3]-region[1])].min
        actualw=(region[2]-region[0])*scale
        actualh=(region[3]-region[1])*scale
        offx=(width-actualw)/2
        offy=(height-actualh)/2
        project=lambda do |xy|
          [offx+(xy[0]-region[0])*scale,offy+(region[3]-xy[1])*scale]
        end
        svg=[]
        svg << %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{width.to_i} #{height.to_i}" width="#{width.to_i}" height="#{height.to_i}">)
        svg << %(<rect width="100%" height="100%" fill="#e5e5e0"/>)
        data[:faces].sort_by(&:first).each do |_z, polygon, fill|
          points=polygon.map { |v| project.call(v).map { |n| n.round(2) }.join(',') }.join(' ')
          svg << %(<polygon points="#{points}" fill="#{fill}" stroke="#999a97" stroke-width=".75"/>)
        end
        data[:cuts].each do |segment|
          x1,y1=project.call(segment[0])
          x2,y2=project.call(segment[1])
          svg << %(<path d="M#{x1.round(2)},#{y1.round(2)} L#{x2.round(2)},#{y2.round(2)}" stroke="#161b1c" stroke-width="2.1" fill="none"/>)
        end
        svg << '</svg>'
        image='data:image/svg+xml;base64,'+Base64.strict_encode64(svg.join)
        rect={'origin'=>[(offx+(0-region[0])*scale)/width,(offy+(region[3]-0)*scale)/height],
              'xaxis'=>[scale/width,0.0],'yaxis'=>[0.0,-scale/height],
              'world_center'=>[0.0,0.0],'world_unit'=>1.0}
        payload={image:image,rect:rect,region:region,cut_z:cut,
                 face_count:data[:faces].length,segment_count:data[:cuts].length}
        (@cache ||= {})[model.object_id]=payload
        [true,nil]
      rescue StandardError=>e
        set_error(model,"#{e.class}: #{e.message}")
        puts "[RM PLAN] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
        [false,last_error(model)]
      end
    end
  end
end
