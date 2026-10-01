# frozen_string_literal: true

require 'sketchup.rb'
require 'json'
require 'digest/sha1'
require 'uri'
require 'fileutils'

module Dvacet20
  module ComponentLibrary
    extend self

    VERSION = '0.3.3'.freeze
    PREF_KEY = 'Dvacet20_ComponentLibrary'.freeze
    PREF_ROOT = 'library_root'.freeze
    DEFAULT_LIBRARY_ROOT = 'S:/PODKLADY/PODKLADY 3D/SKP KOMPONENTY'.freeze
    DIALOG_KEY = 'Dvacet20ComponentLibrary'.freeze

    def library_root
      Sketchup.read_default(PREF_KEY, PREF_ROOT, DEFAULT_LIBRARY_ROOT).to_s
    end

    def library_root=(path)
      Sketchup.write_default(PREF_KEY, PREF_ROOT, path.to_s)
    end

    def cache_root
      base = if Sketchup.platform == :platform_win
               ENV['LOCALAPPDATA'] || ENV['APPDATA'] || Sketchup.temp_dir
             else
               File.expand_path('~/Library/Application Support')
             end
      path = File.join(base, '20-20', 'ComponentLibrary', 'thumbs')
      FileUtils.mkdir_p(path) unless File.directory?(path)
      path
    rescue StandardError
      fallback = File.join(Sketchup.temp_dir, '20-20-component-library-thumbs')
      FileUtils.mkdir_p(fallback) unless File.directory?(fallback)
      fallback
    end

    def file_url(path)
      normalized = File.expand_path(path.to_s).tr('\\', '/')
      prefix = normalized =~ %r{\A[A-Za-z]:/} ? 'file:///' : 'file://'
      URI::DEFAULT_PARSER.escape(prefix + normalized)
    rescue StandardError
      nil
    end

    def sidecar_preview(skp_path)
      base = skp_path.sub(/\.skp\z/i, '')
      candidates = [
        "#{base}.png", "#{base}.jpg", "#{base}.jpeg", "#{base}.webp",
        File.join(File.dirname(skp_path), 'preview.png'),
        File.join(File.dirname(skp_path), 'preview.jpg'),
        File.join(File.dirname(skp_path), 'preview.jpeg'),
        File.join(File.dirname(skp_path), 'preview.webp')
      ]
      candidates.find { |candidate| File.file?(candidate) }
    end

    def thumbnail_cache_path(skp_path, stat = nil)
      stat ||= File.stat(skp_path)
      key = Digest::SHA1.hexdigest("#{skp_path}|#{stat.mtime.to_i}|#{stat.size}")
      File.join(cache_root, "#{key}.png")
    end

    # Vrátí pouze náhled, který už existuje. Nic negeneruje a proto je vhodný
    # pro rychlý prvotní scan síťové knihovny.
    def existing_preview(skp_path, stat = nil)
      custom = sidecar_preview(skp_path)
      return custom if custom

      cached = thumbnail_cache_path(skp_path, stat)
      File.file?(cached) && File.size?(cached) ? cached : nil
    rescue StandardError
      nil
    end

    def thumbnail_for(skp_path)
      stat = File.stat(skp_path)
      existing = existing_preview(skp_path, stat)
      return existing if existing

      thumb = thumbnail_cache_path(skp_path, stat)
      ok = Sketchup.save_thumbnail(skp_path, thumb)
      ok && File.file?(thumb) && File.size?(thumb) ? thumb : nil
    rescue StandardError => e
      puts "[20-20 KOMPONENTY] Náhled selhal: #{skp_path} — #{e.message}"
      nil
    end

    def human_name(path)
      File.basename(path, File.extname(path)).tr('_-', '  ').gsub(/\s+/, ' ').strip
    end

    def pretty_field(value)
      value.to_s.tr('-', ' ').gsub(/\s+/, ' ').strip
    end

    # Konvence názvu:
    # TYP_VYROBCE_MODELOVA-RADA_IDENTIFIKATOR.skp
    # Např. WC_LAUFEN_PRO_820966.skp
    # První tři segmenty jsou pevné; vše od čtvrtého segmentu dál patří
    # do identifikátoru, takže může obsahovat další podtržítka.
    def parse_component_name(path)
      stem = File.basename(path, File.extname(path)).to_s
      parts = stem.split('_').map(&:strip).reject(&:empty?)

      if parts.length >= 4
        type = pretty_field(parts[0])
        manufacturer = pretty_field(parts[1])
        series = pretty_field(parts[2])
        identifier_raw = parts[3..].join('_')
        identifier = pretty_field(identifier_raw.tr('_', ' '))
        {
          naming_ok: true,
          type: type.empty? ? 'NEZAŘAZENO' : type,
          manufacturer: manufacturer.empty? ? 'NEZAŘAZENO' : manufacturer,
          series: series.empty? ? 'NEZAŘAZENO' : series,
          identifier: identifier.empty? ? stem : identifier,
          display_name: [manufacturer, series, identifier].reject(&:empty?).join(' ')
        }
      else
        {
          naming_ok: false,
          type: 'NEZAŘAZENO',
          manufacturer: 'NEZAŘAZENO',
          series: 'NEZAŘAZENO',
          identifier: human_name(path),
          display_name: human_name(path)
        }
      end
    end

    def relative_path(path, root)
      expanded_root = File.expand_path(root).tr('\\', '/')
      expanded_path = File.expand_path(path).tr('\\', '/')
      prefix = expanded_root.end_with?('/') ? expanded_root : "#{expanded_root}/"
      expanded_path.start_with?(prefix) ? expanded_path[prefix.length..] : File.basename(path)
    end

    def pretty_size(bytes)
      return "#{bytes} B" if bytes < 1024
      return format('%.1f KB', bytes / 1024.0) if bytes < 1024 * 1024
      format('%.1f MB', bytes / (1024.0 * 1024.0))
    end

    def scan_library
      root = library_root
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      puts "[20-20 KOMPONENTY] Scan start: #{root}"
      unless File.directory?(root)
        return {
          ok: false,
          root: root,
          version: VERSION,
          message: 'Serverová složka není dostupná.',
          components: [],
          categories: []
        }
      end

      # Síťový disk S: může být u Dir.glob('**/*') překvapivě pomalý nebo
      # se na některých Windows konfiguracích zaseknout. Procházíme proto pouze
      # adresáře a SKP soubory explicitně.
      files = []
      stack = [root]
      until stack.empty?
        dir = stack.pop
        begin
          Dir.each_child(dir) do |name|
            next if name == '.' || name == '..'
            path = File.join(dir, name)
            if File.directory?(path)
              stack << path
            elsif File.file?(path) && File.extname(path).casecmp('.skp').zero?
              files << path
            end
          end
        rescue SystemCallError => e
          puts "[20-20 KOMPONENTY] Nelze projít #{dir}: #{e.class}: #{e.message}"
        end
      end

      components = files.sort_by { |path| relative_path(path, root).downcase }.map.with_index do |path, index|
        stat = File.stat(path)
        parsed = parse_component_name(path)
        # DŮLEŽITÉ: při prvním načtení NIKDY negenerujeme thumbnail každého SKP.
        # To by u síťové knihovny blokovalo UI i několik minut. Použijeme pouze
        # existující sidecar obrázek; chybějící thumbnaily se generují líně až
        # po vykreslení karet v HtmlDialogu.
        preview = existing_preview(path, stat)
        {
          id: index.to_s,
          name: human_name(path),
          display_name: parsed[:display_name],
          naming_ok: parsed[:naming_ok],
          type: parsed[:type],
          manufacturer: parsed[:manufacturer],
          series: parsed[:series],
          identifier: parsed[:identifier],
          relative_path: relative_path(path, root),
          path: path,
          preview: preview ? file_url(preview) : nil,
          size: pretty_size(stat.size),
          modified: stat.mtime.strftime('%d.%m.%Y %H:%M')
        }
      end

      categories = components.map { |c| c[:type] }.uniq.sort_by(&:downcase)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      puts format('[20-20 KOMPONENTY] Scan hotov: %d komponent za %.2f s', components.length, elapsed)
      {
        ok: true,
        root: root,
        version: VERSION,
        message: "Načteno #{components.length} komponent.",
        components: components,
        categories: categories
      }
    rescue StandardError => e
      puts "[20-20 KOMPONENTY] Scan selhal: #{e.class}: #{e.message}\n#{e.backtrace&.join("\n")}"
      {
        ok: false,
        root: root,
        version: VERSION,
        message: "Chyba při načítání knihovny: #{e.message}",
        components: [],
        categories: []
      }
    end

    def send_library(dialog = @dialog)
      return unless dialog
      payload = JSON.generate(scan_library)
      dialog.execute_script("window.ComponentLibrary && window.ComponentLibrary.setLibrary(#{payload});")
    rescue StandardError => e
      puts "[20-20 KOMPONENTY] Odeslání dat do panelu selhalo: #{e.message}"
    end

    def show_dialog
      if @dialog&.visible?
        @dialog.bring_to_front
        send_library(@dialog)
        return
      end

      @dialog = UI::HtmlDialog.new(
        dialog_title: '20-20 KNIHOVNA KOMPONENT',
        preferences_key: DIALOG_KEY,
        scrollable: false,
        resizable: true,
        width: 1120,
        height: 760,
        min_width: 720,
        min_height: 520,
        style: UI::HtmlDialog::STYLE_DIALOG
      )

      @dialog.add_action_callback('ready') do |_action_context, _|
        send_library(@dialog)
      end

      @dialog.add_action_callback('refreshLibrary') do |_action_context, _|
        send_library(@dialog)
      end

      @dialog.add_action_callback('chooseFolder') do |_action_context, _|
        begin
          selected = UI.select_directory(title: 'Vyber složku SKP KOMPONENTY', directory: library_root)
        rescue ArgumentError
          selected = UI.select_directory
        end
        if selected && File.directory?(selected)
          self.library_root = selected
        end
        send_library(@dialog)
      end

      @dialog.add_action_callback('resetFolder') do |_action_context, _|
        self.library_root = DEFAULT_LIBRARY_ROOT
        send_library(@dialog)
      end

      @dialog.add_action_callback('openFolder') do |_action_context, _|
        root = library_root
        unless File.directory?(root)
          UI.messagebox("Složka není dostupná:\n#{root}")
          next
        end

        if Sketchup.platform == :platform_win
          system('explorer.exe', root.tr('/', '\\'))
        else
          system('open', root)
        end
      end

      @dialog.add_action_callback('requestThumbnail') do |_action_context, json|
        begin
          data = JSON.parse(json.to_s)
          path = data['path'].to_s
          request_thumbnail(path, @dialog)
        rescue StandardError => e
          puts "[20-20 KOMPONENTY] Požadavek na náhled selhal: #{e.class}: #{e.message}"
          thumbnail_failed(@dialog, '')
        end
      end

      @dialog.add_action_callback('insertComponent') do |_action_context, json|
        begin
          data = JSON.parse(json.to_s)
          path = data['path'].to_s
          insert_component(path, @dialog)
        rescue StandardError => e
          show_error(@dialog, "Nepodařilo se zpracovat komponentu: #{e.message}")
        end
      end

      @dialog.set_on_closed { @dialog = nil }

      # Callbacky registrujeme PŘED načtením HTML. U HtmlDialogu je to
      # spolehlivější a vyhneme se stavu, kdy stránka zavolá ready dřív,
      # než Ruby callback existuje.
      @dialog.set_file(File.join(__dir__, 'ui', 'library.html'))
      @dialog.show

      # Failsafe: i kdyby JS ready handshake z nějakého důvodu neproběhl,
      # po otevření panelu knihovnu pošleme z Ruby strany. Druhý pokus kryje
      # pomalejší start CEF na některých PC.
      UI.start_timer(0.35, false) { send_library(@dialog) if @dialog }
      UI.start_timer(1.20, false) { send_library(@dialog) if @dialog }
    end

    def request_thumbnail(path, dialog = @dialog)
      unless File.file?(path) && File.extname(path).casecmp('.skp').zero?
        thumbnail_failed(dialog, path)
        return
      end

      # Jeden thumbnail po druhém. HtmlDialog si drží frontu a další požadavek
      # pošle až po odpovědi, takže SketchUp nezamrzne kvůli celé knihovně naráz.
      UI.start_timer(0, false) do
        begin
          preview = thumbnail_for(path)
          if preview && File.file?(preview)
            url = file_url(preview)
            dialog.execute_script(
              "window.ComponentLibrary && window.ComponentLibrary.thumbnailReady(#{JSON.generate(path)}, #{JSON.generate(url)});"
            ) if dialog
          else
            thumbnail_failed(dialog, path)
          end
        rescue StandardError => e
          puts "[20-20 KOMPONENTY] Lazy náhled selhal: #{path} — #{e.class}: #{e.message}"
          thumbnail_failed(dialog, path)
        end
      end
    end

    def thumbnail_failed(dialog, path)
      return unless dialog
      dialog.execute_script(
        "window.ComponentLibrary && window.ComponentLibrary.thumbnailFailed(#{JSON.generate(path)});"
      )
    rescue StandardError
      nil
    end

    # Původní komponenta ze SKP se vkládá přímo. Observer pouze po dokončení
    # placementu obnoví metadata kořenové instance a případnou původní
    # transformaci vůči bodu vložení zdrojového SKP. Nevkládá žádnou obalovou
    # definici, takže ani při chybě observeru nemůže vzniknout komponenta v komponentě.
    class PlacementMetadataObserver < Sketchup::EntitiesObserver
      def initialize(owner, target_definition, source_transform, metadata, file_wrapper)
        @owner = owner
        @target_definition = target_definition
        @source_transform = source_transform
        @metadata = metadata
        @file_wrapper = file_wrapper
        @done = false
      end

      def onElementAdded(entities, entity)
        return if @done
        return unless entity.is_a?(Sketchup::ComponentInstance)
        return unless entity.definition == @target_definition

        @done = true
        @owner.release_placement_observer(self)
        # SketchUp musí nejprve dokončit nativní vložení, jinak může přepsat
        # transformaci instance. Tuto úpravu provedeme až v dalším UI cyklu.
        UI.start_timer(0, false) do
          begin
            if entity.valid?
              initial = Geom::Transformation.new
              unless @source_transform.to_a == initial.to_a
                entity.transformation = entity.transformation * @source_transform
              end
              @owner.apply_instance_metadata(entity, @metadata)
              @owner.discard_unused_file_wrapper(entity.model, @file_wrapper, @target_definition)
            end
          rescue StandardError => e
            puts "[20-20 KOMPONENTY] Metadata po vložení: #{e.class}: #{e.message}"
          end
        end
      end
    end

    def extract_instance_metadata(instance)
      dictionaries = {}
      if instance.attribute_dictionaries
        instance.attribute_dictionaries.each do |dict|
          pairs = {}
          dict.each_pair { |key, value| pairs[key] = value }
          dictionaries[dict.name] = pairs
        end
      end

      {
        layer_name: (instance.layer && instance.layer.name),
        name: instance.name.to_s,
        material_name: (instance.material && instance.material.name),
        hidden: instance.hidden?,
        casts_shadows: instance.casts_shadows?,
        receives_shadows: instance.receives_shadows?,
        locked: (instance.respond_to?(:locked?) ? instance.locked? : false),
        attributes: dictionaries
      }
    rescue StandardError => e
      puts "[20-20 KOMPONENTY] Metadata instance se nepodařilo přečíst: #{e.message}"
      {}
    end

    def apply_instance_metadata(instance, metadata)
      model = instance.model

      layer_name = metadata[:layer_name].to_s
      unless layer_name.empty?
        layer = model.layers[layer_name] || model.layers.add(layer_name)
        instance.layer = layer if layer
      end

      instance.name = metadata[:name].to_s unless metadata[:name].to_s.empty?

      material_name = metadata[:material_name].to_s
      unless material_name.empty?
        material = model.materials[material_name]
        instance.material = material if material
      end

      instance.hidden = metadata[:hidden] unless metadata[:hidden].nil?
      instance.casts_shadows = metadata[:casts_shadows] unless metadata[:casts_shadows].nil?
      instance.receives_shadows = metadata[:receives_shadows] unless metadata[:receives_shadows].nil?
      instance.locked = metadata[:locked] if instance.respond_to?(:locked=) && !metadata[:locked].nil?

      (metadata[:attributes] || {}).each do |dict_name, pairs|
        pairs.each { |key, value| instance.set_attribute(dict_name, key, value) }
      end
    rescue StandardError => e
      puts "[20-20 KOMPONENTY] Metadata instance se nepodařilo aplikovat: #{e.class}: #{e.message}"
    end

    def register_placement_metadata_observer(entities, target_definition, source_transform, metadata, file_wrapper)
      @placement_observers ||= []
      observer = PlacementMetadataObserver.new(self, target_definition, source_transform, metadata, file_wrapper)
      entities.add_observer(observer)
      @placement_observers << [entities, observer]

      # Pokud uživatel vložení zruší přes Esc, observer se automaticky odstraní.
      UI.start_timer(120.0, false) { release_placement_observer(observer) }
      observer
    rescue StandardError => e
      puts "[20-20 KOMPONENTY] Metadata observer selhal: #{e.message}"
      nil
    end

    # A loaded .skp creates an unused file-level component definition.
    # After placing the actual component, remove this unused import wrapper
    # so it does not clutter the In Model component library.
    def discard_unused_file_wrapper(model, wrapper, target)
      return unless wrapper && !wrapper.equal?(target)
      return unless wrapper.respond_to?(:instances) && wrapper.instances.empty?
      model.definitions.remove(wrapper) if model.definitions.respond_to?(:remove)
    rescue StandardError => e
      puts "[20-20 KOMPONENTY] Nepoužitý obal nešel odebrat: #{e.message}"
    end

    def release_placement_observer(observer)
      return unless @placement_observers
      pair = @placement_observers.find { |(_entities, obs)| obs.equal?(observer) }
      return unless pair

      entities, obs = pair
      begin
        entities.remove_observer(obs)
      rescue StandardError
        nil
      end
      @placement_observers.delete(pair)
    end

    # Jediná kořenová komponenta je hotový model, nikoliv obsah pro
    # vytvoření další vnější komponenty. Ignorujeme pouze konstrukční vodítka,
    # nikoliv další viditelnou geometrii, kterou by přímý import ztratil.
    # No fallback to loaded_definition! It is only a temporary file wrapper,
    # NEVER a model the user wants to place. Import the existing SKP component.
    def placement_target(loaded_definition)
      top_level = loaded_definition.entities.to_a
      existing_components = top_level.select { |entity| entity.is_a?(Sketchup::ComponentInstance) }
      if existing_components.length != 1
        classes = top_level.map { |entity| entity.class.name }.each_with_object(Hash.new(0)) { |name, counts| counts[name] += 1 }
        raise "SKP musí mít přesně jednu hlavní komponentu. Načteno: #{existing_components.length}. " \
              "Kořenové objekty: #{classes.map { |k, v| "#{k} (#{v})" }.join(', ')}. " \
              "Další obalovou komponentu knihovna nikdy nevytvoří."
      end

      original = existing_components.first
      other_visible = top_level.reject do |entity|
        entity.equal?(original) ||
          entity.is_a?(Sketchup::ConstructionPoint) ||
          entity.is_a?(Sketchup::ConstructionLine) ||
          (entity.respond_to?(:hidden?) && entity.hidden?)
      end
      unless other_visible.empty?
        raise "Vedle hlavní komponenty je v SKP další viditelná geometrie " \
              "(#{other_visible.map { |entity| entity.class.name }.uniq.join(', ')}). " \
              "Abych ji bez souhlasu nezahodil, import jsem zastavil. Žádný obal nevznikl."
      end

      [original.definition, original.transformation, extract_instance_metadata(original), true]
    end

    def insert_component(path, dialog = @dialog)
      unless File.file?(path) && File.extname(path).casecmp('.skp').zero?
        show_error(dialog, "Soubor komponenty není dostupný:\n#{path}")
        return
      end

      # Odložené spuštění mimo HtmlDialog callback je stabilnější napříč platformami.
      UI.start_timer(0, false) do
        begin
          model = Sketchup.active_model
          Sketchup.set_status_text("20-20: načítám #{File.basename(path)}…")
          loaded_definition = model.definitions.load(path)
          raise 'SketchUp komponentu nenačetl.' unless loaded_definition

          target_definition, source_transform, metadata, unwrapped = placement_target(loaded_definition)
          raise 'Komponenta nemá platnou definici.' unless target_definition
          raise 'Obalová komponenta není povolená.' unless unwrapped && target_definition != loaded_definition

          # There is intentionally NO fallback that places loaded_definition.
          # It is an import wrapper created by SketchUp, not the user's model.
          # Metadata are applied after the existing component is placed.
          register_placement_metadata_observer(
            model.active_entities,
            target_definition,
            source_transform,
            metadata,
            loaded_definition
          )
          model.place_component(target_definition, false)

          Sketchup.set_status_text("20-20: #{File.basename(path)} připraveno – původní komponenta bez obalu")
          dialog.execute_script(
            "window.ComponentLibrary && window.ComponentLibrary.insertDone(#{JSON.generate(path)}, #{unwrapped ? 'true' : 'false'});"
          ) if dialog
        rescue StandardError => e
          Sketchup.set_status_text('')
          puts "[20-20 KOMPONENTY] Vložení selhalo: #{e.class}: #{e.message}\n#{e.backtrace&.join("\n")}"
          show_error(dialog, "Komponentu se nepodařilo načíst.\n\n#{e.message}")
        end
      end
    end

    def show_error(dialog, message)
      if dialog
        dialog.execute_script("window.ComponentLibrary && window.ComponentLibrary.showError(#{JSON.generate(message)});")
      else
        UI.messagebox(message)
      end
    rescue StandardError
      UI.messagebox(message)
    end

    unless file_loaded?(__FILE__)
      command = UI::Command.new('20-20 Knihovna komponent') { show_dialog }
      command.tooltip = '20-20 Knihovna komponent'
      command.status_bar_text = 'Otevře serverovou knihovnu SKP komponent.'
      small_icon = File.join(__dir__, 'icons', 'library_24.png')
      large_icon = File.join(__dir__, 'icons', 'library_32.png')
      command.small_icon = small_icon if File.file?(small_icon)
      command.large_icon = large_icon if File.file?(large_icon)

      UI.menu('Extensions').add_item(command)
      toolbar = UI::Toolbar.new('20-20 KOMPONENTY')
      toolbar.add_item(command)
      toolbar.restore

      file_loaded(__FILE__)
    end
  end
end
