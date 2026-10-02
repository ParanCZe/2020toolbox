# frozen_string_literal: true

require 'sketchup.rb'
require 'json'
require File.join(__dir__, 'agent_autostart')
require File.join(__dir__, 'material_library')

module TwentyTwenty
  module RMToolsSuite
    extend self

    VERSION = '2.0.5.2'.freeze
    TITLE = '20-20 RM TOOLS'.freeze

    def dialog
      return @dialog if @dialog

      @dialog = UI::HtmlDialog.new(
        dialog_title: TITLE,
        preferences_key: '20-20-rm-tools-suite-v2',
        scrollable: true,
        resizable: true,
        width: 680,
        height: 770,
        min_width: 560,
        min_height: 500,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
      @dialog.set_html(html)
      bind_callbacks(@dialog)
      @dialog.set_on_closed { @dialog = nil }
      @dialog
    end

    def show
      dialog.show
    end

    def bind_callbacks(dlg)
      dlg.add_action_callback('suite_ready') { |_ctx| push_version }
      dlg.add_action_callback('suite_model_library') { |_ctx| open_model_library }
      dlg.add_action_callback('suite_meye_cutouts') { |_ctx| open_meye_cutouts }
      dlg.add_action_callback('suite_rm_checker') { |_ctx| open_rm_checker }
      dlg.add_action_callback('suite_tag_manager') { |_ctx| open_manager(:tags) }
      dlg.add_action_callback('suite_scene_manager') { |_ctx| open_manager(:scenes) }
      dlg.add_action_callback('suite_mirror_open') { |_ctx| open_mirror_panel }
      dlg.add_action_callback('suite_material_library') { |_ctx| MaterialLibrary.show }
      dlg.add_action_callback('suite_mirror_make') { |_ctx| mirror_action(:make_mirror_from_selection) }
      dlg.add_action_callback('suite_mirror_refresh') { |_ctx| mirror_action(:refresh_now) }
      dlg.add_action_callback('suite_mirror_raw') { |_ctx| mirror_action(:show_raw_reflection_frame) }
      dlg.add_action_callback('suite_mirror_rebuild') { |_ctx| mirror_action(:rebuild_renderer_scene, true) }
      dlg.add_action_callback('suite_mirror_live') { |_ctx| mirror_action(:toggle_live) }
      dlg.add_action_callback('suite_mirror_shading') { |_ctx| mirror_action(:toggle_shading) }
      dlg.add_action_callback('suite_mirror_edges') { |_ctx| mirror_action(:toggle_edges) }
      dlg.add_action_callback('suite_mirror_quality') { |_ctx, value| mirror_action(:set_quality, value.to_i) }
      dlg.add_action_callback('suite_mirror_limit') { |_ctx, value| mirror_action(:set_triangle_limit, value.to_i) }
      dlg.add_action_callback('suite_mirror_diagnostics') { |_ctx| mirror_action(:diagnostics) }
      dlg.add_action_callback('suite_mirror_remove') { |_ctx| mirror_action(:remove_mirror) }
    end

    def push_version
      exec_js("window.RMTOOLS && RMTOOLS.receiveVersion(#{JSON.generate(VERSION)});")
    end

    def child_path(*parts)
      File.expand_path(File.join('..', *parts), __dir__)
    end

    def open_model_library
      require child_path('dvacet20_component_library', 'main')
      @dialog.hide if @dialog
      Dvacet20::ComponentLibrary.show_dialog
      child = Dvacet20::ComponentLibrary.instance_variable_get(:@dialog)
      install_return_to_home(child) if child
    rescue StandardError => e
      child_error('Model Library', e)
    end

    def open_meye_cutouts
      # Independent HtmlDialog, but still part of the ONE RM TOOLS extension.
      # Only metadata/small remote previews load during browsing.
      require child_path('twentytwenty_meye_cutouts', 'main')
      @dialog.hide if @dialog
      TwentyTwenty::MeyeCutouts.show_dialog
      child = TwentyTwenty::MeyeCutouts.instance_variable_get(:@dialog)
      install_return_to_home(child) if child
    rescue StandardError => e
      show if @dialog
      child_error('2D stromy a keře · Meye', e)
    end

    def open_manager(which)
      require child_path('twentytwenty_rm_managers', 'main')
      @dialog.hide if @dialog
      TwentyTwenty::RMManagers.show(which)
    rescue StandardError => e
      show if @dialog
      child_error(which == :tags ? 'Tag Manager' : 'Scene Manager', e)
    end

    def open_rm_checker
      require File.join(__dir__, '..', 'twentytwenty_rm_checker', 'main')
      require child_path('twentytwenty_rm_tools_suite', 'camera_consistency')
      unless TwentyTwenty::RMPrep.singleton_class.ancestors.include?(TwentyTwenty::RMToolsSuite::CameraConsistency)
        TwentyTwenty::RMPrep.singleton_class.prepend(TwentyTwenty::RMToolsSuite::CameraConsistency)
      end
      @dialog.hide if @dialog
      TwentyTwenty::RMPrep.show
      child = TwentyTwenty::RMPrep.instance_variable_get(:@dialog)
      install_return_to_home(child) if child
    rescue StandardError => e
      child_error('Nastavení SKP / Záběr / Checker', e)
    end

    def install_return_to_home(child_dialog)
      child_dialog.add_action_callback('suite_back_home') do |_ctx|
        begin
          child_dialog.close
        rescue StandardError
          child_dialog.hide rescue nil
        end
        show
        @dialog.bring_to_front if @dialog
        exec_js('window.RMTOOLS && RMTOOLS.home();')
      end

      script = <<~JS
        (function(){
          if(document.getElementById('rmtoolsBackHome')) return;
          var b=document.createElement('button');
          b.id='rmtoolsBackHome';
          b.type='button';
          b.textContent='← HLAVNÍ MENU';
          b.title='Zpět do 20-20 RM TOOLS';
          b.style.cssText='height:36px;padding:0 12px;border:1px solid rgba(255,255,255,.16);border-radius:9px;background:#ffd52a;color:#111;font:800 11px -apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;cursor:pointer;white-space:nowrap;box-shadow:0 4px 14px rgba(0,0,0,.18);z-index:99999;';
          b.onmouseenter=function(){this.style.filter='brightness(1.06)'};
          b.onmouseleave=function(){this.style.filter='none'};
          b.onclick=function(){if(window.sketchup&&window.sketchup.suite_back_home){window.sketchup.suite_back_home();}};
          var top=document.querySelector('.top');
          if(top){b.style.flex='0 0 auto';top.insertBefore(b,top.firstChild);}
          else{
            b.style.position='fixed';b.style.top='12px';b.style.left='12px';
            document.body.appendChild(b);
          }
        })();
      JS

      inject = proc do
        begin
          child_dialog.execute_script(script)
        rescue StandardError
          nil
        end
      end
      UI.start_timer(0.15, false, &inject)
      UI.start_timer(0.80, false, &inject)
    rescue StandardError => e
      puts "20-20 RM TOOLS back button warning: #{e.class}: #{e.message}"
    end

    def live_mirror
      require child_path('twentytwenty_live_mirror', 'main_v0418')
      TwentyTwenty::LiveMirror
    end

    def open_mirror_panel
      mirror = live_mirror
      mirror.install_overlay
      mirror.attach_view_observer
      mirror.ensure_renderer if mirror.load_mirror_record
      push_mirror_state
    rescue StandardError => e
      child_error('Live Mirror', e)
    end

    def mirror_action(method_name, *args)
      mirror = live_mirror
      mirror.public_send(method_name, *args)
      push_mirror_state
    rescue StandardError => e
      child_error('Live Mirror', e)
    end

    def push_mirror_state
      mirror = live_mirror
      state = {
        has_mirror: !mirror.load_mirror_record.nil?,
        live: mirror.live_enabled?,
        shading: mirror.shading_enabled?,
        edges: mirror.edges_enabled?,
        quality: mirror.quality,
        triangle_limit: mirror.triangle_limit
      }
      exec_js("window.RMTOOLS && RMTOOLS.receiveMirrorState(#{JSON.generate(state)});")
    rescue StandardError => e
      puts "20-20 RM TOOLS mirror state warning: #{e.class}: #{e.message}"
    end

    def child_error(name, error)
      puts "20-20 RM TOOLS #{name} error: #{error.class}: #{error.message}"
      puts error.backtrace.join("\n") if error.backtrace
      UI.messagebox("#{name} se nepodařilo otevřít.\n\n#{error.class}: #{error.message}")
    end

    def exec_js(js)
      @dialog.execute_script(js) if @dialog
    rescue StandardError => e
      puts "20-20 RM TOOLS JS warning: #{e.message}"
    end

    def html
      <<~HTML
        <!doctype html>
        <html lang="cs">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <style>
            :root{color-scheme:dark;--bg:#0d0f12;--panel:#15181d;--line:#2a3038;--text:#f7f7f8;--muted:#9299a3;--yellow:#ffd52a}
            *{box-sizing:border-box}html,body{margin:0;min-height:100%;background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}button,select{font:inherit}
            .shell{min-height:100vh;padding:22px}.top{display:flex;justify-content:space-between;align-items:flex-start;gap:18px;margin-bottom:20px}.brand{display:flex;gap:12px;align-items:center}.mark{width:44px;height:44px;border-radius:12px;background:var(--yellow);color:#111;display:grid;place-items:center;font-weight:900;font-size:12px;box-shadow:0 0 0 1px rgba(255,255,255,.08) inset}.title{font-size:18px;font-weight:850;letter-spacing:.02em}.sub{color:var(--muted);font-size:11px;margin-top:4px}.ver{border:1px solid var(--line);border-radius:999px;padding:6px 9px;color:var(--muted);font-size:10px}
            .grid{display:grid;grid-template-columns:1fr;gap:12px}.launcher{appearance:none;width:100%;border:1px solid var(--line);background:linear-gradient(180deg,#191d23,#14171c);color:var(--text);border-radius:15px;padding:19px;text-align:left;display:grid;grid-template-columns:48px 1fr 24px;gap:15px;align-items:center;cursor:pointer;transition:transform .16s ease,border-color .16s ease,background .16s ease,box-shadow .16s ease}.launcher:hover{transform:translateY(-2px);border-color:#5b616a;background:linear-gradient(180deg,#20242b,#171a20);box-shadow:0 10px 28px rgba(0,0,0,.22)}.launcher:active{transform:translateY(0) scale(.995)}.ico{width:48px;height:48px;border-radius:12px;background:#232831;display:grid;place-items:center;color:var(--yellow);font-size:23px}.launcher b{display:block;font-size:15px;letter-spacing:.02em}.launcher span{display:block;color:var(--muted);font-size:11px;margin-top:4px;line-height:1.45}.arrow{color:#757d88;font-size:22px;transition:transform .16s ease}.launcher:hover .arrow{transform:translateX(3px);color:var(--yellow)}
            .page{display:none}.page.on{display:block}.back{appearance:none;border:0;background:transparent;color:var(--muted);padding:0;margin:0 0 14px;cursor:pointer;font-size:12px}.back:hover{color:#fff}.mirror-head{display:flex;justify-content:space-between;gap:12px;align-items:center;margin-bottom:14px}.mirror-head h2{margin:0;font-size:18px}.status{display:flex;gap:6px;flex-wrap:wrap}.pill{font-size:10px;border-radius:999px;padding:5px 8px;background:#252b33;color:#c6cbd2}.pill.on{background:#133c28;color:#8af0b6}.mirror-main{display:grid;grid-template-columns:1.35fr .85fr;gap:12px}.card{border:1px solid var(--line);border-radius:14px;background:var(--panel);padding:15px}.card h3{font-size:11px;letter-spacing:.08em;color:#c8cdd4;margin:0 0 11px}.primary{width:100%;border:0;border-radius:11px;background:var(--yellow);color:#121212;font-weight:850;padding:12px 14px;cursor:pointer;transition:transform .14s ease,filter .14s ease}.primary:hover{filter:brightness(1.05);transform:translateY(-1px)}.row{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:8px}.btn{border:1px solid #343b45;border-radius:10px;background:#20252c;color:#fff;padding:10px 11px;cursor:pointer;font-size:11px}.btn:hover{border-color:#5b626c;background:#262c34}.btn.danger{color:#ffb4b4;border-color:#563032}.control{margin-top:10px}.control label{display:block;color:var(--muted);font-size:10px;margin-bottom:5px}.control select{width:100%;border:1px solid #343b45;background:#111418;color:#fff;border-radius:9px;padding:9px}.hint{font-size:10px;line-height:1.5;color:var(--muted);margin-top:10px}.footer{margin-top:16px;padding-top:13px;border-top:1px solid #242a31;color:#737b86;font-size:10px}
            @media(max-width:620px){.shell{padding:16px}.mirror-main{grid-template-columns:1fr}.top{margin-bottom:15px}}
          </style>
        </head>
        <body>
          <div class="shell">
            <div class="top"><div class="brand"><div class="mark">20-20</div><div><div class="title">20-20 RM TOOLS</div><div class="sub">Jedno místo pro přípravu SketchUp modelu pro RENDERMAKER</div></div></div><div id="version" class="ver">v2.0.5.2</div></div>
            <section id="home" class="page on">
              <div class="grid">
                <button class="launcher" onclick="sketchup.suite_model_library()"><div class="ico">▦</div><div><b>MODEL LIBRARY</b><span>Serverová knihovna SKP komponent, vyhledávání a vložení modelu jedním kliknutím.</span></div><div class="arrow">›</div></button>
                <button class="launcher" onclick="sketchup.suite_meye_cutouts()"><div class="ico">♣</div><div><b>2D STROMY A KEŘE</b><span>Online knihovna Meye: náhledy, druhy, roční období. PNG se stáhne až kliknutím na +.</span></div><div class="arrow">›</div></button>
                <button class="launcher" onclick="sketchup.suite_tag_manager()"><div class="ico">▤</div><div><b>TAG MANAGER</b><span>Hierarchie tagů, viditelnost objektů, detail komponent a náhrada přes Model Library.</span></div><div class="arrow">›</div></button>
                <button class="launcher" onclick="sketchup.suite_scene_manager()"><div class="ico">▣</div><div><b>SCENE MANAGER</b><span>Přehled uložených scén, ohnisek a formátů, vytvoření a aktualizace scén.</span></div><div class="arrow">›</div></button>
                <button class="launcher" onclick="sketchup.suite_rm_checker()"><div class="ico">✓</div><div><b>NASTAVENÍ SKP / ZÁBĚR / CHECKER</b><span>Nastavení modelu a záběru, RM checklist, nálezy a opravy před odesláním do RENDERMAKERU.</span></div><div class="arrow">›</div></button>
                <button class="launcher" onclick="RMTOOLS.openMirror()"><div class="ico">◇</div><div><b>ZRCADLO</b><span>LIVE Mirror – vytvoření živého odrazu, kvalita, hrany, stínování a obnova renderu.</span></div><div class="arrow">›</div></button>
                <button class="launcher" onclick="sketchup.suite_material_library()"><div class="ico">▤</div><div><b>KNIHOVNA MATERIÁLŮ</b><span>Ateliérová knihovna materiálů RENDERMAKER. Otevře se pouze po kliknutí.</span></div><div class="arrow">›</div></button>
              </div>
              <div class="footer">RM TOOLS: Model Library, Meye 2D vegetace, RM Checker, Live Mirror a knihovna materiálů. Agenta a Bridge spouští na pozadí.</div>
            </section>
            <section id="mirror" class="page">
              <button class="back" onclick="RMTOOLS.home()">← HLAVNÍ MENU</button>
              <div class="mirror-head"><h2>LIVE Mirror</h2><div class="status"><span id="mirrorExists" class="pill">ZRCADLO –</span><span id="mirrorLive" class="pill">LIVE –</span><span id="mirrorShade" class="pill">STÍNY –</span><span id="mirrorEdges" class="pill">HRANY –</span></div></div>
              <div class="mirror-main">
                <div class="card"><h3>ZRCADLO</h3><button class="primary" onclick="sketchup.suite_mirror_make()">VYTVOŘIT Z VYBRANÉ PLOCHY</button><div class="row"><button class="btn" onclick="sketchup.suite_mirror_refresh()">Obnovit odraz</button><button class="btn" onclick="sketchup.suite_mirror_rebuild()">Načíst scénu</button></div><div class="row"><button class="btn" onclick="sketchup.suite_mirror_raw()">Surový render</button><button class="btn danger" onclick="sketchup.suite_mirror_remove()">Odstranit zrcadlo</button></div><div class="hint">Vyber jednu plochu, která má být zrcadlem, a klikni na vytvořit. Live Mirror pracuje bez přesouvání SketchUp kamery.</div></div>
                <div class="card"><h3>NASTAVENÍ</h3><div class="row"><button class="btn" onclick="sketchup.suite_mirror_live()">LIVE ON / OFF</button><button class="btn" onclick="sketchup.suite_mirror_shading()">STÍNY ON / OFF</button></div><button class="btn" style="width:100%;margin-top:8px" onclick="sketchup.suite_mirror_edges()">HRANY ON / OFF</button><div class="control"><label>KVALITA ODRAZU</label><select id="quality" onchange="sketchup.suite_mirror_quality(this.value)"><option value="512">512 px</option><option value="768">768 px</option><option value="1024">1024 px</option><option value="1536">1536 px</option><option value="2048">2048 px (2K)</option><option value="3072">3072 px (Ultra)</option><option value="4096">4096 px (4K)</option></select></div><div class="control"><label>DETAIL SCÉNY</label><select id="limit" onchange="sketchup.suite_mirror_limit(this.value)"><option value="180000">180k · Low</option><option value="350000">350k · Medium</option><option value="600000">600k · High</option><option value="900000">900k · Max</option><option value="1500000">1.5M · Very heavy</option></select></div><button class="btn" style="width:100%;margin-top:8px" onclick="sketchup.suite_mirror_diagnostics()">Diagnostika</button></div>
              </div>
            </section>
          </div>
          <script>
            window.RMTOOLS={
              receiveVersion:function(v){document.getElementById('version').textContent='v'+v;},
              home:function(){document.getElementById('mirror').classList.remove('on');document.getElementById('home').classList.add('on');},
              openMirror:function(){document.getElementById('home').classList.remove('on');document.getElementById('mirror').classList.add('on');sketchup.suite_mirror_open();},
              setPill:function(id,label,on){var e=document.getElementById(id);if(!e)return;e.textContent=label+' '+(on?'ON':'OFF');e.classList.toggle('on',!!on);},
              receiveMirrorState:function(s){RMTOOLS.setPill('mirrorExists','ZRCADLO',s.has_mirror);RMTOOLS.setPill('mirrorLive','LIVE',s.live);RMTOOLS.setPill('mirrorShade','STÍNY',s.shading);RMTOOLS.setPill('mirrorEdges','HRANY',s.edges);var q=document.getElementById('quality'),l=document.getElementById('limit');if(q)q.value=String(s.quality);if(l)l.value=String(s.triangle_limit);}
            };
            document.addEventListener('DOMContentLoaded',function(){sketchup.suite_ready();});
          </script>
        </body>
        </html>
      HTML
    end

    def install_ui
      @command ||= UI::Command.new(TITLE) { show }
      @command.tooltip = TITLE
      @command.status_bar_text = 'Model Library, RM Checker a Live Mirror v jednom pluginu.'
      icon = File.join(__dir__, 'icons', 'rm_checker.svg')
      if File.exist?(icon)
        @command.small_icon = icon
        @command.large_icon = icon
      end
      @toolbar ||= UI::Toolbar.new(TITLE)
      unless @toolbar_added
        @toolbar.add_item(@command)
        @toolbar_added = true
      end
      @toolbar.restore
      begin
        UI.menu('Extensions').add_item(@command)
      rescue StandardError
        UI.menu('Plugins').add_item(@command) rescue nil
      end
      true
    rescue StandardError => e
      puts "20-20 RM TOOLS UI error: #{e.class}: #{e.message}"
      false
    end

    unless file_loaded?(__FILE__)
      install_ui
      AgentBoot.install_settings_menu if AgentBoot.windows?
      # The main RM TOOLS window opens normally; ONLY Agent + Bridges run
      # invisibly in the background, with no extra toolbar or chooser popup.
      UI.start_timer(1.5, false) do
        AgentBoot.start
        show
        # Do NOT open the materials dialog automatically. Only the new
        # home-menu button and the existing dockable icon may open it.
        # Give any existing AI-TOOLS/most.rb toolbar time to initialize first:
        # if already present, reuse its original left icon. Otherwise expose
        # our own one-icon native SketchUp toolbar (manually dockable left).
        UI.start_timer(2.0, false) { MaterialLibrary.install_toolbar }
      end
      file_loaded(__FILE__)
    end
  end
end
