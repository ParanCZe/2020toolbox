require 'sketchup.rb'
require 'net/http'
require 'uri'
require 'json'
require 'tmpdir'
require 'fileutils'

module TwentyTwenty
  module ToolboxPrint
    extend self

    BRIDGE_UPLOAD = URI('http://127.0.0.1:8091/sketchup-import')
    TOOLBOX_IMPORT = 'https://parancze.github.io/2020toolbox/sketchup_import.html'

    def safe_name
      model = Sketchup.active_model
      base = File.basename(model.path.to_s, '.*')
      base = model.title.to_s if base.empty?
      base = 'sketchup-model' if base.empty?
      base.gsub(/[^0-9A-Za-z._-]+/, '_')[0, 80]
    end

    def export_temp_stl
      model = Sketchup.active_model
      dir = File.join(Dir.tmpdir, '20-20-toolbox')
      FileUtils.mkdir_p(dir)
      path = File.join(dir, "#{safe_name}-#{Time.now.to_i}.stl")
      options = {
        units: 'mm',
        format: 'binary',
        selectionset_only: false,
        swap_yz: false,
        show_summary: false
      }
      ok = model.export(path, options)
      raise 'SketchUp STL export selhal.' unless ok && File.file?(path) && File.size(path) > 0
      path
    rescue ArgumentError => e
      raise "Tahle verze SketchUpu nema dostupny STL exporter pres Ruby API: #{e.message}"
    end

    def post_stl(path)
      req = Net::HTTP::Post.new(BRIDGE_UPLOAD)
      req['Content-Type'] = 'model/stl'
      req['X-File-Name'] = File.basename(path)
      req['X-20-20-Source'] = 'sketchup'
      req.body = File.binread(path)

      http = Net::HTTP.new(BRIDGE_UPLOAD.host, BRIDGE_UPLOAD.port)
      http.open_timeout = 3
      http.read_timeout = 30
      res = http.request(req)
      raise "PrusaBridge vratil HTTP #{res.code}." unless res.is_a?(Net::HTTPSuccess)
      data = JSON.parse(res.body)
      raise(data['error'] || 'PrusaBridge soubor neprijal.') unless data['ok'] && data['token']
      data['token']
    rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
      raise "20-20 PrusaBridge nebezi na portu 8091. Nejdriv ho spust v Toolboxu. (#{e.class})"
    end

    def send_to_print
      path = export_temp_stl
      token = post_stl(path)
      url = "#{TOOLBOX_IMPORT}?token=#{URI.encode_www_form_component(token)}"
      UI.openURL(url)
      UI.messagebox('Model byl predan do 20-20-TOOLBOXU. Oteviram aplikaci 3D tisk.')
    rescue => e
      UI.messagebox("20-20 Toolbox\n\nPoslani do 3D tisku se nepodarilo:\n#{e.message}")
    ensure
      begin
        File.delete(path) if defined?(path) && path && File.file?(path)
      rescue
      end
    end

    unless file_loaded?(__FILE__)
      cmd = UI::Command.new('Poslat do 3D tisku') { send_to_print }
      cmd.tooltip = 'Poslat model do 20-20-TOOLBOX · 3D tisk'
      cmd.status_bar_text = 'Exportuje model do STL a automaticky ho otevre v 20-20-TOOLBOXU.'

      # SketchUp uses the large icon for the normal toolbar button. The RBZ build
      # packages the official 20-20 Toolbox icon next to this file.
      icon_path = File.join(__dir__, 'toolbox_icon.png')
      if File.file?(icon_path)
        cmd.small_icon = icon_path
        cmd.large_icon = icon_path
      end

      UI.menu('Extensions').add_item(cmd)
      toolbar = UI::Toolbar.new('20-20 TOOLBOX')
      toolbar.add_item(cmd)
      toolbar.show
      file_loaded(__FILE__)
    end
  end
end
