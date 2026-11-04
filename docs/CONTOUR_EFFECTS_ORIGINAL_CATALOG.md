<!-- SPDX-FileCopyrightText: 2026 Daito Manabe -->
<!-- SPDX-License-Identifier: BSD-3-Clause -->

# ContourEffects Original Effect Catalog

## Status

ContourFlow, the VJ application this SDK was extracted from, renders
221 effect variants in 20 groups plus six supporting modules. The SDK
currently exposes one of them: Final Color Grade / Film Finish
(`ws.daito.contour-effects.color.final-grade`). Everything else below is
**not part of the SDK API** until it is migrated and returned by
`ContourEffectsMetalCatalog`.

The original Swift and Metal implementations, specifications, and runtime
assets are kept in a private companion repository. They are not distributed
with this SDK and are not covered by its BSD-3-Clause grant.

Status values:

- `available`: in the SDK catalog.
- `not migrated`: portable to `ContourEffectsMetal`; not yet ported.
- `host-only`: depends on something the SDK products may not link or do, so
  it needs a host adapter or a redesign.

## Groups

The category column uses `EffectCategory` cases. Input names are
`MetalEffectFrame` / `MetalAnalysisTextures` fields.

| Group | Variants | Category | SDK inputs | Status |
| --- | ---: | --- | --- | --- |
| Classic CV overlay | 7 | `analysis` | `source`, `edge`, `opticalFlow`, `featurePoints` | not migrated |
| CV particle field | 14 | `particles` | `opticalFlow`, `edge`, `personMask`, `handLandmarks` | not migrated |
| Analysis FX / ASCII | 10 | `analysis` | `edge`, `opticalFlow`, `depth`, `personMask`; effect-owned history | not migrated |
| Human vision overlay | 4 | `analysis` | `personMask`, `handLandmarks`, `bodyLandmarks` | not migrated |
| Hand geometry | 10 | `analysis` | `handLandmarks` | not migrated |
| Contour geometry | 10 | `analysis` | silhouette contour **polygon** (gap 3) | not migrated |
| Scene intelligence overlay | 4 | `analysis` | `sceneMask`, saliency (gap 3) | not migrated |
| Object detection overlay | 3 | `analysis` | `detections` | not migrated |
| Depth overlay | 15 | `threeDimensional` | `depth` | not migrated |
| Person cutout | 4 | `compositing` | `personMask`, `detections`, `depth`, `handLandmarks` | not migrated |
| MECHA 3D model | 5 | `threeDimensional` | mesh asset (gap 4), `audio`, `rawCamera` | not migrated |
| MECHA material FX | 6 | `threeDimensional` | `rawCamera` | not migrated |
| Post FX | 31 | `distortion`, `glitch` | per effect: effect-owned history, `opticalFlow`, `edge`, `personMask`, `handLandmarks`, `depth` | not migrated |
| Depth fragment style | 8 | `distortion` | `depth` | not migrated |
| Liquid glass lens shape | 3 | `distortion` | `source` | not migrated |
| Optical camouflage style | 54 | `fluid`, `reactionDiffusion`, `compositing` | `personMask`, `opticalFlow`; per style `depth`, `handLandmarks`, `bodyLandmarks`; effect-owned 480x270 simulation state (gap 2) | not migrated |
| Adopted silhouette mode | 11 | `fluid`, `compositing` | as optical camouflage; modes beyond each body's default | not migrated |
| GLIC Metal family | 9 | `glitch` | GLIC Metal host capability (gap 5) | host-only |
| Effect area | 5 | `utility` | `personMask`, `silhouetteContour`, `edge` | not migrated |
| Final color grade look | 8 | `color` | `source`; optional 3D LUT | **available** as `ws.daito.contour-effects.color.final-grade` |

## Supporting modules

| Module | What it needs | Status |
| --- | --- | --- |
| Motion Data Mosh | its own flow estimate and RGB history (temporal) | not migrated |
| Authentic JPEG Glitch | CPU JPEG encode, scan mutation, and decode | host-only: conflicts with the no-CPU-readback rule |
| Attack glitch | GLIC Metal triggered by `audio.attack` | host-only |
| Effect graph and routing | node plans and texture slots | covered by `MetalEffectGraph` |
| 150 factory looks | presets that span many effects | not migrated: needs per-effect `EffectStateSnapshot` presets |
| Audio and performance macros | volume, FFT, attack, 4-step beat, 8 macros | covered by `EffectAudioFeatures` and `EffectPerformanceMacros`, except the beat step (gap 3) |

## What the SDK still lacks

1. **Effect implementations.** Every variant except the final grade must be
   ported as an SDK effect with a stable identifier, descriptor, parameters,
   and state schema. Keep the original code IDs and stored raw values when a
   variant becomes a parameter choice: presets store those numbers, including
   the retired gaps.
2. **Effect-owned GPU state helpers.** Many originals keep persistent textures:
   two-texture RGB history, 480x270 fluid, reaction-diffusion, elastic, and
   mass fields, a jump-flood background field, and particle buffers. The render
   contract already allows an effect to allocate these in `resize`; a shared
   ping-pong helper would keep ports consistent.
3. **Inputs outside Analysis ABI 1.0.** Contour geometry needs the silhouette
   contour as an ordered polygon, not only the `silhouetteContour` coverage
   texture. Scene overlays read a saliency map separate from `sceneMask`. Beat
   effects read a 4-step beat index, while ABI 1.0 carries `beat` as one value.
4. **Geometry assets.** MECHA models (indexed meshes with a hierarchical part
   palette) need an asset contract like the one `MetalLUT3D` provides for
   LUTs: resolved by the host outside the frame path, never read by an effect
   during `encode`.
5. **Host-only capabilities.** GLIC families and the CPU JPEG path cannot live
   in the SDK products. They need a host-side adapter that encodes into the
   same command buffer, or a GPU-only redesign.
6. **Exclusive selection.** ContourFlow selects one Post FX preset at a time.
   SDK effects compose in a graph, so each port should be an independent effect
   rather than one switch over all presets.

## Variant code IDs

- **Classic CV overlay**: `raw`, `opticalFlow`, `edge`, `featurePoints`, `voronoi`, `triangulation`, `plexus`
- **CV particle field**: `flow`, `edge`, `field`, `smart`, `fingertips`, `slimeLife`, `slimeNetwork`, `slimeVelocity`, `slimeTrails`, `slimeNeighbors`, `slimeGroups`, `slimeTriangulation`, `orbitalSkin`, `flowRibbon`
- **Analysis FX / ASCII**: `featureFacets`, `depthSlice`, `asciiContourFlow`, `asciiDepthStrata`, `asciiMotionMemory`, `asciiSilhouetteBreath`, `asciiFlowCalligraphy`, `asciiLayeredSource`, `asciiLayeredColormap`, `silhouettePlexus`
- **Human vision overlay**: `silhouette`, `hands`, `both`, `diagnosticHUD`
- **Hand geometry**: `tipPolygon`, `tipTriangulation`, `enclosingCircle`, `tenTriads`, `circumcircles`, `jointSpheres`, `boneOrbits`, `palmMandala`, `handDelaunay`, `kineticConstellation`
- **Contour geometry**: `outlinePolygon`, `centroidFan`, `triangulatedShell`, `circumcircleField`, `enclosingRings`, `vertexSpheres`, `voronoiRibs`, `nestedContours`, `orbitalHull`, `kineticPlexus`
- **Scene intelligence overlay**: `mask`, `saliency`, `field`, `hud`
- **Object detection overlay**: `boxes`, `tracks`, `hud`
- **Depth overlay**: `map`, `contours`, `mesh`, `field`, `orbitCube`, `orbitPrimitives`, `tripleOrbit`, `wrapRibbon`, `silhouetteTunnel`, `particleHalo`, `plexusVolume`, `shardSwarm`, `depthRain`, `fluidSheet`, `volumetricBeams`
- **Person cutout**: `silhouette`, `boxes`, `depthAndYOLO`, `fingerRectangles`
- **MECHA 3D model**: `voidCrown`, `prismaticRupture`, `orthogonalLabyrinth`, `sphericalRupture`, `axialRupture`
- **MECHA material FX**: `chromatic`, `pixelDither`, `vhs`, `holomatrix`, `colorGrade`, `edgeFlow`
- **Post FX**: `film`, `glitch`, `dataMosh`, `bloom`, `crush`, `flowTrails`, `vectorStreak`, `motionGlitch`, `chromaticAberration`, `chromaticDisplacement`, `pixelDither`, `vhs`, `holomatrix`, `kaleidoscope`, `radialBlur`, `pixelSort`, `feedbackTunnel`, `slitScan`, `waveWarp`, `ripple`, `mirrorTiles`, `stopMotion`, `lumaFeedback`, `fingerFluid`, `liquidGlassLens`, `opticalCamouflage`, `depthFragment`, `glicMetal`, `scanlineShred`, `flowCodec`, `frameFracture`
- **Depth fragment style**: `falseColor`, `topographic`, `relief`, `movingSlice`, `refraction`, `posterizedPlanes`, `dither`, `nearSilhouette`
- **Liquid glass lens shape**: `capsule`, `sphere`, `cube`
- **Optical camouflage style**: `liquidInvisible`, `mercury`, `prism`, `voronoiCrystal`, `waterCaustic`, `flowThreads`, `impactShockwave`, `pixelPhase`, `dataMoshSkin`, `holographicFilm`, `environmentTunnel`, `silhouetteTunnel`, `bodyFluidWake`, `elasticStress`, `massLensing`, `bodyFluidInnerWake`, `elasticInnerStress`, `bodyFluidGlobalWake`, `elasticGlobalStress`, `microlensBody`, `fresnelLensBody`, `bubbleBody`, `contourPressureJets`, `opticalFlowInk`, `depthStratifiedFluid`, `handVortexGloves`, `skeletonFlowRibbons`, `flowDirectionSpectrum`, `pressureIsobars`, `depthThermalPlumes`, `kineticBodyHeat`, `silhouetteOrbitField`, `silhouetteFluidChamber`, `depthGradientRivers`, `depthEdgeVortexSheets`, `depthSilhouetteInterference`, `silhouetteMagneticFlux`, `silhouettePressureMembrane`, `depthCurlCascade`, `depthIsoCellFlow`, `depthBuoyancyFalls`, `contourReactionCoral`, `silhouetteReactionSkin`, `contourReactionHalo`, `silhouetteMitosisCells`, `reactionFlowWake`, `contourReactionCurvatureSpirals`, `silhouetteReactionSDFLamellae`, `contourReactionExcitableWaves`, `silhouetteReactionCellular`, `contourReactionPhaseInterference`, `contourCollapseBody`, `resonantCrumpledMirrorBody`, `ferrofluidSkeletonField`
- **Adopted silhouette mode**: `contourCollapseBody.1`, `contourCollapseBody.2`, `contourCollapseBody.3`, `contourCollapseBody.4`, `resonantCrumpledMirrorBody.1`, `resonantCrumpledMirrorBody.2`, `resonantCrumpledMirrorBody.3`, `ferrofluidSkeletonField.1`, `ferrofluidSkeletonField.2`, `ferrofluidSkeletonField.3`, `ferrofluidSkeletonField.4`
- **GLIC Metal family**: `legacyBlock`, `lineTear`, `channelShear`, `analogSync`, `mirrorFold`, `edgeEcho`, `bitplaneDither`, `waveWarp`, `posterSolar`
- **Effect area**: `native`, `fullFrame`, `personSilhouette`, `silhouetteContour`, `cameraEdges`
- **Final color grade look**: `neutral`, `cinema`, `warmPrint`, `coolPrint`, `reversal`, `bleach`, `night`, `monochrome`
