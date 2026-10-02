# frozen_string_literal: true
# Headless regression checks; do not pretend these substitute for testing in SketchUp.
require 'tmpdir'
require 'fileutils'
$LOADED_FEATURES << 'sketchup.rb'

module Sketchup
  class ComponentInstance; end
  class Group; end
  class ConstructionPoint; end
  class ConstructionLine; end
  def self.active_model; @model; end
  def self.active_model=(value); @model = value; end
end
module UI
  def self.start_timer(_seconds, _repeat, &block); block.call; end
end
class FakeLayer
  attr_reader :name
  def initialize(name); @name=name; @visible=true; end
  def visible?; @visible; end
  def visible=(val); @visible=val; end
end
class FakeLayers < Array
  def [](value)
    value.is_a?(String) ? find { |l| l.name==value } : super
  end
end
class FakeDefinition
  attr_accessor :name,:entities,:instances
  def initialize(name)
    @name=name
    @instances=[]
    @entities=FakeEntities.new(self)
  end
end
class FakeEntities < Array
  attr_reader :owner
  def initialize(owner); @owner=owner; end
  def add_instance(definition, transformation)
    inst=FakeInstance.new(definition, self, transformation)
    self << inst
    inst
  end
end
class FakeInstance < Sketchup::ComponentInstance
  @@next_id=100
  attr_accessor :name,:layer,:material,:hidden,:locked,:transformation,:parent
  attr_reader :definition,:persistent_id
  def initialize(definition, entities, transform='identity')
    @@next_id+=1
    @persistent_id=@@next_id
    @name=definition.name
    @definition=definition
    @parent=entities.owner
    @entities=entities
    @layer=nil
    @material=nil
    @hidden=false
    @locked=false
    @transformation=transform
    @valid=true
    definition.instances << self
  end
  def valid?; @valid; end
  def hidden?; @hidden; end
  def locked?; @locked; end
  def attribute_dictionaries; nil; end
  def erase!
    @entities.delete(self)
    @definition.instances.delete(self)
    @valid=false
  end
end
class FakeDefinitions
  attr_accessor :loaded
  def load(_path); @loaded; end
end
class FakeSelection < Array
  def add(entity); self << entity; end
end
class FakeModel
  attr_reader :entities,:layers,:selection,:definitions,:active_path
  attr_accessor :active_entities
  def initialize
    @entities=FakeEntities.new(self)
    @active_entities=@entities
    @layers=FakeLayers.new
    @selection=FakeSelection.new
    @definitions=FakeDefinitions.new
    @commits=0
  end
  def active_path=(path)
    @active_path=path
    @active_entities=path && !path.empty? ? path.last.definition.entities : @entities
  end
  def start_operation(*_args); end
  def commit_operation; @commits+=1; end
  def abort_operation; raise 'operation aborted'; end
  def active_view; self; end
  def zoom(_selection); end
  def invalidate; end
end
module Dvacet20
  module ComponentLibrary
    def self.library_root; @root; end
    def self.library_root=(val); @root=val; end
    def self.target=(val); @target=val; end
  end
end
require_relative 'RMToolsSuiteSourceV2058/twentytwenty_rm_managers/main'
manager=TwentyTwenty::RMManagers
def check(condition, message)
  raise "FAIL: #{message}" unless condition
  puts "PASS: #{message}"
end

model=FakeModel.new
Sketchup.active_model=model
%w[ZELEN SANITA VLASTNI Untagged].each { |name| model.layers << FakeLayer.new(name) }
plant=FakeDefinition.new('Plant')
top=model.entities.add_instance(plant,'at original coordinates')
top.layer=model.layers['ZELEN']
top.name='Plant001'
nested_def=FakeDefinition.new('Inner')
inside=plant.entities.add_instance(nested_def,'nested transform')
inside.layer=model.layers['SANITA']
second=model.entities.add_instance(plant,'another location')
second.layer=model.layers['ZELEN']
state=manager.tag_data
check(state[:folders].map { |f| f[:name] } == %w[ARCH INTERIER OKOLI POMOCNE DALSI], 'RM root groups plus DALSI, last and separated')
other=state[:folders].last
check(other[:tags].map { |t| t[:name] } == %w[Untagged VLASTNI], 'non-RM tags grouped only in DALSI')
check(state[:folders].find { |f| f[:name]=='OKOLI' }[:children].first[:tags].map { |t| t[:name] } == ['ZELEN'], 'official ZELEN remains inside OKOLI/VENEK')
nested=state[:objects]['SANITA']
check(nested.length==2 && nested.map { |row| row[:key] }.uniq.length==2, 'nested copies are distinguished by full instance path')
manager.select_entity(nested[1][:key],false)
check(model.selection==[inside] && model.active_path==[second], 'nested selection enters correct parent instance edit context')
manager.tag_action({'kind'=>'retag','key'=>top.persistent_id.to_s,'tag'=>'SANITA'})
check(top.layer.name=='SANITA', 'changing tag in inspector assigns target component')
manager.tag_action({'kind'=>'visibility','target'=>'folder','id'=>'rm:other','visible'=>false})
check(!model.layers['Untagged'].visible? && !model.layers['VLASTNI'].visible? && model.layers['ZELEN'].visible?, 'DALSI eye affects only non-RM layers')

Dir.mktmpdir do |root|
  path=File.join(root,'replacement.skp')
  File.write(path,'dummy test asset')
  Dvacet20::ComponentLibrary.library_root=root
  replacement_def=FakeDefinition.new('NewPlant')
  wrapper=FakeDefinition.new('wrapper')
  wrapper.entities.add_instance(replacement_def,'replacement source transform')
  model.definitions.loaded=wrapper
  Dvacet20::ComponentLibrary.target=replacement_def
  manager.instance_variable_set(:@replacement,{model:model,key:top.persistent_id.to_s,definition:plant,all:false})
  check(!Dvacet20::ComponentLibrary.respond_to?(:placement_roots), 'legacy Model Library lacks placement_roots')
  manager.replace_from_library(path)
  fresh=model.entities.find { |x| x.definition==replacement_def }
  check(!!fresh && !top.valid? && fresh.layer.name=='SANITA' && fresh.transformation=='at original coordinates', 'model-library replacement preserves transform and current tag')
  check(second.valid? && second.definition==plant, 'single replacement leaves other instances unchanged')
  check(!manager.replacement_pending?, 'replacement state is cleared on success')
end
puts 'PASS: Tag Manager headless regression tests complete'
