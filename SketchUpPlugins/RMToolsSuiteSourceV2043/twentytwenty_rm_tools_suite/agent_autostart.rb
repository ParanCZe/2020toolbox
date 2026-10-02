# frozen_string_literal: true
# 20-20 RM TOOLS: headless autostart derived from Agent Launcher v0.1.2.
# No separate extension, toolbar or automatic file chooser.
require 'sketchup.rb'
require 'json'
require 'socket'
require 'timeout'
require 'fileutils'

module TwentyTwenty
  module RMToolsSuite
    module AgentBoot
      extend self

      PREF_SECTION = '20-20 Agent Launcher'.freeze
      DEFAULT_ADAPTER = 'C:/2020agent/dist/adapter-agent.exe'.freeze
      DEFAULT_SCRIPT = 'C:/2020agent/dist/sketchup/most.rb'.freeze
      BRIDGE_PORTS = [8093, 8092].freeze
      CHECK_INTERVAL = 40.0
      STATES = {
        agent: 'nezapnutý',
        ruby_bridge: 'nenačtený',
        web_bridge: 'nezapnutý'
      }.freeze

      def windows?
        RUBY_PLATFORM =~ /mswin|mingw|cygwin/i
      end

      def helper_dir
        File.join(ENV.fetch('APPDATA'), '2020toolbox', 'SketchUpPluginInstaller')
      end

      def session_bridge_file
        File.join(__dir__, 'windows_bridge', 'bridge_session.ps1')
      end

      def log(message)
        puts "[20-20 RM TOOLS auto] #{message}"
        return unless windows?
        path = File.join(ENV.fetch('APPDATA'), '2020toolbox', 'rmtools_autostart.log')
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, 'a') { |file| file.puts("#{Time.now}: #{message}") }
      rescue StandardError
        nil
      end

      def status
        @state ||= STATES.dup
        @state.dup
      end

      def stored_path(key, default)
        saved = Sketchup.read_default(PREF_SECTION, key, '').to_s.strip.tr('\\', '/')
        return saved if !saved.empty? && File.file?(saved)
        File.file?(default) ? default : nil
      rescue StandardError
        nil
      end

      def adapter_path
        stored_path('adapter_path', DEFAULT_ADAPTER)
      end

      def script_path
        stored_path('most_rb_path', DEFAULT_SCRIPT)
      end

      def hidden_runner
        FileUtils.mkdir_p(helper_dir)
        file = File.join(helper_dir, 'rmtools_hidden_runner.vbs')
        contents = <<~VBS
          Set sh = CreateObject("WScript.Shell")
          If WScript.Arguments.Count > 1 Then sh.CurrentDirectory = WScript.Arguments(1)
          sh.Run WScript.Arguments(0), 0, False
        VBS
        File.binwrite(file, contents) unless File.file?(file) && File.binread(file) == contents
        file
      end

      # Win32 WScript starts background programs without a console, unlike
      # cmd /c start used by the original standalone launcher.
      def launch_hidden(command, cwd)
        system32 = File.join(ENV.fetch('WINDIR', 'C:/Windows'), 'System32', 'wscript.exe')
        raise 'wscript.exe nebyl nalezen.' unless File.file?(system32)
        pid = Process.spawn(system32, hidden_runner, command, cwd,
                            out: File::NULL, err: File::NULL)
        Process.detach(pid)
        true
      end

      def quoted(file)
        raise 'Neplatná cesta ke spustitelnému souboru.' if file.include?('"')
        %("#{file.tr('/', '\\')}")
      end

      def adapter_running?(file)
        executable = File.basename(file).to_s
        return false if executable.empty?
        result = IO.popen(['tasklist.exe', '/FI', "IMAGENAME eq #{executable}", '/NH'],
                          err: File::NULL) { |stream| stream.read.to_s }
        result.downcase.include?(executable.downcase)
      rescue StandardError
        false
      end

      def start_agent(silent: true)
        return unless windows?
        @state ||= STATES.dup
        adapter = adapter_path
        script = script_path
        unless adapter
          @state[:agent] = 'nenalezena cesta k adapter-agent.exe'
          log(@state[:agent])
        end
        unless script
          @state[:ruby_bridge] = 'nenalezena cesta k most.rb'
          log(@state[:ruby_bridge])
        end
        if adapter && !adapter_running?(adapter)
          @adapter_launch_requested_at ||= Time.at(0)
          if Time.now - @adapter_launch_requested_at >= 15
            launch_hidden(quoted(adapter), File.dirname(adapter))
            @adapter_launch_requested_at = Time.now
          end
        end
        @state[:agent] = 'spuštěný' if adapter
        return if @script_loaded || !script || @loading_script

        # Postpone most.rb until the adapter has had time to open its socket.
        @loading_script = true
        UI.start_timer(adapter ? 1.0 : 0.0, false) do
          begin
            unless @script_loaded
              load script
              @script_loaded = true
              @state[:ruby_bridge] = 'načtený'
              log('most.rb načtený')
            end
          rescue StandardError, ScriptError => e
            @state[:ruby_bridge] = "#{e.class}: #{e.message}"
            log("most.rb chyba: #{@state[:ruby_bridge]}")
            UI.messagebox("20-20 Agent: most.rb se nenačetl:\n#{e.message}") unless silent
          ensure
            @loading_script = false
          end
        end
      rescue StandardError => e
        @state[:agent] = "#{e.class}: #{e.message}"
        log("Agent startup: #{@state[:agent]}")
        UI.messagebox("20-20 Agent: #{e.message}") unless silent
      end

      def web_bridge_online?
        BRIDGE_PORTS.any? do |port|
          Timeout.timeout(0.5) do
            socket = TCPSocket.new('127.0.0.1', port)
            socket.write("GET /status HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
            response = socket.read.to_s
            socket.close
            response.include?('"ok":true') && response.include?('bridge_version')
          end
        rescue StandardError
          false
        end
      end

      def bootstrap_cached_bridge
        FileUtils.mkdir_p(helper_dir)
        packaged = File.join(__dir__, 'windows_bridge')
        %w[bridge_v3.ps1 20-20_BRIDGE_V3.bat register_protocol_v3.ps1].each do |name|
          destination = File.join(helper_dir, name)
          source = File.join(packaged, name)
          FileUtils.cp(source, destination) if !File.file?(destination) && File.file?(source)
        end
        marker = File.join(helper_dir, 'rmtools_bridge_registered.txt')
        return if File.file?(marker)
        installer = File.join(helper_dir, 'register_protocol_v3.ps1')
        if File.file?(installer)
          command = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File #{quoted(installer)}"
          launch_hidden(command, helper_dir)
          File.write(marker, 'RM TOOLS bundled setup')
          log('Registrace lokálního Bridge spuštěna na pozadí.')
        end
      end

      def start_web_bridge
        return unless windows?
        @state ||= STATES.dup
        if web_bridge_online?
          @state[:web_bridge] = 'běží'
          return
        end
        @bridge_starting_at ||= Time.at(0)
        return if Time.now - @bridge_starting_at < 20
        @bridge_starting_at = Time.now

        unless File.file?(session_bridge_file)
          @state[:web_bridge] = 'chybí vestavěný lokální Bridge'
          log(@state[:web_bridge])
          return
        end
        bootstrap_cached_bridge
        # This packaged script remains active while SketchUp is running.
        # A plain old Bridge listening on 8092/8093 is reused instead.
        command = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " \
                  "#{quoted(session_bridge_file)} -SketchUpSession"
        launch_hidden(command, File.dirname(session_bridge_file))
        @state[:web_bridge] = 'spouští se'
        log('Lokální Bridge spuštěn ze souboru, bez stahování.')
      rescue StandardError => e
        @state[:web_bridge] = "#{e.class}: #{e.message}"
        log("Bridge startup: #{@state[:web_bridge]}")
      end

      def start
        return unless windows?
        return if @started
        @started = true
        @state ||= STATES.dup
        start_agent(silent: true)
        start_web_bridge
        # Old cached Bridge versions may stop after two idle minutes.
        # Check periodically, without downloading or opening any windows.
        UI.start_timer(CHECK_INTERVAL, true) { start_web_bridge }
      rescue StandardError => e
        log("Autostart selhal: #{e.class}: #{e.message}")
      end

      def retry_now
        return unless windows?
        start_agent(silent: false)
        @bridge_starting_at = Time.at(0)
        start_web_bridge
      end

      # Explicit manual settings only; NEVER ask for paths on startup.
      def choose_path(key, default, title, extension)
        old = Sketchup.read_default(PREF_SECTION, key, '').to_s
        suggested = File.file?(old) ? old : default
        dir = File.directory?(File.dirname(suggested)) ? File.dirname(suggested) : 'C:/'
        chosen = UI.openpanel(title, dir, extension == '.exe' ? 'EXE|*.exe||' : 'Ruby|*.rb||')
        return unless chosen
        unless File.file?(chosen) && File.extname(chosen).downcase == extension
          UI.messagebox("Vyber existující soubor #{extension}.")
          return
        end
        Sketchup.write_default(PREF_SECTION, key, chosen.tr('\\', '/'))
        @script_loaded = false if key == 'most_rb_path'
        UI.messagebox("Cesta uložena:\n#{chosen}\n\nPříště se spustí automaticky.")
      end

      def install_settings_menu
        return if @settings_menu
        @settings_menu = UI.menu('Extensions').add_submenu('20-20 RM TOOLS – Agent')
        @settings_menu.add_item('Spustit Agent a Bridge na pozadí') { retry_now }
        @settings_menu.add_item('Nastavit adapter-agent.exe…') do
          choose_path('adapter_path', DEFAULT_ADAPTER, 'Vyber adapter-agent.exe', '.exe')
        end
        @settings_menu.add_item('Nastavit most.rb…') do
          choose_path('most_rb_path', DEFAULT_SCRIPT, 'Vyber most.rb', '.rb')
        end
        @settings_menu.add_item('Stav Agenta a Bridge') do
          lines = status.map { |key,value| "#{key}: #{value}" }
          UI.messagebox(lines.join("\n"))
        end
      end
    end
  end
end
