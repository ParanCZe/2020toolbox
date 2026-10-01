# Simulates a 5-piece SKP (e.g. a BIM faucet) and asserts zero wrapper insertion.
$LOADED_FEATURES << "sketchup.rb"
require "ostruct"
require "tmpdir"

module Kernel
  def file_loaded?(*); true; end
end

module UI
  def self.start_timer(seconds, _repeat, &block); block.call if seconds == 0; end
  def self.messagebox(message); $ui_error=message; end
end

module Geom
  class Transformation
    attr_reader :parts
    def initialize(parts=[]); @parts=parts; end
    def to_a; @parts; end
    def *(other); self.class.new(@parts+other.to_a); end
    def self.translation(pt); new(["click",pt]); end
  end
  def self.intersect_line_plane(_ray,_plane); [55,22,0]; end
end
ORIGIN=[0,0,0]
Z_AXIS=[0,0,1]

module Sketchup
  class EntitiesObserver; end
  class ComponentInstance; end
  class ConstructionPoint; end
  class ConstructionLine; end
  class InputPoint
    def valid?; false; end
  end
  def self.active_model; $current_model; end
  def self.set_status_text(text); $last_status=text; end
end

load "SketchUpPlugins/ComponentLibrarySourceV034/dvacet20_component_library/main.rb"
library=Dvacet20::ComponentLibrary

class SourceComponent < Sketchup::ComponentInstance
  attr_reader :definition,:transformation
  def initialize(definition,index)
    @definition=definition
    @index=index
    @transformation=Geom::Transformation.new(["source",index])
  end
  def name; "PART_#{@index}"; end
  def layer; OpenStruct.new(name:"SANITA"); end
  def material; nil; end
  def hidden?; false; end
  def casts_shadows?; true; end
  def receives_shadows?; true; end
  def locked?; false; end
  def attribute_dictionaries; nil; end
end

class DestInstance < Sketchup::ComponentInstance
  attr_reader :definition,:model
  attr_accessor :transformation,:name,:layer,:material,:hidden,:casts_shadows,:receives_shadows,:locked
  def initialize(definition,transform,model)
    @definition,@transformation,@model=definition,transform,model
  end
  def valid?; true; end
  def set_attribute(*); end
end

class MockEntities
  attr_reader :created,:observers
  attr_accessor :items,:model
  def initialize(items=[],model=nil)
    @items,@model=items,model
    @created=[]
    @observers=[]
  end
  def to_a; @items; end
  def add_instance(definition,transform)
    obj=DestInstance.new(definition,transform,@model)
    @created<<obj
    obj
  end
  def add_observer(obs); @observers<<obs; end
  def remove_observer(obs); @observers.delete(obs); end
  def notify(entity); @observers.dup.each{|obs| obs.onElementAdded(self,entity)}; end
end

class MockLayers < Hash
  def add(name); self[name]=OpenStruct.new(name:name); end
end

class MockSelection < Array
  def add(instance); self << instance; end
end

class MockModel
  attr_reader :active_entities,:layers,:materials,:selection,:removed,:started,:committed
  attr_reader :tool,:native_placements
  def initialize(wrapper)
    @wrapper=wrapper
    @active_entities=MockEntities.new([],self)
    @layers=MockLayers.new
    @materials={}
    @selection=MockSelection.new
    @removed=[]
    @started=0
    @committed=0
    @native_placements=[]
  end
  def definitions; self; end
  def load(*); @wrapper; end
  def remove(defn); @removed << defn; end
  def select_tool(tool); @tool=tool; tool.activate if tool; end
  def start_operation(*); @started+=1; end
  def commit_operation; @committed+=1; end
  def abort_operation; raise "unexpected abort"; end
  def place_component(definition,_repeat)
    @native_placements<<definition
    created=@active_entities.add_instance(definition,Geom::Transformation.new(["click"]),self)
    @active_entities.notify(created)
  end
end

class MockView
  def pickray(*); ["fake ray"]; end
end

definitions=Array.new(5){Object.new}
roots=definitions.each_with_index.map{|d,i| SourceComponent.new(d,i)}
wrapper=OpenStruct.new(entities:MockEntities.new(roots),instances:[])
$current_model=MockModel.new(wrapper)
Dir.mktmpdir do |dir|
  skp=File.join(dir,"BATERIE_HANSGROHE_FOCUS_M41.skp")
  File.write(skp,"mock")
  library.insert_component(skp,nil)
end

tool=$current_model.tool
raise "No native multi-root placement tool" unless tool.is_a?(Dvacet20::ComponentLibrary::DirectMultiPlacementTool)
raise "Unexpected file-wrapper placement" unless $current_model.native_placements.empty?
tool.onLButtonDown(0,5,6,MockView.new)
parts=$current_model.active_entities.created
raise "Expected 5 direct components, got #{parts.length}" unless parts.length==5
raise "Unexpected wrapper definition" if parts.any?{|p| p.definition.equal?(wrapper)}
parts.each_with_index do |part,index|
  raise "Wrong definition #{index}" unless part.definition.equal?(definitions[index])
  raise "Wrong original transform #{index}" unless part.transformation.to_a==["click",[55,22,0],"source",index]
  raise "Metadata lost #{index}" unless part.name=="PART_#{index}" && part.layer.name=="SANITA"
end
raise "Wrapper was not removed" unless $current_model.removed.include?(wrapper)
raise "Expected one Undo transaction" unless $current_model.started==1 && $current_model.committed==1
raise "Inserted parts not selected" unless $current_model.selection.length==5
puts "PASS: BIM-like 5-root SKP inserts 5 original components without another wrapper"
puts "PASS: source transforms, original tags, selection, Undo, and wrapper cleanup"

# Single-root file still uses native SketchUp placement and no new definition.
single=SourceComponent.new(Object.new,1)
wrapper_one=OpenStruct.new(entities:MockEntities.new([single,Sketchup::ConstructionPoint.new]),instances:[])
$current_model=MockModel.new(wrapper_one)
Dir.mktmpdir do |dir|
  skp=File.join(dir,"single.skp")
  File.write(skp,"mock")
  library.insert_component(skp,nil)
end
raise "Single root did not use native placement" unless $current_model.native_placements==[single.definition]
raise "Single root introduced wrapper" if $current_model.native_placements.include?(wrapper_one)
puts "PASS: single-root files still place their original component"

# Extra raw geometry causes a diagnostic rather than silent geometry loss.
mixed=OpenStruct.new(entities:MockEntities.new([single,Object.new]),instances:[])
$current_model=MockModel.new(mixed)
$ui_error=nil
Dir.mktmpdir do |dir|
  file=File.join(dir,"mixed.skp")
  File.write(file,"mock")
  library.insert_component(file,nil)
end
raise "Mixed SKP silently dropped geometry" unless $ui_error&.include?("geometrii")
raise "Mixed SKP incorrectly placed a wrapper" unless $current_model.native_placements.empty? && $current_model.active_entities.created.empty?
puts "PASS: unsupported loose geometry is rejected without creating a wrapper"
