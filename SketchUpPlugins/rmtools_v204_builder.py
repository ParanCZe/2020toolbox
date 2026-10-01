#!/usr/bin/env python3
"""Build RM TOOLS v2.0.4: flattened INTERIER tag tree and one suite toolbar.

Input is the released v2.0.3 archive. All unrelated modules are byte-identical.
"""
from pathlib import Path
import zipfile

P = Path(__file__).resolve().parent
SOURCE = P / "RMToolsSuiteSourceV204"
CHECKER = "twentytwenty_rm_checker/main.rb"
LIBRARY = "dvacet20_component_library/main.rb"
SUITE = "twentytwenty_rm_tools_suite/main.rb"
ROOT_LOADER = "twentytwenty_rm_tools_suite.rb"

def replace_once(s, old, new, label):
    found = s.count(old)
    if found != 1:
        raise ValueError(f"{label}: expected exactly one match, got {found}")
    return s.replace(old, new, 1)

def read(path):
    with zipfile.ZipFile(path) as z:
        if z.testzip() is not None:
            raise ValueError(f"Invalid ZIP: {path}")
        return {n: z.read(n) for n in z.namelist() if not n.endswith("/")}

def write(path, entries):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for filename, data in sorted(entries.items()):
            z.writestr(filename, data)
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None

def update_checker(s):
    s = replace_once(s, "VERSION = '1.2.2'.freeze", "VERSION = '1.2.3'.freeze", "checker version")
    s = replace_once(
        s,
        "'INTERIER' => {\n        'PRVKY' => %w[SANITA NABYTEK SPOTREBICE DVERE DOPLNKY OSVETLENI]\n      },",
        "'INTERIER' => {\n        'SANITA' => [],\n        'NABYTEK' => [],\n        'SPOTREBICE' => [],\n        'DVERE' => [],\n        'DOPLNKY' => [],\n        'OSVETLENI' => []\n      },",
        "flat INTERIER tree"
    )
    anchor = """        # Older builds sometimes left an unnecessary empty STRECHA folder."""
    migration = """        # Move ALL direct tags, including user-added ones, from the old PRVKY
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
"""
    s = replace_once(s, anchor, migration + anchor, "legacy PRVKY move")
    s = replace_once(s, "      old_folder_retained = false", "      old_folder_retained = false\n      retained_legacy = false", "cleanup flag")
    s = replace_once(
        s,
        "      message += ' POVRCHY obsahují vlastní prvky, proto zůstaly zachovány.' if old_folder_retained",
        "      message += ' POVRCHY obsahují vlastní prvky, proto zůstaly zachovány.' if old_folder_retained\n"
        "      message += ' PRVKY obsahují vnořené složky; kvůli bezpečnosti zůstaly zachovány.' if retained_legacy",
        "retain message"
    )
    s = replace_once(
        s,
        "Aktualizovat přesune existující tagy do nové struktury a odstraní jen prázdnou starou složku POVRCHY.",
        "Aktualizovat přesune existující tagy do nové struktury a odstraní prázdné staré složky POVRCHY a PRVKY.",
        "UI migration description"
    )
    # Important: bundled children must never register additional SketchUp
    # toolbar buttons. Standalone releases remain unchanged.
    start = s.rfind("    unless file_loaded?(__FILE__)\n      install_ui")
    tail = s.rfind("\n  end\nend")
    if start < 0 or tail <= start:
        raise ValueError("Checker auto-UI block not found")
    s = s[:start] + "    file_loaded(__FILE__) unless file_loaded?(__FILE__)\n" + s[tail:]
    assert "      install_ui\n      file_loaded(__FILE__)" not in s
    assert "def update_tag_tree" in s
    return s

def suppress_library_toolbar(s):
    start = s.rfind("    unless file_loaded?(__FILE__)\n      command = UI::Command.new(")
    tail = s.rfind("\n  end\nend")
    if start < 0 or tail <= start:
        raise ValueError("Embedded component library auto toolbar block not found")
    return s[:start] + "    file_loaded(__FILE__) unless file_loaded?(__FILE__)\n" + s[tail:]

def main():
    previous = read(P / "20-20_RM_TOOLS_v2.0.3.rbz")
    updated = dict(previous)
    updated[CHECKER] = update_checker(previous[CHECKER].decode("utf-8")).encode("utf-8")
    updated[LIBRARY] = suppress_library_toolbar(previous[LIBRARY].decode("utf-8")).encode("utf-8")
    stub = "twentytwenty_rm_checker.rb"
    updated[stub] = replace_once(previous[stub].decode("utf-8"),
                                 "EXTENSION_VERSION = '1.2.2'",
                                 "EXTENSION_VERSION = '1.2.3'",
                                 "bundled Checker stub version").encode("utf-8")
    updated[ROOT_LOADER] = previous[ROOT_LOADER].replace(b"2.0.3", b"2.0.4")
    updated[SUITE] = previous[SUITE].replace(b"2.0.3", b"2.0.4")
    for module in ("twentytwenty_live_mirror/main_v0418.rb",
                   "twentytwenty_live_mirror/renderer_v0418.html",
                   "dvacet20_component_library/ui/library.html"):
        assert previous[module] == updated[module], module
    assert previous[SUITE] != updated[SUITE], "Missing suite version"
    assert previous[ROOT_LOADER] != updated[ROOT_LOADER], "Missing loader version"
    # The suite always launches the embedded module on demand through its main
    # menu; no independent launcher should be created by embedded children.
    assert b"      install_ui\n      file_loaded(__FILE__)" not in updated[CHECKER]
    assert b"UI::Command.new('20-20 Knihovna komponent')" not in updated[LIBRARY]
    assert b"file_loaded(__FILE__) unless file_loaded?(__FILE__)" in updated[CHECKER]
    assert b"file_loaded(__FILE__) unless file_loaded?(__FILE__)" in updated[LIBRARY]
    for module in ("twentytwenty_rm_checker/main.rb",
                   "dvacet20_component_library/main.rb",
                   "twentytwenty_rm_tools_suite/main.rb",
                   ROOT_LOADER):
        f = SOURCE / module
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_bytes(updated[module])
    out = P / "20-20_RM_TOOLS_v2.0.4.rbz"
    write(out, updated)
    print(f"Built {out.name}: {out.stat().st_size} bytes")
    print("Updated direct INTERIER tags and disabled nested toolbar registrations")

if __name__ == "__main__":
    main()
