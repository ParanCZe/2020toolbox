# frozen_string_literal: true
# 20-20 RM TOOLS: headless autostart derived from Agent Launcher v0.1.2.
# No separate extension, toolbar or automatic file chooser.
require 'sketchup.rb'
require 'json'
require 'socket'
require 'timeout'
require 'fileutils'
require 'digest'

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

      # VBScript receives NO command-line arguments: WScript.Arguments(0)
      # previously lost quotes around paths and raised Windows error 80070002.
      # Instead embed the exact validated command and working directory in
      # one private per-command script, escaping VBScript's double quotes.
      def vbs_literal(value)
        raise 'Neplatný znak v cestě nebo příkazu.' if value.to_s =~ /[\r\n]/
        '"' + value.to_s.gsub('"', '""') + '"'
      end

      def powershell_path
        File.join(ENV.fetch('WINDIR', 'C:/Windows'), 'System32',
                  'WindowsPowerShell', 'v1.0', 'powershell.exe')
      end

      def powershell_command(script, extra = '')
        "#{quoted(powershell_path)} -NoProfile -NonInteractive " \
          "-ExecutionPolicy Bypass -WindowStyle Hidden -File #{quoted(script)} #{extra}".strip
      end

      def hidden_runner(command, cwd)
        raise 'Chybí platná pracovní složka spouštěče.' unless File.directory?(cwd)
        # The original runner has a broken argument-based launch syntax and
        # must never be called by this version, even if it remains in AppData.
        FileUtils.mkdir_p(helper_dir)
        digest = Digest::SHA256.hexdigest("#{Process.pid}\0#{command}\0#{cwd}")[0, 20]
        path = File.join(helper_dir, "rmtools_hidden_#{digest}.vbs")
        logfile = File.join(ENV.fetch('APPDATA'), '2020toolbox', 'rmtools_autostart.log')
        contents = <<~VBS
          On Error Resume Next
          Set sh = CreateObject("WScript.Shell")
          sh.CurrentDirectory = #{vbs_literal(cwd.tr('/', '\\'))}
          If Err.Number = 0 Then sh.Run #{vbs_literal(command)}, 0, False
          If Err.Number <> 0 Then
            errorNumber = Err.Number
            errorText = Err.Description
            Err.Clear
            Set fs = CreateObject("Scripting.FileSystemObject")
            Set output = fs.OpenTextFile(#{vbs_literal(logfile.tr('/', '\\'))}, 8, True)
            If Err.Number = 0 Then
              output.WriteLine Now & " WScript: " & errorNumber & " " & errorText
              output.Close
            End If
          End If
        VBS
        # WScript understands UTF-16 LE with BOM; Windows user paths may have
        # accented characters that ANSI/UTF-8 .vbs files would corrupt.
        data = "\xFF\xFE".b + contents.encode('UTF-16LE').b
        File.binwrite(path, data) unless File.file?(path) && File.binread(path) == data
        path
      end

      # WScript //B suppresses all host dialogs if the called program is
      # missing; hidden_runner logs errors instead of showing a popup.
      def launch_hidden(command, cwd)
        windir = ENV.fetch('WINDIR', 'C:/Windows')
        wscript = File.join(windir, 'System32', 'wscript.exe')
        raise "Windows Script Host nebyl nalezen: #{wscript}" unless File.file?(wscript)
        executable = command.start_with?('"') ? command.split('"', 3)[1] : command.split(/\s+/, 2).first
        unless executable && File.file?(executable)
          raise "Spouštěný program nebyl nalezen: #{executable || command}"
        end
        runner = hidden_runner(command, cwd)
        pid = Process.spawn(wscript, '//B', '//Nologo', runner,
                            out: File::NULL, err: File::NULL)
        Process.detach(pid)
        true
      end

      def quoted(file)
        raise 'Neplatná cesta ke spustitelnému souboru.' if file.to_s =~ /["\r\n]/
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
          next unless File.file?(source)

          # Repair the one malformed legacy release only. Never overwrite an
          # otherwise valid cached user-installed Bridge at every startup.
          bad_bridge = false
          if name == 'bridge_v3.ps1' && File.file?(destination)
            cached = File.binread(destination)
            bad_bridge = cached.scan('$su=Get-SketchUp').length > 1 ||
                         cached.include?("BRIDGE STOP'\n){Remove-StandaloneLaunchers")
          end
          if !File.file?(destination) || bad_bridge
            FileUtils.cp(source, destination)
            log('Opraven poškozený lokální Bridge.') if bad_bridge
          end
        end
        marker = File.join(helper_dir, 'rmtools_bridge_registered.txt')
        return if File.file?(marker)
        installer = File.join(helper_dir, 'register_protocol_v3.ps1')
        if File.file?(installer)
          command = powershell_command(installer)
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
        command = powershell_command(session_bridge_file, '-SketchUpSession')
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
