---
title: "AI Asset Generation"
description: "How to prompt Nano Banana Pro and Nano Banana 2 for game textures and assets, and how to get a real alpha channel out of models that cannot produce one"
updated: 2026-08-13
confidence: documented
tags:
  - method
  - reference
---

Researched 2026-08-13 against current guides, and checked against what actually happened
building the `ALBION REFORGED` title logo for this project. → [[Formats]]

## The model line, as of August 2026

| Model | Id | Notes |
|---|---|---|
| Nano Banana | Gemini 2.5 Flash Image | Aug 2025, the original |
| **Nano Banana Pro** | `google/gemini-3-pro-image` | Nov 2025. Reasoning backbone, 65,536-token context |
| **Nano Banana 2** | `google/gemini-3.1-flash-lite-image` family | 131,072 tokens, **~95% of Pro at a fraction of the cost** |

- Resolutions: **1K / 2K / 4K** on both; **Nano Banana 2 also does 512px**.
- Aspect ratios on both: `1:1 3:2 2:3 3:4 4:3 4:5 5:4 9:16 16:9 21:9`.
- **Nano Banana 2 adds `1:4`, `4:1`, `1:8`, `8:1`** - which is the whole ballgame for texture
  work, because banner and strip textures are exactly those shapes. Fable III's title logo is
  1024x256, a native `4:1`. On Pro you have to generate `21:9` and crop, which throws away
  pixels and forces a composition guess.
- Up to **14 reference images**. Model knowledge cutoff January 2025.

## Prompt them as reasoning models, not diffusion models

This is the single biggest change and it invalidates most older prompt advice. These run on a
Gemini reasoning backbone: the model **plans the composition before it renders pixels**.

- **Drop the tag soup.** Comma-separated keyword lists and quality boosters -
  `masterpiece, best quality, trending on ArtStation, 8k, highly detailed` - are dead weight.
- **Write sentences.** Natural language, describing a scene the way you would to a person.
- **Official structure:** `[Subject] + [Action] + [Location/context] + [Composition] + [Style]`
- **With references:** `[Reference images] + [Relationship instruction] + [New scenario]`,
  e.g. *"Using the attached sketch as the structure and the attached fabric sample as the
  texture, render this as..."*
- **Positive framing only.** Say `empty street`, not `no cars`. Naming a thing to exclude
  tends to summon it.
- **Text goes in quotes**, with the typeface named: `"ALBION REFORGED" in thin spaced serif
  capitals`. Text rendering is a genuine strength of this generation.
- **Thinking mode OFF** for ordinary generation; only turn it on when output is nonsensical.
- **At 80% right, edit - do not regenerate.** Re-rolling loses everything that was working.

### Materiality is what makes assets look like assets

Name the material, never just the object:

| Weak | Strong |
|---|---|
| a suit jacket | a **navy blue tweed** suit jacket |
| armour | **ornate elven plate armour, etched with silver leaf patterns** |
| a mug | a **minimalist ceramic** coffee mug |

Finish vocabulary carries a lot: `gloss finish`, `matte surface`, `brushed metal`,
`woven fabric`, `aged brass`, `worn metallic sheen`.

## Seamless tileable textures: short prompts beat long ones

Counterintuitive and well attested. The prompt that tiles best is close to the minimum:

```
Create a seamless texture on all sides of <material>, Albedo.
```

Elaborate prompts - the kind ChatGPT or Gemini will happily write for you - **produce visible
seams**. Settings that go with it: generate **4 variants at 4K**, and **disable any prompt
rewriting** the host offers so your exact wording reaches the model.

The PBR stack comes from separate follow-up prompts, not one request:

```
Generate a normal map texture
Generate the roughness map
Generate ambient occlusion map
Generate the height map texture. <describe the relief>, medium contrast
```

Height maps specifically need the **contrast** called out or they come back flat.

Verify tiling with a pattern preview (Photoshop `View > Pattern Preview`, or any renderer
that repeats). Residual seams get fixed by offsetting the layer by half the resolution,
masking, and painting the seam out. **Expect iteration; first shot is rarely clean.**

## Getting a real alpha channel  **[VERIFIED here]**

> [!warning] No Nano Banana model can output an alpha channel. At all.
> They emit flat RGB. Ask for a transparent background and you get solid white, solid black,
> or - worst - a **painted-on checkerboard** that looks like transparency and is not.

Two documented recoveries, and they are not equally reliable:

**1. Chromakey green.** Prompt a flat `#00FF00` ground, require crisp edges, and require the
subject to contain no green; then key in HSV with a dilate/erode pass. Good for hard-edged
subjects.

> **It failed here.** Asked emphatically and repeatedly for `#00FF00`, Nano Banana Pro
> returned a **white** background twice for a logo. The logo-on-white prior is very strong.
> Do not build a pipeline on the model honouring a background colour instruction.

**2. Two-ground recovery. Exact, and what actually worked.** Render the same art over white
and over black, then solve for alpha:

```
over white:  Cw = a*C + (1-a)
over black:  Cb = a*C
             a = 1 - (Cw - Cb)        C = Cb / a
```

This recovers **true fractional alpha** on antialiased edges, which no keying heuristic does -
that is why it removed a grey halo that luminance and saturation keys both left behind.

Practical notes:

- Get the second ground with **`edit_image`**, not a second generation: *"Change ONLY the
  background colour from white to pure black. Do not move, resize, redraw or recolour the
  artwork. Pixel-identical except the background."* Measured alignment here was **0.962 IoU**,
  easily enough.
- **Median-filter the alpha** (3x3) to kill speckle from the residual misalignment.
- Unpremultiply with `C = Cb / a` or light edges keep a dark fringe.

## The Fable III recipe that shipped

1. Generate the wordmark at `21:9` on Nano Banana Pro, style-locked with `reference_images`
   set to the **stock game texture** exported by `tools/tex.py` and `reference_mode: "style"`.
   That is what made it look like Lionhead drew it.
2. `edit_image` the same file to a black ground.
3. Two-ground alpha recovery, median filter, unpremultiply.
4. Crop to the texture's real aspect (4:1), resize to its real dimensions.
5. `tools/tex-patch.py apply` - same size, same format, same mip count, so it overwrites in
   place and no bank index moves.

**Next time, use Nano Banana 2 for step 1** and ask for `4:1` directly. Cheaper, and no crop.

## Related

- [[Formats]] · [[Preservation]]
