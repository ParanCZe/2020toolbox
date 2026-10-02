# frozen_string_literal: true

# 20-20 Meye Cutouts — metadata-only remote browsing. Full-resolution PNG
# is transferred exclusively after an explicit click on a specific "+". No
# PNGs are bundled in the RBZ, scraped in bulk, or uploaded anywhere else.
# Meye / Mikkel Eye permits use as part of landscape/architectural projects.
require 'sketchup.rb'
require 'net/http'
require 'uri'
require 'json'
require 'cgi'
require 'fileutils'
require 'digest'
require 'zlib'
require 'thread'

module TwentyTwenty
  module MeyeCutouts
    extend self

    VERSION = '0.1.1'.freeze
    API_ROOT = 'https://meye.dk/wp-json/wp/v2'.freeze
    MAX_PNG_BYTES = 100 * 1024 * 1024
    MAX_PIXEL_DATA = 160 * 1024 * 1024
    PAGE_SIZE = 12
    CATALOG_TTL = 12 * 60 * 60
    TAXONOMY_TTL = 24 * 60 * 60
    SEASONS = %w[spring summer autumn winter].freeze
    SOURCE_CREDIT = 'Meye © Mikkel Eye · meye.dk'.freeze

    # SketchUp operations always happen on the main thread. Worker threads
    # perform HTTP and PNG analysis only and communicate via a polled Queue.
    def show_dialog
      if @dialog
        @dialog.show
        return @dialog
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: '20-20 | 2D STROMY A KEŘE · MEYE',
        preferences_key: '2020-rmtools-meye-cutouts-v1',
        scrollable: true,
        resizable: true,
        width: 1130,
        height: 795,
        min_width: 740,
        min_height: 540,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_file(File.join(__dir__, 'ui', 'library.html'))
      bind_callbacks(@dialog)
      @dialog.set_on_closed do
        @dialog = nil
        @revision = (@revision || 0) + 1
        if @timer
          UI.stop_timer(@timer)
          @timer = nil
        end
      end
      @messages ||= Queue.new
      @items ||= {}
      @timer = UI.start_timer(0.15, true) { poll_messages }
      @dialog.show
      @dialog
    end

    def bind_callbacks(dlg)
      dlg.add_action_callback('meye_ready') do |_ctx|
        send_js("MeyeLibrary.ready(#{JSON.generate({version: VERSION, source: SOURCE_CREDIT})})")
      end
      dlg.add_action_callback('meye_catalog') do |_ctx, raw|
        request_catalog(raw)
      end
      dlg.add_action_callback('meye_insert') do |_ctx, raw|
        request_insert(raw)
      end
    end

    def send_js(source)
      @dialog.execute_script("window.MeyeLibrary && #{source};") if @dialog
    rescue StandardError => e
      puts "[20-20 Meye] UI: #{e.message}"
    end

    def sanitize_text(value)
      CGI.unescapeHTML(value.to_s.gsub(/<[^>]*>/, '')).strip[0, 120]
    end

    def meye_url?(value, png: false)
      u = URI.parse(value.to_s)
      return false unless u.scheme == 'https' && u.host == 'meye.dk'
      return false unless u.userinfo.nil? && !u.port.nil? && u.port == 443
      return false unless u.fragment.nil?
      png ? !!(u.path =~ %r{\A/wp-content/uploads/[0-9]{4}/[0-9]{2}/[^/]+\.png\z}i) : true
    rescue URI::InvalidURIError
      false
    end

    def request_json(path, max_bytes = 5 * 1024 * 1024)
      url = path.start_with?('https://') ? path : "#{API_ROOT}#{path}"
      raise 'Nepovolená adresa katalogu.' unless meye_url?(url)
      result = get_request(url, max_bytes)
      JSON.parse(result)
    end

    def get_request(url, max_bytes, retries: 1)
      u = URI.parse(url)
      raise 'Nepovolený zdroj dat.' unless meye_url?(url)
      result = nil
      Net::HTTP.start(u.host, u.port, use_ssl: true, open_timeout: 9, read_timeout: 20) do |http|
        req = Net::HTTP::Get.new(u.request_uri)
        req['User-Agent'] = 'Mozilla/5.0 20-20 RM TOOLS (metadata and user-selected PNG from meye.dk)'
        req['Accept'] = '*/*'
        http.request(req) do |response|
          if response.is_a?(Net::HTTPRedirection)
            dest = URI.join(url, response['location'].to_s).to_s
            raise 'Přesměrování mimo Meye není povolené.' unless meye_url?(dest)
            return get_request(dest, max_bytes, retries: retries - 1) if retries > 0
            raise 'Příliš mnoho přesměrování.'
          end
          raise "Meye odpovědělo HTTP #{response.code}." unless response.is_a?(Net::HTTPSuccess)
          result = +''.b
          response.read_body do |chunk|
            result << chunk
            raise 'Odpověď Meye překročila bezpečný limit.' if result.bytesize > max_bytes
          end
        end
      end
      result
    end

    def cache_dir
      home = ENV['APPDATA'] || File.join(Dir.home, '.config')
      File.join(home, '2020toolbox', 'MeyeCutouts')
    end

    # Metadata only (not Meye artwork). The cache survives SketchUp restarts.
    # Expiry and an explicit Refresh prevent the UI from serving stale items.
    def metadata_dir
      File.join(cache_dir, 'metadata')
    end

    def metadata_cache_read(path, ttl)
      return nil unless File.file?(path) && Time.now - File.mtime(path) < ttl
      JSON.parse(File.binread(path))
    rescue JSON::ParserError, SystemCallError
      nil
    end

    def metadata_cache_write(path, payload)
      FileUtils.mkdir_p(File.dirname(path))
      tmp = path + ".#{Process.pid}.#{Thread.current.object_id}.part"
      begin
        File.binwrite(tmp, JSON.generate(payload))
        File.rename(tmp, path)
      ensure
        File.delete(tmp) if File.exist?(tmp)
      end
    end

    def taxonomy
      return @taxonomy if @taxonomy
      @taxonomy_mutex ||= Mutex.new
      @taxonomy_mutex.synchronize do
        return @taxonomy if @taxonomy
        cache = File.join(metadata_dir, 'taxonomy.json')
        list = metadata_cache_read(cache, TAXONOMY_TTL)
        unless list.is_a?(Array)
          list = request_json('/project_category?per_page=100&_fields=id,name,slug')
          metadata_cache_write(cache, list)
        end
        @taxonomy = list.each_with_object({}) do |row, acc|
          acc[row['id'].to_i] = { 'name' => sanitize_text(row['name']),
                                 'slug' => row['slug'].to_s.downcase }
        end
      end
      @taxonomy
    end

    def catalog_cache_path(params)
      key = ['page', 'search', 'season', 'species'].map do |field|
        params[field].to_s.strip.downcase
      end.join("\0")
      File.join(metadata_dir, "catalog_#{Digest::SHA256.hexdigest(key)}.json")
    end

    def ensure_https(item)
      return nil unless meye_url?(item)
      item.to_s
    end

    def remote_catalog(params)
      cache_file = catalog_cache_path(params)
      unless params['force']
        cached = metadata_cache_read(cache_file, CATALOG_TTL)
        return cached.merge('cached' => true) if cached.is_a?(Hash) && cached['items'].is_a?(Array)
      end

      page = [[params['page'].to_i, 1].max, 30].min
      search = params['search'].to_s.strip[0, 80]
      season = params['season'].to_s.strip.downcase
      genus = params['species'].to_s.strip.downcase
      categories = taxonomy
      seasons = categories.select { |_id, row| SEASONS.include?(row['slug']) }
      species = categories.reject { |_id, row| SEASONS.include?(row['slug']) }
                          .sort_by { |_id, row| row['name'].downcase }
      selected_season = seasons.find { |_id, row| row['slug'] == season }&.first
      selected_species = species.find { |_id, row| row['slug'] == genus }&.first
      chosen = selected_species || selected_season

      base_query = { 'per_page' => PAGE_SIZE, 'page' => page }
      base_query['search'] = search unless search.empty?
      base_query['project_category'] = chosen if chosen

      # Meye's _embed=1 returns entire projects plus all embedded post/media
      # objects (measured ~259 kB for just 4 trees). This public two-step
      # equivalent returned ~19 kB on the same sample and preserves originals.
      lean_query = base_query.merge('_fields' =>
        'id,title,link,featured_media,project_category')
      lean_url = "/project?#{URI.encode_www_form(lean_query)}"
      begin
        data = request_json(lean_url, 2 * 1024 * 1024)
        raise 'Neplatný formát projektů Meye.' unless data.is_a?(Array)
        media_ids = data.map { |post| post['featured_media'].to_i }.select(&:positive?).uniq
        media = if media_ids.empty?
                  {}
                else
                  media_query = {
                    'include' => media_ids.join(','),
                    'per_page' => media_ids.length,
                    '_fields' => 'id,source_url,media_details'
                  }
                  records = request_json("/media?#{URI.encode_www_form(media_query)}",
                                         3 * 1024 * 1024)
                  records.each_with_object({}) { |m, memo| memo[m['id'].to_i] = m }
                end
      rescue StandardError => e
        # Keep the public original API as a robust fallback if Meye changes
        # access to the media endpoint; never prefetch original PNG files.
        puts "[20-20 Meye] Lehká metadata API není dostupná: #{e.message}"
        data = request_json("/project?#{URI.encode_www_form(base_query.merge('_embed' => '1'))}",
                            6 * 1024 * 1024)
        raise 'Neplatný formát katalogu Meye.' unless data.is_a?(Array)
        media = {}
        data.each do |post|
          featured = ((post['_embedded'] || {})['wp:featuredmedia'] || []).first
          media[post['featured_media'].to_i] = featured if featured
        end
      end
      items = data.filter_map do |post|
        next unless post.is_a?(Hash)
        entry = media[post['featured_media'].to_i]
        next unless entry.is_a?(Hash)
        full = entry['source_url'].to_s
        sizes = (entry['media_details'] || {})['sizes'] || {}
        # Medium remains an UNCROPPED tree preview unlike 150x150 WP thumbnail.
        thumb = sizes.dig('medium', 'source_url') || sizes.dig('large', 'source_url')
        next unless meye_url?(full, png: true) && thumb && meye_url?(thumb, png: true)
        page_url = post['link'].to_s
        next unless meye_url?(page_url) && page_url.include?('/project/')
        tag_ids = Array(post['project_category']).map(&:to_i)
        next if selected_species && !tag_ids.include?(selected_species)
        next if selected_season && !tag_ids.include?(selected_season)
        active_season = tag_ids.map { |id| categories.dig(id, 'slug') }
                               .find { |slug| SEASONS.include?(slug) }
        botanical = tag_ids.map { |id| categories.dig(id, 'name') }.compact
                          .reject { |name| SEASONS.include?(name.downcase) }.first
        {
          'id' => post['id'].to_i,
          'title' => sanitize_text((post['title'] || {})['rendered']),
          'species' => botanical,
          'season' => active_season,
          'thumb' => thumb.to_s,
          'full' => full,
          'page' => page_url
        }
      end

      payload = {
        'items' => items,
        'page' => page,
        'more' => data.length >= PAGE_SIZE,
        'seasons' => seasons.map { |id, row| { 'id' => id, 'slug' => row['slug'],
                                              'name' => row['name'] } },
        'species' => species.map { |id, row| { 'id' => id, 'slug' => row['slug'],
                                              'name' => row['name'] } },
        'cached' => false
      }
      metadata_cache_write(cache_file, payload)
      payload
    end

    def request_catalog(raw)
      params = JSON.parse(raw.to_s)
      raise 'Neplatný katalogový dotaz.' unless params.is_a?(Hash)
      @revision = (@revision || 0) + 1
      revision = @revision
      @messages ||= Queue.new
      Thread.new do
        begin
          result = remote_catalog(params)
          @messages << [:catalog, revision, result]
        rescue StandardError => e
          @messages << [:catalog_error, revision, e.message]
        end
      end
    rescue StandardError => e
      send_js("MeyeLibrary.error(#{JSON.generate(e.message)})")
    end

    def request_insert(raw)
      params = JSON.parse(raw.to_s)
      id = params.fetch('id').to_i
      height = Float(params.fetch('height'))
      raise 'Výška musí být od 0,5 do 30 metrů.' unless height.finite? && height.between?(0.5, 30.0)
      @items ||= {}
      item = @items[id]
      raise 'Položka už není v katalogu. Obnov nabídku.' unless item
      raise 'Již probíhá stahování tohoto cutoutu.' if (@busy ||= {})[id]
      @busy[id] = true
      @messages ||= Queue.new
      send_js("MeyeLibrary.setBusy(#{id},true)")
      Thread.new do
        begin
          path = download_full_png(item)
          bounds = cached_png_opaque_bounds(path)
          @messages << [:insert, id, item, height, path, bounds]
        rescue StandardError => e
          @messages << [:insert_error, id, e.message]
        end
      end
    rescue StandardError, ArgumentError => e
      send_js("MeyeLibrary.error(#{JSON.generate(e.message)})")
    end

    def official_download_url(item)
      # WP media's source_url is the same ORIGINAL PNG as the official lightbox
      # on checked Meye projects. It is already delivered in the catalog.
      # Avoid a second slow HTML page request every time "+" is clicked.
      url = item['full'].to_s
      raise 'Položka nemá ověřený původní PNG soubor na Meye.' unless meye_url?(url, png: true)
      url
    end

    def download_full_png(item)
      url = official_download_url(item)
      FileUtils.mkdir_p(cache_dir)
      basename = "#{item['id']}_#{Digest::SHA256.hexdigest(url)[0, 12]}.png"
      file = File.join(cache_dir, basename)
      return file if File.file?(file) && File.size(file) > 24 &&
                     File.binread(file, 8) == "\x89PNG\r\n\x1a\n".b

      data = get_request(url, MAX_PNG_BYTES, retries: 1)
      raise 'Stažený soubor není platný PNG.' unless data.byteslice(0, 8) == "\x89PNG\r\n\x1a\n".b
      tmp = file + ".#{Process.pid}.#{Thread.current.object_id}.part"
      begin
        File.binwrite(tmp, data)
        File.rename(tmp, file)
      ensure
        File.delete(tmp) if File.exist?(tmp)
      end
      file
    end

    # Reuse pixel bounds on the second insertion; the cache is keyed to the
    # exact local PNG's size and mtime, so a changed download is reprocessed.
    def cached_png_opaque_bounds(path)
      sidecar = path + '.bounds.json'
      stat = File.stat(path)
      cached = metadata_cache_read(sidecar, 365 * 24 * 3600)
      if cached && cached['bytes'] == stat.size &&
         cached['mtime'] == stat.mtime.to_i && cached['bounds'].is_a?(Hash)
        return cached['bounds'].each_with_object({}) do |(key, value), data|
          data[key.to_sym] = value
        end
      end
      bounds = png_opaque_bounds(path)
      metadata_cache_write(sidecar, {
        'bytes' => stat.size, 'mtime' => stat.mtime.to_i, 'bounds' => bounds
      })
      bounds
    end

    # PNG's five scanline filters are independent for each colour channel:
    # alpha's left/above/Paeth predictor NEVER depends on RGB. Reconstruct
    # ONLY the alpha byte for each pixel, not 4 channels in Ruby. That is
    # significantly cheaper while preserving the exact visible trunk origin.
    def png_opaque_bounds(file)
      bytes = File.binread(file)
      raise 'Neplatný PNG obrázek.' unless bytes.start_with?("\x89PNG\r\n\x1a\n".b)
      index = 8
      chunks = []
      width = height = depth = colour = interlace = nil
      until index + 12 > bytes.bytesize
        size = bytes.byteslice(index, 4).unpack1('N')
        kind = bytes.byteslice(index + 4, 4)
        raise 'Poškozený PNG.' if size > MAX_PNG_BYTES || index + size + 12 > bytes.bytesize
        payload = bytes.byteslice(index + 8, size)
        if kind == 'IHDR'
          width, height, depth, colour, _compression, _filter, interlace =
            payload.unpack('NNC5')
        elsif kind == 'IDAT'
          chunks << payload
        elsif kind == 'IEND'
          break
        end
        index += 12 + size
      end
      raise 'PNG nemá platné rozměry.' unless width && height &&
                                                  width.between?(1, 14_000) &&
                                                  height.between?(1, 14_000)
      fallback = { width: width, height: height, base_x: (width - 1) / 2.0,
                   bottom_y: height - 1, top_y: 0, alpha_aligned: false }
      channels = { 6 => 4, 4 => 2 }[colour]
      return fallback unless depth == 8 && interlace == 0 && channels && !chunks.empty?
      stride = width * channels
      return fallback if stride * height > MAX_PIXEL_DATA
      inflated = Zlib::Inflate.inflate(chunks.join)
      raise 'Poškozená PNG obrazová data.' if inflated.bytesize < (stride + 1) * height

      previous_alpha = Array.new(width, 0)
      offset = 0
      top = height
      bottom = -1
      row_bases = []
      height.times do |y|
        filter = inflated.getbyte(offset)
        raise 'Nepodporovaný PNG filtr.' unless filter && filter.between?(0, 4)
        previous = previous_alpha
        current = Array.new(width, 0)
        total_weight = 0
        weighted_x = 0
        alpha_byte_offset = offset + channels
        width.times do |x|
          raw_alpha = inflated.getbyte(alpha_byte_offset + x * channels)
          a = x.positive? ? current[x - 1] : 0
          b = previous[x]
          c = x.positive? ? previous[x - 1] : 0
          predictor = case filter
                      when 0 then 0
                      when 1 then a
                      when 2 then b
                      when 3 then (a + b) / 2
                      when 4
                        p = a + b - c
                        da, db, dc = (p - a).abs, (p - b).abs, (p - c).abs
                        da <= db && da <= dc ? a : (db <= dc ? b : c)
                      end
          pixel_alpha = (raw_alpha + predictor) & 255
          current[x] = pixel_alpha
          next unless pixel_alpha >= 48
          top = y if y < top
          bottom = y
          if pixel_alpha >= 110
            weighted_x += x * pixel_alpha
            total_weight += pixel_alpha
          end
        end
        row_bases << [y, weighted_x, total_weight] if total_weight > 0
        previous_alpha = current
        offset += stride + 1
      end
      return fallback if bottom < 0
      tail = row_bases.select { |y, _wx, _w| y >= bottom - 11 }
      weight = tail.sum { |_y, _wx, w| w }
      x = weight.positive? ? tail.sum { |_y, wx, _w| wx }.to_f / weight : fallback[:base_x]
      { width: width, height: height, base_x: x, bottom_y: bottom,
        top_y: top, alpha_aligned: true }
    rescue Zlib::DataError => e
      raise "Neplatné PNG: #{e.message}"
    end

    def place_png(item, height_m, path, bounds)
      model = Sketchup.active_model
      raise 'Ve SketchUpu není otevřený model.' unless model
      width_px = bounds[:width]
      # Opaque top and bottom PIXEL CENTRES define the requested tree height.
      visible_px = [bounds[:bottom_y] - bounds[:top_y], 1].max
      raise 'PNG nemá platnou výšku.' unless visible_px.positive?
      inch_per_pixel = (height_m * 39.3700787402) / visible_px
      x0 = -bounds[:base_x] * inch_per_pixel
      x1 = (width_px - bounds[:base_x]) * inch_per_pixel
      z0 = (bounds[:bottom_y] - (bounds[:height] - 1)) * inch_per_pixel
      z1 = bounds[:bottom_y] * inch_per_pixel

      model.start_operation('20-20 · Vložit Meye 2D cutout', true)
      begin
        material_name = "MEYE_#{item['id']}"
        material = model.materials[material_name] || model.materials.add(material_name)
        material.texture = path
        defn = model.definitions.add("MEYE · #{item['title']} · #{item['id']}")
        p0 = Geom::Point3d.new(x0, 0, z0)
        p1 = Geom::Point3d.new(x1, 0, z0)
        p2 = Geom::Point3d.new(x1, 0, z1)
        p3 = Geom::Point3d.new(x0, 0, z1)
        face = defn.entities.add_face(p0, p1, p2, p3)
        raise 'SketchUp nedokázal vytvořit plochu cutoutu.' unless face
        face.material = material
        face.back_material = material
        uv = [p0, Geom::Point3d.new(0, 0, 0),
              p1, Geom::Point3d.new(1, 0, 0),
              p3, Geom::Point3d.new(0, 1, 0)]
        face.position_material(material, uv, true)
        face.position_material(material, uv, false)
        defn.behavior.always_face_camera = true
        defn.set_attribute('20-20 MEYE', 'Source', item['page'])
        defn.set_attribute('20-20 MEYE', 'Credit', SOURCE_CREDIT)
        defn.set_attribute('20-20 MEYE', 'HeightMetres', height_m)
        defn.set_attribute('20-20 MEYE', 'BaseAxis', 'visible opaque bottom / trunk')
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
      # With the material surface built around [0,0,0] (visible trunk base),
      # native placement preview grabs the correct origin BEFORE the click.
      model.place_component(defn, false)
      Sketchup.set_status_text('MEYE: klikni pro umístění 2D cutoutu za spodní bod kmene.')
      true
    end

    def poll_messages
      @messages ||= Queue.new
      8.times do
        break if @messages.empty?
        type, *args = @messages.pop(true)
        case type
        when :catalog
          rev, payload = args
          next unless rev == @revision
          @items ||= {}
          payload['items'].each { |item| @items[item['id']] = item }
          send_js("MeyeLibrary.receiveCatalog(#{JSON.generate(payload)})")
        when :catalog_error
          rev, error = args
          send_js("MeyeLibrary.error(#{JSON.generate(error)})") if rev == @revision
        when :insert
          id, item, height, path, bounds = args
          @busy.delete(id) if @busy
          begin
            place_png(item, height, path, bounds)
            send_js("MeyeLibrary.insertDone(#{id})")
          rescue StandardError => e
            send_js("MeyeLibrary.insertError(#{id},#{JSON.generate(e.message)})")
          end
        when :insert_error
          id, error = args
          @busy.delete(id) if @busy
          send_js("MeyeLibrary.insertError(#{id},#{JSON.generate(error)})")
        end
      end
    rescue ThreadError
      nil
    rescue StandardError => e
      puts "[20-20 Meye] Poll: #{e.class}: #{e.message}"
    end
  end
end
