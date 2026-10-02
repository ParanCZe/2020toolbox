# frozen_string_literal: true
# Meye REST catalogue, explicit PNG download and anchored transparent billboards.
$LOADED_FEATURES << 'sketchup.rb'
require 'tmpdir'
require 'json'
require 'zlib'
require 'ostruct'
module UI
  @timers=[]
  attr_reader :timers
  def self.start_timer(delay,recur,&block)
    @timers << [delay,recur,block]
    @timers.size
  end
  def self.stop_timer(_id);end
  def self.messagebox(message);raise "Unexpected SketchUp popup: #{message}";end
  class HtmlDialog
    STYLE_DIALOG=1
    attr_reader :scripts,:actions,:url
    def initialize(**opts);@scripts=[];@actions={};end
    def set_file(path);@file=path;end
    def add_action_callback(name,&block);@actions[name]=block;end
    def set_on_closed(&block);@on_closed=block;end
    def show;@shown=true;end
    def execute_script(script);@scripts << script;end
  end
end
module Geom
  class Point3d
    attr_reader :x,:y,:z
    def initialize(x,y,z);@x,@y,@z=x,y,z;end
    def to_a;[x,y,z];end
  end
end
class FakeFace
  attr_accessor :material,:back_material
  attr_reader :uv,:points
  def initialize(points);@points=points;@uv=[];end
  def position_material(mat,uv,side);@uv<<[mat,uv,side];true;end
end
class FakeBehavior
  attr_accessor :always_face_camera
end
class FakeDefinition
  attr_reader :entities,:behavior,:attributes
  def initialize
    @entities=self
    @behavior=FakeBehavior.new
    @attributes={}
  end
  def add_face(*points);@face=FakeFace.new(points);end
  def face;@face;end
  def set_attribute(dict,key,value);@attributes[[dict,key]]=value;end
end
class FakeDefinitions
  attr_reader :added
  def initialize;@added=[];end
  def add(name);@added<<FakeDefinition.new;end
end
class FakeMaterials < Hash
  def add(name)
    material=OpenStruct.new(name:name)
    self[name]=material
  end
end
class FakeModel
  attr_reader :definitions,:materials,:placed,:operations
  def initialize;@definitions=FakeDefinitions.new;@materials=FakeMaterials.new;@operations=[];end
  def start_operation(name,_transparent);@operations<<:start;end
  def commit_operation;@operations<<:commit;end
  def abort_operation;@operations<<:abort;end
  def place_component(defn,copy);@placed=[defn,copy];end
end
module Sketchup
  def self.active_model;$model;end
  def self.set_status_text(text);$status=text;end
end
require_relative '../MeyeCutoutsSourceV010/twentytwenty_meye_cutouts/main'
lib=TwentyTwenty::MeyeCutouts

# Canonical WP v2 format with the EXACT public Meye domain; no high-res data.
taxonomy=[
  {'id'=>3,'name'=>'Summer','slug'=>'summer'},
  {'id'=>8,'name'=>'Winter','slug'=>'winter'},
  {'id'=>36,'name'=>'Acer','slug'=>'acer'},
  {'id'=>56,'name'=>'Syringa','slug'=>'syringa'}
]
full='https://meye.dk/wp-content/uploads/2024/01/meye_acer-platanoides_s14850.png'
thumb='https://meye.dk/wp-content/uploads/2024/01/meye_acer-platanoides_s14850-203x300.png'
record={
 'id'=>8647,'title'=>{'rendered'=>'Acer platanoides'},
 'link'=>'https://meye.dk/project/acer-platanoides/',
 'project_category'=>[36,3],
 '_embedded'=>{'wp:featuredmedia'=>[{
   'source_url'=>full,'media_details'=>{'sizes'=>{'medium'=>{'source_url'=>thumb}}}
 }]}
}
network=[]
lib.define_singleton_method(:request_json) do |path,*_|
  network<<path
  path.start_with?('/project_category') ? taxonomy : [record]
end
result=lib.remote_catalog({'season'=>'summer','species'=>'acer','page'=>1})
raise 'Catalogue must contain exact Meye item' unless result['items'].length==1
item=result['items'].first
raise 'Wrong image preview: must not use full PNG' unless item['thumb']==thumb && item['full']==full
raise 'Filter category wrong' unless network.last.include?('project_category=36')
raise 'Filter season wrong' unless item['season']=='summer'
raise 'Missing species names' unless result['species'].any?{|x|x['slug']=='syringa'}
raise 'Wrong season exclusion' unless lib.remote_catalog({'season'=>'winter','species'=>'acer'})['items'].empty?
raise 'Insecure external image accepted' if lib.meye_url?('https://evil.example.com/wp-content/uploads/2024/01/tree.png',png:true)
raise 'Full PNG downloaded while catalog was browsed' if network.any?{|x|x.end_with?('.png')}
puts 'PASS: public WordPress Meye metadata/thumbnail catalog, season+genus filters, no PNG downloads'

# Tiny RGBA8 PNG: 5px x 5px, opaque crown and lowest stem at pixel 2.
def create_rgba_png
  rows=[
    [0,0,255,0,0],
    [0,255,255,255,0],
    [255,255,255,255,255],
    [0,0,255,0,0],
    [0,0,255,0,0]
  ]
  scan=rows.map do |alphas|
    ([0]+alphas.flat_map{|a|[32,150,33,a]}).pack('C*')
  end.join
  chunk=lambda do |kind,data|
    [data.bytesize].pack('N')+kind+data+
      [Zlib.crc32(kind+data)].pack('N')
  end
  signature="\x89PNG\r\n\x1a\n".b
  ihdr=[5,5,8,6,0,0,0].pack('NNC5')
  signature+chunk.call('IHDR',ihdr)+chunk.call('IDAT',Zlib::Deflate.deflate(scan))+chunk.call('IEND','')
end
original=create_rgba_png
Dir.mktmpdir('2020-meye-test') do |dir|
  lib.define_singleton_method(:cache_dir){dir}
  requests=[]
  lib.define_singleton_method(:get_request) do |url,max,*|
    requests<<url
    url==item['page'] ?
      '<article class="project"><a class="et_pb_lightbox_image" href="' + full + '">Download</a></article>' :
      (url==full ? original : raise("Unexpected HTTP request: #{url}"))
  end
  path=lib.download_full_png(item)
  raise 'Expected exactly one official Meye PNG request on demand' unless requests==[item['page'],full]
  again=lib.download_full_png(item)
  raise 'PNG cache was not used' unless again==path && requests==[item['page'],full,item['page']]
  bounds=lib.png_opaque_bounds(path)
  raise 'Alpha bounds did not find real lower stem' unless bounds[:alpha_aligned] && bounds[:base_x]==2.0 && bounds[:bottom_y]==4
  raise 'Alpha top missing' unless bounds[:top_y]==0
  $model=FakeModel.new
  result=lib.place_png(item,5.0,path,bounds)
  raise 'Placement did not succeed' unless result
  defn=$model.placed.first
  raise 'Cutout should be camera-facing' unless defn.behavior.always_face_camera
  raise 'Two-sided transparent PNG texture missing' unless defn.face.material.texture==path && defn.face.back_material.texture==path
  raise 'UV mapping needs three 3D-UV pairs per side' unless defn.face.uv.length==2 && defn.face.uv.all?{|x|x[1].length==6}
  raise 'No insertion operation' unless $model.operations==[:start,:commit]
  raise 'Model must be placed by native cursor tool, not immediately' unless $model.placed[1]==false
  raise 'Wrong source attribution' unless defn.attributes[['20-20 MEYE','Credit']].include?('Mikkel Eye')
  scale=5.0*39.3700787402/5
  pts=defn.face.points
  raise 'Cutout bottom is not z=0' unless pts[0].z.abs<0.001
  raise 'Cutout x=0 should be aligned to visible trunk stem' unless (pts[0].x+2*scale).abs<0.001 && (pts[1].x-3*scale).abs<0.001
  raise 'Invalid height scale' unless (pts[2].z-5*scale).abs<0.001
  puts 'PASS: full PNG fetched only on plus, reused from private local cache'
  puts 'PASS: PNG alpha finds actual bottom stem and offsets cutout about exact local origin'
  puts 'PASS: 5m transparent two-sided camera-facing component uses native SketchUp cursor placement'
end
