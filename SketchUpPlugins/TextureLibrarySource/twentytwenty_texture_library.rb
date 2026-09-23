# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module TwentyTwenty
  module TextureLibrary
    EXTENSION ||= SketchupExtension.new(
      '20-20 Texture Library',
      'twentytwenty_texture_library/main'
    )
    EXTENSION.description = 'Texture library with SIKO, EGGER, Poly Haven CC0 and direct 1200 px SIKO textures for RAKO Rave.'
    EXTENSION.version = '0.2.4'
    EXTENSION.creator = '20-20'
    Sketchup.register_extension(EXTENSION, true)
  end
end
