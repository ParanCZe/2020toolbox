# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module TwentyTwenty
  module TextureLibrary
    EXTENSION ||= SketchupExtension.new(
      '20-20 Texture Library',
      'twentytwenty_texture_library/main'
    )
    EXTENSION.description = 'Texture library with SIKO, EGGER, Poly Haven CC0 and sharp RAKO Rave product-page textures.'
    EXTENSION.version = '0.2.3'
    EXTENSION.creator = '20-20'
    Sketchup.register_extension(EXTENSION, true)
  end
end
