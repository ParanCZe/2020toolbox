# frozen_string_literal: true
require 'base64'
class Numeric
  def m; self*1000.0; end
  def mm; self.to_f; end
  def to_l; self.to_f; end
end
module Geom
  class Transformation
    def self.new; allocate; end
  end
  Point3d=Struct.new(:x,:y,:z) do
    def transform(_t); self; end
  end
  Vector3d=Struct.new(:x,:y,:z) do
    def transform(_t); self; end
  end
end
module Sketchup
  class Face; end
  class ComponentInstance; end
  class Group; end
end
class CameraStub
  attr_accessor :eye,:direction
  def initialize(x,y,z,dx=1.0,dy=0.0)
    @eye=Geom::Point3d.new(x,y,z)
    @direction=Geom::Vector3d.new(dx,dy,0.0)
  end
end
class FaceStub < Sketchup::Face
  attr_reader :normal,:outer_loop,:bounds
  def initialize(points, normal)
    @normal=Geom::Vector3d.new(*normal)
    @outer_loop=Struct.new(:vertices).new(points.map { |p| Struct.new(:position).new(Geom::Point3d.new(*p)) })
    xs,ys,zs=points.transpose
    @bounds=Struct.new(:min,:max).new(Geom::Point3d.new(xs.min,ys.min,zs.min),
      Geom::Point3d.new(xs.max,ys.max,zs.max))
  end
  def valid?; true; end
  def material; nil; end
  def back_material; nil; end
end
class ModelStub
  attr_reader :pages,:bounds,:entities,:active_view
  def initialize(cameras, bounds, entities)
    @pages=cameras.map { |cam| Struct.new(:camera).new(cam) }
    @active_view=Struct.new(:camera).new(cameras.first)
    @bounds=bounds
    @entities=entities
  end
end
def check(result, label)
  raise "FAIL #{label}" unless result
  puts "PASS #{label}"
end
require_relative 'RMToolsSuiteSourceV2060/twentytwenty_rm_managers/floorplan'
fp=TwentyTwenty::RMManagers::Floorplan
bounds=Struct.new(:min,:max) do
  def valid?; true; end
end.new(Geom::Point3d.new(-8_000_000,-8_000_000,-300_000),
        Geom::Point3d.new(8_000_000,8_000_000,300_000))
cam=CameraStub.new(100_000,200_000,1_800)
floor=FaceStub.new([[90_000,190_000,0],[125_000,190_000,0],[125_000,225_000,0],[90_000,225_000,0]],[0,0,1])
wall=FaceStub.new([[110_000,190_000,0],[110_000,190_000,4_000],[110_000,225_000,4_000],[110_000,225_000,0]],[1,0,0])
model=ModelStub.new([cam],bounds,[floor,wall])
region=fp.camera_region(model)
check(region[2]-region[0]<70_000 && region[3]-region[1]<70_000,'camera-scoped map ignores remote objects')
check(fp.cut_height(model)==2_000,'cut height ignores remote low-Z garbage')
original=model.active_view.camera
ok,err=fp.build(model)
check(ok && err.nil?,'read-only plan generated')
payload=fp.cached_data(model)
check(payload[:image].start_with?('data:image/svg+xml;base64,'),'map exports SVG without viewport screenshot')
svg=Base64.strict_decode64(payload[:image].split(',').last)
check(svg.include?('<polygon') && svg.include?('<path'),'map contains floor fills and true 2m intersections')
check(model.active_view.camera.equal?(original),'floorplan never changes camera')
check(!fp.needs_rebuild?(model),'unchanged camera uses cached map')
model.pages << Struct.new(:camera).new(CameraStub.new(400_000,200_000,1800))
check(fp.needs_rebuild?(model),'additional remote scene expands map')
puts 'PASS floorplan regression suite'
