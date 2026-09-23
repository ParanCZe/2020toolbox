# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module TwentyTwenty
  module AIModelExporter
    EXTENSION ||= SketchupExtension.new(
      '20-20 AI Model Exporter',
      'twentytwenty_ai_model_exporter/main'
    )

    EXTENSION.description = 'Exports an AI-ready model package: FBX + GLB + scenes, cameras, tags, hierarchy and material metadata.'
    EXTENSION.version = '0.1.0'
    EXTENSION.creator = '20-20'

    Sketchup.register_extension(EXTENSION, true)
  end
end
