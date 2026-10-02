# frozen_string_literal: true
require 'sketchup.rb'
require 'json'
require 'cgi'

module TwentyTwenty
  module RMManagers
    extend self
    VERSION = '0.2.1'.freeze
    # Observer follows the active SketchUp selection without changing it.
    def html_escape(v); CGI.escapeHTML(v.to_s); end
    def show(which)
      install_selection_observer if which == :tags
      @dialogs ||= {}
      if (dlg = @dialogs[which])
        dlg.show
        refresh(which)
        return dlg
      end
      dlg = UI::HtmlDialog.new(dialog_title: "20-20 RM #{which == :tags ? 'TAG' : 'SCENE'} MANAGER",
        preferences_key: "2020-rm-#{which}-manager", scrollable: true, resizable: true,
        width: 1000, height: 740, min_width: 650, min_height: 490,
        style: UI::HtmlDialog::STYLE_DIALOG)
      @dialogs[which] = dlg
      dlg.add_action_callback('ready') { |_ctx| refresh(which) }
      dlg.add_action_callback('action') do |_ctx, raw|
        begin
          data = JSON.parse(raw.to_s)
          which == :tags ? tag_action(data) : scene_action(data)
        rescue StandardError => e
          notify(which, "#{e.class}: #{e.message}")
        end
      end
      dlg.add_action_callback('back') do |_ctx|
        dlg.close
        TwentyTwenty::RMToolsSuite.show
      end
      dlg.set_on_closed { @dialogs.delete(which) }
      dlg.set_html(html(which))
      dlg.show
      dlg
    end
    def js(which, fn, data)
      dlg = @dialogs && @dialogs[which]
      dlg.execute_script("window.Manager && Manager.#{fn}(#{JSON.generate(data)});") if dlg
    end
    def notify(which, message); js(which, 'notice', message); end
    def refresh(which)
      js(which, 'receive', which == :tags ? tag_data : scene_data)
    end


    # Keep this hierarchy synchronized with the existing RM Checker TAG_TREE.
    # Virtual grouping: the manager never moves or renames tags in the SKP file.
    RM_TAG_TREE = {
      'ARCH' => {'FASADA' => %w[OMITKA OBKLAD SOKL], 'OKNA' => [],
                 'STRECHA' => [], 'PODLAHA' => [], 'STENY' => [],
                 'STROP' => [], 'SLOUPY' => [], 'PODHLED' => []},
      'INTERIER' => {'SANITA' => [], 'NABYTEK' => [], 'SPOTREBICE' => [],
                     'DVERE' => [], 'DOPLNKY' => [], 'OSVETLENI' => []},
      'OKOLI' => {'VENEK' => %w[TEREN ZELEN SOUSEDNI_BUDOVY]},
      'POMOCNE' => {'DOKUMENTACE' => %w[KOTY TEXTY PODKLADY]}
    }.freeze
    def entity_id(ent)
      ent.respond_to?(:persistent_id) ? ent.persistent_id : ent.entityID
    end
    def nested_members(entities, parents, output, seen = {})
      entities.each do |ent|
        next unless ent.valid?
        next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
        id = entity_id(ent)
        path = parents + [id]
        output << {
          id: id, key: path.join('/'), path: parents, name: (ent.name.to_s.empty? ? ent.definition.name : ent.name),
          definition: ent.definition.name, tag: ent.layer.name,
          hidden: ent.hidden?, materials: component_materials(ent),
          kind: ent.is_a?(Sketchup::Group) ? 'Group' : 'Component'
        }
        definition = ent.definition
        next unless definition && path.length < 9 && !seen[definition.object_id]
        nested_members(definition.entities, path, output, seen.merge(definition.object_id => true))
      end
    end
    def component_materials(ent)
      names = []
      names << ent.material.name if ent.material
      ent.definition.entities.each do |child|
        names << child.material.name if child.respond_to?(:material) && child.material
        names << child.back_material.name if child.respond_to?(:back_material) && child.back_material
      end
      names.compact.uniq.first(30)
    end
    def object_cache
      output = []
      nested_members(Sketchup.active_model.entities, [], output)
      output
    end
    def rm_folder(name, id, children, tags, layers)
      leaves = tags.select { |name| layers[name] }
      all_names = leaves + children.flat_map { |child| child[:tag_names] }
      visible = all_names.all? { |n| layers[n].visible? }
      mixed = all_names.any? { |n| layers[n].visible? } && !visible
      {name: name, id: id, visible: visible, mixed: mixed, tag_names: all_names,
       children: children, tags: leaves.map { |n| tag_item(layers[n]) }}
    end
    def tag_item(layer)
      {name: layer.name, id: "tag:#{layer.name}", visible: layer.visible?}
    end
    def tag_data
      model = Sketchup.active_model
      layers = model.layers
      objs = object_cache
      expected = []
      roots = RM_TAG_TREE.map do |root_name, entries|
        nested = []
        direct = []
        entries.each do |entry, tags|
          if tags.empty?
            direct << entry
            expected << entry
          else
            expected.concat(tags)
            nested << rm_folder(entry, "rm:#{root_name}/#{entry}", [], tags, layers)
          end
        end
        rm_folder(root_name, "rm:#{root_name}", nested, direct, layers)
      end
      # All non-RM tags (including Untagged and imported library tags) appear
      # only in a separately collapsible virtual group at the bottom.
      other = layers.to_a.reject { |l| expected.include?(l.name) }.sort_by { |l| l.name.downcase }
      roots << rm_folder('DALSI', 'rm:other', [], other.map(&:name), layers) unless other.empty?
      {selected_key: selected_model_key, folders: roots, root_tags: [],
       objects: objs.group_by { |o| o[:tag] },
       tag_options: layers.to_a.sort_by { |l| l.name.downcase }.map { |l| {name: l.name, rm: expected.include?(l.name)} },
       count: objs.length}
    end
    # SketchUp only selects entities in the current editing context. Prefix
    # their persistent IDs with the active component path to match the tree.
    def selected_model_key
      model = Sketchup.active_model
      selected = model.selection.to_a.select do |item|
        item.valid? && (item.is_a?(Sketchup::ComponentInstance) || item.is_a?(Sketchup::Group))
      end
      return nil unless selected.length == 1
      ancestors = model.respond_to?(:active_path) ? Array(model.active_path) : []
      (ancestors + selected).map { |entity| entity_id(entity) }.join('/')
    end
    class TagSelectionObserver < (defined?(Sketchup::SelectionObserver) ? Sketchup::SelectionObserver : Object)
      def onSelectionBulkChange(_selection); TwentyTwenty::RMManagers.selection_changed; end
      def onSelectionCleared(_selection); TwentyTwenty::RMManagers.selection_changed; end
      def onSelectionAdded(_selection, _entity); TwentyTwenty::RMManagers.selection_changed; end
      def onSelectionRemoved(_selection, _entity); TwentyTwenty::RMManagers.selection_changed; end
    end
    def selection_changed
      refresh(:tags) if @dialogs && @dialogs[:tags]
    end
    def install_selection_observer
      return unless defined?(Sketchup::SelectionObserver)
      model = Sketchup.active_model
      return if @observed_tag_model.equal?(model) && @tag_selection_observer
      @observed_tag_model.selection.remove_observer(@tag_selection_observer) if
        @observed_tag_model && @tag_selection_observer && @observed_tag_model.selection.respond_to?(:remove_observer)
      @tag_selection_observer ||= TagSelectionObserver.new
      model.selection.add_observer(@tag_selection_observer)
      @observed_tag_model = model
    end
    def entity_path(key)
      ids = key.to_s.split('/').map { |v| Integer(v, 10) }
      raise 'Vyber konkrétní komponentu.' if ids.empty?
      model = Sketchup.active_model
      entities = model.entities
      parents = []
      target = nil
      ids.each_with_index do |id, idx|
        target = entities.find { |e| e.valid? && e.respond_to?(:persistent_id) && entity_id(e) == id }
        raise 'Objekt nebo jeho nadřazená komponenta se mezitím změnila. Obnov seznam.' unless target
        if idx < ids.length - 1
          raise 'Nadřazený objekt není komponenta.' unless target.respond_to?(:definition)
          parents << target
          entities = target.definition.entities
        end
      end
      [target, parents]
    end
    def find_entity(key)
      entity_path(key).first
    end
    def select_entity(key, zoom = false)
      model = Sketchup.active_model
      target, ancestors = entity_path(key)
      if ancestors.empty?
        model.active_path = nil if model.respond_to?(:active_path=) && model.active_path && !model.active_path.empty?
      elsif model.respond_to?(:active_path=)
        model.active_path = ancestors
      else
        notify(:tags, 'Tato verze SketchUpu neumožňuje otevřít vnořenou komponentu automaticky.')
        return
      end
      if !model.active_entities.to_a.include?(target)
        # A stale or locked editing context must not select an unrelated entity.
        notify(:tags, 'Nelze otevřít editační kontext objektu. Otevři jeho rodiče ručně.')
        return
      end
      model.selection.clear
      model.selection.add(target)
      model.active_view.zoom(model.selection) if zoom
      model.active_view.invalidate
    end
    def layer_names_in_folder(id)
      if id == 'rm:other'
        expected = RM_TAG_TREE.values.flat_map { |entry| entry.flat_map { |key, names| names.empty? ? [key] : names } }
        return Sketchup.active_model.layers.to_a.map(&:name) - expected
      end
      segments = id.to_s.sub(/\Arm:/, '').split('/')
      node = RM_TAG_TREE[segments[0]]
      raise 'Neznámá RM složka.' unless node
      if segments.length == 1
        node.flat_map { |name, names| names.empty? ? [name] : names }
      else
        val = node[segments[1]]
        raise 'Neznámá RM podsložka.' unless val && !val.empty?
        val
      end
    end
    def tag_action(d)
      model = Sketchup.active_model
      case d['kind']
      when 'refresh'
      when 'visibility'
        if d['target'] == 'object'
          target = find_entity(d['key'])
          model.start_operation('RM viditelnost objektu', true)
          begin
            target.hidden = !d['visible']
            model.commit_operation
          rescue StandardError
            model.abort_operation
            raise
          end
        elsif d['target'] == 'tag'
          layer = model.layers[d['id'].to_s]
          raise 'Tag nebyl nalezen.' unless layer
          layer.visible = !!d['visible']
        elsif d['target'] == 'folder'
          names = layer_names_in_folder(d['id'].to_s)
          layers = names.map { |name| model.layers[name] }.compact
          layers.each { |layer| layer.visible = !!d['visible'] }
        end
      when 'select', 'zoom'
        select_entity(d['key'], d['kind'] == 'zoom')
      when 'retag'
        target = find_entity(d['key'])
        dest = model.layers[d['tag'].to_s]
        raise 'Cílový tag v modelu neexistuje.' unless dest
        model.start_operation('RM změna tagu komponenty', true)
        begin
          target.layer = dest
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
      when 'replace'
        target, ancestors = entity_path(d['key'])
        raise 'Nahrazovat lze jen komponenty, nikoliv skupiny.' unless target.is_a?(Sketchup::ComponentInstance)
        if !d['all'] && ancestors.any? { |parent| parent.definition.instances.length > 1 }
          raise 'Tato vnořená komponenta je sdílená více instancemi rodiče. Pro bezpečnou výměnu použij „Nahradit všechny stejné“, nebo rodiče nejdřív vytvoř unikátním.'
        end
        @replacement = {model: model, key: d['key'].to_s, definition: target.definition, all: !!d['all']}
        require File.expand_path('../dvacet20_component_library/main', __dir__)
        install_library_replace_hook
        Dvacet20::ComponentLibrary.show_dialog
        libdlg = Dvacet20::ComponentLibrary.instance_variable_get(:@dialog)
        owner = self
        libdlg.set_on_closed do
          Dvacet20::ComponentLibrary.instance_variable_set(:@dialog, nil)
          owner.cancel_replacement
        end if libdlg
        @dialogs[:tags].hide if @dialogs && @dialogs[:tags]
        notify(:tags, 'Vyber náhradní model z Model Library. Původní objekt zůstane, dokud náhrada neproběhne.')
        return
      else
        raise 'Neznámá operace Tag Manageru.'
      end
      refresh(:tags)
    end
    def install_library_replace_hook
      return if @library_hook
      owner = self
      patch = Module.new do
        define_method(:insert_component) do |path, dialog = @dialog|
          if owner.replacement_pending?
            # The actual Model Library method normally runs on a delayed timer.
            # Dispatch replacement identically to avoid changing definition
            # while Chromium is still handling the button click.
            UI.start_timer(0, false) do
              begin
                owner.replace_from_library(path)
                dialog.execute_script("window.ComponentLibrary && window.ComponentLibrary.insertDone(#{JSON.generate(path)}, true);") if dialog
              rescue StandardError => e
                puts "[RM TAG MANAGER] Náhrada selhala: #{e.class}: #{e.message}\n#{e.backtrace&.join("\n")}"
                owner.notify(:tags, "Náhrada selhala: #{e.message}")
                Dvacet20::ComponentLibrary.show_error(dialog, "Náhrada selhala:\n#{e.message}")
              end
            end
          else
            super(path, dialog)
          end
        end
      end
      Dvacet20::ComponentLibrary.singleton_class.prepend(patch)
      @library_hook = true
    end
    def replacement_pending?
      !!@replacement
    end
    def cancel_replacement
      pending = !!@replacement
      @replacement = nil
      if pending && @dialogs && @dialogs[:tags]
        @dialogs[:tags].show
        refresh(:tags)
        notify(:tags, 'Nahrazování zrušeno; původní model zůstal beze změny.')
      end
    end
    def copy_instance_properties(from, to)
      to.name = from.name
      to.layer = from.layer
      to.material = from.material if from.material
      to.hidden = from.hidden?
      # Lock only after replacement is created and original is erased.
      if from.respond_to?(:casts_shadows?) && to.respond_to?(:casts_shadows=)
        to.casts_shadows = from.casts_shadows?
      end
      if from.respond_to?(:receives_shadows?) && to.respond_to?(:receives_shadows=)
        to.receives_shadows = from.receives_shadows?
      end
      from.attribute_dictionaries.each do |dictionary|
        dictionary.each_pair { |k, val| to.set_attribute(dictionary.name, k, val) }
      end if from.attribute_dictionaries
    end
    # Resolve imported SKP independently of the Model Library plugin version.
    # Bundled older library versions implement placement_target, not placement_roots.
    # Do not call either: validating one visible root here ensures consistent
    # replacement with every installed Model Library version.
    def replacement_root_definition(wrapper)
      raise 'Nepodařilo se načíst vybraný model.' unless wrapper
      items = wrapper.entities.to_a
      roots = items.select { |item| item.is_a?(Sketchup::ComponentInstance) }
      if roots.length != 1
        raise "Náhradní SKP musí obsahovat právě jednu hlavní komponentu (nalezeno #{roots.length})."
      end
      selected = roots.first
      extras = items.reject do |item|
        item.equal?(selected) ||
          item.is_a?(Sketchup::ConstructionPoint) ||
          item.is_a?(Sketchup::ConstructionLine) ||
          (item.respond_to?(:hidden?) && item.hidden?)
      end
      unless extras.empty?
        raise 'Náhradní model má kromě hlavní komponenty i další viditelnou geometrii.'
      end
      raise 'Hlavní komponenta nemá platnou definici.' unless selected.definition
      selected.definition
    end
    def replace_from_library(path)
      request = @replacement
      raise 'Nejdřív vyber komponentu v Tag Manageru.' unless request
      model = Sketchup.active_model
      raise 'V průběhu nahrazování se změnil model.' unless request[:model].equal?(model)
      root = File.expand_path(Dvacet20::ComponentLibrary.library_root)
      candidate = File.expand_path(path.to_s)
      raise 'Model musí pocházet z nastavené Model Library.' unless candidate.start_with?(root + File::SEPARATOR)
      raise 'Soubor SKP není dostupný.' unless File.file?(candidate) && File.extname(candidate).casecmp('.skp').zero?
      old, ancestors = entity_path(request[:key])
      raise 'Původní definice se mezitím změnila.' unless old.is_a?(Sketchup::ComponentInstance) && old.definition == request[:definition]
      model.start_operation('RM náhrada komponent z Model Library', true)
      begin
        wrapper = model.definitions.load(candidate)
        # Replace geometry only: use the imported ROOT definition, not its
        # wrapper, whose placement transform could multiply the original scale.
        # Preserve the original instance transformation (position, rotation,
        # non-uniform scale and mirroring) without auto-fitting or compensation.
        definition = replacement_root_definition(wrapper)
        targets = request[:all] ? request[:definition].instances.to_a.select(&:valid?) : [old]
        raise 'Žádné komponenty k nahrazení.' if targets.empty?
        raise 'Komponenta nemůže být nahrazena sama sebou.' if definition == request[:definition]
        result = targets.map do |original|
          parent = original.parent
          entities = parent.respond_to?(:entities) ? parent.entities : nil
          raise 'Nepodařilo se najít kontext komponenty.' unless entities
          target_layer = original.layer
          target_transform = original.transformation
          replacement = entities.add_instance(definition, target_transform)
          copy_instance_properties(original, replacement)
          was_locked = original.respond_to?(:locked?) && original.locked?
          original.locked = false if was_locked
          original.erase!
          replacement.locked = true if replacement.respond_to?(:locked=) && was_locked
          replacement
        end
        model.selection.clear
        # A single top-level replacement can be selected immediately.
        if result.length == 1 && result.first.parent == model.active_entities
          model.selection.add(result.first)
        end
        model.commit_operation
        @replacement = nil
        libdlg = Dvacet20::ComponentLibrary.instance_variable_get(:@dialog)
        UI.start_timer(0.15, false) do
          libdlg.close if libdlg && libdlg.visible?
          @dialogs[:tags].show if @dialogs && @dialogs[:tags]
          refresh(:tags)
          notify(:tags, "Nahrazeno #{result.length} instancí. Pozice, transformace a tag zachovány.")
        end
      rescue StandardError
        model.abort_operation
        raise
      end
      true
    end

    # All lens values shown in RM Tools are 35mm-equivalent focal lengths.
    # SketchUp Camera#focal_length depends on Camera#image_width, which other
    # extensions may modify; deriving from FOV avoids silently wrong presets.
    RATIOS = {'16:9'=>16.0/9.0, '3:2'=>1.5, '4:3'=>4.0/3.0,
              '1:1'=>1.0, '9:16'=>9.0/16.0, '21:9'=>21.0/9.0}.freeze
    SCENE_DICT = '20-20 RM SCENES'.freeze
    # Evaluate SketchUp constants only inside running SketchUp, not while loading.
    def scene_options
      PAGE_USE_CAMERA | PAGE_USE_RENDERING_OPTIONS |
        PAGE_USE_SHADOWINFO | PAGE_USE_LAYER_VISIBILITY
    end

    def focal_35(camera)
      return nil unless camera && camera.perspective?
      fov = camera.fov.to_f
      return nil unless fov > 0 && fov < 180
      (36.0 / (2.0 * Math.tan(fov * Math::PI / 360.0))).round(1)
    end
    def set_focal_35(camera, millimeters)
      mm = Float(millimeters)
      raise 'Ohnisko musí být v rozsahu 10–200 mm.' unless mm.finite? && mm.between?(10, 200)
      camera.perspective = true unless camera.perspective?
      camera.fov = (2.0 * Math.atan(36.0 / (2.0 * mm)) * 180.0 / Math::PI)
      mm
    end
    def ratio_name(camera)
      val = camera.aspect_ratio.to_f
      return '' if val <= 0
      nearest = RATIOS.min_by { |_name, ratio| (ratio - val).abs }
      (nearest[1] - val).abs < 0.007 ? nearest[0] : format('%.3f', val)
    end
    def camera_info(camera)
      {focal: focal_35(camera), ratio: ratio_name(camera),
       frame: camera.aspect_ratio.to_f > 0,
       perspective: camera.perspective?,
       two_point: camera.respond_to?(:is_2d?) ? !!camera.is_2d? : false}
    end
    def scene_data
      model = Sketchup.active_model
      selected = model.pages.selected_page
      {current: camera_info(model.active_view.camera),
       scenes: model.pages.map { |page|
         cam = page.camera
         {name: page.name, selected: page == selected,
          focal: focal_35(cam),
          ratio: page.get_attribute(SCENE_DICT, 'ratio', '').to_s.empty? ? ratio_name(cam) : page.get_attribute(SCENE_DICT, 'ratio'),
          perspective: cam.perspective?,
          two_point: cam.respond_to?(:is_2d?) ? !!cam.is_2d? : false}
       }}
    end
    def page_by_name(name)
      Sketchup.active_model.pages.find { |page| page.name == name.to_s }
    end
    def scene_action(d)
      model = Sketchup.active_model
      name = d['name'].to_s
      page = page_by_name(name)
      view = model.active_view
      case d['kind']
      when 'refresh'
        # No changes to model.
      when 'activate'
        raise 'Scéna nebyla nalezena.' unless page
        model.pages.selected_page = page
      when 'create'
        clean = name.strip
        raise 'Zadej název scény.' if clean.empty?
        raise 'Scéna s tímto názvem již existuje.' if page
        model.start_operation('RM vytvořit scénu', true)
        begin
          page = model.pages.add(clean)
          page.update(scene_options)
          page.set_attribute(SCENE_DICT, 'ratio', ratio_name(view.camera))
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
      when 'update'
        raise 'Scéna nebyla nalezena.' unless page
        # Current view is source. Do NOT activate saved page before update!
        model.start_operation('RM aktualizovat scénu', true)
        begin
          page.update(scene_options)
          page.set_attribute(SCENE_DICT, 'ratio', ratio_name(view.camera))
          model.commit_operation
        rescue StandardError
          model.abort_operation
          raise
        end
      when 'rename'
        raise 'Scéna nebyla nalezena.' unless page
        clean = d['new_name'].to_s.strip
        raise 'Neplatný nový název.' if clean.empty? || (clean != name && page_by_name(clean))
        page.name = clean
      when 'delete'
        raise 'Scéna nebyla nalezena.' unless page
        model.pages.erase(page)
      when 'camera'
        raise 'Scéna nebyla nalezena.' unless page
        ratio = d['ratio'].to_s
        raise 'Vyber platný poměr stran.' unless RATIOS.key?(ratio)
        # Explicit edit of a saved page: activate it, then adjust its camera.
        model.pages.selected_page = page
        cam = view.camera
        set_focal_35(cam, d['focal'])
        cam.aspect_ratio = RATIOS.fetch(ratio)
        view.camera = cam
        view.invalidate
        page.set_attribute(SCENE_DICT, 'ratio', ratio)
        page.update(scene_options)
      when 'lens'
        cam = view.camera
        set_focal_35(cam, d['mm'])
        view.camera = cam
        view.invalidate
        notify(:scenes, "Aktuální kamera: #{focal_35(cam)} mm (35mm ekv.). Pro zachování změny aktualizuj scénu.")
      when 'frame'
        cam = view.camera
        ratio = d['ratio'].to_s
        raise 'Vyber platný poměr stran.' unless RATIOS.key?(ratio) || ratio == 'off'
        cam.aspect_ratio = ratio == 'off' ? 0.0 : RATIOS.fetch(ratio)
        view.camera = cam
        view.invalidate
      when 'height'
        cam = view.camera
        bounds = model.bounds
        ground = bounds.valid? ? bounds.min.z : 0.to_l
        desired = ground + 1800.mm
        delta = desired - cam.eye.z
        eye = Geom::Point3d.new(cam.eye.x, cam.eye.y, desired)
        target = Geom::Point3d.new(cam.target.x, cam.target.y, cam.target.z + delta)
        cam.set(eye, target, cam.up)
        view.camera = cam
        view.invalidate
      when 'two_point'
        return notify(:scenes, 'Dvoubodová perspektiva už je aktivní.') if view.camera.respond_to?(:is_2d?) && view.camera.is_2d?
        ok = Sketchup.send_action('viewTwoPointPerspective;')
        if !ok && Sketchup.platform == :platform_win
          ok = Sketchup.send_action(10_627)
        end
        notify(:scenes, ok ? 'Příkaz pro dvoubodovou perspektivu odeslán.' : 'Dvoubodovou perspektivu zapni v nabídce Kamera.')
        UI.start_timer(0.35, false) { refresh(:scenes) }
      else
        raise 'Neznámá operace scén.'
      end
      refresh(:scenes)
    end
    def html(which)
      is_tags = which == :tags
      <<~HTML
      <!doctype html><html lang="cs"><head><meta charset="utf-8">
      <style>
      :root{color-scheme:dark;--bg:#101215;--p:#191d23;--line:#343941;--muted:#9ca5af;--yellow:#ffd52a}
      *{box-sizing:border-box}body{margin:0;color:white;background:var(--bg);font:13px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
      header{display:flex;gap:16px;align-items:center;padding:17px 22px;border-bottom:1px solid var(--line)}
      h2{margin:0;font-size:18px}.small{color:var(--muted);font-size:11px}.back{background:var(--yellow);color:#151515;font-weight:800}
      button{cursor:pointer;border-radius:8px;border:1px solid var(--line);padding:8px 11px;color:#eee;background:#2b3037;font:inherit}
      button:hover{border-color:var(--yellow)}button.primary{background:var(--yellow);color:#111;font-weight:800}
      .layout{display:grid;grid-template-columns:minmax(280px,1fr) minmax(300px,1fr);min-height:calc(100vh - 75px)}
      aside,main{padding:18px;min-width:0}aside{border-right:1px solid var(--line)}
      input,select{background:#22272e;border:1px solid var(--line);color:white;border-radius:8px;padding:9px;width:100%}
      .entry{display:flex;gap:6px;align-items:center;min-height:33px;border-radius:6px;padding:2px 5px}
      .entry:hover,.entry.active{background:#313641}.entry span{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;cursor:pointer}
      .eye{border:0;padding:3px 7px;background:transparent;color:var(--yellow);font-size:16px}
      .otherDivider{border:0;border-top:2px solid #545c67;margin:16px 4px 8px}.children{margin-left:19px;border-left:1px solid #323944;padding-left:7px}
      .card{border:1px solid var(--line);background:var(--p);border-radius:12px;padding:15px;margin:10px 0}
      .line{display:flex;justify-content:space-between;gap:10px;border-bottom:1px solid #2a3038;padding:9px 0;overflow-wrap:anywhere}
      .line strong{text-align:right}.buttons{display:flex;gap:8px;flex-wrap:wrap;margin-top:12px}
      .lensgrid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:5px;margin:9px 0}.lensgrid button{padding:8px 4px}.current{color:var(--yellow);font-weight:700}.viewtools{padding:13px;border:1px solid var(--line);background:#1a1e24;border-radius:11px;margin:14px 0}.viewtools h3{margin:0 0 6px;font-size:13px}.viewtools select{width:100%;margin:7px 0}.viewtools .buttons button{flex:1}.viewtools .note{margin:8px 0} 
      .note{margin-top:8px;font-size:11px;color:var(--muted);line-height:1.6}#message{color:var(--yellow);min-height:20px;padding:8px 0}
      @media(max-width:740px){.layout{grid-template-columns:1fr}aside{border-right:0;border-bottom:1px solid var(--line)}}
      </style></head><body>
      <header><button class="back" onclick="sketchup.back()">← RM TOOLS</button>
        <div><h2>#{is_tags ? 'TAG MANAGER' : 'SCENE MANAGER'}</h2><div class="small">20-20 · správa modelu pro render</div></div>
        <button onclick="Manager.act({kind:'refresh'})">↻ Obnovit</button></header>
      <div class="layout"><aside>
      <input id="search" placeholder="#{is_tags ? 'Hledat tag nebo komponentu…' : 'Hledat scénu…'}" oninput="Manager.draw()" />
      <div id="tree"></div></aside>
      <main>
      <div id="viewTools" class="viewtools" style="display:#{is_tags ? 'none' : 'block'}">
        <h3>KAMERA · AKTUÁLNÍ POHLED</h3>
        <div class="note">Nastavení z RM Checkeru. Změny se projeví hned v pohledu; uložíš je tlačítkem aktualizace vybrané scény.</div>
        <div class="line"><span>Ohnisko (35mm ekv.)</span><strong class="current" id="currentFocal">–</strong></div>
        <div class="lensgrid">
          <button onclick="Manager.act({kind:'lens',mm:16})">16 mm</button>
          <button onclick="Manager.act({kind:'lens',mm:18})">18 mm</button>
          <button onclick="Manager.act({kind:'lens',mm:24})">24 mm</button>
          <button onclick="Manager.act({kind:'lens',mm:28})">28 mm</button>
          <button onclick="Manager.act({kind:'lens',mm:35})">35 mm</button>
          <button onclick="Manager.act({kind:'lens',mm:50})">50 mm</button>
        </div>
        <div class="line"><span>Rámeček výsledného záběru</span><strong id="frameState">–</strong></div>
        <select id="viewRatio">
          <option value="16:9">16:9</option><option value="3:2">3:2</option>
          <option value="4:3">4:3</option><option value="1:1">1:1</option>
          <option value="9:16">9:16</option><option value="21:9">21:9</option>
        </select>
        <div class="buttons">
          <button class="primary" onclick="Manager.act({kind:'frame',ratio:document.getElementById('viewRatio').value})">Zobrazit rám</button>
          <button onclick="Manager.act({kind:'frame',ratio:'off'})">Vypnout</button>
        </div>
        <div class="buttons">
          <button onclick="Manager.act({kind:'height'})">Výška 1,8 m</button>
          <button onclick="Manager.act({kind:'two_point'})">2-bodová perspektiva</button>
        </div>
        <div id="currentProjection" class="note"></div>
      </div>
      <div id="details" class="card"><div class="small">Vyber položku vlevo.</div></div>
      <div id="message"></div></main></div>
      <script>
      (function(){
      const TAG_MODE = #{is_tags ? 'true' : 'false'};
      let data={}, selected=null, expanded={};
      const el=id=>document.getElementById(id);
      const esc=s=>String(s==null?'':s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
      const send=d=>sketchup.action(JSON.stringify(d));
      const eye=(target,id,visible,key)=>'<button class="eye" title="Viditelnost" onclick="event.stopPropagation();Manager.act({kind:\\'visibility\\',target:\\''+target+'\\',id:'+esc(JSON.stringify(id))+',key:'+esc(JSON.stringify(key||''))+',visible:'+(!visible)+'})">'+(visible?'◉':'○')+'</button>';
      const selectedObject=o=>{selected={type:'object',item:o};draw();send({kind:'select',key:o.key});};
      function objects(tag,query){
        const list=(data.objects||{})[tag]||[];
        return list.filter(o=>!query||((o.name+' '+o.definition).toLowerCase().includes(query)));
      }
      function folder(f,depth,query){
        const folderItems=[...(f.tags||[])], children=(f.children||[]);
        let content='';
        for(const sub of children)content+=folder(sub,depth+1,query);
        for(const t of folderItems)content+=tag(t,depth+1,query);
        if(query&&!f.name.toLowerCase().includes(query)&&!content)return '';
        const open=expanded[f.id]||!!query;
        return (f.id==='rm:other'?'<hr class="otherDivider"/>':'')+'<div class="entry" style="padding-left:'+depth*10+'px"><button onclick="Manager.toggle('+esc(JSON.stringify(f.id))+')">'+(open?'▾':'▸')+'</button><span onclick="Manager.toggle('+esc(JSON.stringify(f.id))+')">▣ '+esc(f.name)+'</span>'+eye('folder',f.id,f.visible)+'</div>'+(open?'<div class="children">'+content+'</div>':'');
      }
      function tag(t,depth,query){
        const rows=objects(t.name,query);
        if(query&&!t.name.toLowerCase().includes(query)&&!rows.length)return '';
        const open=expanded[t.id]||!!query;
        let out='<div class="entry" style="padding-left:'+depth*10+'px"><button onclick="Manager.toggle('+esc(JSON.stringify(t.id))+')">'+(open?'▾':'▸')+'</button><span onclick="Manager.toggle('+esc(JSON.stringify(t.id))+')">▤ '+esc(t.name)+' ('+((data.objects||{})[t.name]||[]).length+')</span>'+eye('tag',t.name,t.visible)+'</div>';
        if(open)out+='<div class="children">'+rows.map(o=>'<div class="entry '+(selected&&selected.type==='object'&&selected.item.key===o.key?'active':'')+'" style="padding-left:'+((depth+1)*8)+'px"><span onclick="Manager.pick('+esc(JSON.stringify(o.key))+')">⬡ '+esc(o.name||o.definition)+'</span>'+eye('object',o.id,!o.hidden,o.key)+'</div>').join('')+'</div>';
        return out;
      }
      function draw(){
        const q=el('search').value.trim().toLowerCase();
        if(TAG_MODE){
          el('tree').innerHTML=(data.folders||[]).map(f=>folder(f,0,q)).join('')+(data.root_tags||[]).map(t=>tag(t,0,q)).join('');
        } else {
          el('tree').innerHTML=(data.scenes||[]).filter(s=>s.name.toLowerCase().includes(q)).map(s=>
            '<div class="entry '+(s.selected?'active':'')+'"><span onclick="Manager.pickScene('+esc(JSON.stringify(s.name))+')" ondblclick="Manager.activateScene('+esc(JSON.stringify(s.name))+')" title="Dvojklik aktivuje scénu">◈ '+esc(s.name)+'</span></div>').join('');
        }
        details();
      }
      function line(k,v){return '<div class="line"><span class="small">'+esc(k)+'</span><strong>'+esc(v)+'</strong></div>';}
      function nextSceneName(){const nums=(data.scenes||[]).map(s=>Number((s.name.match(/^([0-9]+)/)||[])[1])).filter(Number.isFinite);return String(Math.max(0,...nums)+1).padStart(2,'0')+' - EXTERIER - HLAVNI';}
      function details(){
        const box=el('details');
        if(TAG_MODE){
          if(!selected||selected.type!=='object'){box.innerHTML='<h2>TAG MANAGER</h2><p class="note">Rozbal tag, vyber komponentu a zobraz její definici a materiály. Oko umožňuje vypínat jednotlivé objekty, tagy i složky.</p>';return;}
          const o=Object.values(data.objects||{}).flat().find(x=>x.key===selected.item.key);
          if(!o){selected=null;details();return;}selected.item=o;
          box.innerHTML='<h2>'+esc(o.name)+'</h2>'+line('Typ',o.kind)+line('Definice',o.definition)+
            '<div class="line"><span class="small">Tag</span><select style="width:60%" id="objectTag" onchange="Manager.act({kind:\\'retag\\',key:'+esc(JSON.stringify(o.key))+',tag:this.value})">'+
             '<optgroup label="RM TAGY">'+(data.tag_options||[]).filter(x=>x.rm).map(x=>'<option value="'+esc(x.name)+'" '+(x.name===o.tag?'selected':'')+'>'+esc(x.name)+'</option>').join('')+'</optgroup>'+
             '<optgroup label="DALŠÍ">'+(data.tag_options||[]).filter(x=>!x.rm).map(x=>'<option value="'+esc(x.name)+'" '+(x.name===o.tag?'selected':'')+'>'+esc(x.name)+'</option>').join('')+'</optgroup></select></div>'+
            line('Materiály',(o.materials||[]).join(', ')||'Žádné na první úrovni')+line('Vnořeno',o.path.length?'Ano':'Ne')+
            '<div class="buttons"><button onclick="Manager.act({kind:\\'select\\',key:'+esc(JSON.stringify(o.key))+'})">Označit v modelu</button>'+
            '<button onclick="Manager.act({kind:\\'zoom\\',key:'+esc(JSON.stringify(o.key))+'})">Zaměřit</button>'+
            (o.kind==='Component'?'<button class="primary" onclick="Manager.act({kind:\\'replace\\',key:'+esc(JSON.stringify(o.key))+',all:false})">Nahradit z Model Library</button>'+
            '<button onclick="Manager.act({kind:\\'replace\\',key:'+esc(JSON.stringify(o.key))+',all:true})">Nahradit všechny stejné</button>':'')+'</div>'+
            '<p class="note">Náhrada zachovává instanční transformaci a tag. Model musí obsahovat jednu hlavní komponentu.</p>';
        }else{
          // Full scene inspector is supplied by scene_ui.js.
          // Deliberately keep only a placeholder here: no duplicate
          // focal/ratio inputs, legacy save-camera or create buttons.
          box.innerHTML='<p class="note">Vyber scénu vlevo. Ovládání kamery je nahoře.</p>';
        }
      }
      window.Manager={
        receive(d){
          data=d;
          if(TAG_MODE){
            const key=d.selected_key;
            const chosen=key ? Object.values(d.objects||{}).flat().find(x=>x.key===key) : null;
            selected=chosen ? {type:'object',item:chosen} : null;
            if(chosen){
              (d.folders||[]).forEach(function reveal(f){
                if((f.tags||[]).some(t=>t.name===chosen.tag)){expanded[f.id]=true;expanded['tag:'+chosen.tag]=true;}
                (f.children||[]).forEach(reveal);
              });
            }
          }
          draw();
          if(!TAG_MODE && d.current){
            const c=d.current;
            el('currentFocal').textContent=c.focal ? c.focal+' mm' : 'Rovnoběžné promítání';
            el('frameState').textContent=c.frame ? c.ratio : 'VYPNUTO';
            if(c.ratio && Array.from(el('viewRatio').options).some(o=>o.value===c.ratio)) el('viewRatio').value=c.ratio;
            el('currentProjection').textContent=(c.two_point?'2-bod ON · ':'')+(c.perspective?'Perspektiva':'Rovnoběžné promítání');
          }
        },notice(s){el('message').textContent=s;},
        act(d){send(d);},
        toggle(id){expanded[id]=!expanded[id];draw();},
        pick(id){const o=Object.values(data.objects||{}).flat().find(x=>x.key===id);if(o)selectedObject(o);},
        pickScene(name){const s=(data.scenes||[]).find(x=>x.name===name);if(s){selected={type:'scene',item:s};draw();}},
        activateScene(name){this.pickScene(name);send({kind:'activate',name});},
        draw
      };
      document.addEventListener('DOMContentLoaded',()=>sketchup.ready());
      })();
      </script></body></html>
      HTML
    end
  end
end
require File.join(__dir__, 'scene_experience')
TwentyTwenty::RMManagers.singleton_class.prepend(TwentyTwenty::RMManagers::SceneExperience)
