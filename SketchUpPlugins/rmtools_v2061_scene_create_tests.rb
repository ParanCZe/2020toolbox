# frozen_string_literal: true
# Regression: create scene from Scene Manager without touching active camera.
$LOADED_FEATURES << 'sketchup.rb'
PAGE_USE_CAMERA=1
PAGE_USE_RENDERING_OPTIONS=2
PAGE_USE_SHADOWINFO=4
PAGE_USE_LAYER_VISIBILITY=32
class Numeric
  def m; self*1000.0; end
  def mm; self; end
  def to_l; self; end
end
module Sketchup
  class Camera
    attr_accessor :fov,:aspect_ratio,:perspective
    attr_reader :eye,:target,:up
    def initialize(eye,target,up)
      @eye,@target,@up=eye,target,up
      @perspective=true;@fov=60.0;@aspect_ratio=16.0/9
    end
    def perspective?;@perspective;end
    def set(eye,target,up);@eye,@target,@up=eye,target,up;end
  end
  class ComponentInstance; end
  class Group; end
  class Face; end
  def self.active_model; @model; end
  def self.active_model=(model); @model=model; end
  def self.platform; :platform_win; end
end
module UI
  def self.start_timer(_seconds, _repeat, &_block); true; end
end
Eye=Struct.new(:x,:y,:z)
Direction=Struct.new(:x,:y,:z)
class Cam
  attr_accessor :fov,:aspect_ratio,:perspective
  attr_reader :eye,:target,:up
  def initialize(x=0,y=0)
    @fov=60.0;@aspect_ratio=16.0/9;@perspective=true
    @eye=Eye.new(x,y,1800);@target=Eye.new(x+1000,y,1800);@up=Direction.new(0,0,1)
    @direction=Direction.new(1,0,0)
  end
  def direction; @direction; end
  def perspective?;@perspective;end
  def is_2d?;false;end
  def set(eye,target,up);@eye,@target,@up=eye,target,up;end
end
class Page
  attr_accessor :name,:use_camera
  attr_reader :camera,:updates
  def initialize(name,cam,pages=nil,view=nil)
    @name=name;@camera=Cam.new
    @camera.set(cam.eye,cam.target,cam.up)
    @camera.fov=cam.fov;@camera.aspect_ratio=cam.aspect_ratio
    @pages=pages;@view=view
    @updates=[];@attrs={}
  end
  def update(flags)
    @updates << flags
    # Reproduce the real-world failure mode: updating a non-selected page can
    # cause the currently selected page to absorb the CURRENT viewport camera.
    if @pages && @view && @pages.selected_page && !@pages.selected_page.equal?(self)
      victim=@pages.selected_page.camera
      source=@view.camera
      victim.set(source.eye,source.target,source.up)
      victim.fov=source.fov
      victim.aspect_ratio=source.aspect_ratio
    end
    true
  end
  def set_attribute(group,name,val); @attrs[[group,name]]=val;end
  def get_attribute(group,name,default=nil);@attrs.fetch([group,name],default);end
end
class TestView
  attr_accessor :camera
  def initialize(camera);@camera=camera;end
  def invalidate;true;end
end
class Pages < Array
  attr_reader :selected_page
  def initialize(view);super();@view=view;end
  def selected_page=(page)
    @selected_page=page
    return unless page
    src=page.camera
    cam=Cam.new
    cam.set(src.eye,src.target,src.up)
    cam.fov=src.fov;cam.aspect_ratio=src.aspect_ratio;cam.perspective=src.perspective?
    @view.camera=cam
  end
  def add(name)
    p=Page.new(name,@view.camera,self,@view)
    self << p
    p
  end
end
class Model
  attr_reader :pages,:active_view,:bounds
  def initialize
    @active_view=TestView.new(Cam.new)
    @pages=Pages.new(@active_view)
    @bounds=Struct.new(:valid?).new(false)
  end
  def start_operation(*_);end
  def commit_operation;end
  def abort_operation;raise "unexpected abort";end
  def path; ''; end
  def guid; 'scene-creation-regression'; end
  def options; {'PageOptions'=>{'ShowTransition'=>true}}; end
end
Sketchup.active_model=Model.new
require_relative 'RMToolsSuiteSourceV2061/twentytwenty_rm_managers/main'
mgr=TwentyTwenty::RMManagers
model=Sketchup.active_model
before_eye=model.active_view.camera.eye
mgr.scene_action({'kind'=>'create','name'=>'02 - EXTERIER - HLAVNI'})
raise 'Scene missing!' unless model.pages.length==1
raise 'Scene name wrong!' unless model.pages.first.name=='02 - EXTERIER - HLAVNI'
raise 'Viewport moved during first scene creation!' unless model.active_view.camera.eye==before_eye
raise 'Scene update flags not used!' unless model.pages.first.updates==[39]
first_eye=model.pages.first.camera.eye
model.active_view.camera=Cam.new(5000,7000)
mgr.scene_action({'kind'=>'create','name'=>'03 - EXTERIER - DETAIL'})
raise 'Second scene missing!' unless model.pages.length==2
raise 'First scene camera was overwritten by second scene creation!' unless model.pages.first.camera.eye==first_eye
raise 'Second scene did not keep current viewport!' unless model.pages.last.camera.eye.x==5000 && model.pages.last.camera.eye.y==7000
raise 'New scene was not selected!' unless model.pages.selected_page.equal?(model.pages.last)
raise 'Consecutive scenes share camera object!' if model.pages.first.camera.equal?(model.pages.last.camera)
puts 'PASS consecutive scene creation preserves independent camera snapshots'
puts 'PASS new scene is actually created with camera/shadow/style/tag flags'
puts 'PASS opening and creating does not change active camera'
