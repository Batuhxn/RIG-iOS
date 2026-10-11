## Goal Description
As the visual adversary for RiG Atelier, here is the harsh, specific visual teardown of the rendering comparisons (v1 vs atelier).

### 1. Is the atelier side visibly better than v1?
Yes, but it trades old problems for new ones.
*   **Better:** The catastrophic texture stretching on the sides in v1 is gone, replaced by the solid color fade. Contact shadows ground the garments nicely, and the darker lining creates a much-needed illusion of thickness compared to v1's paper-thin edges.
*   **Worse:** The 57-69 degree transition is too abrupt, appearing as a harsh, artificial vertical seam rather than a soft fade. The studio lighting feels flatter on solid colors than v1, washing out mid-tones.
*   **No different:** Severe mesh clipping on extreme body shapes remains entirely unresolved.

### 2. Rank the 5 most damaging remaining visual defects:
1.  **Vanishing Silhouette:** The white tee's side perfectly camouflages into the white mannequin, erasing the torso entirely. (Evidence: `cmp_separates_stripes.png`, row 1, col 7).
2.  **Abrupt Fade Seam:** The 57-69 degree photo-to-plain transition acts like a harsh cutoff rather than a soft blend, looking like a broken texture seam. (Evidence: `cmp_dress_stripes.png`, row 1, col 6).
3.  **Shoulder Clipping:** The mannequin's geometry violently pierces the garment's neckline in jagged polygons. (Evidence: `cmp_dress_plain.png`, row 4, col 8).
4.  **Black-Hole Lining:** The "darker lining" inside the neck/hem has zero lighting reaction, rendering as a flat black void rather than shaded fabric. (Evidence: `cmp_dress_plain.png`, row 1, col 8).
5.  **Sleeve Intersection:** The sleeve hems clip directly into the bicep geometry, destroying the illusion of draped cloth. (Evidence: `cmp_separates_plain.png`, row 4, col 7).

### 3. The red/white striped tee vanishing:
*Options:*
1.  Set the tee's data so its "main color" fallback is red instead of white.
2.  Programmatically darken any pure-white main color to an off-white/grey for the sides/back.
3.  Change the mannequin's base albedo to a neutral mid-grey.

*Pick:* **Option 3 (Change the mannequin to mid-grey).** This is the only universal fix. White garments will always exist in a wardrobe app, and a pure white mannequin will always cause them to vanish in side/back views regardless of the lighting setup.

### 4. Lighting: does the studio light help? What concrete SceneKit change?
The IBL studio light helps soften the overall aesthetic, but it fails to define form, leaving garments looking flat (especially the plain terracotta dress). It lacks directional contrast to wrap around the cylindrical shapes of the body.

*Concrete SceneKit change:* Add a single `SCNLightTypeDirectional` key light (intensity ~400-500) angled at a 45° offset (e.g., `euler-angles: x: -45, y: 45, z: 0`) with a subtle warm tint and soft shadows enabled. This provides a gentle core shadow across the torso to define volume without the "drama" of harsh spotlights. 
> [!WARNING]
> **UNVERIFIED**: Whether SceneKit's PBR shader is properly reacting to the IBL's directional peaks. Simply rotating the `scene.lightingEnvironment.contents` HDRI by 45 degrees on the Y-axis might achieve the necessary volume without needing to add a new light node at all.

## User Review Required
Please review the visual teardown above. No code changes will be made as per your READ-ONLY instructions.
