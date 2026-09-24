# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module TwentyTwenty
  module ModelLibrary
    EXTENSION ||= SketchupExtension.new(
      '20-20 Model Library',
      'twentytwenty_model_library/main_v020'
    )
    EXTENSION.description = 'Parametric SketchUp object library with electrical devices, 2D vegetation, windows, doors and hosted cut-opening objects.'
    EXTENSION.version = '0.2.0'
    EXTENSION.creator = '20-20'
    Sketchup.register_extension(EXTENSION, true)
  end
end
