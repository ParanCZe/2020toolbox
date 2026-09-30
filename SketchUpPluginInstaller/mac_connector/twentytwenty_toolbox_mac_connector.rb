require 'sketchup.rb'
require 'extensions.rb'

module TwentyTwenty
  module ToolboxConnector
    EXTENSION_NAME = '20-20 Toolbox Connector'.freeze
    EXTENSION_VERSION = '2.0.3'.freeze
    BASE_DIR = File.dirname(__FILE__).freeze
    MAIN_FILE = File.join(BASE_DIR, 'twentytwenty_toolbox_mac_connector', 'main').freeze

    unless file_loaded?(__FILE__)
      ext = SketchupExtension.new(EXTENSION_NAME, MAIN_FILE)
      ext.description = 'Lokální propojení 20-20 Toolboxu se SketchUpem pro Windows a macOS. Kontrola verzí, instalace, aktualizace a odinstalace 20-20 pluginů. Podpora SketchUp 2017–2026.'
      ext.version = EXTENSION_VERSION
      ext.creator = '20-20 ARCHITEKTI'
      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end
  end
end
