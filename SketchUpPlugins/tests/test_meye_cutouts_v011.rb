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
  def get_attribute(dict,key);@attributes[[dict,key]];end
end
class FakeDefinitions
  attr_reader :added
  def initialize;@added=[];@names={};end
  def add(name);defn=FakeDefinition.new;@added << defn;@names[name]=defn;defn;end
  def [](name);@names[name];end
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
require_relative '../MeyeCutoutsSourceV011/twentytwenty_meye_cutouts/main'
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
 'id'=>8647,'featured_media'=>8646,'title'=>{'rendered'=>'Acer platanoides'},
 'link'=>'https://meye.dk/project/acer-platanoides/',
 'project_category'=>[36,3],
 '_embedded'=>{'wp:featuredmedia'=>[{
   'source_url'=>full,'media_details'=>{'sizes'=>{'medium'=>{'source_url'=>thumb}}}
 }]}
}
metadata_home=Dir.mktmpdir('meye-metadata')
lib.define_singleton_method(:cache_dir){metadata_home}
network=[]
lib.define_singleton_method(:request_json) do |path,*_|
  network << path
  case path
  when /\A\/project_category/ then taxonomy
  when /\A\/media\?/ then [{
    'id'=>8646,'source_url'=>full,
    'media_details'=>{'sizes'=>{'medium'=>{'source_url'=>thumb}}}
  }]
  when /\A\/project\?/ then [record]
  else raise "Unexpected metadata request: #{path}"
  end
end
result=lib.remote_catalog({'season'=>'summer','species'=>'acer','page'=>1})
raise 'Catalogue must contain exact Meye item' unless result['items'].length==1
item=result['items'].first
raise 'Wrong image preview: must not use full PNG' unless item['thumb']==thumb && item['full']==full
raise 'Filter category wrong' unless network.any?{|x|x.include?('project_category=36')}
raise 'Lean two-stage API absent' unless network.any?{|x|x.include?('_fields=id') && x.start_with?('/project?')} && network.any?{|x|x.start_with?('/media?')}
raise 'Old bloated embedded endpoint used' if network.any?{|x|x.include?('_embed=1')}
raise 'Filter season wrong' unless item['season']=='summer'
raise 'Missing species names' unless result['species'].any?{|x|x['slug']=='syringa'}
raise 'Wrong season exclusion' unless lib.remote_catalog({'season'=>'winter','species'=>'acer'})['items'].empty?
raise 'Insecure external image accepted' if lib.meye_url?('https://evil.example.com/wp-content/uploads/2024/01/tree.png',png:true)
raise 'Full PNG downloaded while catalog was browsed' if network.any?{|x|x.end_with?('.png')}
requests_before_cache=network.length
cached=lib.remote_catalog({'season'=>'summer','species'=>'acer','page'=>1})
raise 'Second catalog call should be disk-cached' unless cached['cached'] && network.length==requests_before_cache
lib.instance_variable_set(:@taxonomy,nil)
taxonomy_calls=network.length
lib.taxonomy
raise 'Taxonomy refetched despite 24h disk cache' unless network.length==taxonomy_calls
fresh=lib.remote_catalog({'season'=>'summer','species'=>'acer','page'=>1,'force'=>true})
raise 'Refresh did not bypass cache' unless !fresh['cached'] && network.length>requests_before_cache
raise 'Wrong first-page thumbnail count' unless lib::PAGE_SIZE==12
puts 'PASS: lean public metadata and native un-cropped thumbnails; catalog + taxonomy disk cache'
puts 'PASS: manual force refresh bypasses cache without downloading original PNG'

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
    url==full ? original : raise("Unexpected HTTP request: #{url}")
  end
  path=lib.download_full_png(item)
  raise 'Expected exactly one official Meye PNG request on demand' unless requests==[full]
  again=lib.download_full_png(item)
  raise 'PNG cache was not used' unless again==path && requests==[full]
  bounds=lib.cached_png_opaque_bounds(path)
  cached_sidecar=lib.cached_png_opaque_bounds(path)
  raise 'Alpha bounds were not persisted beside the downloaded PNG' unless File.file?(path+'.bounds.json')
  raise 'Cached PNG alpha origin changed' unless cached_sidecar==bounds
  lib.define_singleton_method(:png_opaque_bounds) do |_file|
    raise 'PNG alpha scanning repeated despite valid cached sidecar'
  end
  raise 'Cached bounds are not actually used' unless lib.cached_png_opaque_bounds(path)==bounds
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
  scale=5.0*39.3700787402/4
  pts=defn.face.points
  raise 'Cutout bottom is not z=0' unless pts[0].z.abs<0.001
  raise 'Cutout x=0 should be aligned to visible trunk stem' unless (pts[0].x+2*scale).abs<0.001 && (pts[1].x-3*scale).abs<0.001
  raise 'Invalid height scale' unless (pts[2].z-5.0*39.3700787402).abs<0.001
  puts 'PASS: direct official PNG fetched ONLY on plus, without extra HTML page request'
  puts 'PASS: repeated PNG imports use local image+alpha-bounds cache'
  puts 'PASS: PNG alpha finds actual bottom stem and offsets cutout about exact local origin'
  puts 'PASS: 5m transparent two-sided camera-facing component uses native SketchUp cursor placement'
  definition_count=$model.definitions.added.size
  previous=$model.placed.first
  lib.place_png(item,5.0,path,bounds)
  raise 'Repeat cutout created a redundant component' unless $model.definitions.added.size==definition_count
  raise 'Repeat cutout used a new definition' unless $model.placed.first.equal?(previous)
  raise 'Repeat cutout should skip texture and geometry Undo operation' unless $model.operations==[:start,:commit]
  puts 'PASS: second insertion of same tree+height reuses existing native SketchUp component'

end


# PNG alpha scanline reconstruction is EXACT for each PNG filter type 0..4.
def filter_png(filter)
  original_rows=[[0,0,255,0,0],[0,255,255,255,0],[255,255,255,255,255],[0,0,255,0,0],[0,0,255,0,0]]
  prev=Array.new(20,0)
  scan=+''
  original_rows.each do |alphas|
    row=alphas.flat_map{|a|[32,150,33,a]}
    encoded=row.each_index.map do |i|
      left=i>=4 ? row[i-4] : 0
      up=prev[i]
      ul=i>=4 ? prev[i-4] : 0
      predictor=case filter
                when 0 then 0
                when 1 then left
                when 2 then up
                when 3 then (left+up)/2
                when 4
                  p=left+up-ul
                  da,db,dc=(p-left).abs,(p-up).abs,(p-ul).abs
                  da<=db && da<=dc ? left : (db<=dc ? up : ul)
                end
      (row[i]-predictor)&255
    end
    scan<<([filter]+encoded).pack('C*')
    prev=row
  end
  make=lambda{|kind,data|[data.bytesize].pack('N')+kind+data+[Zlib.crc32(kind+data)].pack('N')}
  "\x89PNG\r\n\x1a\n".b+
  make.call('IHDR',[5,5,8,6,0,0,0].pack('NNC5'))+
  make.call('IDAT',Zlib::Deflate.deflate(scan))+
  make.call('IEND','')
end
# Restore method from source after deliberately replacing it to test caching.
lib.singleton_class.send(:remove_method,:png_opaque_bounds)
Dir.mktmpdir('2020-meye-filters') do |dir|
  0.upto(4) do |filter|
    path=File.join(dir,"filter#{filter}.png")
    File.binwrite(path,filter_png(filter))
    b=lib.png_opaque_bounds(path)
    raise "Broken filter #{filter}" unless b[:top_y]==0 && b[:bottom_y]==4 &&
                                        b[:base_x]==2.0 && b[:alpha_aligned]
  end
end
puts 'PASS: alpha-only decoder preserves exact stem position for ALL five PNG filters'
