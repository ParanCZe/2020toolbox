# frozen_string_literal: true
# Shared 35mm-equivalent lens convention used by both Checker and Scene Manager.
# Camera#focal_length depends on Camera#image_width, so never use it for 35mm presets.
module TwentyTwenty
  module RMToolsSuite
    module CameraConsistency
      def set_aspect_ratio(ratio)
        val = ratio.to_f
        return notify('Neplatný poměr stran.', 'warn') if val.negative?
        cam = model.active_view.camera
        eye = cam.eye.clone
        target = cam.target.clone
        up = cam.up.clone
        cam.aspect_ratio = val
        moved = cam.eye.distance(eye) > 0.001 ||
                cam.target.distance(target) > 0.001 ||
                cam.up.angle_between(up) > 0.00001
        cam.set(eye, target, up) if moved
        model.active_view.invalidate
        notify(val.zero? ? 'Rámeček záběru vypnutý.' : "Rámeček záběru: #{format('%.3f', val)}")
        push_state
      rescue StandardError => e
        notify("Poměr stran: #{e.message}", 'error')
      end

      def set_focal_length(mm)
        val = mm.to_f
        return notify('Ohnisko musí být mezi 10 a 200 mm.', 'warn') unless val.between?(10.0, 200.0)
        view = model.active_view
        cam = view.camera
        eye = cam.eye.clone
        target = cam.target.clone
        up = cam.up.clone
        cam.perspective = true unless cam.perspective?
        cam.fov = 2.0 * Math.atan(36.0 / (2.0 * val)) * 180.0 / Math::PI
        cam.set(eye, target, up)
        view.invalidate
        notify("Ohnisko: #{val.round} mm (35mm ekv.).")
      rescue StandardError => e
        notify("Ohnisko: #{e.message}", 'error')
      end
    end
  end
end
