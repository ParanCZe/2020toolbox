# frozen_string_literal: true

require 'sketchup.rb'
require 'json'
require 'digest/sha1'
require 'uri'
require 'fileutils'

module Dvacet20
  module ComponentLibrary
    extend self

    VERSION = '0.3.4'.freeze
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

      # Síťový disk: každý File.file?/File.directory? je další round-trip.
      # Proto uděláme jeden File.stat na položku a zároveň si v jednom průchodu
      # zaindexujeme sidecar náhledy ve stejné složce.
      records = []
      stack = [root]
      until stack.empty?
        dir = stack.pop
        begin
          entries = Dir.children(dir)
          files_in_dir = {}
          entries.each do |name|
            path = File.join(dir, name)
            begin
              stat = File.stat(path)
            rescue SystemCallError
              next
            end
            if stat.directory?
              stack << path
            elsif stat.file?
              files_in_dir[name.downcase] = [path, stat]
            end
          end

          files_in_dir.each_value do |path, stat|
            next unless File.extname(path).casecmp('.skp').zero?
            stem = File.basename(path, File.extname(path))
            candidate_names = [
              "#{stem}.png", "#{stem}.jpg", "#{stem}.jpeg", "#{stem}.webp",
              'preview.png', 'preview.jpg', 'preview.jpeg', 'preview.webp'
            ]
            preview = candidate_names.lazy.map { |name| files_in_dir[name.downcase]&.first }.find(&:itself)
            unless preview
              cached = thumbnail_cache_path(path, stat)
              preview = cached if File.file?(cached) && File.size?(cached)
            end
            records << [path, stat, preview]
          end
        rescue SystemCallError => e
          puts "[20-20 KOMPONENTY] Nelze projít #{dir}: #{e.class}: #{e.message}"
        end
      end

      components = records.sort_by { |path, _stat, _preview| relative_path(path, root).downcase }.map.with_index do |record, index|
        path, stat, preview = record
        parsed = parse_component_name(path)
        # Náhledy se při scanu pouze dohledají; chybějící se stále generují
        # líně až po požadavku HtmlDialogu.
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

    # Several ComponentInstances at SKP root are legitimate (some BIM models
    # expose their individual parts this way). Never choose an arbitrary first
    # component and never place the file wrapper definition.
    def placement_roots(loaded_definition)
      top_level = loaded_definition.entities.to_a
      components = top_level.select { |entity| entity.is_a?(Sketchup::ComponentInstance) }
      raise 'SKP neobsahuje žádnou existující komponentu. Import zastaven bez vytvoření obalu.' if components.empty?

      extra = top_level.reject do |entity|
        entity.is_a?(Sketchup::ComponentInstance) ||
          entity.is_a?(Sketchup::ConstructionPoint) ||
          entity.is_a?(Sketchup::ConstructionLine) ||
          (entity.respond_to?(:hidden?) && entity.hidden?)
      end
      unless extra.empty?
        names = extra.map { |entity| entity.class.name }.uniq.join(', ')
        raise "Soubor má vedle komponent také samostatnou geometrii (#{names}). " \
              'Aby se žádná neztratila a nevznikl další obal, import je zastaven.'
      end

      components.map do |instance|
        {
          definition: instance.definition,
          transform: instance.transformation,
          metadata: extract_instance_metadata(instance)
        }
      end
    end

    # Standard SketchUp placement can only place ONE definition at once. For a
    # model containing several top-level instances, a native SketchUp Tool
    # inserts each ORIGINAL instance into the same relative position upon click.
    # No new ComponentDefinition or wrapper is created by this Tool.
    class DirectMultiPlacementTool
      def initialize(owner, roots, file_wrapper)
        @owner = owner
        @roots = roots
        @file_wrapper = file_wrapper
        @input_point = Sketchup::InputPoint.new
        @point = nil
      end

      def activate
        Sketchup.set_status_text("20-20: klikni pro vložení #{@roots.length} existujících komponent bez obalu. Esc = zrušit.")
      end

      def onMouseMove(_flags, x, y, view)
        @input_point.pick(view, x, y)
        @point = @input_point.valid? ? @input_point.position : ground_point(view, x, y)
        view.tooltip = @input_point.tooltip if @input_point.valid?
        view.invalidate
      end

      def draw(view)
        @input_point.draw(view) if @input_point.valid?
      end

      def onLButtonDown(_flags, x, y, view)
        # The source SKP's [0,0,0] is the insertion point, not a component
        # bounding-box corner. Keep every component's relative transform.
        point = @point || ground_point(view, x, y)
        unless point
          UI.messagebox('Vyber bod v modelu nebo v rovině terénu pro vložení.')
          return
        end
        model = Sketchup.active_model
        model.start_operation('20-20 Vložit model bez obalové komponenty', true)
        begin
          translation = Geom::Transformation.translation(point)
          new_instances = @roots.map do |root|
            placed = model.active_entities.add_instance(
              root[:definition], translation * root[:transform]
            )
            @owner.apply_instance_metadata(placed, root[:metadata])
            placed
          end
          model.commit_operation
          begin
            model.selection.clear
            new_instances.each { |instance| model.selection.add(instance) }
          rescue StandardError
            nil
          end
          @owner.discard_unused_file_wrapper(model, @file_wrapper, nil)
          Sketchup.set_status_text("20-20: vloženo #{new_instances.length} komponent bez dalšího obalu.")
          model.select_tool(nil)
        rescue StandardError => e
          model.abort_operation
          UI.messagebox("Vložení komponent selhalo: #{e.message}")
        end
      end

      def ground_point(view, x, y)
        ray = view.pickray(x, y)
        Geom.intersect_line_plane(ray, [ORIGIN, Z_AXIS])
      rescue StandardError
        nil
      end

      def onCancel(_reason, _view)
        Sketchup.set_status_text('20-20: vkládání zrušeno')
      end
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

          roots = placement_roots(loaded_definition)
          raise 'Ve zdrojovém souboru nejsou žádné komponenty.' if roots.empty?

          if roots.length == 1
            root = roots.first
            raise 'Nelze vložit obalovou definici.' if root[:definition].equal?(loaded_definition)
            register_placement_metadata_observer(
              model.active_entities,
              root[:definition],
              root[:transform],
              root[:metadata],
              loaded_definition
            )
            model.place_component(root[:definition], false)
          else
            # Five original component instances, for example, become five
            # instances in the target model. They are NOT nested in an extra
            # component and all their original tags/transforms are preserved.
            model.select_tool(DirectMultiPlacementTool.new(self, roots, loaded_definition))
          end

          Sketchup.set_status_text(
            "20-20: #{File.basename(path)} – připraveno #{roots.length} komponent bez obalu"
          )
          dialog.execute_script(
            "window.ComponentLibrary && window.ComponentLibrary.insertDone(#{JSON.generate(path)}, true);"
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

    file_loaded(__FILE__) unless file_loaded?(__FILE__)

  end
end
