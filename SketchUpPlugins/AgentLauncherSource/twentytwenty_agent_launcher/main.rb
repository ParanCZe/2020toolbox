# frozen_string_literal: true

require 'sketchup.rb'
require 'fileutils'

module TwentyTwenty
  module AgentLauncher
    extend self

    VERSION = '0.1.2'.freeze
    PREF_SECTION = '20-20 Agent Launcher'.freeze
    PREF_ADAPTER = 'adapter_path'.freeze
    PREF_SCRIPT = 'most_rb_path'.freeze

    DEFAULT_ADAPTER = 'C:/2020agent/dist/adapter-agent.exe'.freeze
    DEFAULT_SCRIPT = 'C:/2020agent/dist/sketchup/most.rb'.freeze

    def init
      return if @loaded
      @loaded = true
      create_commands
      create_menu
      create_toolbar
    end

    def create_commands
      @launch_command = UI::Command.new('Spustit 20-20 Agent') { launch_all }
      @launch_command.tooltip = 'Spustit adapter-agent + načíst most.rb'
      @launch_command.status_bar_text = 'Spustí adapter-agent.exe a potom načte most.rb do SketchUp Ruby prostředí.'
      setup_icon(@launch_command, 'agent_launcher.svg')

      @adapter_path_command = UI::Command.new('Změnit cestu adapter-agent.exe…') { change_adapter_path }
      @adapter_path_command.tooltip = 'Vybrat jiný adapter-agent.exe'
      @adapter_path_command.status_bar_text = 'Změní uloženou cestu k adapter-agent.exe.'

      @script_path_command = UI::Command.new('Změnit cestu most.rb…') { change_script_path }
      @script_path_command.tooltip = 'Vybrat jiný most.rb'
      @script_path_command.status_bar_text = 'Změní uloženou cestu k most.rb.'

      @show_paths_command = UI::Command.new('Zobrazit nastavené cesty') { show_paths }
      @show_paths_command.tooltip = 'Zobrazit aktuálně uložené cesty'
    end

    def create_menu
      root = UI.menu('Extensions').add_submenu('20-20 Agent Launcher')
      root.add_item(@launch_command)
      root.add_separator
      root.add_item(@adapter_path_command)
      root.add_item(@script_path_command)
      root.add_item(@show_paths_command)
    end

    def create_toolbar
      @toolbar = UI::Toolbar.new('20-20 Agent')
      @toolbar.add_item(@launch_command)
      @toolbar.restore
    rescue StandardError
      nil
    end

    def setup_icon(command, filename)
      path = File.join(__dir__, 'icons', filename)
      return unless File.file?(path)
      command.small_icon = path
      command.large_icon = path
    rescue StandardError
      nil
    end

    def launch_all
      paths = ensure_paths
      return unless paths

      adapter, script = paths

      unless adapter_running?(adapter)
        launch_adapter(adapter)
      end

      # Give the adapter a short moment to initialize before the bridge script loads.
      UI.start_timer(0.8, false) do
        begin
          load script
          Sketchup.status_text = '20-20 Agent: adapter běží + most.rb načten.'
        rescue StandardError, ScriptError => e
          UI.messagebox(
            "20-20 Agent Launcher\n\nmost.rb se nepodařilo načíst:\n" \
            "#{e.class}: #{e.message}\n\n" \
            "Cesta:\n#{script}"
          )
        end
      end
    rescue StandardError => e
      UI.messagebox("20-20 Agent Launcher\n\nSpuštění selhalo:\n#{e.class}: #{e.message}")
    end

    def ensure_paths
      adapter = stored_adapter_path
      script = stored_script_path

      # Both paths are user-specific. On first run ask for BOTH, even when the
      # conventional C:/2020agent paths happen to exist on this machine.
      unless adapter && File.file?(adapter)
        adapter = choose_adapter(adapter || DEFAULT_ADAPTER)
        return nil unless adapter
        save_adapter_path(adapter)
      end

      unless script && File.file?(script)
        script = choose_script(script || DEFAULT_SCRIPT)
        return nil unless script
        save_script_path(script)
      end

      [adapter, script]
    end

    def change_adapter_path
      current=stored_adapter_path || DEFAULT_ADAPTER
      path=choose_adapter(current)
      return unless path
      save_adapter_path(path)
      UI.messagebox("20-20 Agent Launcher\n\nCesta k adapteru uložena:\n#{path}")
    rescue StandardError => e
      UI.messagebox("Nastavení adapteru selhalo:\n#{e.class}: #{e.message}")
    end

    def change_script_path
      current=stored_script_path || DEFAULT_SCRIPT
      path=choose_script(current)
      return unless path
      save_script_path(path)
      UI.messagebox("20-20 Agent Launcher\n\nCesta k most.rb uložena:\n#{path}")
    rescue StandardError => e
      UI.messagebox("Nastavení most.rb selhalo:\n#{e.class}: #{e.message}")
    end

    def show_paths
      adapter=stored_adapter_path
      script=stored_script_path
      UI.messagebox(
        "20-20 Agent Launcher\n\n" \
        "adapter-agent.exe:\n#{adapter || '(zatím nenastaveno)'}\n\n" \
        "most.rb:\n#{script || '(zatím nenastaveno)'}"
      )
    end

    def choose_adapter(suggested)
      dir = File.dirname(normalize_path(suggested))
      dir = 'C:/' unless File.directory?(dir)
      path = UI.openpanel(
        'Vyber adapter-agent.exe',
        dir,
        'Spustitelný soubor|*.exe||'
      )
      return nil unless path
      path = normalize_path(path)
      unless File.file?(path) && File.extname(path).downcase == '.exe'
        UI.messagebox('Vyber platný soubor adapter-agent.exe.')
        return nil
      end
      path
    end

    def choose_script(suggested)
      dir = File.dirname(normalize_path(suggested))
      dir = 'C:/' unless File.directory?(dir)
      path = UI.openpanel(
        'Vyber most.rb',
        dir,
        'Ruby soubor|*.rb||'
      )
      return nil unless path
      path = normalize_path(path)
      unless File.file?(path) && File.extname(path).downcase == '.rb'
        UI.messagebox('Vyber platný soubor most.rb.')
        return nil
      end
      path
    end

    def stored_adapter_path
      value = Sketchup.read_default(PREF_SECTION, PREF_ADAPTER, '').to_s
      value.empty? ? nil : normalize_path(value)
    rescue StandardError
      nil
    end

    def stored_script_path
      value = Sketchup.read_default(PREF_SECTION, PREF_SCRIPT, '').to_s
      value.empty? ? nil : normalize_path(value)
    rescue StandardError
      nil
    end

    def save_adapter_path(path)
      Sketchup.write_default(PREF_SECTION, PREF_ADAPTER, normalize_path(path))
    end

    def save_script_path(path)
      Sketchup.write_default(PREF_SECTION, PREF_SCRIPT, normalize_path(path))
    end

    def normalize_path(path)
      path.to_s.tr('\\', '/')
    end

    def adapter_running?(adapter_path)
      exe = File.basename(adapter_path).to_s
      return false if exe.empty?

      output = IO.popen(
        ['tasklist.exe', '/FI', "IMAGENAME eq #{exe}", '/NH'],
        err: File::NULL
      ) { |io| io.read.to_s }

      output.downcase.include?(exe.downcase)
    rescue StandardError
      false
    end

    def launch_adapter(adapter_path)
      adapter = normalize_path(adapter_path)
      raise 'adapter-agent.exe nebyl nalezen.' unless File.file?(adapter)

      # cmd START detaches the adapter from SketchUp. The empty string after START
      # is the Windows window-title argument.
      pid = Process.spawn(
        'cmd.exe',
        '/c',
        'start',
        '',
        adapter,
        chdir: File.dirname(adapter),
        out: File::NULL,
        err: File::NULL
      )
      Process.detach(pid)
      true
    rescue StandardError
      # Fallback for environments where cmd START behaves differently.
      pid = Process.spawn(adapter, chdir: File.dirname(adapter))
      Process.detach(pid)
      true
    end

  end
end

TwentyTwenty::AgentLauncher.init
