# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module Dvacet20
  module ComponentLibrary
    EXTENSION_NAME = '20-20 Knihovna komponent'.freeze
    EXTENSION_VERSION = '0.3.2'.freeze

    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new(EXTENSION_NAME, 'dvacet20_component_library/main')
      extension.description = 'Serverová knihovna SKP komponent s náhledy a vložením jedním kliknutím.'
      extension.version = EXTENSION_VERSION
      extension.creator = '20-20 ARCHITEKTI'
      extension.copyright = '2026 20-20 ARCHITEKTI'
      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
