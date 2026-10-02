# frozen_string_literal: true
require 'sketchup.rb'

module TwentyTwenty
  module RMToolsBundledChecker
    EXTENSION_VERSION = '1.2.4'.freeze unless const_defined?(:EXTENSION_VERSION)
  end
end

file_loaded(__FILE__) unless file_loaded?(__FILE__)
