# frozen_string_literal: true
require 'sketchup.rb'

module Dvacet20
  module RMToolsBundledComponentLibrary
    EXTENSION_VERSION = '0.3.2.1'.freeze unless const_defined?(:EXTENSION_VERSION)
  end
end

file_loaded(__FILE__) unless file_loaded?(__FILE__)
