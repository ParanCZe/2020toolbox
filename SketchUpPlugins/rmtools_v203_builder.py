#!/usr/bin/env python3
"""Publish Model Library v0.3.2 and RM TOOLS v2.0.3, preserving all other modules."""
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parent.parent
P = ROOT / "SketchUpPlugins"
SOURCE = P / "ComponentLibrarySourceV032"
SUITE_SOURCE = P / "RMToolsSuiteSourceV203"

def read_zip(path):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, path
        return {name: archive.read(name) for name in archive.namelist() if not name.endswith("/")}

def write_zip(path, entries):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, contents in sorted(entries.items()):
            archive.writestr(name, contents)
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, path

def swap(src, old, new):
    assert src.count(old) == 1, f"Expected one anchor: {old!r}; found {src.count(old)}"
    return src.replace(old, new, 1)

def main():
    loader = SOURCE / "dvacet20_component_library.rb"
    main = SOURCE / "dvacet20_component_library/main.rb"
    ui = SOURCE / "dvacet20_component_library/ui/library.html"
    src = {
        "dvacet20_component_library.rb": loader.read_bytes(),
        "dvacet20_component_library/main.rb": main.read_bytes(),
        "dvacet20_component_library/ui/library.html": ui.read_bytes()
    }
    text = src["dvacet20_component_library/main.rb"].decode("utf-8")
    assert "VERSION = '0.3.2'" in text
    assert "model.place_component(target_definition, false)" in text
    assert "register_placement_metadata_observer" in text
    assert "model.place_component(loaded_definition, false)" in text
    assert "PlacementConversionObserver" not in text

    standalone_old = read_zip(P / "20-20_Component_Library_v0.3.1.rbz")
    standalone = dict(standalone_old)
    standalone.update(src)
    standalone_out = P / "20-20_Component_Library_v0.3.2.rbz"
    write_zip(standalone_out, standalone)

    bundled_old = read_zip(P / "20-20_RM_TOOLS_v2.0.2.rbz")
    bundled = dict(bundled_old)
    # The suite uses an autostart-disabled stub loader to avoid duplicate toolbar buttons.
    for member in ("dvacet20_component_library/main.rb", "dvacet20_component_library/ui/library.html"):
        assert member in bundled, f"Suite member missing: {member}"
        bundled[member] = src[member]
    stub = "dvacet20_component_library.rb"
    previous = bundled[stub].decode("utf-8")
    bundled[stub] = swap(previous, "EXTENSION_VERSION = '0.3.1'", "EXTENSION_VERSION = '0.3.2'").encode("utf-8")
    for member in ("twentytwenty_rm_tools_suite.rb", "twentytwenty_rm_tools_suite/main.rb"):
        data = bundled[member].decode("utf-8")
        assert "2.0.2" in data
        bundled[member] = data.replace("2.0.2", "2.0.3").encode("utf-8")

    bundle_out = P / "20-20_RM_TOOLS_v2.0.3.rbz"
    write_zip(bundle_out, bundled)

    for member in (
        "twentytwenty_rm_tools_suite.rb", "twentytwenty_rm_tools_suite/main.rb",
        "dvacet20_component_library.rb", "dvacet20_component_library/main.rb",
        "dvacet20_component_library/ui/library.html"
    ):
        dst = SUITE_SOURCE / member
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(bundled[member])

    # All existing RM tag migration / Live Mirror module contents must remain identical.
    for member in (
        "twentytwenty_rm_checker/main.rb", "twentytwenty_rm_checker.rb",
        "twentytwenty_live_mirror/main_v0418.rb", "twentytwenty_live_mirror/renderer_v0418.html"
    ):
        assert bundled[member] == bundled_old[member], f"Unexpected modification: {member}"
    print("Built", standalone_out.name, standalone_out.stat().st_size)
    print("Built", bundle_out.name, bundle_out.stat().st_size)
    print("Unchanged RM tag updater and Live Mirror")

if __name__ == "__main__":
    main()
