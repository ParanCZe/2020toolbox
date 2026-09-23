# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module TwentyTwenty
  module TextureLibrary
    EXTENSION ||= SketchupExtension.new(
      '20-20 Texture Library',
      'twentytwenty_texture_library/main'
    )
    EXTENSION.description = 'Persistent texture/color library with click-to-paint workflow, merged SIKO Obklady filters, RAL and NCS palettes.'
    EXTENSION.version = '0.1.5'
    EXTENSION.creator = '20-20'
    Sketchup.register_extension(EXTENSION, true)
  end
end
