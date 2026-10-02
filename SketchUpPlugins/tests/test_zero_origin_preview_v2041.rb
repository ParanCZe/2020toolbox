# Regression tests for RM TOOLS 2.0.4.1 source-origin PREVIEW hotfix.
# Simulates SketchUp native placement plus EntitiesObserver callbacks without SketchUp.
$LOADED_FEATURES << 'sketchup.rb'
require 'ostruct'
require 'tmpdir'

module Kernel
  def file_loaded?(_path)
    true
  end
end

module UI
  @pending = []
  @timeouts = []
  class << self
    attr_reader :pending, :timeouts
    attr_accessor :last_message
  end
  def self.start_timer(seconds, _repeat, &block)
    (seconds == 0 ? @pending : @timeouts) << block
  end
  def self.flush_one
    block=@pending.shift
    raise 'Expected a queued SketchUp UI event' unless block
    block.call
  end
  def self.messagebox(message)
    @last_message = message
  end
end

module Geom
  class Transformation
    attr_reader :ops
    def initialize(ops = [])
      @ops=ops
    end
    def to_a
      @ops
    end
    def *(other)
      self.class.new(@ops + other.to_a)
    end
  end
end

module Sketchup
  class EntitiesObserver; end
  class ComponentInstance; end
  class ConstructionPoint; end
  class ConstructionLine; end
  def self.active_model
    $model
  end
  def self.set_status_text(text)
    $status=text
  end
end

load 'SketchUpPlugins/RMToolsSuiteSourceV2041/dvacet20_component_library/main.rb'
library=Dvacet20::ComponentLibrary
raise 'Changed base module version' unless library::VERSION=='0.3.2.1'

class SourceInstance < Sketchup::ComponentInstance
  attr_reader :definition, :transformation, :name, :material
  def initialize(definition, transformation, name='VANICKA')
    @definition, @transformation, @name=definition,transformation,name
    @material=OpenStruct.new(name:'CHROME')
  end
  def layer; OpenStruct.new(name:'SANITA'); end
  def hidden?; false; end
  def casts_shadows?; true; end
  def receives_shadows?; true; end
  def locked?; false; end
  def attribute_dictionaries; nil; end
end

class PlacedInstance < Sketchup::ComponentInstance
  attr_accessor :definition, :transformation, :name, :layer, :material,
                :hidden, :casts_shadows, :receives_shadows, :locked
  def initialize(definition, transformation, model)
    @definition,@transformation,@model=definition,transformation,model
  end
  def model; @model; end
  def valid?; true; end
  def set_attribute(*args); end
end

class MockEntities
  attr_accessor :items
  attr_reader :observers
  def initialize(items=[])
    @items=items
    @observers=[]
  end
  def to_a; @items; end
  def add_observer(observer)
    @observers << observer
    true
  end
  def remove_observer(observer)
    @observers.delete(observer)
  end
  def notify(instance)
    @observers.dup.each { |observer| observer.onElementAdded(self, instance) }
  end
end

class MockLayers < Hash
  def add(name); self[name]=OpenStruct.new(name:name); end
end

class MockModel
  attr_reader :active_entities,:layers,:materials,:placed_instance,:preview_definition,:native_calls
  def initialize(loaded)
    @loaded=loaded
    @layers=MockLayers.new
    @materials={'CHROME'=>OpenStruct.new(name:'CHROME')}
    @active_entities=MockEntities.new
    @native_calls=0
  end
  def definitions; self; end
  def load(_path); @loaded; end
  def place_component(definition,_repeat)
    @native_calls+=1
    @preview_definition=definition
    @placed_instance=PlacedInstance.new(definition, Geom::Transformation.new(['DROP']),self)
    @active_entities.notify(@placed_instance)
  end
end

source=Geom::Transformation.new(['SOURCE_0_0_0_OFFSET','SOURCE_ROTATION'])
target=Object.new
original=SourceInstance.new(target,source,'BATERIE_FOCUS')
root_entities=MockEntities.new([original,Sketchup::ConstructionPoint.new])
file_definition=OpenStruct.new(entities:root_entities)
$model=MockModel.new(file_definition)

Dir.mktmpdir do |dir|
  file=File.join(dir,'model.skp')
  File.write(file,'mock')
  library.insert_component(file,nil)
end

# Pre-click native preview uses the SKP FILE definition, not the corner/axes
# of the internal component. Thus it displays child at DROP * SOURCE_OFFSET.
UI.flush_one
raise 'Native preview did not use the source SKP origin' unless $model.preview_definition.equal?(file_definition)
raise 'Preview root was converted before click' unless $model.placed_instance.definition.equal?(file_definition)
raise 'Expected deferred post-click conversion' unless UI.pending.length==1
raise 'Native placement invoked more than once' unless $model.native_calls==1
expected_preview=Geom::Transformation.new(['DROP'])*source
raise 'Unexpected preview transform model' unless expected_preview.to_a==['DROP','SOURCE_0_0_0_OFFSET','SOURCE_ROTATION']

# After-click conversion composes exactly the SAME transform as the preview,
# retaining original instance, metadata, and NO extra wrapper component.
UI.flush_one
placed=$model.placed_instance
raise 'Placed file-level wrapper instead of original component' unless placed.definition.equal?(target)
raise 'Object jumps after click' unless placed.transformation.to_a == expected_preview.to_a
raise 'Original tag lost' unless placed.layer.name=='SANITA'
raise 'Original name lost' unless placed.name=='BATERIE_FOCUS'
raise 'Original material lost' unless placed.material.name=='CHROME'
raise 'Observer not released after click' unless $model.active_entities.observers.empty?
raise 'Expected no pending UI conversions' unless UI.pending.empty?
raise 'Missing preview status' unless $status.include?('nulu SKP')
puts 'PASS: while dragging, native preview is anchored to the original SKP file 0,0,0'
puts 'PASS: after click, exact same transform and original component, tag, name and material'
puts 'PASS: observer runs once and is removed (no extra component or double placement)'

# Non-unwrappable file preserves 2.0.4 fallback untouched.
two=MockEntities.new([original,SourceInstance.new(Object.new,source)])
multi_definition=OpenStruct.new(entities:two)
$model=MockModel.new(multi_definition)
Dir.mktmpdir do |dir|
  file=File.join(dir,'multi.skp')
  File.write(file,'mock')
  library.insert_component(file,nil)
end
UI.flush_one
raise '2.0.4 fallback was changed' unless $model.preview_definition.equal?(multi_definition)
raise 'Unexpected observer for old fallback' unless $model.active_entities.observers.empty?
puts 'PASS: original 2.0.4 fallback for multi-object files is unchanged'
