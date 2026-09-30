# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module TwentyTwenty
  module LiveMirror
    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new('20-20 Live Mirror', 'twentytwenty_live_mirror/main_v0418')
      extension.description = 'Projected planar mirror simulation using a private WebGL renderer and a native SketchUp face texture. v0.4.14 adds a full icon toolbar, Czech hover help, a larger adjustable scene budget and safe group/component culling behind the mirror plane. It never moves the SketchUp camera or duplicates model geometry.'
      extension.version = '0.4.18'
      extension.creator = '20-20 ARCHITEKTI'
      extension.copyright = '2026 20-20 ARCHITEKTI'
      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
