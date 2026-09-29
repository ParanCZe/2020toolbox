# frozen_string_literal: true

require 'sketchup.rb'
require 'socket'
require 'json'
require 'net/http'
require 'uri'
require 'tmpdir'
require 'fileutils'
require 'shellwords'

module TwentyTwenty
  module ToolboxMacConnector
    extend self

    VERSION = '1.0.0'.freeze
    PORT = 8092
    HOST = '127.0.0.1'.freeze
    ALLOWED_PREFIXES = %w[twentytwenty_ 2020_ dvacet20-].freeze

    def plugins_dir
      @plugins_dir ||= Sketchup.find_support_file('Plugins')
    end

    def start
      return if @server_thread&.alive?
      @server_thread = Thread.new { server_loop }
      @server_thread.abort_on_exception = false
      puts "20-20 Toolbox Mac Connector v#{VERSION} listening on #{HOST}:#{PORT}"
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
      server&.close rescue nil
    end

    def handle_client(socket)
      request_line = socket.gets
      return unless request_line
      method, raw_path, = request_line.split(' ', 3)
      headers = {}
      while (line = socket.gets)
        line = line.strip
        break if line.empty?
        key, value = line.split(':', 2)
        headers[key.downcase] = value.to_s.strip if key
      end
      length = headers['content-length'].to_i
      body = length.positive? ? socket.read(length) : ''.b

      return respond(socket, 204, {}) if method == 'OPTIONS'

      uri = URI.parse("http://localhost#{raw_path}")
      params = URI.decode_www_form(uri.query.to_s).to_h

      case [method, uri.path]
      when ['GET', '/status']
        respond(socket, 200, status_payload)
      when ['POST', '/install']
        install_plugin(params['file'], params['repo'], body)
        respond(socket, 200, status_payload.merge(ok: true))
      when ['POST', '/uninstall']
        uninstall_plugin(params['loader'])
        respond(socket, 200, status_payload.merge(ok: true))
      else
        respond(socket, 404, { ok: false, error: 'Unknown endpoint' })
      end
    rescue StandardError => e
      respond(socket, 500, { ok: false, error: "#{e.class}: #{e.message}" }) rescue nil
    ensure
      socket.close rescue nil
    end

    def respond(socket, code, obj)
      body = code == 204 ? '' : JSON.generate(obj)
      status = code == 200 ? 'OK' : code == 204 ? 'No Content' : code == 404 ? 'Not Found' : 'Error'
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
        ok: true,
        platform: 'mac',
        bridge_version: VERSION,
        sketchup: "SketchUp #{Sketchup.version}",
        plugins_dir: plugins_dir,
        installed: installed_versions
      }
    end

    def installed_versions
      out = {}
      Dir.glob(File.join(plugins_dir, '*.rb')).each do |path|
        name = File.basename(path)
        next unless ALLOWED_PREFIXES.any? { |prefix| name.downcase.start_with?(prefix) }
        text = File.read(path, encoding: 'UTF-8') rescue next
        out[name] = extract_version(text)
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

    def install_plugin(file_name, repo_path, body)
      raise 'Chybí název RBZ.' if file_name.to_s.empty?
      raise 'Neplatný název RBZ.' unless file_name.match?(/\A[A-Za-z0-9._-]+\.rbz\z/i)

      Dir.mktmpdir('2020toolbox-mac-') do |tmp|
        rbz = File.join(tmp, file_name)
        if repo_path && !repo_path.empty?
          raise 'Neplatná cesta v repozitáři.' unless repo_path.match?(%r{\ASketchUpPlugins/[A-Za-z0-9._/-]+\.rbz\z}) && !repo_path.include?('..')
          download_repo_file(repo_path, rbz)
        else
          raise 'Prázdný RBZ obsah.' if body.nil? || body.bytesize < 64
          File.binwrite(rbz, body)
        end

        sig = File.binread(rbz, 2)
        raise 'Stažený soubor není ZIP/RBZ.' unless sig == "PK"

        extract_dir = File.join(tmp, 'extract')
        FileUtils.mkdir_p(extract_dir)
        unzip(rbz, extract_dir)
        copy_plugin_tree(extract_dir)
      end
    end

    def download_repo_file(repo_path, target)
      uri = URI("https://raw.githubusercontent.com/ParanCZe/2020toolbox/main/#{repo_path}")
      response = Net::HTTP.get_response(uri)
      raise "Stažení RBZ selhalo: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      File.binwrite(target, response.body)
    end

    def unzip(rbz, target)
      commands = [
        ['/usr/bin/ditto', '-x', '-k', rbz, target],
        ['/usr/bin/unzip', '-qq', '-o', rbz, '-d', target]
      ]
      ok = commands.any? do |cmd|
        next false unless File.exist?(cmd[0])
        system(*cmd)
      end
      raise 'RBZ se na macOS nepodařilo rozbalit.' unless ok
    end

    def copy_plugin_tree(source)
      copied = 0
      Dir.children(source).each do |name|
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
      raise 'RBZ neobsahuje rozpoznatelný SketchUp plugin.' if copied.zero?
    end

    def uninstall_plugin(loader)
      raise 'Chybí loader.' if loader.to_s.empty?
      raise 'Neplatný loader.' unless loader.match?(/\A[A-Za-z0-9._-]+\.rb\z/)
      loader_path = File.join(plugins_dir, loader)
      folder_path = File.join(plugins_dir, File.basename(loader, '.rb'))
      FileUtils.rm_f(loader_path)
      FileUtils.rm_rf(folder_path)
    end

    unless file_loaded?(__FILE__)
      start if Sketchup.platform == :platform_osx
      file_loaded(__FILE__)
    end
  end
end
