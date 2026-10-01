#!/usr/bin/env python3
"""Non-destructively migrate RM tag layout and build RM TOOLS v2.0.2."""
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parent.parent
P = ROOT / "SketchUpPlugins"
SRC = P / "RMToolsSuiteSourceV202"

def swap(text, old, new):
    assert text.count(old) == 1, "Patch anchor mismatch: " + old[:75]
    return text.replace(old, new, 1)

OLD = """    TAG_TREE = {
      'ARCH' => {
        'FASADA' => %w[OMITKA OBKLAD SOKL],
        'OKNA' => %w[RAM SKLO],
        'STRECHA' => []
      },
      'INTERIER' => {
        'POVRCHY' => %w[PODLAHA STENY STROP],
        'PRVKY' => %w[SANITA NABYTEK SPOTREBICE]
      },
      'OKOLI' => {
        'VENEK' => %w[TEREN ZELEN SOUSEDNI_BUDOVY]
      },
      'POMOCNE' => {
        'DOKUMENTACE' => %w[KOTY TEXTY PODKLADY]
      }
    }.freeze"""

NEW = """    TAG_TREE = {
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
        'PRVKY' => %w[SANITA NABYTEK SPOTREBICE DVERE DOPLNKY OSVETLENI]
      },
      'OKOLI' => {
        'VENEK' => %w[TEREN ZELEN SOUSEDNI_BUDOVY]
      },
      'POMOCNE' => {
        'DOKUMENTACE' => %w[KOTY TEXTY PODKLADY]
      }
    }.freeze"""

NEW_METHOD = """    def create_tag_tree
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
      notify(message)
      push_state
    rescue StandardError => e
      m.abort_operation rescue nil
      notify("Aktualizace RM tagů selhala: #{e.message}", 'error')
    end

"""

OLD_UI = '<div class="card"><h3>Struktura pro RENDERMAKER</h3><p>Vytvoří základní strukturu rolí, skupin a tagů podle příručky. Existující tagy nemaže.</p><div class="row"><button class="btn yellow" onclick="sketchup.rm_create_tags()">Vytvořit RM tagy</button><button class="btn" onclick="sketchup.rm_open_tags()">Otevřít Tagy</button></div></div>'
NEW_UI = '<div class="card"><h3>Struktura pro RENDERMAKER</h3><p>Vytvořit doplní potřebné tagy. Aktualizovat přesune existující tagy do nové struktury a odstraní jen prázdnou starou složku POVRCHY. Objekty ani materiály nemaže.</p><div class="row"><button class="btn yellow" onclick="sketchup.rm_create_tags()">Vytvořit RM tagy</button><button class="btn primary" onclick="if(confirm(\'Přesunout existující RM tagy do nové struktury? Změnu lze vrátit Ctrl+Z.\'))sketchup.rm_update_tags()">Aktualizovat RM tagy</button><button class="btn" onclick="sketchup.rm_open_tags()">Otevřít Tagy</button></div></div>'

def patch_checker(s):
    s = swap(s, "VERSION = '1.2.1'.freeze", "VERSION = '1.2.2'.freeze")
    s = swap(s, OLD, NEW)
    s = swap(s, "dlg.add_action_callback('rm_create_tags') { |_ctx| create_tag_tree }",
        "dlg.add_action_callback('rm_create_tags') { |_ctx| create_tag_tree }\n"
        "      dlg.add_action_callback('rm_update_tags') { |_ctx| update_tag_tree }")
    left = s.index("    def create_tag_tree\n")
    right = s.index("    def find_or_create_folder(parent, name)\n", left)
    s = s[:left] + NEW_METHOD + s[right:]
    s = swap(s, OLD_UI, NEW_UI)
    assert "'POVRCHY' =>" not in s and "rm_update_tags" in s
    return s

def read(path):
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None
        return {name: z.read(name) for name in z.namelist() if not name.endswith("/")}

def write(path, entries):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for name, contents in sorted(entries.items()):
            z.writestr(name, contents)
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None

def main():
    child = read(P / "20-20_RM_Tools_v1.2.1.rbz")
    checker = "twentytwenty_rm_checker/main.rb"
    child[checker] = patch_checker(child[checker].decode("utf-8")).encode("utf-8")
    loader = "twentytwenty_rm_checker.rb"
    child[loader] = swap(child[loader].decode("utf-8"),
        "EXTENSION_VERSION = '1.2.1'", "EXTENSION_VERSION = '1.2.2'").encode("utf-8")
    standalone_out = P / "20-20_RM_Tools_v1.2.2.rbz"
    write(standalone_out, child)

    suite = read(P / "20-20_RM_TOOLS_v2.0.1.rbz")
    suite[checker] = child[checker]
    suite[loader] = swap(suite[loader].decode("utf-8"),
        "EXTENSION_VERSION = '1.2.1'", "EXTENSION_VERSION = '1.2.2'").encode("utf-8")
    for name in ["twentytwenty_rm_tools_suite.rb", "twentytwenty_rm_tools_suite/main.rb"]:
        src = suite[name].decode("utf-8")
        assert "2.0.1" in src
        suite[name] = src.replace("2.0.1", "2.0.2").encode("utf-8")
    suite_out = P / "20-20_RM_TOOLS_v2.0.2.rbz"
    write(suite_out, suite)

    for name in ["twentytwenty_rm_tools_suite.rb", "twentytwenty_rm_tools_suite/main.rb",
                 loader, checker]:
        output = SRC / name
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(suite[name])
    print("BUILT", standalone_out.name, standalone_out.stat().st_size)
    print("BUILT", suite_out.name, suite_out.stat().st_size)

if __name__ == "__main__":
    main()
