# frozen_string_literal: true

require 'sketchup.rb'
require 'socket'
require 'json'
require 'net/http'
require 'uri'
require 'tmpdir'
require 'fileutils'
require 'zlib'

module TwentyTwenty
  module ToolboxConnector
    extend self

    VERSION = '2.0.2'.freeze
    PORT = 8092
    HOST = '127.0.0.1'.freeze
    ALLOWED_PREFIXES = %w[twentytwenty_ 2020_ dvacet20-].freeze

    def windows?
      Sketchup.platform == :platform_win
    end

    def mac?
      Sketchup.platform == :platform_osx
    end

    def platform_name
      windows? ? 'windows' : (mac? ? 'mac' : Sketchup.platform.to_s)
    end

    def plugins_dir
      @plugins_dir ||= Sketchup.find_support_file('Plugins')
    end

    def ruby_legacy?
      RUBY_VERSION.split('.').map { |x| x.to_i }[0, 2] < [2, 3]
    rescue
      true
    end

    def start
      return if @server_thread && @server_thread.alive?
      @server_thread = Thread.new { server_loop }
      @server_thread.abort_on_exception = false
      puts "20-20 Toolbox Connector v#{VERSION} listening on #{HOST}:#{PORT} | SketchUp #{Sketchup.version} | Ruby #{RUBY_VERSION}"
    rescue StandardError => e
      puts "20-20 Toolbox Mac Connector start error: #{e.class}: #{e.message}"
    end

    def server_loop
      server = TCPServer.new(HOST, PORT)
      loop do
        socket = server.accept
        handle_client(socket)
      rescue IOError, Errno::EBADF
        break
      rescue StandardError => e
        puts "20-20 Toolbox Mac Connector server error: #{e.class}: #{e.message}"
      end
    ensure
      begin
        server.close if server
      rescue
      end
    end

    def handle_client(socket)
      request_line = socket.gets
      return unless request_line
      parts = request_line.split(' ', 3)
      method = parts[0]
      raw_path = parts[1]
      headers = {}
      while (line = socket.gets)
        line = line.strip
        break if line.empty?
        pair = line.split(':', 2)
        headers[pair[0].downcase] = pair[1].to_s.strip if pair[0]
      end

      length = headers['content-length'].to_i
      body = length > 0 ? socket.read(length) : ''

      if method == 'OPTIONS'
        respond(socket, 204, {})
        return
      end

      uri = URI.parse("http://localhost#{raw_path}")
      params = {}
      URI.decode_www_form(uri.query.to_s).each { |k, v| params[k] = v }

      if method == 'GET' && uri.path == '/status'
        respond(socket, 200, status_payload)
      elsif method == 'POST' && uri.path == '/install'
        install_plugin(params['file'], params['repo'], body)
        respond(socket, 200, status_payload.merge(:ok => true))
      elsif method == 'POST' && uri.path == '/uninstall'
        uninstall_plugin(params['loader'])
        respond(socket, 200, status_payload.merge(:ok => true))
      else
        respond(socket, 404, { :ok => false, :error => 'Unknown endpoint' })
      end
    rescue StandardError => e
      begin
        respond(socket, 500, { :ok => false, :error => "#{e.class}: #{e.message}" })
      rescue
      end
    ensure
      begin
        socket.close if socket
      rescue
      end
    end

    def respond(socket, code, obj)
      body = code == 204 ? '' : JSON.generate(obj)
      status = if code == 200
                 'OK'
               elsif code == 204
                 'No Content'
               elsif code == 404
                 'Not Found'
               else
                 'Error'
               end
      headers = [
        "HTTP/1.1 #{code} #{status}",
        'Content-Type: application/json; charset=utf-8',
        'Access-Control-Allow-Origin: *',
        'Access-Control-Allow-Private-Network: true',
        'Access-Control-Allow-Methods: GET, POST, OPTIONS',
        'Access-Control-Allow-Headers: Content-Type',
        'Cache-Control: no-store',
        "Content-Length: #{body.bytesize}",
        'Connection: close',
        '',
        ''
      ].join("\r\n")
      socket.write(headers)
      socket.write(body) unless body.empty?
      socket.flush
    end

    def status_payload
      {
        :ok => true,
        :platform => platform_name,
        :bridge_version => VERSION,
        :sketchup => "SketchUp #{Sketchup.version}",
        :sketchup_major => Sketchup.version.to_i,
        :ruby_version => RUBY_VERSION,
        :legacy_ruby => ruby_legacy?,
        :plugins_dir => plugins_dir,
        :installed => installed_versions
      }
    end

    def installed_versions
      out = {}
      Dir.glob(File.join(plugins_dir, '*.rb')).each do |path|
        name = File.basename(path)
        lower = name.downcase
        next unless ALLOWED_PREFIXES.any? { |prefix| lower.start_with?(prefix) }
        begin
          text = File.open(path, 'rb') { |f| f.read }
          out[name] = extract_version(text)
        rescue StandardError
        end
      end
      out
    end

    def extract_version(text)
      patterns = [
        /(?:EXTENSION|extension)\.version\s*=\s*['"]([^'"]+)['"]/m,
        /^\s*EXTENSION_VERSION\s*=\s*['"]([^'"]+)['"]/m,
        /^\s*VERSION\s*=\s*['"]([^'"]+)['"]/m
      ]
      patterns.each do |pattern|
        match = text.match(pattern)
        return match[1] if match
      end
      '?'
    end

    def valid_file_name?(name)
      !!(name.to_s =~ /\A[A-Za-z0-9._-]+\.rbz\z/i)
    end

    def valid_repo_path?(path)
      value = path.to_s
      return false if value.include?('..')
      !!(value =~ %r{\ASketchUpPlugins/[A-Za-z0-9._/-]+\.rbz\z})
    end

    def install_plugin(file_name, repo_path, body)
      raise 'Chybí název RBZ.' if file_name.to_s.empty?
      raise 'Neplatný název RBZ.' unless valid_file_name?(file_name)

      Dir.mktmpdir('2020toolbox-mac-') do |tmp|
        rbz = File.join(tmp, file_name)

        if repo_path && !repo_path.empty?
          raise 'Neplatná cesta v repozitáři.' unless valid_repo_path?(repo_path)
          download_repo_file(repo_path, rbz)
        else
          raise 'Prázdný RBZ obsah.' if body.nil? || body.bytesize < 64
          File.open(rbz, 'wb') { |f| f.write(body) }
        end

        sig = File.open(rbz, 'rb') { |f| f.read(2) }
        raise 'Stažený soubor není ZIP/RBZ.' unless sig == 'PK'

        extract_dir = File.join(tmp, 'extract')
        FileUtils.mkdir_p(extract_dir)
        unzip(rbz, extract_dir)
        copy_plugin_tree(extract_dir)
      end
    end

    def shell_quote_ps(value)
      "'" + value.to_s.gsub("'", "''") + "'"
    end

    def download_repo_file(repo_path, target)
      url = "https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/#{repo_path}"

      if mac? && File.exist?('/usr/bin/curl')
        ok = system('/usr/bin/curl', '-L', '--fail', '--silent', '--show-error', '-o', target, url)
        return if ok && File.exist?(target) && File.size(target) > 0
      end

      if windows?
        begin
          require 'win32ole'
          http = WIN32OLE.new('WinHttp.WinHttpRequest.5.1')
          http.Open('GET', url, false)
          http.SetRequestHeader('Cache-Control', 'no-cache')
          http.Send
          status = http.Status.to_i
          raise "HTTP #{status}" unless status >= 200 && status < 300
          bytes = http.ResponseBody
          bytes = bytes.to_a if bytes.respond_to?(:to_a)
          File.open(target, 'wb') { |f| f.write(bytes.pack('C*')) }
          return if File.exist?(target) && File.size(target) > 0
        rescue StandardError => e
          puts "20-20 Toolbox Connector WinHTTP fallback: #{e.message}"
        end
      end

      uri = URI.parse(url)
      response = Net::HTTP.get_response(uri)
      raise "Stažení RBZ selhalo: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      File.open(target, 'wb') { |f| f.write(response.body) }
    end

    def safe_zip_name?(name)
      value = name.to_s.tr('\\', '/')
      return false if value.start_with?('/') || value =~ /\A[A-Za-z]:/
      parts = value.split('/')
      !parts.include?('..')
    end

    def extract_zip_ruby(rbz, target)
      data = File.open(rbz, 'rb') { |f| f.read }
      pos = 0
      extracted = 0

      while pos + 30 <= data.bytesize
        sig = data[pos, 4].unpack('V')[0]
        break if sig == 0x02014b50 || sig == 0x06054b50
        raise 'Neplatná ZIP struktura.' unless sig == 0x04034b50

        h = data[pos, 30].unpack('VvvvvvVVVvv')
        flags = h[2]
        method = h[3]
        csize = h[7]
        usize = h[8]
        nlen = h[9]
        xlen = h[10]
        raise 'ZIP používá nepodporovaný data-descriptor.' if (flags & 0x08) != 0

        name = data[pos + 30, nlen]
        raise 'Nebezpečná cesta v RBZ.' unless safe_zip_name?(name)
        start = pos + 30 + nlen + xlen
        compressed = data[start, csize]

        normalized = name.tr('\\', '/')
        dst = File.join(target, normalized)
        if normalized.end_with?('/')
          FileUtils.mkdir_p(dst)
        else
          FileUtils.mkdir_p(File.dirname(dst))
          content = case method
                    when 0
                      compressed
                    when 8
                      inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
                      begin
                        inflater.inflate(compressed) + inflater.finish
                      ensure
                        inflater.close
                      end
                    else
                      raise "Nepodporovaná ZIP komprese: #{method}"
                    end
          raise 'Poškozená položka v RBZ.' if usize > 0 && content.bytesize != usize
          File.open(dst, 'wb') { |f| f.write(content) }
          extracted += 1
        end
        pos = start + csize
      end

      raise 'RBZ neobsahuje žádné soubory.' if extracted == 0
      true
    end

    def unzip(rbz, target)
      extract_zip_ruby(rbz, target)
    rescue StandardError => e
      puts "20-20 Toolbox Connector ZIP error: #{e.class}: #{e.message}"
      raise "RBZ se nepodařilo rozbalit: #{e.message}"
    end

    def show_connector_status
      alive = @server_thread && @server_thread.alive?
      UI.messagebox("20-20 Toolbox Connector v#{VERSION}\n\nPlatforma: #{platform_name}\nSketchUp: #{Sketchup.version}\nServer: #{alive ? 'AKTIVNÍ' : 'NEAKTIVNÍ'}\nAdresa: http://localhost:#{PORT}")
    end

    def restart_connector
      begin
        @server_thread.kill if @server_thread && @server_thread.alive?
      rescue
      end
      @server_thread = nil
      UI.start_timer(0.2, false) { start }
      UI.messagebox('20-20 Toolbox Connector se restartuje. Za chvíli obnov Toolbox.')
    end

    def child_names(path)
      Dir.entries(path).reject { |name| name == '.' || name == '..' }
    end

    def copy_plugin_tree(source)
      copied = 0
      child_names(source).each do |name|
        next if name == '__MACOSX'
        src = File.join(source, name)

        if File.directory?(src)
          dst = File.join(plugins_dir, name)
          FileUtils.rm_rf(dst)
          FileUtils.cp_r(src, dst)
          copied += 1
        elsif File.extname(name).downcase == '.rb'
          FileUtils.cp(src, File.join(plugins_dir, name))
          copied += 1
        end
      end
      raise 'RBZ neobsahuje rozpoznatelný SketchUp plugin.' if copied == 0
    end

    def uninstall_plugin(loader)
      raise 'Chybí loader.' if loader.to_s.empty?
      raise 'Neplatný loader.' unless loader.to_s =~ /\A[A-Za-z0-9._-]+\.rb\z/

      loader_path = File.join(plugins_dir, loader)
      folder_path = File.join(plugins_dir, File.basename(loader, '.rb'))

      FileUtils.rm_f(loader_path)
      FileUtils.rm_rf(folder_path)
    end

    unless file_loaded?(__FILE__)
      if windows? || mac?
        UI.start_timer(0.2, false) { start }
        begin
          menu = UI.menu('Extensions').add_submenu('20-20 Toolbox Connector')
          menu.add_item('Stav Connectoru') { show_connector_status }
          menu.add_item('Restartovat Connector') { restart_connector }
        rescue StandardError
        end
      end
      file_loaded(__FILE__)
    end
  end
end
