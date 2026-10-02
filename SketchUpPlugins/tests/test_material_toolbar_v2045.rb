# frozen_string_literal: true
# Test the REAL original 20/20 material-library toolbar icon and startup panel.
$LOADED_FEATURES << 'sketchup.rb'
require 'ostruct'

module UI
  @timers=[]
  @dialogs=[]
  @toolbars=[]
  @commands=[]
  @messages=[]
  class << self
    attr_reader :timers, :dialogs, :toolbars, :commands, :messages
  end
  def self.start_timer(delay, repeat, &block)
    @timers << [delay,repeat,block]
    @timers.size
  end
  def self.messagebox(text)
    @messages << text
  end
  class Command
    attr_accessor :tooltip,:status_bar_text,:small_icon,:large_icon
    def initialize(name,&block)
      @name,@action=name,block
      UI.commands << self
    end
    def call
      @action.call
    end
  end
  class Toolbar
    attr_reader :name,:items,:restore_calls,:show_calls
    def initialize(name)
      @name=name
      @items=[]
      @restore_calls=0
      @show_calls=0
      @visible=false
      UI.toolbars << self
    end
    def add_item(item); @items << item; end
    def restore; @restore_calls+=1;end
    def visible?; @visible;end
    def show; @visible=true; @show_calls+=1;end
  end
  class HtmlDialog
    STYLE_DIALOG=1
    attr_reader :options,:url,:show_calls
    def initialize(**opts)
      @options=opts
      @show_calls=0
      UI.dialogs << self
    end
    def set_url(url);@url=url;end
    def set_on_closed(&block);@on_closed=block;end
    def show;@show_calls+=1;end
  end
end

require_relative '../RMToolsSuiteSourceV2045/twentytwenty_rm_tools_suite/material_library'
lib=TwentyTwenty::RMToolsSuite::MaterialLibrary
unless lib::URL=='http://127.0.0.1:8787/knihovna?cad=sketchup'
  raise "Not the original AI-TOOLS/Rhino material URL"
end

online=false
lib.define_singleton_method(:agent_online?){online}
lib.install_toolbar
toolbar=UI.toolbars.last
raise 'Wrong native dockable toolbar' unless toolbar.name=='20-20 Knihovna materiálů'
raise 'Missing material icon' unless toolbar.items.size==1
icon=toolbar.items.first
raise 'Missing 24px original AI icon' unless File.file?(icon.small_icon)
raise 'Missing 32px original AI icon' unless File.file?(icon.large_icon)
raise 'Toolbar did not appear' unless toolbar.show_calls==1 && toolbar.restore_calls==1
raise 'Wrong title on icon' unless icon.tooltip=='20-20 Knihovna materiálů'
lib.install_toolbar
raise 'Duplicate toolbar added' unless UI.toolbars.size==1
raise 'Duplicate icon added' unless UI.commands.size==1
puts 'PASS: one original Materials Library icon on independent left-dockable SketchUp toolbar'

# Silent startup while adapter boots: no error box or blank HtmlDialog.
lib.startup
lib.startup
raise 'Two concurrent startup retries' unless UI.timers.size==1
first=UI.timers.shift
first.last.call
raise 'Opened while adapter offline' unless UI.dialogs.empty?
raise 'Unexpected offline popup on startup' unless UI.messages.empty?
raise 'No scheduled retry' unless UI.timers.size==1
online=true
UI.timers.shift.last.call
raise 'No material panel on agent readiness' unless UI.dialogs.size==1
dialog=UI.dialogs.first
raise 'Material panel uses wrong page' unless dialog.url==lib::URL
raise 'Material dialog not automatically shown' unless dialog.show_calls==1
raise 'Material panel size changed' unless dialog.options[:width]==1000 && dialog.options[:height]==720
lib.startup
raise 'Repeated startup opened duplicate material panel' unless UI.dialogs.size==1 && UI.timers.empty?
icon.call
raise 'Icon did not reopen original material panel' unless dialog.show_calls==2
raise 'Icon created duplicate dialogs' unless UI.dialogs.size==1
puts 'PASS: original material page automatically opens once after agent comes online'
puts 'PASS: icon reopens same panel without creating additional windows or popups'

# Preserve installed AI-TOOLS toolbar rather than rendering a duplicate RM icon.
lib.instance_variable_set(:@toolbar,nil)
module Dvacet20
  module Most
    class << self
      attr_reader :opened,:toolbar_restored
      def zobraz_listu; @toolbar_restored=true; end
      def panel_knihovny; @opened=(@opened||0)+1;end
    end
  end
end
prior=UI.toolbars.size
lib.install_toolbar
raise 'Did not restore existing AI-TOOLS toolbar' unless Dvacet20::Most.toolbar_restored
raise 'Created a second 20/20 icon while AI-TOOLS exists' unless UI.toolbars.size==prior
raise 'Wrong existing-toolbar marker' unless lib.instance_variable_get(:@toolbar)==:existing_ai_tools
lib.show
raise 'Did not delegate panel to AI-TOOLS' unless Dvacet20::Most.opened==1
raise 'Existing AI-TOOLS created another duplicate panel' unless UI.dialogs.size==1
puts 'PASS: when original AI-TOOLS is loaded, reuse its toolbar icon and panel'
