# frozen_string_literal: true

# 20-20 Materials Library: an icon toolbar that can be docked on the left.
# Uses the SAME material panel as AI-TOOLS and Rhino, hosted by the local Agent.
# A SketchUp HtmlDialog itself cannot be inserted into the native side tray;
# the one-icon native UI::Toolbar is dockable and opens the original panel.
require 'sketchup.rb'
require 'socket'
require 'timeout'

module TwentyTwenty
  module RMToolsSuite
    module MaterialLibrary
      extend self

      URL = 'http://127.0.0.1:8787/knihovna?cad=sketchup'.freeze
      TOOLBAR_TITLE = '20-20 Knihovna materiálů'.freeze
      MAX_STARTUP_ATTEMPTS = 20
      RETRY_SECONDS = 3.0

      def log(message)
        if defined?(TwentyTwenty::RMToolsSuite::AgentBoot)
          TwentyTwenty::RMToolsSuite::AgentBoot.log("Knihovna materiálů: #{message}")
        else
          puts "[20-20 RM TOOLS materials] #{message}"
        end
      rescue StandardError
        nil
      end

      def agent_online?
        Timeout.timeout(0.5) do
          socket = TCPSocket.new('127.0.0.1', 8787)
          socket.close
          true
        end
      rescue StandardError
        false
      end

      def show(silent: false)
        unless agent_online?
          log('Agent na portu 8787 ještě neodpovídá.')
          UI.messagebox(
            "Knihovna materiálů: lokální Agent ještě neběží.\n" \
            "Ověř cestu k adapter-agent.exe v Rozšíření → 20-20 RM TOOLS – Agent."
          ) unless silent
          return false
        end

        # If the existing AI-TOOLS material dialog is already installed, reuse
        # it. This keeps the existing API, saved window size and prevents two
        # material-library windows when both extensions are installed.
        if defined?(Dvacet20::Most) && Dvacet20::Most.respond_to?(:panel_knihovny)
          Dvacet20::Most.panel_knihovny
          @last_open_method = :existing_ai_tools
          return true
        end

        unless @dialog
          @dialog = UI::HtmlDialog.new(
            dialog_title: TOOLBAR_TITLE,
            preferences_key: 'cz.dvacet20.knihovna',
            scrollable: true,
            resizable: true,
            width: 1000,
            height: 720,
            min_width: 580,
            min_height: 430,
            style: UI::HtmlDialog::STYLE_DIALOG
          )
          @dialog.set_url(URL)
          @dialog.set_on_closed { @dialog = nil }
        end
        @dialog.show
        @last_open_method = :integrated
        true
      rescue StandardError => e
        log("Otevření okna selhalo: #{e.class}: #{e.message}")
        UI.messagebox("Knihovnu materiálů se nepodařilo otevřít:\n#{e.message}") unless silent
        false
      end

      def install_toolbar
        return @toolbar if @toolbar
        # most.rb / separately installed AI-TOOLS may already provide this
        # exact native library button. Reuse it to avoid two left-side icons.
        if defined?(Dvacet20::Most) && Dvacet20::Most.respond_to?(:zobraz_listu)
          Dvacet20::Most.zobraz_listu
          @toolbar = :existing_ai_tools
          log('Použita stávající ikona Knihovny materiálů z most.rb.')
          return @toolbar
        end
        @command = UI::Command.new(TOOLBAR_TITLE) { show }
        @command.tooltip = TOOLBAR_TITLE
        @command.status_bar_text = 'Otevře původní Knihovnu materiálů 20/20 (lokální Agent).'
        small_icon = File.join(__dir__, 'icons', 'material_library_24.png')
        large_icon = File.join(__dir__, 'icons', 'material_library_32.png')
        @command.small_icon = small_icon if File.file?(small_icon)
        @command.large_icon = large_icon if File.file?(large_icon)
        @toolbar = UI::Toolbar.new(TOOLBAR_TITLE)
        @toolbar.add_item(@command)
        # SketchUp restores a toolbar's last docked position. On first install
        # the user can dock it on the left once, as for every native toolbar.
        @toolbar.restore
        @toolbar.show unless @toolbar.visible?
        @toolbar
      rescue StandardError => e
        log("Lišta s ikonou se nepodařila vytvořit: #{e.class}: #{e.message}")
        nil
      end

      def startup
        return if @startup_finished || @startup_pending
        @startup_pending = true
        @startup_attempts = 0
        schedule_startup_retry
      end

      def schedule_startup_retry
        UI.start_timer(RETRY_SECONDS, false) do
          @startup_attempts += 1
          if agent_online?
            @startup_finished = show(silent: true)
            @startup_pending = false
            log('Okno knihovny otevřeno po spuštění SketchUpu.') if @startup_finished
          elsif @startup_attempts < MAX_STARTUP_ATTEMPTS
            schedule_startup_retry
          else
            @startup_finished = true
            @startup_pending = false
            log('Agent nezačal odpovídat do minuty; ikona knihovny je stále dostupná.')
          end
        end
      rescue StandardError => e
        @startup_pending = false
        log("Odložené otevření se nezdařilo: #{e.message}")
      end

      def command
        @command
      end
    end
  end
end
