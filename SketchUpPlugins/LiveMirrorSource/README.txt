20-20 Live Mirror v0.4.6

Architecture:
- No SketchUp camera switching or camera writes.
- No mirrored/duplicated room geometry in the SketchUp model.
- A private WebGL renderer calculates a planar reflection from the real camera position.
- The reflection is projected onto the selected face through a SketchUp Overlay texture.

Install with Extension Manager, fully restart SketchUp, select one planar face and choose:
Extensions > 20-20 Live Mirror > Make Projected Mirror from Selected Face

v0.4.3 fixes:
- Forces the Overlay draw color to pure white before drawing the reflection texture. SketchUp View#draw textures are affected by the current drawing color, and the previous build could therefore show a red-tinted image instead of the renderer's real RGB frame.
- Removes the group/component bounds pre-culling from the private renderer scene traversal. All visible geometry is traversed and the mirror-plane clipping is done at face/triangle level, avoiding missing reflected objects in nested/transformed groups.
- Adds "Show Raw Reflection Frame". It displays the exact PNG produced by the private WebGL renderer before SketchUp maps it onto the mirror. This cleanly separates renderer-camera issues from Overlay/UV issues.
- Diagnostics reports the v0.4.3 white texture modulation fix.

Renderer scope:
- geometry, depth, material colors and transparency
- live camera-position-dependent planar reflection
- SketchUp image textures are not yet reproduced by the private renderer


v0.4.4 high-resolution update:
- Reflection quality presets now include 1536, 2048, 3072 and 4096 px.
- New models default to 2048 px. Existing models keep their saved quality until changed from Reflection Quality.
- The WebGL renderer clamps the requested size to the actual GPU/browser limit and Diagnostics reports requested size, actual frame size and renderer maximum.
- High-resolution modes use progressively slower live-update debounce to avoid generating multiple 4K PNG frames while orbiting.
- 4096 px is 16x the pixel count of 1024 px and can be heavy; use 2048 px for normal live orbiting and 4096 px for final inspection.


v0.4.5: switched reflection projection to full reflected-camera (selfie camera) mode. The SketchUp camera is never changed.


v0.4.6 mapping fix:
- Raw renderer output was proven to contain the reflected scene, so the remaining problem was the mapping stage.
- The renderer now uses a generalized asymmetric off-axis projection where the selected mirror itself is the camera window. The output PNG therefore corresponds exactly to the mirror aperture instead of being a full camera frame.
- Overlay triangle winding is corrected toward the current viewer so reversed SketchUp faces cannot cull the texture.
- Overlay U coordinates are horizontally flipped because the virtual camera sees the back side of the mirror plane.
- Overlay is offset 3 mm toward the viewer to avoid depth fighting with the original face.
- The SketchUp camera is still never modified and no mirrored model geometry is created.


Update 0.4.7: The raw reflection frame was already correct, so the overlay mapping was simplified to an explicit rectangle remap (two textured triangles over the mirror bounds) instead of face-mesh UV reuse. This is intended to fix the case where the mirror plane only showed a flat tinted color instead of the reflection.


Update 0.4.8: Raw Reflection Frame was confirmed correct, so the remaining 3D View#draw mapping path has been removed. The reflection is now projected in screen space with View#draw2d using a tessellated grid over the projected mirror rectangle. This bypasses the 3D textured overlay behavior that was showing only a flat/tinted color. The raw frame is mapped 1:1 with no additional horizontal flip.


UPDATE 0.4.9
The Raw Reflection Frame was confirmed correct while SketchUp Overlay drawing still appeared as a flat changing color. v0.4.9 therefore removes Overlay from the final display path. Each WebGL mirror frame is loaded as a native SketchUp material texture and positioned directly on the original Face using Face#position_material with a full 0..1 UV tile. No mirrored geometry is created and the user's SketchUp camera is never written to. For the most reliable mapping, re-select the mirror face and run Make Projected Mirror once after installing v0.4.9 so the exact edit-context transformation is stored.


Update 0.4.10: The reflection finally displays through the native face material path. This update rotates the applied framebuffer by 90 degrees clockwise when pinning it back to the mirror face, to correct the last orientation mismatch on the mirror plane.


Update 0.4.11: Replaces the mistaken 90° remap with a pure horizontal mirror remap of the native face material. The reflection should stay upright and only flip left/right, matching the expected mirror behavior.


Update 0.4.12: fixes shifted reflection/camera in mirrors inside scaled or nested groups/components. The mirror plane and renderer face normals are now derived from actual transformed world-space polygon vertices instead of directly transforming Face#normal. This is robust under non-uniform scaling. Mirror local axes also use the longest real edge for better stability.


Update 0.4.13: Reflection rendering now includes renderer-side directional shading and visible hard model edges, closer to SketchUp's Shaded with Edges look. Extensions > 20-20 Live Mirror now includes separate Shading ON/OFF and Edges ON/OFF switches. Soft/smoothed edges are omitted. The final reflection is still applied through the native face material path; the SketchUp camera is never changed.


Update 0.4.14:
- Raises the default scene triangle budget from 180k to 600k, with menu presets up to 900k.
- Adds safe world-space bounds culling for nested groups/components that are completely behind the mirror plane, reducing wasted geometry when the mirror is placed on a different wall.
- Expands the toolbar from 2 buttons to the primary mirror commands: create, refresh, raw frame, rebuild scene, live updates, shading, edges, diagnostics and remove.
- All toolbar buttons use dedicated 20-20-style icons and Czech hover/status descriptions.


Update 0.4.15 – complex model stability:
- fixes group bounds pre-culling so nested/scaled groups are not accidentally transformed twice,
- adds conservative mirror-frustum culling (4x expanded aperture) before scene serialization,
- culls individual triangles and hard edges outside the reflection volume,
- automatically retries without frustum culling if the culler unexpectedly produces an empty scene,
- adds 1,500,000 triangle budget option but relies on culling instead of blindly sending the whole model,
- diagnostics now report transfer MB and culled geometry counts.


Update 0.4.16: Complex models could still omit valid reflected objects because the scene-transfer frustum culler was too aggressive. This version switches the offscreen renderer to an accuracy-first mode: it disables reflection-cone culling and keeps only safe rejection of geometry wholly behind the mirror plane (plus nested bounds skipping behind the mirror). The result is heavier but more complete reflections.


Update 0.4.17: Adds adaptive scene LOD. Instead of stopping at the first N triangles in SketchUp entity order, the extension estimates scene complexity, preserves low-poly architectural faces in full, and proportionally samples dense/high-poly faces across the whole model. This is designed to keep all important objects represented in complex reflections without sending a 1.5M-triangle JSON payload.


Update 0.4.18: High-poly objects in reflections are now handled with object-level adaptive LOD. Instead of judging only individual faces, the engine classifies whole groups/components by subtree triangle count. Dense objects are sampled evenly across the object, which keeps high-poly furniture, fixtures and decorations visible in the mirror instead of disappearing because each tiny face looked 'simple'.
