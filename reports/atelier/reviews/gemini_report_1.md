Here is the adversarial critique, open-source research, and proposed fixes for the RiG Atelier Garment Engine v1.

### TASK 1 — Adversarial Visual Critique

The garments look artificial because they combine the rigidity of a plastic shell with the rendering properties of paper. Ranked from most to least damaging to credibility:

1. **Flat, plastic lighting on fabric**
   * **Cause:** `Sources/AvatarLab/AvatarStageView.swift` (lines 65-81). The scene uses a basic directional key light, ambient fill, and directional rim light. Despite setting `.physicallyBased` (line 177) with roughness 0.85, the lack of an Image-Based Lighting (IBL) environment map means the material has nothing realistic to reflect or diffuse, making it look matte and flat.
2. **Stretched and smeared textures at glancing angles (three-quarter view)**
   * **Cause:** `Sources/AvatarLab/Core/GarmentPhotoMapping.swift` (`uvs` function, lines 39-41). The horizontal UV coordinate `t` is calculated using a 1D planar projection: `t = min(max((p.x - left) / (right - left), 0), 1)`. On surfaces perpendicular to the camera (the sides), a few photo pixels are stretched across a large 3D surface area.
3. **Harsh, unblended jagged seams between front and back**
   * **Cause:** `Tools/AvatarAssets/build_garment_templates.py` (`split_panels` function, lines 458-484). Faces are cleanly sliced into `front_faces` and `back_faces` based on a binary normal facing check (`facing = n[2] >= 0.35`). This creates a hard geometric material boundary with zero blending, making it look like two separate pieces glued together.
4. **Paper-thin edges with zero thickness**
   * **Cause:** `Tools/AvatarAssets/build_garment_templates.py` generates a single-layer 2D topology from MakeHuman's helper meshes without geometric extrusion. `AvatarStageView.swift` (line 180) sets `material.isDoubleSided = true` to hide holes, which makes edges infinitely thin like CGI paper rather than folded fabric.
5. **Unnatural, perfectly straight trouser hems**
   * **Cause:** `Tools/AvatarAssets/build_garment_templates.py` (`straighten_hems` function, line 328). It averages the lowest boundary vertices and snaps their height to a single Y coordinate: `y = float(np.mean([new[v][1] for v in hem]))`. This destroys natural fabric drape and irregularity.
6. **Abruptly chopped off sleeves**
   * **Cause:** `Tools/AvatarAssets/build_garment_templates.py` (`straighten_sleeves` function, line 360). Open-edge sleeve vertices are projected to a single flat mathematical plane along the arm axis: `target = float(np.mean([s[v] for v in ring]))`, creating rigid tube ends instead of natural sleeve openings.

---

### TASK 2 — Focused Open-Source Research

Below is the evaluation of the requested projects, separating redistributable code from offline tools. 

#### Offline Build-Time Tools / Inspiration
* **MakeHuman**
  * **URL:** http://www.makehumancommunity.org
  * **Maintenance:** Legacy 1.x is unmaintained; community shifted to MPFB2.
  * **License:** Code is AGPL v3; exported Assets are CC0.
  * **Feasibility:** AGPL code cannot be used in a closed iOS app. However, CC0 assets are perfectly safe.
  * **Use:** Offline reference / asset generation.
* **MPFB2 (MakeHuman Plugin for Blender)**
  * **URL:** https://github.com/makehumancommunity/mpfb2
  * **Maintenance:** Actively maintained.
  * **License:** Code is GPLv3+; Assets are CC0.
  * **Feasibility:** Blender plugin only; GPL code cannot be used on iOS.
  * **Use:** Offline tool.
* **Blender**
  * **URL:** https://blender.org
  * **Maintenance:** Actively maintained.
  * **License:** GPLv2+.
  * **Feasibility:** No native iOS runtime.
  * **Use:** Offline build-time tool.
* **GarmentCode**
  * **URL:** https://github.com/EPFL-VRLab/GarmentCode
  * **Maintenance:** Active.
  * **License:** MIT.
  * **Feasibility:** Python-based, so offline only. 
  * **Use:** Inspiration only. Could inspire algorithms to fix **Defect 4** (Paper-thin edges) by analyzing how it generates sewing patterns and seams.
* **Open3D**
  * **URL:** https://github.com/isl-org/Open3D
  * **Maintenance:** Actively maintained.
  * **License:** MIT.
  * **Feasibility:** Desktop/server focused; not officially supported for iOS (compiling for iOS is highly difficult, UNVERIFIED if a stable iOS build is practical).
  * **Use:** Offline Python/C++ tool for mesh processing.
* **NVIDIA Kaolin**
  * **URL:** https://github.com/NVIDIAGameWorks/kaolin
  * **Maintenance:** Actively maintained.
  * **License:** Apache-2.0 (Core) / NSCL (Restrictive non-commercial for some legacy modules).
  * **Feasibility:** PyTorch-based ML toolkit. Unsuitable for on-device iOS rendering.
  * **Use:** Offline ML tool.
* **PyTorch3D**
  * **URL:** https://github.com/facebookresearch/pytorch3d
  * **Maintenance:** Actively maintained.
  * **License:** BSD 3-Clause.
  * **Feasibility:** Cross-compiling the C++/CUDA core for iOS is notoriously difficult.
  * **Use:** Offline ML tool.

#### Redistributable Code / APIs
* **Google Filament**
  * **URL:** https://github.com/google/filament
  * **Maintenance:** Actively maintained by Google.
  * **License:** Apache-2.0.
  * **Feasibility:** High. Native C++ with excellent iOS Metal support.
  * **Use:** Redistributable code. Could fix **Defect 1** (Lighting) by replacing SceneKit with a state-of-the-art PBR engine.
* **libigl**
  * **URL:** https://github.com/libigl/libigl
  * **Maintenance:** Actively maintained.
  * **License:** MPL-2.0 (Some optional dependencies are GPL).
  * **Feasibility:** Feasible for iOS as a header-only C++ geometry library.
  * **Use:** Redistributable code. Useful for geometry processing (e.g., smoothing edges or recalculating normals) if you avoid GPL modules.
* **Apple SceneKit/RealityKit PBR Docs**
  * **URL:** Apple Developer Documentation.
  * **Maintenance:** RealityKit is active; SceneKit is deprecated but stable.
  * **License:** Proprietary (Apple).
  * **Feasibility:** Native to iOS.
  * **Use:** Redistributable API. Correct usage fixes **Defect 1** directly.

---

### TASK 3 — Concrete Low-Risk Fixes

These are the top 5 high-ROI changes, implementable within your current stack.

**1. Add Image-Based Lighting (Environment Map) [Highest ROI]**
* **Fix:** In `AvatarStageView.swift`, replace or supplement the basic directional lights with an HDRI environment map using `scene.lightingEnvironment.contents = UIImage(named: "studio_hdri")`. 
* **Effect:** Instantly resolves **Defect 1**. The `physicallyBased` fabric material will react to the environment, gaining realistic ambient occlusion, subtle reflections, and natural shadow gradients.
* **Risk:** Low. Very little code; requires adding one small HDR asset.

**2. Arc-Length (Cylindrical) UV Mapping**
* **Fix:** In `GarmentPhotoMapping.swift`, instead of mapping the horizontal UV `t` using `p.x` (planar projection), calculate it by accumulating the 3D surface distance along horizontal rings (arc-length), or use a cylindrical projection. 
* **Effect:** Fixes **Defect 2**. The vertical stripes will wrap cleanly around the torso and arms instead of smearing horizontally at glancing angles. 
* **Risk:** Medium. Requires math changes in the UV generation loop.

**3. Soften the Geometric Hem Snapping**
* **Fix:** In `Tools/AvatarAssets/build_garment_templates.py` (`straighten_hems` and `straighten_sleeves`), do not snap vertices 100% to the mean Y-coordinate. Instead, blend them: `new[v] = (..., original_y * 0.2 + mean_y * 0.8, ...)`. 
* **Effect:** Mitigates **Defects 5 & 6**. Trousers and sleeves will look naturally cut but retain slight organic fabric irregularities, removing the stiff "CGI cylinder" look.
* **Risk:** Low. A one-line math change in the offline Python builder.

**4. Bake Fake Ambient Occlusion into Vertex Colors**
* **Fix:** In the offline Python builder, calculate the distance of each vertex to the nearest boundary edge (hems, necklines). Bake a slight darkening gradient into the mesh's vertex colors (e.g., from 1.0 to 0.7 at the absolute edge). Ensure `AvatarStageView` multiplies diffuse by vertex color.
* **Effect:** Mitigates **Defect 4**. While the mesh remains paper-thin, the dark gradient fakes the shadowing of a rolled hem or fabric thickness, tricking the eye. 
* **Risk:** Low. Completely offline processing; SceneKit supports vertex colors natively.

**5. SceneKit Shader Modifier for Seam Blending**
* **Fix:** In `AvatarStageView.swift`, inject a simple Metal snippet into the fabric's `SCNShaderModifierEntryPoint.fragment`. Use the UV coordinates or surface normal to smoothly mix a few pixels of the front texture with the back's solid color at the boundary, replacing the binary split.
* **Effect:** Fixes **Defect 3**. The transition from the photo to the "unknown region" becomes a soft, plausible blend instead of a jagged polygonal line.
* **Risk:** Medium. Requires writing a few lines of Metal shader code and testing it on a physical iOS device.
