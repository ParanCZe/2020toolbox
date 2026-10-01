# frozen_string_literal: true
# Regression test for migration of existing SketchUp tag objects.
$LOADED_FEATURES << 'sketchup.rb'
require 'json'

module Kernel
  def file_loaded?(_path)
    true
  end
end

class FakeFolder
  attr_reader :name, :folders, :layers
  def initialize(name)
    @name = name
    @folders = []
    @layers = []
  end
  def add_folder(name)
    folder = FakeFolder.new(name)
    @folders << folder
    folder
  end
  def remove_folder(folder)
    raise 'Trying to remove nonempty folder' unless folder.layers.empty? && folder.folders.empty?
    raise 'Unknown folder' unless @folders.delete(folder)
  end
end

class FakeTag
  attr_reader :name
  attr_accessor :assigned_entities
  def initialize(name)
    @name = name
    @assigned_entities = []
  end
  def folder
    @folder
  end
  def folder=(new_folder)
    @folder.layers.delete(self) if @folder
    @folder = new_folder
    new_folder.layers << self if new_folder
  end
end

class FakeLayers < FakeFolder
  def initialize
    super('MODEL')
    @by_name = {}
  end
  def [](name)
    @by_name[name]
  end
  def add(name)
    @by_name[name] = FakeTag.new(name)
  end
end

class FakeModel
  attr_reader :layers
  def initialize
    @layers = FakeLayers.new
    @operation_open = false
  end
  def start_operation(*)
    raise 'Double transaction' if @operation_open
    @operation_open = true
  end
  def commit_operation
    raise 'No transaction' unless @operation_open
    @operation_open = false
  end
  def abort_operation
    @operation_open = false
  end
end

module Sketchup
  def self.active_model
    $fake_model
  end
end

load 'SketchUpPlugins/RMToolsSuiteSourceV204/twentytwenty_rm_checker/main.rb'
prep = TwentyTwenty::RMPrep
def prep.push_state; end
def prep.notify(message, *); @last_notification=message; end

model = $fake_model = FakeModel.new
layers = model.layers
interior = layers.add_folder('INTERIER')
legacy = interior.add_folder('PRVKY')
custom = layers.add('CUSTOM')
tags = {}
%w[SANITA NABYTEK SPOTREBICE DVERE DOPLNKY OSVETLENI].each do |name|
  tags[name] = layers.add(name)
  tags[name].folder = legacy
  tags[name].assigned_entities << "instance-#{name}"
end
custom.folder = legacy
custom.assigned_entities << 'custom-instance'
surfaces = interior.add_folder('POVRCHY')
floor = layers.add('PODLAHA')
floor.folder = surfaces
floor.assigned_entities << 'floor-instance'
originals = tags.merge('CUSTOM' => custom, 'PODLAHA' => floor)

prep.update_tag_tree
raise 'Legacy PRVKY folder was not removed' if interior.folders.any? { |f| f.name == 'PRVKY' }
raise 'Legacy POVRCHY folder was not removed' if interior.folders.any? { |f| f.name == 'POVRCHY' }
raise 'New PRVKY folder was created' if interior.folders.any? { |f| f.name == 'PRVKY' }
raise 'Wrong ARCH floor destination' unless floor.folder == layers.folders.find { |f| f.name == 'ARCH' }
expected = %w[SANITA NABYTEK SPOTREBICE DVERE DOPLNKY OSVETLENI] + ['CUSTOM']
expected.each do |name|
  raise "Misplaced tag #{name}" unless layers[name].folder == interior
  raise "Replaced tag #{name}" unless layers[name].equal?(originals[name])
  raise "Lost assigned entities for #{name}" if layers[name].assigned_entities.empty?
end
first_folder_count = layers.folders.length
prep.update_tag_tree
raise 'Migration is not repeatable' unless layers.folders.length == first_folder_count
raise 'Repeated update created PRVKY' if interior.folders.any? { |f| f.name == 'PRVKY' }

# Custom nested subfolders are retained rather than destroyed.
special = interior.add_folder('PRVKY')
special.add_folder('USER_SUBFOLDER')
prep.update_tag_tree
raise 'Nested user folder was deleted' unless interior.folders.include?(special)

puts 'PASS: flatten INTERIER, move custom tags, preserve assignments, clean empty folders'
puts 'PASS: updater is repeatable and custom nested folders remain safe'
