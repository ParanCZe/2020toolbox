require 'sketchup.rb'
require 'extensions.rb'

module TwentyTwenty
  module ToolboxPrint
    EXTENSION = SketchupExtension.new(
      '20-20 Toolbox · Poslat do 3D tisku',
      'twenty_twenty_toolbox/main'
    )
    EXTENSION.creator = '20-20-ARCHITEKTI'
    EXTENSION.description = 'Jednim kliknutim exportuje aktualni SketchUp model do STL, preda ho 20-20 PrusaBridge a otevre 3D tisk v 20-20-TOOLBOXU.'
    EXTENSION.version = '0.1.0'
    EXTENSION.copyright = '2026 20-20-ARCHITEKTI'
    Sketchup.register_extension(EXTENSION, true)
  end
end
