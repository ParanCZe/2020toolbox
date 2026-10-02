# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module TwentyTwenty
  module RMToolsSuite
    EXTENSION_NAME = '20-20 RM TOOLS'.freeze unless const_defined?(:EXTENSION_NAME)
    EXTENSION_VERSION = '2.0.6.0'.freeze unless const_defined?(:EXTENSION_VERSION)
    MAIN_FILE = File.join(__dir__, 'twentytwenty_rm_tools_suite', 'main').freeze unless const_defined?(:MAIN_FILE)

    unless file_loaded?(__FILE__)
      begin
        extension = SketchupExtension.new(EXTENSION_NAME, MAIN_FILE)
        extension.description = '20-20 RM TOOLS: Model Library, nastavení SKP / záběr / checker a Live Mirror v jednom pluginu.'
        extension.version = EXTENSION_VERSION
        extension.creator = '20-20 ARCHITEKTI'
        Sketchup.register_extension(extension, true)
        require MAIN_FILE
      rescue StandardError => e
        puts "20-20 RM TOOLS loader error: #{e.class}: #{e.message}"
        puts e.backtrace.join("\n") if e.backtrace
        UI.messagebox("20-20 RM TOOLS se nepodařilo načíst.\n\n#{e.class}: #{e.message}")
      ensure
        file_loaded(__FILE__)
      end
    end
  end
end
