# frozen_string_literal: true
require 'net/http'
require 'uri'
require 'cgi'
require 'fileutils'

module TwentyTwenty
  module RMManagers
    module StreetView
      extend self
      DICT = '20-20 RM STREETVIEW'.freeze
      PREF = '20-20 RM StreetView'.freeze
      ATTR = '20-20 RM STREETVIEW TEMP'.freeze

      def api_key
        if Sketchup.respond_to?(:read_default)
          Sketchup.read_default(PREF, 'api_key', '').to_s
        else
          @fallback_api_key.to_s
        end
      end
      def api_key=(value)
        value = value.to_s.strip
        if Sketchup.respond_to?(:write_default)
          Sketchup.write_default(PREF, 'api_key', value)
        else
          @fallback_api_key = value
        end
      end
      def configured?
        !api_key.empty?
      end

      def config(page)
        {
          enabled: !!page.get_attribute(DICT, 'enabled', false),
          source_url: page.get_attribute(DICT, 'source_url', '').to_s,
          pano: page.get_attribute(DICT, 'pano', '').to_s,
          location: page.get_attribute(DICT, 'location', '').to_s,
          heading: page.get_attribute(DICT, 'heading', 0.0).to_f,
          pitch: page.get_attribute(DICT, 'pitch', 0.0).to_f,
          fov: page.get_attribute(DICT, 'fov', 90.0).to_f,
          distance_m: page.get_attribute(DICT, 'distance_m', 80.0).to_f,
          api_key_set: configured?
        }
      end

      def save_config(page, data)
        parsed = parse_url(data['url'].to_s)
        page.set_attribute(DICT, 'source_url', data['url'].to_s.strip)
        page.set_attribute(DICT, 'pano', parsed[:pano].to_s)
        page.set_attribute(DICT, 'location', parsed[:location].to_s)
        page.set_attribute(DICT, 'heading', parsed[:heading].to_f)
        page.set_attribute(DICT, 'pitch', parsed[:pitch].to_f)
        page.set_attribute(DICT, 'fov', parsed[:fov].to_f)
        distance = Float(data['distance_m'] || 80.0) rescue 80.0
        distance = 80.0 unless distance.finite? && distance.between?(5.0, 1000.0)
        page.set_attribute(DICT, 'distance_m', distance)
        parsed
      end

      def enabled=(pair)
        page, value = pair
        page.set_attribute(DICT, 'enabled', !!value)
      end

      def parse_url(raw)
        text = raw.to_s.strip
        raise 'Vlož odkaz na Google Street View.' if text.empty?
        decoded = CGI.unescape(text)
        pano = ''
        location = ''
        heading = nil
        pitch = nil
        fov = nil
        begin
          uri = URI.parse(text)
          params = CGI.parse(uri.query.to_s)
          pano = params['pano']&.first.to_s
          location = params['viewpoint']&.first.to_s
          heading = params['heading']&.first
          pitch = params['pitch']&.first
          fov = params['fov']&.first
        rescue URI::InvalidURIError
          nil
        end
        if location.empty? && decoded =~ /@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/
          location = "#{Regexp.last_match(1)},#{Regexp.last_match(2)}"
        end
        if decoded =~ /(?:3a,)?([\d.]+)y,(-?[\d.]+)h,(-?[\d.]+)t/
          fov ||= Regexp.last_match(1)
          heading ||= Regexp.last_match(2)
          pitch ||= (90.0 - Regexp.last_match(3).to_f).to_s
        end
        raise 'Z odkazu se nepodařilo zjistit polohu/panorama. Použij odkaz přímo z otevřeného Street View.' if pano.empty? && location.empty?
        {
          pano: pano,
          location: location,
          heading: [[Float(heading || 0.0), -360.0].max, 360.0].min,
          pitch: [[Float(pitch || 0.0), -90.0].max, 90.0].min,
          fov: [[Float(fov || 90.0), 10.0].max, 120.0].min
        }
      rescue ArgumentError
        raise 'Street View odkaz obsahuje neplatné údaje pohledu.'
      end

      def maps_url(cfg)
        q = {'api'=>'1','map_action'=>'pano','heading'=>cfg[:heading], 'pitch'=>cfg[:pitch], 'fov'=>cfg[:fov]}
        q['pano'] = cfg[:pano] unless cfg[:pano].to_s.empty?
        q['viewpoint'] = cfg[:location] unless cfg[:location].to_s.empty?
        'https://www.google.com/maps/@?' + URI.encode_www_form(q)
      end

      def static_url(cfg)
        key = api_key
        raise 'Nejdřív nastav Google Maps API klíč pro Street View Static API.' if key.empty?
        q = {
          'size'=>'640x360',
          'heading'=>cfg[:heading],
          'pitch'=>cfg[:pitch],
          'fov'=>cfg[:fov],
          'return_error_code'=>'true',
          'key'=>key
        }
        if !cfg[:pano].to_s.empty?
          q['pano'] = cfg[:pano]
        elsif !cfg[:location].to_s.empty?
          q['location'] = cfg[:location]
        else
          raise 'Scéna nemá uloženou Street View polohu.'
        end
        URI('https://maps.googleapis.com/maps/api/streetview?' + URI.encode_www_form(q))
      end

      def temp_file(model, page)
        root = File.join(Sketchup.temp_dir, '20-20', 'RMStreetView')
        FileUtils.mkdir_p(root)
        id = TwentyTwenty::RMManagers.scene_id(page).gsub(/[^a-zA-Z0-9_-]/,'_')
        File.join(root, "#{model.object_id}_#{id}.jpg")
      end

      def download(uri, destination, redirects = 0)
        raise 'Příliš mnoho přesměrování Street View.' if redirects > 4
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 8, read_timeout: 20) do |http|
          http.get(uri.request_uri)
        end
        case response
        when Net::HTTPSuccess
          File.binwrite(destination, response.body)
        when Net::HTTPRedirection
          download(URI.join(uri.to_s, response['location']), destination, redirects + 1)
        else
          raise "Street View obrázek se nepodařilo načíst (HTTP #{response.code})."
        end
        destination
      end

      def clear(model)
        model.entities.to_a.each do |entity|
          next unless entity.respond_to?(:get_attribute)
          next unless entity.get_attribute(ATTR, 'background', false)
          entity.erase! if entity.valid?
        end
      end

      def horizontal_fov(camera)
        f = TwentyTwenty::RMManagers.focal_35(camera)
        return 70.0 unless f && f > 0
        2.0 * Math.atan(36.0 / (2.0 * f)) * 180.0 / Math::PI
      end

      class SaveObserver < (defined?(Sketchup::ModelObserver) ? Sketchup::ModelObserver : Object)
        def onPreSaveModel(model)
          @restore_page = model.pages.selected_page
          StreetView.clear(model)
        rescue StandardError => e
          puts "[RM STREETVIEW] pre-save: #{e.class}: #{e.message}"
        end
        def onPostSaveModel(model)
          page = @restore_page
          @restore_page = nil
          return unless page && model.pages.to_a.include?(page)
          UI.start_timer(0.05, false) do
            begin
              StreetView.apply(model, page) if StreetView.config(page)[:enabled]
            rescue StandardError => e
              puts "[RM STREETVIEW] post-save: #{e.class}: #{e.message}"
            end
          end
        end
      end

      def install_save_observer(model)
        @save_observers ||= {}
        key = model.object_id
        return if @save_observers[key]
        obs = SaveObserver.new
        model.add_observer(obs)
        @save_observers[key] = obs
      end

      def apply(model, page)
        install_save_observer(model)
        clear(model)
        cfg = config(page)
        return false unless cfg[:enabled]
        uri = static_url(cfg)
        file = temp_file(model, page)
        download(uri, file)

        cam = page.camera
        direction = cam.direction.clone
        direction.normalize!
        up = cam.up.clone
        up.normalize!
        right = direction.cross(up)
        right.normalize!
        up = right.cross(direction)
        up.normalize!

        distance = cfg[:distance_m].m
        hfov = horizontal_fov(cam) * Math::PI / 180.0
        width = 2.0 * distance * Math.tan(hfov / 2.0)
        ratio = cam.aspect_ratio.to_f
        ratio = 16.0 / 9.0 if ratio <= 0.05
        height = width / ratio
        center = cam.eye.offset(direction, distance)
        origin = center.offset(right, -width / 2.0).offset(up, -height / 2.0)

        group = model.entities.add_group
        group.name = "RM STREETVIEW · #{page.name}"
        group.set_attribute(ATTR, 'background', true)
        group.set_attribute(ATTR, 'scene_id', TwentyTwenty::RMManagers.scene_id(page))
        image = group.entities.add_image(file, Geom::Point3d.new(0,0,0), width, height)
        raise 'SketchUp nevytvořil Street View pozadí.' unless image
        axes = Geom::Transformation.axes(origin, right, up, direction.reverse)
        group.transformation = axes
        true
      ensure
        begin
          File.delete(file) if file && File.file?(file)
        rescue StandardError
          nil
        end
      end
    end
  end
end
