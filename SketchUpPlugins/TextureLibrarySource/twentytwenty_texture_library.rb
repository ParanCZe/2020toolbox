# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module TwentyTwenty
  module TextureLibrary
    EXTENSION ||= SketchupExtension.new(
      '20-20 Texture Library',
      'twentytwenty_texture_library/main'
    )
    EXTENSION.description = 'Texture library with SIKO, EGGER, direct Poly Haven CC0 materials, per-face positioning, RAL and NCS.'
    EXTENSION.version = '0.2.0'
    EXTENSION.creator = '20-20'
    Sketchup.register_extension(EXTENSION, true)
  end
end
