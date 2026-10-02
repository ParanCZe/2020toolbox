# frozen_string_literal: true
# Standalone mocks test region cropping independent of external model extents.
require 'tmpdir'
class Numeric
  def m; self * 1000.0; end
  def mm; self; end
end
Point = Struct.new(:x,:y,:z)
Vector = Struct.new(:x,:y,:z)
class CameraStub
  attr_reader :eye, :direction
  def initialize(x,y,z,dx=1,dy=0)
    @eye = Point.new(x,y,z)
    @direction = Vector.new(dx,dy,0)
  end
end
BoundsStub = Struct.new(:min,:max) do
  def valid?; true; end
end
class ModelStub
  attr_reader :pages, :bounds, :guid, :path, :active_view
  def initialize(cameras,bounds)
    @pages = cameras.map { |cam| Struct.new(:camera).new(cam) }
    @bounds = bounds
    @guid = 'test-floorplan'
    @path = ''
    @active_view = Struct.new(:camera).new(cameras.first)
  end
end
module Sketchup
  def self.platform; :platform_win; end
end
require_relative 'RMToolsSuiteSourceV2059/twentytwenty_rm_managers/floorplan'
plan = TwentyTwenty::RMManagers::Floorplan
def check(value,desc)
  raise "FAIL: #{desc}" unless value
  puts "PASS: #{desc}"
end
first=CameraStub.new(100_000.0,200_000.0,1800.0)
# A remote discarded component must not increase the minimap extent.
remote=BoundsStub.new(Point.new(-1_000_000.0,-1_000_000.0,-100_000.0),
  Point.new(8_000_000.0,8_000_000.0,200_000.0))
model=ModelStub.new([first],remote)
region=plan.camera_region(model)
check(region[2]-region[0]<60_000.0 && region[3]-region[1]<60_000.0,
  'single camera gives local floorplan despite kilometer-distant junk')
check(region[0]<first.eye.x && region[2]>first.eye.x+15_000.0,
  'single camera includes viewing direction and margin')
check(plan.cut_height(model)==2000.0,
  'remote negative Z objects do not set the section cut height')
Dir.mktmpdir do |cache|
  plan.define_singleton_method(:cache_dir) { |_model| cache }
  check(plan.needs_rebuild?(model),'missing plan triggers automatic build')
  File.binwrite(plan.raster_file(model),'fake-png-bytes')
  File.write(plan.meta_file(model),JSON.generate({'rect'=>{'origin'=>[0.5,0.5]},'region'=>region,
    'width'=>300,'height'=>200,'cut_z'=>plan.cut_height(model)}))
  check(!plan.needs_rebuild?(model),'valid cached region is reused')
  model.pages << Struct.new(:camera).new(CameraStub.new(300_000,200_000,1800.0))
  check(plan.needs_rebuild?(model),'a new camera beyond the cached region expands the map')
  expanded=plan.camera_region(model)
  check(expanded[2]-expanded[0]>region[2]-region[0] && expanded[0]<=region[0],
    'expansion keeps the first camera and includes the next')
end
puts 'PASS: camera-area floorplan tests complete'
