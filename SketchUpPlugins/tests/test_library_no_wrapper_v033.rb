# Tests the exact insertion path without requiring SketchUp on CI.
$LOADED_FEATURES << 'sketchup.rb'
require 'ostruct'
require 'tmpdir'

module Kernel
  def file_loaded?(_)
    true
  end
end

module UI
  def self.messagebox(message)
    $last_error = message
  end
  def self.start_timer(seconds, _repeat, &block)
    block.call if seconds == 0
  end
end

module Geom
  class Transformation
    attr_reader :components
    def initialize(components = [])
      @components = components
    end
    def to_a
      @components
    end
    def *(other)
      self.class.new(@components + other.to_a)
    end
  end
end

module Sketchup
  class EntitiesObserver; end
  class ComponentInstance; end
  class ConstructionPoint; end
  class ConstructionLine; end

  def self.active_model
    $fake_model
  end

  def self.set_status_text(_message); end
end

load 'SketchUpPlugins/ComponentLibrarySourceV033/dvacet20_component_library/main.rb'
library = Dvacet20::ComponentLibrary
target = Object.new

class RootInstance < Sketchup::ComponentInstance
  attr_reader :definition, :transformation
  def initialize(definition)
    @definition = definition
    @transformation = Geom::Transformation.new([42])
  end
  def layer
    OpenStruct.new(name: 'SANITA')
  end
  def name
    'WC_LIB'
  end
  def material
    nil
  end
  def hidden?
    false
  end
  def casts_shadows?
    true
  end
  def receives_shadows?
    true
  end
  def locked?
    false
  end
  def attribute_dictionaries
    nil
  end
end

class MockEntities
  attr_reader :observers
  attr_accessor :items
  def initialize
    @observers = []
    @items = []
  end
  def to_a
    @items
  end
  def add_observer(observer)
    @observers << observer
  end
  def remove_observer(observer)
    @observers.delete(observer)
  end
  def notify(instance)
    @observers.dup.each { |observer| observer.onElementAdded(self, instance) }
  end
end

class PlacedInstance < Sketchup::ComponentInstance
  attr_accessor :transformation, :name, :layer, :material, :hidden,
                :casts_shadows, :receives_shadows, :locked
  attr_reader :definition
  def initialize(definition, model)
    @definition, @model = definition, model
    @transformation = Geom::Transformation.new([9])
  end
  def model
    @model
  end
  def valid?
    true
  end
  def set_attribute(*); end
end

class MockLayers < Hash
  def add(name)
    self[name] = OpenStruct.new(name: name)
  end
end

class MockModel
  attr_reader :active_entities, :layers, :materials, :placed_definition, :placed_instance, :removed_definitions
  def initialize(wrapper)
    @wrapper = wrapper
    @active_entities = MockEntities.new
    @layers = MockLayers.new
    @materials = {}
    @removed_definitions = []
  end
  def definitions
    self
  end
  def load(_path)
    @wrapper
  end
  def remove(definition)
    @removed_definitions << definition
  end
  def place_component(definition, _repeat)
    @placed_definition = definition
    @placed_instance = PlacedInstance.new(definition, self)
    @active_entities.notify(@placed_instance)
  end
end

root = RootInstance.new(target)
entities = MockEntities.new
entities.items = [root, Sketchup::ConstructionPoint.new]
wrapper = OpenStruct.new(entities: entities, instances: [])
$fake_model = MockModel.new(wrapper)

Dir.mktmpdir do |dir|
  file = File.join(dir, 'test.skp')
  File.write(file, 'mock')
  library.insert_component(file, nil)
end

raise 'BUG: inserted wrapper instead of root component' unless $fake_model.placed_definition.equal?(target)
raise 'Missing instance tag' unless $fake_model.placed_instance.layer.name == 'SANITA'
raise 'Missing source component name' unless $fake_model.placed_instance.name == 'WC_LIB'
raise 'Wrong original source transformation' unless $fake_model.placed_instance.transformation.to_a == [9, 42]
raise 'Observer leaked' unless $fake_model.active_entities.observers.empty?

raise 'Temporary wrapper definition was not cleaned up' unless $fake_model.removed_definitions.include?(wrapper)

# Regression: a malformed file or extra visible geometry must NEVER be placed
# inside a new wrapping component; it should be rejected with an explanation.
Dir.mktmpdir do |dir|
  file = File.join(dir, 'problem.skp')
  File.write(file, 'mock')
  cases = [
    [root, Object.new],
    [root, RootInstance.new(target)],
    [Object.new]
  ]
  cases.each do |root_objects|
    entities.items = root_objects
    $fake_model = MockModel.new(wrapper)
    $last_error = nil
    library.insert_component(file, nil)
    raise 'BUG: importer placed wrapper' unless $fake_model.placed_definition.nil?
    raise 'Missing actionable import error' unless $last_error && $last_error.include?('obal')
  end
end

puts 'PASS: inserted original component directly, preserved metadata and original transformation'
puts 'PASS: cleaned unused file wrapper after placement'
puts 'PASS: additional visible entities, multiple components, and raw geometry never create a wrapper'
