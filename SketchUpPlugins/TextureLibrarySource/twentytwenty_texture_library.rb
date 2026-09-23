# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module TwentyTwenty
  module TextureLibrary
    EXTENSION ||= SketchupExtension.new(
      '20-20 Texture Library',
      'twentytwenty_texture_library/main'
    )
    EXTENSION.description = 'Texture library with cleaned SIKO filters, EGGER decor textures, per-face positioning, RAL and NCS.'
    EXTENSION.version = '0.1.7'
    EXTENSION.creator = '20-20'
    Sketchup.register_extension(EXTENSION, true)
  end
end
