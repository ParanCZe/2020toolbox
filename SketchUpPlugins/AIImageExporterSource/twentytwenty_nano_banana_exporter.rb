# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module TwentyTwenty
  module NanoBananaExporter
    EXTENSION ||= SketchupExtension.new(
      '20-20 AI Image Exporter',
      'twentytwenty_nano_banana_exporter/main_v030'
    )

    EXTENSION.description = '16:9 SketchUp exporter: standard PNG or AI pack with RGB, Z-depth, line pass and camera metadata.'
    EXTENSION.version     = '0.3.0'
    EXTENSION.creator     = '20-20'

    Sketchup.register_extension(EXTENSION, true)
  end
end
