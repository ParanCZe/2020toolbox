# frozen_string_literal: true
# Focused regression checks for Street View URL parsing and scene-set payloads.
module Sketchup
  def self.respond_to?(name, include_private=false)
    return false if [:read_default, :write_default].include?(name)
    super
  end
end
require_relative 'RMToolsSuiteSourceV2061/twentytwenty_rm_managers/street_view'

sv = TwentyTwenty::RMManagers::StreetView

api = sv.parse_url('https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=50.0755%2C14.4378&heading=123.5&pitch=-7&fov=82')
raise 'API=1 location parse failed' unless api[:location] == '50.0755,14.4378'
raise 'heading parse failed' unless (api[:heading]-123.5).abs < 0.001
raise 'pitch parse failed' unless (api[:pitch]+7.0).abs < 0.001
raise 'fov parse failed' unless (api[:fov]-82.0).abs < 0.001

classic = sv.parse_url('https://www.google.com/maps/@50.0755,14.4378,3a,75y,224h,86t/data=!3m6')
raise 'classic location parse failed' unless classic[:location] == '50.0755,14.4378'
raise 'classic heading parse failed' unless (classic[:heading]-224.0).abs < 0.001
raise 'classic pitch conversion failed' unless (classic[:pitch]-4.0).abs < 0.001
raise 'classic fov parse failed' unless (classic[:fov]-75.0).abs < 0.001

begin
  sv.parse_url('https://example.com/no-street-view')
  raise 'invalid Street View URL was accepted'
rescue RuntimeError => e
  raise unless e.message.include?('nepodařilo')
end

puts 'PASS: Street View URL formats and camera parameters parse safely'
