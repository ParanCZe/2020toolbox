# frozen_string_literal: true

require 'sketchup.rb'
require 'json'
require 'time'

module TwentyTwenty
  module RMPrep
    extend self

    VERSION = '1.2.3'.freeze
    ATTR_DICT = '20-20_RM'.freeze
    PROJECT_KEY = 'project_number'.freeze
    HELPER_WORDS = %w[POMOCNE DOKUMENTACE ANOT VYKRES PODKLAD SKICA].freeze
    GENERIC_NAMES = /\A(?:component|group|instance|object|solid)[# _-]*\d*\z/i

    TAG_TREE = {
      'ARCH' => {
        'FASADA' => %w[OMITKA OBKLAD SOKL],
        'OKNA' => %w[RAM SKLO],
        'STRECHA' => [],
        'PODLAHA' => [],
        'STENY' => [],
        'STROP' => [],
        'SLOUPY' => [],
        'PODHLED' => []
      },
      'INTERIER' => {
        'SANITA' => [],
        'NABYTEK' => [],
        'SPOTREBICE' => [],
        'DVERE' => [],
        'DOPLNKY' => [],
        'OSVETLENI' => []
      },
      'OKOLI' => {
        'VENEK' => %w[TEREN ZELEN SOUSEDNI_BUDOVY]
      },
      'POMOCNE' => {
        'DOKUMENTACE' => %w[KOTY TEXTY PODKLADY]
      }
    }.freeze

    def model
      Sketchup.active_model
    end

    def dialog
      return @dialog if @dialog && @dialog.visible?

      @dialog = UI::HtmlDialog.new(
        dialog_title: '20-20 RM Tools',
        preferences_key: '20-20-rm-tools-v1',
        scrollable: true,
        resizable: true,
        width: 520,
        height: 720,
        min_width: 430,
        min_height: 560,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(html)
      bind_callbacks(@dialog)
      @dialog.set_on_closed { @dialog = nil }
      @dialog
    end

    def show
      dialog.show
      push_state
    end

    def push_state
      payload = {
        version: VERSION,
        project_number: project_number,
        georeferenced: model.georeferenced?,
        shadows: !!model.shadow_info['DisplayShadows'],
        scene: model.pages.selected_page ? model.pages.selected_page.name : '',
        aspect_ratio: model.active_view.camera.aspect_ratio.to_f,
        two_point: model.active_view.camera.respond_to?(:is_2d?) ? model.active_view.camera.is_2d? : false
      }
      send_js('receiveState', payload)
    end

    def bind_callbacks(dlg)
      dlg.add_action_callback('rm_ready') { |_ctx| push_state }
      dlg.add_action_callback('rm_create_tags') { |_ctx| create_tag_tree }
      dlg.add_action_callback('rm_update_tags') { |_ctx| update_tag_tree }
      dlg.add_action_callback('rm_shadows') { |_ctx, on| set_shadows(on == true || on.to_s == 'true') }
      dlg.add_action_callback('rm_geo') { |_ctx| open_geolocation }
      dlg.add_action_callback('rm_project') { |_ctx, value| set_project_number(value.to_s) }
      dlg.add_action_callback('rm_name_selected') { |_ctx, value| rename_selected(value.to_s) }
      dlg.add_action_callback('rm_assign_tag') { |_ctx, tag| assign_selected_to_tag(tag.to_s) }
      dlg.add_action_callback('rm_untag_geometry') { |_ctx| untag_raw_geometry }
      dlg.add_action_callback('rm_ratio') { |_ctx, ratio| set_aspect_ratio(ratio.to_f) }
      dlg.add_action_callback('rm_ratio_off') { |_ctx| set_aspect_ratio(0.0) }
      dlg.add_action_callback('rm_focal_length') { |_ctx, mm| set_focal_length(mm.to_f) }
      dlg.add_action_callback('rm_camera_height') { |_ctx| set_camera_height(1800.mm) }
      dlg.add_action_callback('rm_two_point') { |_ctx| enable_two_point }
      dlg.add_action_callback('rm_scene') { |_ctx, name| create_scene(name.to_s) }
      dlg.add_action_callback('rm_scan') { |_ctx| run_scan }
      dlg.add_action_callback('rm_focus_finding') { |_ctx, ids_json| focus_finding(ids_json.to_s) }
      dlg.add_action_callback('rm_ai_context') { |_ctx| send_ai_context }
      dlg.add_action_callback('rm_ai_plan_selected') { |_ctx, indexes_json| ai_plan_selected(indexes_json.to_s) }
      dlg.add_action_callback('rm_ai_fix_selected') { |_ctx, indexes_json| ai_fix_selected(indexes_json.to_s) }
      dlg.add_action_callback('rm_fix_safe') { |_ctx| fix_safe_items }
      dlg.add_action_callback('rm_open_tags') { |_ctx| open_tags_panel }
      dlg.add_action_callback('rm_open_materials') { |_ctx| open_materials_panel }
    end

    def send_js(function_name, payload)
      return unless @dialog
      js = "window.RM && RM.#{function_name}(#{JSON.generate(payload)});"
      @dialog.execute_script(js)
    rescue StandardError => e
      puts "20-20 RM Tools JS error: #{e.message}"
    end

    def notify(message, kind = 'ok')
      send_js('toast', { message: message, kind: kind })
    end

    # ---------------- MODEL ----------------

    def create_tag_tree
      apply_tag_tree(false)
    end

    def update_tag_tree
      apply_tag_tree(true)
    end

    def apply_tag_tree(cleanup_legacy)
      m = model
      layers = m.layers
      unless layers.respond_to?(:add_folder) && layers.respond_to?(:folders)
        return notify('Složky tagů vyžadují SketchUp 2021 nebo novější.', 'warn')
      end

      m.start_operation(cleanup_legacy ? '20-20 Aktualizovat RM tagy' : '20-20 Vytvořit RM tagy', true)
      created = 0
      moved = 0
      TAG_TREE.each do |root_name, groups|
        root = find_or_create_folder(layers, root_name)
        groups.each do |group_name, tags|
          if tags.empty?
            existed = !layers[group_name].nil?
            layer = layers[group_name] || layers.add(group_name)
            created += 1 unless existed
            if layer.folder != root
              layer.folder = root
              moved += 1 if existed
            end
          else
            group = find_or_create_folder(root, group_name)
            tags.each do |tag_name|
              existed = !layers[tag_name].nil?
              layer = layers[tag_name] || layers.add(tag_name)
              created += 1 unless existed
              if layer.folder != group
                layer.folder = group
                moved += 1 if existed
              end
            end
          end
        end
      end

      removed = []
      old_folder_retained = false
      retained_legacy = false
      if cleanup_legacy
        interior = layers.folders.find { |folder| folder.name == 'INTERIER' }
        if interior
          old = interior.folders.find { |folder| folder.name == 'POVRCHY' }
          if old
            if old.layers.empty? && old.folders.empty?
              interior.remove_folder(old)
              removed << 'INTERIER/POVRCHY'
            else
              old_folder_retained = true
            end
          end
        end
        # Move ALL direct tags, including user-added ones, from the old PRVKY
        # folder. Reparenting existing tag objects preserves model assignments.
        if interior
          old_prvky = interior.folders.find { |folder| folder.name == 'PRVKY' }
          if old_prvky
            old_prvky.layers.to_a.each do |layer|
              next if layer.folder == interior
              layer.folder = interior
              moved += 1
            end
            if old_prvky.layers.empty? && old_prvky.folders.empty?
              interior.remove_folder(old_prvky)
              removed << 'INTERIER/PRVKY'
            else
              retained_legacy = true
            end
          end
        end
        # Older builds sometimes left an unnecessary empty STRECHA folder.
        arch = layers.folders.find { |folder| folder.name == 'ARCH' }
        if arch
          empty_roof = arch.folders.find { |folder| folder.name == 'STRECHA' }
          if empty_roof && empty_roof.layers.empty? && empty_roof.folders.empty?
            arch.remove_folder(empty_roof)
            removed << 'ARCH/STRECHA (prázdná složka)'
          end
        end
      end

      m.commit_operation
      message = "RM tagy: #{created} nových, #{moved} přesunutých."
      message += " Odstraněné prázdné složky: #{removed.join(', ')}." unless removed.empty?
      message += ' POVRCHY obsahují vlastní prvky, proto zůstaly zachovány.' if old_folder_retained
      message += ' PRVKY obsahují vnořené složky; kvůli bezpečnosti zůstaly zachovány.' if retained_legacy
      notify(message)
      push_state
    rescue StandardError => e
      m.abort_operation rescue nil
      notify("Aktualizace RM tagů selhala: #{e.message}", 'error')
    end

    def find_or_create_folder(parent, name)
      folders = parent.respond_to?(:folders) ? parent.folders : []
      found = folders.find { |f| f.name == name }
      return found if found
      parent.add_folder(name)
    end

    def set_shadows(on)
      model.start_operation('20-20 RM stíny', true)
      model.shadow_info['DisplayShadows'] = on
      model.commit_operation
      notify(on ? 'Stíny jsou zapnuté.' : 'Stíny jsou vypnuté.')
      push_state
    rescue StandardError => e
      model.abort_operation rescue nil
      notify("Stíny: #{e.message}", 'error')
    end

    def open_geolocation
      # Add Location je ve SketchUpu 2024+ samostatné rozšíření.
      # Na Windows je nejspolehlivější nativní command id 24216.
      # Příkaz pouštíme až v dalším UI ticku, mimo HtmlDialog callback.
      UI.start_timer(0.12, false) do
        begin
          opened = false
          if Sketchup.platform == :platform_win
            opened = !!Sketchup.send_action(24_216)
            opened = !!Sketchup.send_action('importFromGoogleEarth:') unless opened
            opened = !!Sketchup.send_action('showGeoLocation:') unless opened
          else
            opened = !!Sketchup.send_action('showGeoLocation:')
            opened = !!Sketchup.send_action('importFromGoogleEarth:') unless opened
          end
          unless opened
            notify('Příkaz Přidat umístění není dostupný. Zkontroluj, že je Add Location ve SketchUpu zapnuté.', 'warn')
          end
        rescue StandardError => e
          notify("Geolokace: #{e.message}", 'error')
        end
      end
      notify('Otevírám Přidat umístění…')
    end

    def project_number
      model.get_attribute(ATTR_DICT, PROJECT_KEY, '').to_s
    end

    def set_project_number(value)
      model.start_operation('20-20 RM číslo zakázky', true)
      model.set_attribute(ATTR_DICT, PROJECT_KEY, value.strip)
      model.commit_operation
      notify('Číslo zakázky je uložené v modelu.')
      push_state
    rescue StandardError => e
      model.abort_operation rescue nil
      notify("Číslo zakázky: #{e.message}", 'error')
    end

    def rename_selected(value)
      name = value.strip
      return notify('Zadej nový název.', 'warn') if name.empty?
      sel = model.selection.to_a
      targets = sel.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
      return notify('Vyber skupinu nebo komponentu.', 'warn') if targets.empty?

      model.start_operation('20-20 RM přejmenování', true)
      targets.each do |entity|
        entity.name = name if entity.respond_to?(:name=)
        if entity.is_a?(Sketchup::ComponentInstance) && entity.definition && generic_name?(entity.definition.name)
          entity.definition.name = name
        end
      end
      model.commit_operation
      notify("Přejmenováno: #{targets.length}× #{name}")
    rescue StandardError => e
      model.abort_operation rescue nil
      notify("Přejmenování: #{e.message}", 'error')
    end

    def assign_selected_to_tag(tag_name)
      layer = model.layers[tag_name]
      return notify("Tag #{tag_name} neexistuje. Nejdřív vytvoř RM tagy.", 'warn') unless layer
      targets = model.selection.to_a
      return notify('Nejdřív něco vyber.', 'warn') if targets.empty?

      model.start_operation("20-20 RM tag #{tag_name}", true)
      targets.each { |e| e.layer = layer if e.respond_to?(:layer=) }
      model.commit_operation
      notify("Výběr přiřazen na tag #{tag_name}.")
    rescue StandardError => e
      model.abort_operation rescue nil
      notify("Přiřazení tagu: #{e.message}", 'error')
    end

    def untag_raw_geometry
      m = model
      layer0 = m.layers[0]
      changed = 0
      m.start_operation('20-20 RM Untagged geometrie', true)
      walk_entities(m.entities, nil, 0) do |entity, _depth, _effective_layer|
        next unless entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge)
        next if entity.layer == layer0
        entity.layer = layer0
        changed += 1
      end
      m.commit_operation
      notify("Hotovo. #{changed} hran/ploch převedeno na Untagged.")
    rescue StandardError => e
      m.abort_operation rescue nil
      notify("Untagged geometrie: #{e.message}", 'error')
    end

    def open_tags_panel
      Sketchup.send_action('showLayers:') || Sketchup.send_action('showLayerManager:')
    rescue StandardError
      notify('Panel Tagy otevři přes Výchozí panel > Tagy.', 'warn')
    end

    def open_materials_panel
      Sketchup.send_action('showMaterials:')
    rescue StandardError
      notify('Panel Materiály otevři přes Výchozí panel > Materiály.', 'warn')
    end

    # ---------------- SHOT ----------------

    def set_aspect_ratio(ratio)
      return notify('Neplatný poměr stran.', 'warn') if ratio.negative?
      cam = model.active_view.camera
      cam.aspect_ratio = ratio
      model.active_view.invalidate
      notify(ratio.zero? ? 'Rámeček záběru vypnutý.' : "Rámeček záběru: #{format('%.3f', ratio)}")
      push_state
    rescue StandardError => e
      notify("Poměr stran: #{e.message}", 'error')
    end

    def set_focal_length(mm)
      return notify('Neplatné ohnisko.', 'warn') if mm <= 0
      cam = model.active_view.camera
      if cam.respond_to?(:focal_length=)
        cam.focal_length = mm
        model.active_view.camera = cam
        model.active_view.invalidate
        notify("Ohnisko nastaveno na #{mm.round} mm.")
      else
        notify('Tato verze SketchUpu neumí ohnisko nastavit přes API.', 'warn')
      end
    rescue StandardError => e
      notify("Ohnisko: #{e.message}", 'error')
    end

    def ground_z
      bb = model.bounds
      bb.valid? ? bb.min.z : 0.to_l
    end

    def set_camera_height(height)
      view = model.active_view
      cam = view.camera
      eye = cam.eye
      target = cam.target
      desired_z = ground_z + height
      dz = desired_z - eye.z
      new_eye = Geom::Point3d.new(eye.x, eye.y, desired_z)
      new_target = Geom::Point3d.new(target.x, target.y, target.z + dz)
      cam.set(new_eye, new_target, cam.up)
      view.camera = cam
      view.invalidate
      notify('Kamera nastavena na 1,8 m nad nejnižší bod modelu.')
    rescue StandardError => e
      notify("Výška kamery: #{e.message}", 'error')
    end

    def enable_two_point
      before = model.active_view.camera.respond_to?(:is_2d?) && model.active_view.camera.is_2d?
      if before
        return notify('Dvoubodová perspektiva už je aktivní.')
      end

      ok = false
      begin
        ok = Sketchup.send_action('viewTwoPointPerspective;')
      rescue StandardError
        ok = false
      end
      if !ok && Sketchup.platform == :platform_win
        begin
          ok = Sketchup.send_action(10_627)
        rescue StandardError
          ok = false
        end
      end
      UI.start_timer(0.25, false) do
        active = model.active_view.camera.respond_to?(:is_2d?) && model.active_view.camera.is_2d?
        notify(active ? 'Dvoubodová perspektiva je zapnutá.' : 'Příkaz byl odeslán. Pokud se režim nezměnil, zapni Kamera > Dvoubodová perspektiva ručně.', active ? 'ok' : 'warn')
        push_state
      end
    end

    def create_scene(name)
      clean = name.strip.upcase.gsub(/\s+/, '_')
      return notify('Zadej název záběru, např. INT_03_KOUPELNA.', 'warn') if clean.empty?

      m = model
      m.start_operation('20-20 RM scéna', true)
      existing = m.pages.find { |p| p.name == clean }
      page = existing || m.pages.add(clean)
      page.update(PAGE_USE_CAMERA | PAGE_USE_RENDERING_OPTIONS | PAGE_USE_SHADOWINFO | PAGE_USE_LAYER_VISIBILITY)
      m.pages.selected_page = page
      m.set_attribute(ATTR_DICT, 'last_scene', clean)
      m.commit_operation
      notify(existing ? "Scéna #{clean} aktualizována." : "Scéna #{clean} vytvořena.")
      push_state
    rescue StandardError => e
      m.abort_operation rescue nil
      notify("Scéna: #{e.message}", 'error')
    end

    # ---------------- CHECKER ----------------

    def run_scan
      started = Time.now
      findings = []
      stats = {
        faces: 0,
        groups: 0,
        components: 0,
        max_depth: 0,
        tags: {},
        default_material_faces: 0,
        raw_tagged_geometry: 0,
        default_material_ids: [],
        raw_tagged_ids: [],
        tag_entity_ids: Hash.new { |h, k| h[k] = [] }
      }
      layer0 = model.layers[0]

      walk_entities(model.entities, nil, 0) do |entity, depth, effective_layer|
        stats[:max_depth] = [stats[:max_depth], depth].max
        if depth > 4
          findings << finding('error', 'Vnoření nad 4 úrovně', entity_label(entity), false, 'RM most hlubší obsah nemusí přečíst.', [entity.entityID])
        end

        case entity
        when Sketchup::Face
          stats[:faces] += 1
          if entity.layer != layer0
            stats[:raw_tagged_geometry] += 1
            stats[:raw_tagged_ids] << entity.entityID
          end
          if entity.material.nil?
            stats[:default_material_faces] += 1
            stats[:default_material_ids] << entity.entityID
          end
          tag = effective_layer || layer0
          path = layer_path(tag)
          stats[:tags][path] ||= { materials: {}, faces: 0 }
          stats[:tags][path][:faces] += 1
          stats[:tag_entity_ids][path] << entity.entityID
          mat_name = entity.material ? entity.material.display_name.to_s : '__DEFAULT__'
          stats[:tags][path][:materials][mat_name] = true

          if entity.material && entity.material.alpha < 0.98
            unless path =~ /(SKLO|GLASS|ZRCAD|MIRROR)/i
              findings << finding('warn', 'Průhledný povrch není na tagu SKLO/ZRCADLO', path, false, 'Sklo a zrcadla mají být samostatné plochy/tagy.', [entity.entityID])
            end
          end
        when Sketchup::Group
          stats[:groups] += 1
          check_name(entity, findings)
        when Sketchup::ComponentInstance
          stats[:components] += 1
          check_name(entity, findings)
        end
      end

      if stats[:default_material_faces] > 0
        findings.unshift(finding('error', 'Viditelné plochy bez materiálu', "#{stats[:default_material_faces]} ploch používá výchozí materiál", false, 'RM pak neví, čím povrch je.', stats[:default_material_ids].take(80)))
      end

      if stats[:raw_tagged_geometry] > 0
        findings << finding('warn', 'Geometrie má vlastní tag', "#{stats[:raw_tagged_geometry]} hran/ploch není Untagged", true, 'Tagovat se mají skupiny a komponenty, geometrie uvnitř má zůstat Untagged.', stats[:raw_tagged_ids].take(80))
      end

      stats[:tags].each do |path, data|
        mats = data[:materials].keys.reject { |n| n == '__DEFAULT__' }
        if mats.length > 1
          findings << finding('error', 'Jeden tag obsahuje více materiálů', "#{path}: #{mats.take(5).join(', ')}", false, 'Pro RM má platit jeden tag = jeden povrch = jeden materiál.', stats[:tag_entity_ids][path].take(80))
        end
        if path == 'Untagged' && data[:faces] > 0
          findings << finding('warn', 'Plochy zůstávají efektivně Untagged', "#{data[:faces]} ploch", false, 'Plochy pro RM mají být rozdělené do srozumitelných tagů.', stats[:tag_entity_ids][path].take(80))
        end
      end

      visible_helpers = model.layers.select do |layer|
        next false unless layer.visible?
        HELPER_WORDS.any? { |word| layer_path(layer).upcase.include?(word) }
      end
      unless visible_helpers.empty?
        findings << finding('warn', 'Pomocné tagy jsou viditelné', visible_helpers.map { |l| layer_path(l) }.join(', '), false, 'Kóty, texty a podklady mají být vypnuté nebo mimo záběr.')
      end

      findings << finding('error', 'Model není geolokovaný', 'Chybí geolokace', false, 'RM čte polohu a sever pro světlo.') unless model.georeferenced?
      findings << finding('error', 'Stíny jsou vypnuté', 'RM pak nepřevezme denní dobu', true, 'Před přenosem zapni stíny.') unless model.shadow_info['DisplayShadows']
      findings << finding('warn', 'Chybí číslo zakázky', 'Pole čísla zakázky je prázdné', false, 'Číslo zakázky propojuje záběr s projektem.') if project_number.strip.empty?
      findings << finding('error', 'Aktuální záběr není uložený jako scéna', 'Není vybraná pojmenovaná scéna', false, 'Každý záběr pro RM má být uložená pojmenovaná scéna.') unless model.pages.selected_page

      cam = model.active_view.camera
      findings << finding('info', 'Dvoubodová perspektiva není aktivní', 'Pro běžný architektonický záběr ji můžeš zapnout v záložce Záběr.', false, nil) if cam.respond_to?(:is_2d?) && !cam.is_2d?
      findings << finding('warn', 'Rámeček záběru není nastavený', 'Poměr stran kamery je 0 = podle okna SketchUpu', false, 'V záložce Záběr zvol cílový poměr stran.') if cam.aspect_ratio.to_f.zero?

      has_ground = stats[:tags].keys.any? { |p| p =~ /(TEREN|PODLAHA|FLOOR|GROUND)/i }
      findings << finding('warn', 'Nenašel jsem terén ani podlahu podle názvu tagu', 'Výška kamery se pak odhaduje hůř.', false, nil) unless has_ground

      severities = Hash.new(0)
      findings.each { |f| severities[f[:severity]] += 1 }
      ordered = dedupe_findings(findings).sort_by { |f| { 'info' => 0, 'warn' => 1, 'error' => 2 }.fetch(f[:severity].to_s, 9) }
      report = {
        findings: ordered,
        stats: stats.merge(duration_ms: ((Time.now - started) * 1000).round),
        counts: severities
      }
      @last_report = report
      send_js('receiveScan', report)
    rescue StandardError => e
      send_js('receiveScan', { findings: [finding('error', 'Checker selhal', e.message, false, e.backtrace&.first)], stats: {}, counts: { error: 1 } })
    end

    def dedupe_findings(items)
      seen = {}
      items.each_with_object([]) do |item, out|
        key = [item[:severity], item[:title], item[:detail]]
        next if seen[key]
        seen[key] = true
        out << item
      end
    end

    def finding(severity, title, detail, fixable = false, hint = nil, targets = nil)
      { severity: severity, title: title, detail: detail.to_s, fixable: fixable, hint: hint, targets: Array(targets).compact }
    end

    def check_name(entity, findings)
      name = entity.respond_to?(:name) ? entity.name.to_s.strip : ''
      if entity.is_a?(Sketchup::ComponentInstance) && name.empty?
        name = entity.definition.name.to_s.strip
      end
      if name.empty? || generic_name?(name)
        findings << finding('warn', 'Nepopsaná skupina/komponenta', entity_label(entity), false, 'Sanitu, spotřebiče, vestavby a další nejasné prvky pojmenuj srozumitelně.', [entity.entityID])
      end
    end

    def generic_name?(name)
      n = name.to_s.strip
      n.empty? || n.match?(GENERIC_NAMES) || n.match?(/\AComponent[#_ ]/i)
    end

    def entity_label(entity)
      if entity.is_a?(Sketchup::ComponentInstance)
        n = entity.name.to_s.strip
        n = entity.definition.name.to_s if n.empty?
        "Komponenta #{n.empty? ? entity.entityID : n}"
      elsif entity.is_a?(Sketchup::Group)
        n = entity.name.to_s.strip
        "Skupina #{n.empty? ? entity.entityID : n}"
      else
        "#{entity.typename} ##{entity.entityID}"
      end
    rescue StandardError
      entity.typename.to_s
    end

    def layer_path(layer)
      return 'Untagged' unless layer
      names = [layer.respond_to?(:display_name) ? layer.display_name.to_s : layer.name.to_s]
      folder = layer.respond_to?(:folder) ? layer.folder : nil
      while folder
        names.unshift(folder.name.to_s)
        folder = folder.respond_to?(:folder) ? folder.folder : nil
      end
      names.join('::')
    end

    def walk_entities(entities, inherited_layer, depth, &block)
      layer0 = model.layers[0]
      entities.each do |entity|
        next if entity.respond_to?(:hidden?) && entity.hidden?
        layer = entity.respond_to?(:layer) ? entity.layer : layer0
        next if layer && !layer.visible?
        effective = (layer.nil? || layer == layer0) ? inherited_layer : layer
        yield(entity, depth, effective)
        child_entities = if entity.is_a?(Sketchup::Group)
                           entity.entities
                         elsif entity.is_a?(Sketchup::ComponentInstance)
                           entity.definition.entities
                         end
        walk_entities(child_entities, effective, depth + 1, &block) if child_entities
      end
    end

    class FindingHighlighter
      FADE = 0.80

      def initialize(boxes, edit_path = nil)
        @boxes = boxes
        @edit_path = Array(edit_path).compact
        @restored = false
        @previous_active_path = nil
        @previous_rendering = {}
      end

      def activate
        m = Sketchup.active_model
        @previous_active_path = m.active_path ? m.active_path.to_a : nil
        ro = m.rendering_options
        %w[InactiveFade InactiveHidden InstanceFade InstanceHidden].each do |key|
          @previous_rendering[key] = ro[key] if true                 
        end

        unless @edit_path.empty?
          begin
            m.active_path = Sketchup::InstancePath.new(@edit_path)
            ro['InactiveHidden'] = false if true                              
            ro['InstanceHidden'] = false if true                              
            ro['InactiveFade'] = FADE if true                            
            ro['InstanceFade'] = FADE if true                            
          rescue StandardError
          end
        end
        m.active_view.invalidate
      end

      def draw(view)
        view.drawing_color = Sketchup::Color.new(220, 40, 35)
        view.line_width = 4
        @boxes.each do |bb|
          pts = (0..7).map { |i| bb.corner(i) }
          edges = [[0,1],[1,3],[3,2],[2,0],[4,5],[5,7],[7,6],[6,4],[0,4],[1,5],[2,6],[3,7]]
          edges.each { |a,b| view.draw(GL_LINES, pts[a], pts[b]) }
        end
      end

      def onCancel(_reason, view)
        restore(view)
        view.model.select_tool(nil)
      end

      def onLButtonDown(_flags, _x, _y, view)
        restore(view)
        view.model.select_tool(nil)
      end

      def deactivate(view)
        restore(view)
      end

      def restore(view)
        return if @restored
        @restored = true
        m = view.model
        begin
          ro = m.rendering_options
          @previous_rendering.each { |key, value| ro[key] = value }
          m.active_path = @previous_active_path
        rescue StandardError
        ensure
          view.invalidate
        end
      end
    end

    def find_entity_by_id(entities, wanted, tr = nil, path = [])
      tr ||= Geom::Transformation.new
      entities.each do |e|
        bounds_tr = tr
        child_tr = tr
        child_path = path
        if e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
          child_tr = tr * e.transformation
          child_path = path + [e]
        end
        return [e, bounds_tr, path] if wanted.include?(e.entityID)
        child = if e.is_a?(Sketchup::Group)
                  e.entities
                elsif e.is_a?(Sketchup::ComponentInstance)
                  e.definition.entities
                end
        if child
          hit = find_entity_by_id(child, wanted, child_tr, child_path)
          return hit if hit
        end
      end
      nil
    end

    def transformed_bounds(entity, tr)
      bb = Geom::BoundingBox.new
      if entity.respond_to?(:bounds)
        8.times { |i| bb.add(entity.bounds.corner(i).transform(tr)) }
      end
      bb
    end

    def focus_finding(ids_json)
      ids = JSON.parse(ids_json) rescue []
      ids = Array(ids).map(&:to_i).uniq.first(30)
      return notify('U tohoto nálezu není konkrétní objekt k zaměření.', 'warn') if ids.empty?

      boxes = []
      zoom_entity = nil
      edit_path = nil
      ids.each do |id|
        hit = find_entity_by_id(model.entities, [id])
        next unless hit
        entity, tr, parent_path = hit
        next unless entity.respond_to?(:valid?) ? entity.valid? : true
        zoom_entity ||= entity
        edit_path ||= if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                        parent_path + [entity]
                      else
                        parent_path
                      end
        bb = transformed_bounds(entity, tr)
        boxes << bb if bb.valid?
      end

      return notify('Objekt už v modelu není nebo ho nelze zaměřit.', 'warn') if boxes.empty? || zoom_entity.nil?

      begin
        model.active_view.zoom(zoom_entity)
      rescue StandardError
        model.active_view.zoom_extents
      end

      model.select_tool(FindingHighlighter.new(boxes, edit_path))
      model.active_view.invalidate
      notify('Focus nálezu: okolí je ztlumené cca 80 %. ESC nebo kliknutí vše vrátí zpět.')
    rescue StandardError => e
      notify("Zaměření nálezu: #{e.message}", 'error')
    end

    def ai_context_payload
      {
        schema: '20-20-rm-checker-ai-context-v1',
        generated_at: Time.now.utc.iso8601,
        project_number: project_number,
        scene: model.pages.selected_page ? model.pages.selected_page.name : '',
        georeferenced: model.georeferenced?,
        shadows: !!model.shadow_info['DisplayShadows'],
        camera: {
          aspect_ratio: model.active_view.camera.aspect_ratio.to_f,
          focal_length_mm: (model.active_view.camera.respond_to?(:focal_length) ? model.active_view.camera.focal_length.to_f : nil),
          two_point: (model.active_view.camera.respond_to?(:is_2d?) ? model.active_view.camera.is_2d? : nil)
        },
        checker: @last_report || { findings: [], stats: {}, counts: {} }
      }
    end

    def send_ai_context
      send_js('receiveAIContext', ai_context_payload)
    rescue StandardError => e
      notify("AI kontext: #{e.message}", 'error')
    end

    def selected_findings(indexes_json)
      indexes = JSON.parse(indexes_json) rescue []
      indexes = Array(indexes).map(&:to_i).uniq
      report = @last_report || { findings: [] }
      all = Array(report[:findings] || report['findings'])
      indexes.filter_map { |i| all[i] if i >= 0 && i < all.length }
    end

    def ai_rule_for(finding)
      title = (finding[:title] || finding['title']).to_s
      case title
      when 'Geometrie má vlastní tag'
        { can_fix: true, action: 'Přesunout označenou raw geometrii na Untagged', note: 'Bezpečná RM oprava. Nemění materiál ani nadřazený tag komponenty.' }
      when 'Stíny jsou vypnuté'
        { can_fix: true, action: 'Zapnout stíny', note: 'Bezpečná změna nastavení modelu.' }
      when 'Dvoubodová perspektiva není aktivní'
        { can_fix: true, action: 'Zapnout dvoubodovou perspektivu', note: 'Změní pouze aktivní kameru.' }
      when 'Pomocné tagy jsou viditelné'
        { can_fix: true, action: 'Skrýt pomocné tagy', note: 'Skryje viditelné pomocné tagy podle názvu.' }
      when 'Model není geolokovaný'
        { can_fix: false, action: 'Otevřít Přidat umístění', note: 'Polohu musí potvrdit uživatel ve SketchUpu.' }
      when 'Chybí číslo zakázky'
        { can_fix: false, action: 'Doplnit číslo zakázky v záložce Model', note: 'AI ho nesmí hádat.' }
      when 'Aktuální záběr není uložený jako scéna'
        { can_fix: false, action: 'Pojmenovat a uložit scénu v záložce Záběr', note: 'Je potřeba zvolit název záběru.' }
      when 'Rámeček záběru není nastavený'
        { can_fix: false, action: 'Vybrat cílový poměr stran v záložce Záběr', note: 'Poměr závisí na požadovaném výstupu.' }
      when 'Nepopsaná skupina/komponenta'
        { can_fix: false, action: 'Pojmenovat objekt podle jeho funkce', note: 'Bez znalosti významu objektu ho automaticky nepřejmenovávám.' }
      when 'Viditelné plochy bez materiálu'
        { can_fix: false, action: 'Přiřadit správný materiál', note: 'Materiál nelze bezpečně odhadnout jen z geometrie.' }
      when 'Jeden tag obsahuje více materiálů'
        { can_fix: false, action: 'Rozdělit povrchy/tagy podle materiálů', note: 'Vyžaduje rozhodnutí o správné RM struktuře.' }
      when 'Průhledný povrch není na tagu SKLO/ZRCADLO'
        { can_fix: false, action: 'Oddělit sklo/zrcadlo na samostatný RM tag', note: 'Je potřeba ověřit význam povrchu.' }
      when 'Vnoření nad 4 úrovně'
        { can_fix: false, action: 'Zjednodušit hierarchii komponent', note: 'Automatické rozbití hierarchie by mohlo poškodit model.' }
      else
        { can_fix: false, action: 'Zkontrolovat ručně', note: (finding[:hint] || finding['hint']).to_s }
      end
    end

    def ai_plan_selected(indexes_json)
      selected = selected_findings(indexes_json)
      return notify('Nejdřív označ jednu nebo více položek v Checkeru.', 'warn') if selected.empty?
      items = selected.map do |f|
        rule = ai_rule_for(f)
        {
          title: (f[:title] || f['title']).to_s,
          severity: (f[:severity] || f['severity']).to_s,
          can_fix: rule[:can_fix],
          action: rule[:action],
          note: rule[:note]
        }
      end
      send_js('receiveAIPlan', { items: items, selected: items.length, fixable: items.count { |x| x[:can_fix] } })
    rescue StandardError => e
      notify("AI plán: #{e.message}", 'error')
    end

    def ai_fix_selected(indexes_json)
      selected = selected_findings(indexes_json)
      return notify('Nejdřív označ jednu nebo více položek v Checkeru.', 'warn') if selected.empty?
      fixable = selected.select { |f| ai_rule_for(f)[:can_fix] }
      return notify('U označených nálezů není bezpečná automatická oprava. AI ti u nich připraví postup.', 'warn') if fixable.empty?

      m = model
      m.start_operation('20-20 RM AI opravy', true)
      fixed = []
      layer0 = m.layers[0]

      fixable.each do |f|
        title = (f[:title] || f['title']).to_s
        case title
        when 'Geometrie má vlastní tag'
          targets = Array(f[:targets] || f['targets']).map(&:to_i)
          targets.each do |id|
            hit = find_entity_by_id(m.entities, [id])
            next unless hit
            entity = hit[0]
            if entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge)
              entity.layer = layer0
            end
          end
          fixed << title
        when 'Stíny jsou vypnuté'
          m.shadow_info['DisplayShadows'] = true
          fixed << title
        when 'Dvoubodová perspektiva není aktivní'
          cam = m.active_view.camera
          cam.set_2d if cam.respond_to?(:set_2d)
          fixed << title
        when 'Pomocné tagy jsou viditelné'
          m.layers.each do |layer|
            next unless layer.visible?
            path = layer_path(layer).upcase
            layer.visible = false if HELPER_WORDS.any? { |word| path.include?(word) }
          end
          fixed << title
        end
      end

      m.commit_operation
      notify("AI opravy hotové: #{fixed.uniq.join(', ')}. Ctrl+Z vrátí celou dávku.")
      run_scan
    rescue StandardError => e
      m.abort_operation rescue nil
      notify("AI oprava: #{e.message}", 'error')
    end

    def fix_safe_items
      m = model
      m.start_operation('20-20 RM bezpečné opravy', true)
      m.shadow_info['DisplayShadows'] = true
      layer0 = m.layers[0]
      walk_entities(m.entities, nil, 0) do |entity, _depth, _effective|
        if (entity.is_a?(Sketchup::Face) || entity.is_a?(Sketchup::Edge)) && entity.layer != layer0
          entity.layer = layer0
        end
      end
      m.commit_operation
      notify('Bezpečné opravy hotové: zapnuté stíny + geometrie uvnitř na Untagged. Ctrl+Z vrátí celou dávku.')
      run_scan
    rescue StandardError => e
      m.abort_operation rescue nil
      notify("Automatická oprava: #{e.message}", 'error')
    end

    # ---------------- UI ----------------

    def html
      <<~HTML
        <!doctype html>
        <html lang="cs">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <style>
            :root{--bg:#f4f4f2;--card:#fff;--ink:#161616;--muted:#737373;--line:#deded9;--yellow:#f6e867;--red:#c83b31;--orange:#b96c16;--green:#32814a}
            *{box-sizing:border-box} body{margin:0;font:13px/1.42 Arial,Helvetica,sans-serif;background:var(--bg);color:var(--ink)}
            header{padding:18px 18px 12px;background:#111;color:#fff}.brand{display:flex;justify-content:space-between;align-items:flex-end}.brand b{font-size:20px;letter-spacing:.4px}.ver{font-size:11px;color:#aaa}
            nav{display:flex;background:#111;padding:0 10px 10px;gap:6px;position:sticky;top:0;z-index:4}.tab{flex:1;border:0;padding:10px 8px;border-radius:8px;background:#262626;color:#bbb;font-weight:700;cursor:pointer}.tab.on{background:var(--yellow);color:#111}
            main{padding:14px}.panel{display:none}.panel.on{display:block}.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px;margin-bottom:12px}.card h3{margin:0 0 6px;font-size:14px}.card p{margin:0 0 10px;color:var(--muted)}
            .row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}.row>*{flex:1}.btn{border:1px solid #c9c9c4;background:#fff;border-radius:8px;padding:9px 10px;font-weight:700;cursor:pointer;min-width:115px}.btn:hover{background:#f5f5ef}.btn.primary{background:#111;color:#fff;border-color:#111}.btn.yellow{background:var(--yellow);border-color:#d8cb57}.btn.danger{color:var(--red)}
            input,select{width:100%;border:1px solid #c9c9c4;border-radius:8px;background:#fff;padding:9px 10px;outline:none} label{font-size:11px;font-weight:700;color:#656565;display:block;margin:9px 0 4px}
            .status{display:flex;gap:6px;flex-wrap:wrap;margin-top:9px}.pill{padding:5px 8px;border:1px solid var(--line);border-radius:999px;background:#fafafa;color:#666;font-size:11px}.pill.ok{color:var(--green);border-color:#b8d9c0}.pill.bad{color:var(--red);border-color:#e6b9b5}
            .finding{border-left:4px solid #aaa;padding:10px 10px 10px 12px;background:#fff;border-radius:8px;margin:8px 0}.finding.error{border-color:var(--red)}.finding.warn{border-color:var(--orange)}.finding.info{border-color:#5783bd}.finding .t{font-weight:700}.finding .d{color:#555;margin-top:2px}.finding .h{font-size:11px;color:#777;margin-top:5px}
            .summary{display:flex;gap:8px;margin:10px 0}.summary .box{flex:1;text-align:center;padding:10px;border-radius:9px;background:#fff;border:1px solid var(--line)}.num{font-size:20px;font-weight:800}.small{font-size:11px;color:#777}
            #toast{position:fixed;left:14px;right:14px;bottom:14px;background:#111;color:#fff;border-radius:10px;padding:11px 13px;display:none;z-index:20;box-shadow:0 8px 30px #0003}#toast.warn{background:#7a4b12}#toast.error{background:#8d2822}
            .lensgrid{display:grid;grid-template-columns:repeat(3,1fr);gap:7px}.focusbtn{float:right;min-width:0;padding:5px 8px;font-size:15px;line-height:1}.sevtitle{font-size:11px;font-weight:800;letter-spacing:.6px;color:#777;margin:14px 2px 4px}.hint{background:#fff9c8;border:1px solid #ece09a;border-radius:9px;padding:9px 10px;color:#62591d;font-size:11px}.split{display:grid;grid-template-columns:1fr 1fr;gap:8px}.findingcheck{float:left;margin:3px 9px 0 0;width:auto}.ai-actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:8px}.ai-actions .btn{flex:1}.ai-plan{margin-top:10px}.ai-plan-item{border-top:1px solid var(--line);padding:9px 0}.ai-plan-item:first-child{border-top:0}.ai-plan-item b{display:block}.fixok{color:var(--green);font-weight:700}.fixask{color:var(--orange);font-weight:700}
          </style>
        </head>
        <body>
          <header><div class="brand"><b>20-20 RM TOOLS</b><span class="ver">v#{VERSION}</span></div></header>
          <nav><button class="tab on" data-tab="model">MODEL</button><button class="tab" data-tab="shot">ZÁBĚR</button><button class="tab" data-tab="checker">CHECKER</button></nav>
          <main>
            <section class="panel on" id="model">
              <div class="card"><h3>Struktura pro RENDERMAKER</h3><p>Vytvořit doplní potřebné tagy. Aktualizovat přesune existující tagy do nové struktury a odstraní prázdné staré složky POVRCHY a PRVKY. Objekty ani materiály nemaže.</p><div class="row"><button class="btn yellow" onclick="sketchup.rm_create_tags()">Vytvořit RM tagy</button><button class="btn primary" onclick="if(confirm('Přesunout existující RM tagy do nové struktury? Změnu lze vrátit Ctrl+Z.'))sketchup.rm_update_tags()">Aktualizovat RM tagy</button><button class="btn" onclick="sketchup.rm_open_tags()">Otevřít Tagy</button></div></div>
              <div class="card"><h3>Povrchy a komponenty</h3><p>Geometrie uvnitř skupin má zůstat Untagged; tagovat se mají skupiny a komponenty.</p><div class="row"><button class="btn" onclick="sketchup.rm_untag_geometry()">Geometrii → Untagged</button><button class="btn" onclick="sketchup.rm_open_materials()">Otevřít Materiály</button></div><label>Název vybrané komponenty/skupiny</label><div class="row"><input id="rename" placeholder="VANICKA_SPRCHOVA"><button class="btn" onclick="sketchup.rm_name_selected(document.getElementById('rename').value)">Přejmenovat</button></div></div>
              <div class="card"><h3>Slunce, poloha a zakázka</h3><div class="row"><button id="shadowBtn" class="btn" onclick="RM.toggleShadows()">Stíny</button><button class="btn" onclick="sketchup.rm_geo()">Geolokace</button></div><label>Číslo zakázky</label><div class="row"><input id="project" placeholder="např. 26042"><button class="btn" onclick="sketchup.rm_project(document.getElementById('project').value)">Uložit</button></div><div class="status" id="modelStatus"></div></div>
            </section>

            <section class="panel" id="shot">
              <div class="card"><h3>Rámeček výsledného záběru</h3><p>SketchUp použije poměr stran kamery a přímo v pohledu ukáže ořezové pruhy.</p><label>Poměr stran</label><div class="row"><select id="ratio"><option value="1.7777777778">16:9</option><option value="1.5">3:2</option><option value="1.3333333333">4:3</option><option value="1">1:1</option><option value="0.5625">9:16</option><option value="2.3333333333">21:9</option></select><button class="btn yellow" onclick="sketchup.rm_ratio(parseFloat(document.getElementById('ratio').value))">Zobrazit rám</button><button class="btn" onclick="sketchup.rm_ratio_off()">Vypnout</button></div></div>
              <div class="card"><h3>Kamera</h3><p>Jedním klikem nastav výšku člověka, dvoubodovou perspektivu a běžné ohnisko.</p><div class="row"><button class="btn" onclick="sketchup.rm_camera_height()">Výška 1,8 m</button><button class="btn" onclick="sketchup.rm_two_point()">2-bodová perspektiva</button></div><label>Standardní ohniska (35mm ekv.)</label><div class="lensgrid"><button class="btn" onclick="sketchup.rm_focal_length(16)">16 mm</button><button class="btn" onclick="sketchup.rm_focal_length(18)">18 mm</button><button class="btn" onclick="sketchup.rm_focal_length(24)">24 mm</button><button class="btn" onclick="sketchup.rm_focal_length(28)">28 mm</button><button class="btn" onclick="sketchup.rm_focal_length(35)">35 mm</button><button class="btn" onclick="sketchup.rm_focal_length(50)">50 mm</button></div><div class="hint" style="margin-top:10px">Výška 1,8 m se počítá od nejnižšího bodu modelu. Proto je vhodné mít v modelu terén nebo podlahu.</div></div>
              <div class="card"><h3>Vytvořit / aktualizovat záběr</h3><p>Uloží aktuální kameru, stíny, styl a viditelnost tagů do scény.</p><label>Název scény</label><div class="row"><input id="scene" placeholder="INT_03_KOUPELNA"><button class="btn primary" onclick="sketchup.rm_scene(document.getElementById('scene').value)">Uložit scénu</button></div><div class="status" id="shotStatus"></div></div>
            </section>

            <section class="panel" id="checker">
              <div class="card"><h3>Kontrola před přenosem do RM</h3><p>Kontroluje materiály, tagy, vnoření, názvy komponent, pomocné prvky, scénu, stíny, geolokaci a číslo zakázky.</p><div class="row"><button class="btn primary" onclick="sketchup.rm_scan()">Spustit kontrolu</button><button class="btn" onclick="sketchup.rm_fix_safe()">Bezpečné opravy</button></div><div class="small" style="margin-top:7px">Bezpečné opravy pouze zapnou stíny a vrátí raw geometrii na Untagged. Celou dávku lze vrátit Ctrl+Z.</div></div>
              <div id="summary"></div><div id="findings"></div>
              <div class="card ai"><h3>AI asistent Checkeru</h3><p>Označ nálezy, se kterými chceš pomoct. Asistent oddělí bezpečné automatické opravy od věcí, kde je potřeba tvoje rozhodnutí.</p><div class="row"><button class="btn" onclick="RM.selectAllFindings(true)">Označit vše</button><button class="btn" onclick="RM.selectAllFindings(false)">Zrušit výběr</button><span id="aiSelected" class="pill">0 označeno</span></div><div class="ai-actions"><button class="btn yellow" onclick="RM.aiPlan()">✨ AI · navrhnout postup</button><button class="btn primary" onclick="RM.aiFix()">🔧 AI · opravit bezpečné</button></div><div id="aiStatus" class="small" style="margin-top:8px">AI pracuje jen s označenými nálezy. Automatické zásahy jsou jedna SketchUp operace a jdou vrátit Ctrl+Z.</div><div id="aiPlan" class="ai-plan"></div></div>
            </section>
          </main>
          <div id="toast"></div>
          <script>
            window.RM={state:{shadows:false},
              tabs:function(){var t=document.querySelectorAll('.tab');for(var i=0;i<t.length;i++){t[i].onclick=function(){var a=document.querySelectorAll('.tab,.panel');for(var j=0;j<a.length;j++)a[j].classList.remove('on');this.classList.add('on');document.getElementById(this.getAttribute('data-tab')).classList.add('on');};}},
              esc:function(s){return String(s==null?'':s).replace(/[&<>\"]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;'}[c];});},
              toast:function(o){var e=document.getElementById('toast');e.className=o.kind||'ok';e.textContent=o.message;e.style.display='block';clearTimeout(RM._tt);RM._tt=setTimeout(function(){e.style.display='none';},3200);},
              receiveState:function(s){RM.state=s;document.getElementById('project').value=s.project_number||'';if(s.scene)document.getElementById('scene').value=s.scene;var ms=document.getElementById('modelStatus');ms.innerHTML='<span class="pill '+(s.shadows?'ok':'bad')+'">Stíny '+(s.shadows?'ON':'OFF')+'</span><span class="pill '+(s.georeferenced?'ok':'bad')+'">Geolokace '+(s.georeferenced?'OK':'chybí')+'</span>';document.getElementById('shadowBtn').textContent=s.shadows?'Vypnout stíny':'Zapnout stíny';var ss=document.getElementById('shotStatus');ss.innerHTML='<span class="pill '+(s.scene?'ok':'bad')+'">Scéna '+(s.scene?RM.esc(s.scene):'chybí')+'</span><span class="pill '+(s.two_point?'ok':'bad')+'">2-bod '+(s.two_point?'ON':'OFF')+'</span>';},
              toggleShadows:function(){sketchup.rm_shadows(!RM.state.shadows);},
              focus:function(ids){sketchup.rm_focus_finding(JSON.stringify(ids||[]));},
              selectedIndexes:function(){var a=[],els=document.querySelectorAll('.findingcheck:checked');for(var i=0;i<els.length;i++)a.push(parseInt(els[i].getAttribute('data-index'),10));return a;},
              updateSelected:function(){var n=RM.selectedIndexes().length;var e=document.getElementById('aiSelected');if(e)e.textContent=n+' označeno';},
              selectAllFindings:function(on){var els=document.querySelectorAll('.findingcheck');for(var i=0;i<els.length;i++)els[i].checked=on;RM.updateSelected();},
              aiPlan:function(){var ids=RM.selectedIndexes();if(!ids.length){RM.toast({kind:'warn',message:'Nejdřív označ nález v Checkeru.'});return;}sketchup.rm_ai_plan_selected(JSON.stringify(ids));},
              aiFix:function(){var ids=RM.selectedIndexes();if(!ids.length){RM.toast({kind:'warn',message:'Nejdřív označ nález v Checkeru.'});return;}sketchup.rm_ai_fix_selected(JSON.stringify(ids));},
              receiveScan:function(r){RM.report=r;var c=r.counts||{};document.getElementById('summary').innerHTML='<div class="summary"><div class="box"><div class="num">'+(c.info||0)+'</div><div class="small">INFO</div></div><div class="box"><div class="num">'+(c.warn||0)+'</div><div class="small">VAROVÁNÍ</div></div><div class="box"><div class="num">'+(c.error||0)+'</div><div class="small">CHYBY</div></div></div>';var f=r.findings||[],groups={info:[],warn:[],error:[]};for(var i=0;i<f.length;i++){var y=Object.assign({},f[i]);y._index=i;(groups[y.severity]||groups.info).push(y);}var h='';var order=[['info','INFO'],['warn','VAROVÁNÍ'],['error','CHYBY']];var total=f.length;if(!total)h='<div class="card"><b>Model vypadá pro RM čistě.</b></div>';for(var g=0;g<order.length;g++){var key=order[g][0],arr=groups[key];if(!arr.length)continue;h+='<div class="sevtitle">'+order[g][1]+'</div>';for(var j=0;j<arr.length;j++){var x=arr[j],targets=x.targets||[];h+='<div class="finding '+RM.esc(x.severity)+'"><input class="findingcheck" type="checkbox" data-index="'+x._index+'" onchange="RM.updateSelected()">'+(targets.length?'<button class="btn focusbtn" title="Najít v modelu" onclick="RM.focus('+JSON.stringify(targets)+')">🔎</button>':'')+'<div class="t">'+RM.esc(x.title)+'</div><div class="d">'+RM.esc(x.detail)+'</div>'+(x.hint?'<div class="h">'+RM.esc(x.hint)+'</div>':'')+'</div>';}}document.getElementById('findings').innerHTML=h;RM.updateSelected();document.getElementById('aiPlan').innerHTML='';},
              receiveAIPlan:function(p){var h='<div class="small">Vybráno '+p.selected+' · bezpečně opravitelné '+p.fixable+'</div>';var a=p.items||[];for(var i=0;i<a.length;i++){var x=a[i];h+='<div class="ai-plan-item"><b>'+RM.esc(x.title)+'</b><span class="'+(x.can_fix?'fixok':'fixask')+'">'+(x.can_fix?'MŮŽU OPRAVIT':'POTŘEBUJE ROZHODNUTÍ')+'</span><div>'+RM.esc(x.action)+'</div><div class="small">'+RM.esc(x.note||'')+'</div></div>';}document.getElementById('aiPlan').innerHTML=h;},
              receiveAIContext:function(c){var n=((c.checker||{}).findings||[]).length;document.getElementById('aiStatus').textContent='Kontext modelu připraven: '+n+' nálezů.';},
              init:function(){RM.tabs();sketchup.rm_ready();}
            };document.addEventListener('DOMContentLoaded',RM.init);
          </script>
        </body></html>
      HTML
    end

    def install_ui
      @command ||= UI::Command.new('20-20 RM Tools') { show }
      @command.tooltip = '20-20 RM Tools'
      @command.status_bar_text = 'Příprava modelu, záběru a kontrola pro RENDERMAKER.'

      icon = File.join(__dir__, 'icons', 'rm_checker.svg')
      if File.exist?(icon)
        begin
          @command.small_icon = icon
          @command.large_icon = icon
        rescue StandardError => e
          puts "20-20 RM Tools icon warning: #{e.message}"
        end
      end

      @toolbar ||= UI::Toolbar.new('20-20 RM Tools')
      unless @toolbar_item_added
        @toolbar.add_item(@command)
        @toolbar_item_added = true
      end
      begin
        @toolbar.restore
      rescue StandardError
        @toolbar.show
      end

      begin
        UI.menu('Extensions').add_item(@command)
      rescue StandardError
        UI.menu('Plugins').add_item(@command) rescue nil
      end
      true
    rescue StandardError => e
      puts "20-20 RM Tools UI error: #{e.class}: #{e.message}"
      puts e.backtrace.join("\n") if e.backtrace
      UI.messagebox("20-20 RM Tools: chyba při vytvoření toolbaru.\n\n#{e.class}: #{e.message}")
      false
    end

    file_loaded(__FILE__) unless file_loaded?(__FILE__)

  end
end
