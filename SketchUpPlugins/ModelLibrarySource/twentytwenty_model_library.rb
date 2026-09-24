# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module TwentyTwenty
  module ModelLibrary
    EXTENSION ||= SketchupExtension.new(
      '20-20 Model Library',
      'twentytwenty_model_library/main'
    )
    EXTENSION.description = 'Smart SketchUp model library with placement metadata for wall and ground assets.'
    EXTENSION.version = '0.1.1'
    EXTENSION.creator = '20-20'
    Sketchup.register_extension(EXTENSION, true)
  end
end
