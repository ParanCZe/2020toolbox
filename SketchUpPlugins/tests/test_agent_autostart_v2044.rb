# frozen_string_literal: true
# Mock SketchUp + local Windows files to verify fully headless bundled autostart.
$LOADED_FEATURES << 'sketchup.rb'
require 'tmpdir'
require 'fileutils'

module UI
  @timers=[]
  @messages=[]
  @menus=[]
  class << self
    attr_reader :timers,:messages,:menus
  end
  class Menu
    attr_reader :items
    def initialize; @items=[]; end
    def add_submenu(name)
      @items << name
      Menu.new
    end
    def add_item(label)
      @items << label
    end
  end
  def self.menu(_name)
    @menu ||= Menu.new
  end
  def self.start_timer(seconds, repeating, &block)
    @timers << [seconds, repeating, block]
    @timers.size
  end
  def self.messagebox(message)
    @messages << message
  end
end

module Sketchup
  @prefs={}
  class << self
    attr_reader :prefs
  end
  def self.read_default(section,key,default)
    @prefs.fetch([section,key],default)
  end
  def self.write_default(section,key,value)
    @prefs[[section,key]]=value
  end
end

require_relative '../RMToolsSuiteSourceV2044/twentytwenty_rm_tools_suite/agent_autostart'
agent=TwentyTwenty::RMToolsSuite::AgentBoot
raise 'Wrong uploaded launcher preference section' unless agent::PREF_SECTION=='20-20 Agent Launcher'
raise 'Wrong default adapter path' unless agent::DEFAULT_ADAPTER=='C:/2020agent/dist/adapter-agent.exe'
raise 'Wrong default most.rb path' unless agent::DEFAULT_SCRIPT=='C:/2020agent/dist/sketchup/most.rb'

Dir.mktmpdir('rmtools-autostart-test') do |dir|
  adapter=File.join(dir,'adapter-agent.exe')
  script=File.join(dir,'most.rb')
  File.write(adapter,"fake exe")
  File.write(script,"$most_load_count ||= 0\n$most_load_count += 1\n")
  ENV['APPDATA']=dir
  # The generated VBS receives the command and cwd as escaped source
  # literals. Nothing goes through WScript.Arguments(0) anymore.
  command = '"C:\Program Files\2020agent\adapter-agent.exe" --start'
  runner=agent.hidden_runner(command,dir)
  bytes=File.binread(runner)
  raise 'WScript runner must be UTF-16 with BOM' unless bytes.start_with?("\xFF\xFE".b)
  contents=bytes.byteslice(2..-1).force_encoding('UTF-16LE').encode('UTF-8')
  raise 'Old fragile argument-based launch survived' if contents.include?('WScript.Arguments')
  raise 'Executable quote escaping lost' unless contents.include?(
    'sh.Run """C:\Program Files\2020agent\adapter-agent.exe"" --start", 0, False')
  raise 'No cwd in script' unless contents.include?('sh.CurrentDirectory')
  raise 'No silent error logging' unless contents.include?('rmtools_autostart.log')
  raise 'Generated runner changes on each call' unless agent.hidden_runner(command,dir)==runner
  raise 'VBScript quote escaping is broken' unless agent.vbs_literal('a"b')=='"a""b"'

  # Simulate installed WScript; a nonexistent target executable must fail
  # with an actionable Ruby error instead of an OS popup.
  ENV['WINDIR']=dir
  FileUtils.mkdir_p(File.join(dir,'System32'))
  File.write(File.join(dir,'System32','wscript.exe'),'fake exe')
  begin
    agent.launch_hidden('"C:\DefinitelyMissing\adapter-agent.exe"',dir)
    raise 'Missing executable was launched!'
  rescue RuntimeError => e
    raise unless e.message.include?('Spouštěný program nebyl nalezen')
  end
  puts 'PASS: generated WScript command preserves quoted executable paths, logs errors, and detects missing EXE'

  Sketchup.prefs[['20-20 Agent Launcher','adapter_path']]=adapter
  Sketchup.prefs[['20-20 Agent Launcher','most_rb_path']]=script
  operations=[]
  online=false
  agent.define_singleton_method(:windows?){true}
  agent.define_singleton_method(:helper_dir){File.join(dir,'helper')}
  agent.define_singleton_method(:adapter_running?){|_|false}
  agent.define_singleton_method(:launch_hidden){|command,cwd|operations << [command,cwd];true}
  agent.define_singleton_method(:web_bridge_online?){online}
  agent.install_settings_menu
  agent.install_settings_menu
  raise 'Duplicated Agent menu' unless UI.menu('Extensions').items.length==1
  raise 'Settings leaked a popup on startup' unless UI.messages.empty?

  agent.start
  raise 'Auto-start did not launch EXE invisibly' unless operations.any?{|x|x[0].include?('adapter-agent.exe')}
  raise 'Auto-start did not launch persisted session Bridge invisibly' unless operations.any?{|x|x[0].include?('bridge_session.ps1') && x[0].include?('-SketchUpSession')}
  raise 'Auto-start helper tried a remote download' if operations.any?{|x|x[0].include?('Invoke-WebRequest')}
  raise 'Auto-start did not create local helper files' unless File.file?(File.join(dir,'helper','bridge_v3.ps1'))
  raise 'Protocol registration was skipped' unless operations.any?{|x|x[0].include?('register_protocol_v3.ps1')}
  raise 'Agent not deferred until after EXE start' unless UI.timers.any?{|t|t[0]==1.0 && !t[1]}
  raise 'Web Bridge not monitored during SketchUp session' unless UI.timers.any?{|t|t[0]==agent::CHECK_INTERVAL && t[1]}
  raise 'Unexpected popup during invisible startup' unless UI.messages.empty?

  first=operations.size
  agent.start
  raise 'Second initialization created duplicate processes' unless first==operations.size
  agent_timers=UI.timers.select{|t|t[0]==1.0 && !t[1]}
  raise 'Duplicate most.rb timer' unless agent_timers.size==1
  agent_timers.first[2].call
  raise 'most.rb not loaded exactly once' unless $most_load_count==1
  agent.retry_now
  raise 'most.rb was reloaded by manual retry' unless $most_load_count==1
  raise 'Missing agent status' unless agent.status[:ruby_bridge]=='načtený'

  online=true
  repeat=UI.timers.select{|t|t[1] && t[0]==agent::CHECK_INTERVAL}
  raise 'Duplicate monitor' unless repeat.size==1
  before=operations.size
  repeat.first[2].call
  raise 'Running Bridge should be reused' unless operations.size==before
  raise 'Bridge status incorrectly offline' unless agent.status[:web_bridge]=='běží'
  puts 'PASS: startup loads original Agent Launcher paths and most.rb once'
  puts 'PASS: adapter and persistent website Bridge are launched invisibly without downloads or popups'
  puts 'PASS: repeated boot and Bridge monitoring do not create duplicate processes'
  puts 'PASS: original settings retained, optional manual menu has no toolbar'
end
