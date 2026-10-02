# frozen_string_literal: true
# Regression suite for ARCH/OKNA migration in the v2.0.4.2 line.
$LOADED_FEATURES << 'sketchup.rb'
require 'json'

module Kernel
  def file_loaded?(_path); true; end
end

class FakeFolder
  attr_accessor :folder
  attr_reader :name, :folders, :layers
  def initialize(name, parent = nil)
    @name, @folder, @folders, @layers = name, parent, [], []
  end
  def add_folder(name)
    folder=FakeFolder.new(name,self)
    @folders << folder
    folder
  end
  def remove_folder(folder)
    raise 'Not an empty/direct child folder' unless @folders.include?(folder) && folder.layers.empty? && folder.folders.empty?
    @folders.delete(folder)
  end
  def folder=(destination)
    @folder.folders.delete(self) if @folder
    @folder=destination
    destination.folders << self if destination
  end
end

class FakeTag
  attr_reader :name
  attr_accessor :visible
  def initialize(name)
    @name=name
    @visible=true
  end
  def folder; @folder; end
  def folder=(new_folder)
    @folder.layers.delete(self) if @folder
    @folder=new_folder
    new_folder.layers << self if new_folder
  end
end

class FakeLayers < FakeFolder
  attr_reader :remove_calls
  def initialize
    super('MODEL')
    @tags={}
    @remove_calls=[]
  end
  def [](name); @tags[name]; end
  def add(name); @tags[name] ||= FakeTag.new(name); end
  def remove(tag, remove_geometry=false)
    raise 'Geometry must never be removed' if remove_geometry
    @remove_calls << [tag.name, remove_geometry]
    @tags.delete(tag.name)
    tag.folder=nil
    true
  end
end

class FakeEntity
  attr_accessor :layer
  attr_reader :material
  def initialize(tag, material)
    @layer=tag
    @material=material
  end
end
class FakeDefinition
  attr_reader :entities
  def initialize(entities); @entities=entities; end
end

class FakeModel
  attr_accessor :active_layer
  attr_reader :layers, :entities, :definitions
  def initialize
    @layers=FakeLayers.new
    @entities=[]
    @definitions=[]
    @active_layer=nil
    @transaction=false
    @committed=0
  end
  def start_operation(*)
    raise 'Already in operation' if @transaction
    @transaction=true
  end
  def commit_operation
    raise 'No transaction' unless @transaction
    @transaction=false
    @committed+=1
  end
  def abort_operation
    @transaction=false
  end
end

module Sketchup
  def self.active_model; $fake_model; end
end

load 'SketchUpPlugins/RMToolsSuiteSourceV2042/twentytwenty_rm_checker/main.rb'
prep=TwentyTwenty::RMPrep
def prep.push_state; end
def prep.notify(message, *); @notification=message; end
def prep.last_notification; @notification; end

raise 'New OKNA is not a leaf tag' unless prep::TAG_TREE['ARCH']['OKNA']==[]
raise 'Old RAM/SKLO are still configured' if prep::TAG_TREE['ARCH'].values.flatten.include?('RAM') || prep::TAG_TREE['ARCH'].values.flatten.include?('SKLO')

# Fresh project: create a lone OKNA tag, no old folder or old tags.
fresh=$fake_model=FakeModel.new
prep.create_tag_tree
fresh_arch=fresh.layers.folders.find{|f|f.name=='ARCH'}
raise 'Missing ARCH folder' unless fresh_arch
raise 'Fresh project did not get OKNA tag' unless fresh.layers['OKNA']&.folder.equal?(fresh_arch)
raise 'Fresh project incorrectly creates OKNA folder' if fresh_arch.folders.any?{|f|f.name=='OKNA'}
raise 'Fresh project creates RAM/SKLO tags' if fresh.layers['RAM'] || fresh.layers['SKLO']
puts 'PASS: new models have direct ARCH/OKNA and never create old RAM/SKLO'

# Existing project: preserve nested geometry, materials, custom tags and folders.
m=$fake_model=FakeModel.new
arch=m.layers.add_folder('ARCH')
windows=arch.add_folder('OKNA')
ram=m.layers.add('RAM')
sklo=m.layers.add('SKLO')
ram.folder=windows
sklo.folder=windows
custom=m.layers.add('STINENI')
custom.folder=windows
custom_child=windows.add_folder('Vlastni_podslozka')
original_chrome=Object.new
original_glass=Object.new
original_group=FakeEntity.new(ram,original_chrome)
nested_face=FakeEntity.new(sklo,original_glass)
more_nested=FakeEntity.new(ram,original_chrome)
m.entities << original_group
m.definitions << FakeDefinition.new([nested_face,more_nested])
m.active_layer=sklo
prep.update_tag_tree
target=m.layers['OKNA']
raise 'Merged OKNA tag is missing' unless target
raise 'Merged OKNA tag is not in ARCH' unless target.folder.equal?(arch)
raise 'Legacy OKNA folder survived migration' if arch.folders.any?{|f|f.name=='OKNA'}
raise 'RAM/SKLO still in model' if m.layers['RAM'] || m.layers['SKLO']
raise 'Original root entity tag not migrated' unless original_group.layer.equal?(target)
raise 'Nested definition tag not migrated' unless nested_face.layer.equal?(target) && more_nested.layer.equal?(target)
raise 'Original materials were modified' unless original_group.material.equal?(original_chrome) && nested_face.material.equal?(original_glass)
raise 'Current active layer still refers to removed tag' unless m.active_layer.equal?(target)
raise 'Custom tag from old folder was lost' unless custom.folder.equal?(arch) && m.layers['STINENI'].equal?(custom)
raise 'Custom folder from old folder was lost' unless custom_child.folder.equal?(arch) && arch.folders.include?(custom_child)
raise 'Did not delete exactly two old tags' unless m.layers.remove_calls.map(&:first).sort==%w[RAM SKLO]
raise 'Unsafe removal API was used' unless m.layers.remove_calls.all?{|_,remove|remove==false}
raise 'Status does not mention reassigned entities' unless prep.last_notification.include?('3 objektů převedeno na OKNA')
puts 'PASS: RAM/SKLO geometry including nested definitions re-tagged to OKNA without material changes'
puts 'PASS: old tags/folder removed; custom user content and active layer preserved'

# Repeating the update must not recreate obsolete tags or duplicate folders.
prep.update_tag_tree
raise 'Repeating update recreated legacy tags' if m.layers['RAM'] || m.layers['SKLO']
raise 'Repeating update recreated old OKNA folder' if arch.folders.any?{|f|f.name=='OKNA'}
raise 'Repeating update replaced target tag' unless m.layers['OKNA'].equal?(target)
raise 'Repeated tag deletions' unless m.layers.remove_calls.size==2
puts 'PASS: repeated Aktualizovat RM tagy is safe and idempotent'
