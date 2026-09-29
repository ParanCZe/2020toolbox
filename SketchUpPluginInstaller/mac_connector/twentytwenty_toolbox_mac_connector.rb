require 'sketchup.rb'
require 'extensions.rb'

module TwentyTwenty
  module ToolboxMacConnector
    EXTENSION_NAME = '20-20 Toolbox Mac Connector'.freeze
    EXTENSION_VERSION = '1.0.0'.freeze
    MAIN_FILE = File.join(__dir__, 'twentytwenty_toolbox_mac_connector', 'main').freeze

    unless file_loaded?(__FILE__)
      ext = SketchupExtension.new(EXTENSION_NAME, MAIN_FILE)
      ext.description = 'Lokální propojení 2020 Toolboxu se SketchUpem na macOS pro kontrolu verzí, instalaci, aktualizaci a odinstalaci 20-20 pluginů.'
      ext.version = EXTENSION_VERSION
      ext.creator = '20-20 ARCHITEKTI'
      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end
  end
end
