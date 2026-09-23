# frozen_string_literal: true

require 'sketchup.rb'
require 'extensions.rb'

module TwentyTwenty
  module AgentLauncher
    EXTENSION ||= SketchupExtension.new(
      '20-20 Agent Launcher',
      'twentytwenty_agent_launcher/main'
    )

    EXTENSION.description = 'One-click launcher for user-selected adapter-agent.exe and most.rb; both paths can be changed from Extensions.'
    EXTENSION.version = '0.1.2'
    EXTENSION.creator = '20-20'

    Sketchup.register_extension(EXTENSION, true)
  end
end
