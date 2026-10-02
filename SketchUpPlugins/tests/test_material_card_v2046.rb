# frozen_string_literal: true
# Regression for 2.0.4.6: ONLY a visible menu card or toolbar icon opens library.
source=File.read("SketchUpPlugins/RMToolsSuiteSourceV2046/twentytwenty_rm_tools_suite/main.rb",encoding:"UTF-8")

def check(ok, description)
  raise "FAIL: #{description}" unless ok
  puts "PASS: #{description}"
end

check(source.include?("VERSION = '2.0.4.6'"),"v2.0.4.6")
check(source.include?("require File.join(__dir__, 'material_library')"),"original materials module retained")
check(source.include?("AgentBoot.start"),"background Agent and Bridge startup retained")
check(source.include?("MaterialLibrary.install_toolbar"),"existing left-side materials icon retained")
check(!source.include?("MaterialLibrary.startup"),"materials popup not opened at startup")
check(source.include?("dlg.add_action_callback('suite_material_library') { |_ctx| MaterialLibrary.show }"),
      "new UI button opens existing material-library panel")

menu_begin=source.index('<section id="home" class="page on">')
menu_end=source.index('<section id="mirror" class="page">')
raise "Home section missing" unless menu_begin && menu_end && menu_end>menu_begin
menu=source[menu_begin...menu_end]
buttons=menu.scan(/<button class="launcher" onclick="[^"]+">/)
check(buttons.length==4,"four main-menu cards only")
check(menu.index("<b>MODEL LIBRARY</b>") < menu.index("<b>NASTAVENÍ SKP / ZÁBĚR / CHECKER</b>"),
      "Model Library before Checker")
check(menu.index("<b>ZRCADLO</b>") < menu.index("<b>KNIHOVNA MATERIÁLŮ</b>"),
      "material-library button directly below Mirror")
check(menu.index("<b>KNIHOVNA MATERIÁLŮ</b>") < menu_end,"material button in home section")
check(menu.include?('onclick="sketchup.suite_material_library()"'),
      "material card correctly connected to SketchUp callback")
check(source.scan(/dlg\.add_action_callback\('suite_material_library'\)/).length==1,
      "no duplicate click callbacks")
check(!source.match?(/UI\.start_timer\([^\n]*\).*MaterialLibrary\.show/),
      "no immediate materials-popup timer")
check(source.include?("height: 650"),"window has enough room for fourth menu card")
puts "PASS: manual materials button without automatic material window"
