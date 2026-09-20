---
name: Neural Acoustic Studio
colors:
  surface: '#faf8ff'
  surface-dim: '#d2d9f4'
  surface-bright: '#faf8ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f3ff'
  surface-container: '#eaedff'
  surface-container-high: '#e2e7ff'
  surface-container-highest: '#dae2fd'
  on-surface: '#131b2e'
  on-surface-variant: '#464555'
  inverse-surface: '#283044'
  inverse-on-surface: '#eef0ff'
  outline: '#777587'
  outline-variant: '#c7c4d8'
  surface-tint: '#4d44e3'
  primary: '#3525cd'
  on-primary: '#ffffff'
  primary-container: '#4f46e5'
  on-primary-container: '#dad7ff'
  inverse-primary: '#c3c0ff'
  secondary: '#00687a'
  on-secondary: '#ffffff'
  secondary-container: '#57dffe'
  on-secondary-container: '#006172'
  tertiary: '#005338'
  on-tertiary: '#ffffff'
  tertiary-container: '#006e4b'
  on-tertiary-container: '#67f4b7'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#e2dfff'
  primary-fixed-dim: '#c3c0ff'
  on-primary-fixed: '#0f0069'
  on-primary-fixed-variant: '#3323cc'
  secondary-fixed: '#acedff'
  secondary-fixed-dim: '#4cd7f6'
  on-secondary-fixed: '#001f26'
  on-secondary-fixed-variant: '#004e5c'
  tertiary-fixed: '#6ffbbe'
  tertiary-fixed-dim: '#4edea3'
  on-tertiary-fixed: '#002113'
  on-tertiary-fixed-variant: '#005236'
  background: '#faf8ff'
  on-background: '#131b2e'
  surface-variant: '#dae2fd'
typography:
  display-lg:
    fontFamily: Inter
    fontSize: 36px
    fontWeight: '700'
    lineHeight: 44px
    letterSpacing: -0.025em
  display-lg-mobile:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.015em
  headline-sm:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: -0.01em
  body-lg:
    fontFamily: Inter
    fontSize: 17px
    fontWeight: '400'
    lineHeight: 28px
    letterSpacing: -0.01em
  body-md:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: -0.005em
  body-sm:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
  label-lg:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.005em
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.01em
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.02em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-tablet: 1.5rem
  margin: 1rem
  margin-tablet: 2rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

This design system establishes a high-precision, tactile, and intelligent mobile audio workbench. Designed for creators, researchers, executives, and journalists who depend on seamless speech-to-text intelligence, the aesthetic bridges deterministic engineering (OpenAI Whisper) with organic cognitive transformation (DeepSeek AI).

The overarching aesthetic blends **Modern Material 3 token architecture** with **controlled Glassmorphism**. Rather than superficial, heavy frosted glass, the design applies structural translucency: frosted navigation planes, floating processing bars, and multi-layered contextual canvases that preserve background awareness. The emotional tone is authoritative, hyper-responsive, calm, and distraction-free, elevating audio recording, playback, and transcript editing into a premium flagship tactile experience.

## Colors

The color system operates on purposeful contrast, pairing deep indigo foundation values with radiant, glowing AI accents:

- **Primary Tech Indigo (`#4F46E5`, hover/active `#4338CA`, light tint `#EEF2FF`):** Represents structural logic, recording stability, and core navigation actions.
- **AI Secondary & Accent Cyan (`#06B6D4`, light `#38BDF8`):** Denotes active LLM inference, DeepSeek linguistic polish routines, and synthetic intelligence operations.
- **Acoustic Emerald (`#10B981`):** Represents optimal microphone fidelity, completed transcriptions, and successful sync states.
- **Neutral Canvas & Architecture:** Surface foundation leverages ultra-soft slate tints (`#F8FAFC` base, `#F1F5F9` nested tracks) paired with crisp pure white (`#FFFFFF`) elevated cards, encased in hairline borders (`#E2E8F0`).
- **Typography Tiers:** Primary headings and transcript body anchor to high-contrast deep slate (`#0F172A`), secondary attributes to muted slate (`#64748B`), and peripheral metadata to subtle slate (`#94A3B8`).
- **Semantic States:** Processing pulses Sky Blue (`#0EA5E9`), warnings trigger Amber (`#F59E0B`), and errors/cancellations trigger Rose (`#F43F5E`).

## Typography

Typography prioritizes prolonged readability and scannability during transcript verification and audio timeline synchronization. 

- **Body Scale & Height:** Long-form transcript views utilize `body-lg` (17px) paired with an expansive 28px line-height. This increased vertical rhythm prevents line jumping during variable-speed audio playback and karaoke-style text highlighting.
- **Font Selection:** Powered by Inter, leveraging open aperture counters, uniform tabular numerals (`tnum`) for audio timestamps and decibel metering, and tight negative tracking on headlines to convey a technical, editorial posture.
- **Multilingual Harmony:** System fallback stacks resolve automatically to native platform typography (PingFang SC, HarmonyOS Sans, or Roboto Flex) with optical metrics calibrated to match Inter’s x-height.

## Layout & Spacing

The layout model is anchored in a mobile-first fluid grid optimized for thumb-driven ergonomics and single-handed capture:

- **Mobile Viewport (up to 599px):** 4-column fluid layout with an edge margin of `1rem` (16px) and an inner gutter of `1rem` (16px). Key interactive triggers (shutter/record buttons, mode switches, audio scrubbers) remain confined to the bottom 40% thumb zone.
- **Tablet & Split-Screen Viewport (600px - 1023px):** Expands to an 8-column layout with `2rem` (32px) margins and `1.5rem` (24px) gutters. Adopts a split-pane hierarchy: sticky waveform analysis on the left/top pane, and polished document workspace on the right/bottom.
- **Component Density:** Internal component padding scales strictly along a 4px-aligned modular scale (`space-xs` through `space-xl`) ensuring rhythmic alignment across transcript speaker blocks and segmented parameter controls.

## Elevation & Depth

Depth is conveyed through a combination of structural glass surfaces, ambient tinted shadows, and hairline light-refraction borders:

- **Base Level (Canvas):** Flat `#F8FAFC` foundation. Non-elevated, absorbs background light.
- **Tier 1 (Resting Cards & Segmented Containers):** Pure `#FFFFFF` fill with a subtle perimeter border of `1px solid #E2E8F0`. Shadow is ambient and tinted: `0 1px 3px rgba(15, 23, 42, 0.04), 0 4px 12px rgba(15, 23, 42, 0.02)`.
- **Tier 2 (Glassmorphic Floating Panels & Metric Overlays):** Background uses `rgba(255, 255, 255, 0.75)` supported by a hardware-accelerated `backdrop-filter: blur(16px) saturate(180%)`. Outlined by `1px solid rgba(255, 255, 255, 0.6)` on top and `1px solid rgba(226, 232, 240, 0.6)` on bottom, casting an ambient shadow: `0 8px 24px rgba(15, 23, 42, 0.06)`.
- **Tier 3 (Floating Action Controls & Active Microphones):** Elevated indigo and cyan buttons feature an active luminous aura: `0 8px 20px rgba(79, 70, 229, 0.28), 0 2px 6px rgba(79, 70, 229, 0.16)`.
- **Tier 4 (Bottom Sheets & Modals):** Pure `#FFFFFF` surface floating over a blurred scrim (`rgba(15, 23, 42, 0.4)` with `backdrop-filter: blur(8px)`), casting an elevation shadow of `0 -8px 32px rgba(15, 23, 42, 0.12)`.

## Shapes

The design system employs Level 2 (Rounded) geometry, balancing software engineering clarity with ergonomic touch interaction:

- **Standard Elements (0.5rem / 8px):** Checkboxes, form fields, playback speed controls, context menu dropdowns, and waveform scrub bars.
- **Cards & Containers (1rem / 16px):** Audio session cards, transcript paragraph sections, deep-insight summaries, and modal content areas.
- **Structural Sheets & Bottom Drawers (1.5rem / 24px):** Applied to the top-left and top-right radii of sliding panels, recording sheets, and audio source selectors.
- **Pills & Circular Triggers (Full Radius / 9999px):** Reserved for segmented pill controls, dynamic tags, AI status chips, and primary floating microphone triggers.

## Components

### 1. Buttons & Floating Action Buttons (FAB)
- **Primary Action (Record / Polish):** Full-bleed pill or large circular trigger (64x64dp on mobile). Employs gradient illumination from `#4F46E5` to `#6366F1`. Includes an outer pulsating dynamic halo when audio is actively being buffered or transcribed by Whisper.
- **Secondary Glass Buttons:** Height 44dp, radius 12dp. Filled with `rgba(255, 255, 255, 0.8)` with `1px solid #E2E8F0` border, `backdrop-filter: blur(8px)`. Text in `#0F172A`.
- **Icon Utility Buttons:** 40x40dp rounded-full surfaces with low-contrast borders for scrubbing, looping, and bookmarking timestamps.

### 2. Status Chips & Glowing Indicators
- **State Badges:** Capsule form (`height: 24dp`, `padding: 0 10px`, `border-radius: 9999px`).
- **Whisper & DeepSeek Inference States:** Translucent tinted background (`rgba(6, 182, 212, 0.12)` for Cyan AI, `rgba(16, 185, 129, 0.12)` for Completed). Accompanied by a leading 6dp dot with an active animated CSS pulse or radial glow (`box-shadow: 0 0 8px currentColor`).

### 3. Segmented Controls
- Contained track with `#F1F5F9` background and `0.5rem` inner padding.
- Active tab floats with `#FFFFFF` fill, `0.5rem` corner radius, hairline shadow (`0 2px 4px rgba(15, 23, 42, 0.06)`), and contrasting `#0F172A` bold typography.
- Used to switch between *Raw Audio*, *Verbatim Transcript*, *DeepSeek Polished*, and *Action Items*.

### 4. Audio Waveform Widget
- Multi-bar or continuous SVG path representation. Active segments illuminate in `#4F46E5` (Primary) transitioning into `#06B6D4` (AI sync), with unplayed sections rendered in muted `#CBD5E1`.
- Integrated scrub playhead features a teardrop or rounded pill timestamp indicator floating via `backdrop-filter: blur(12px)`.

### 5. Transcript Paragraph Cards
- Isolated speech bubbles and speaker turn blocks rendered in `#FFFFFF` with 16px radius and `1px solid #E2E8F0`.
- Speaker metadata bar displays speaker initials avatar, speaker name in `label-lg`, and timestamp in `label-sm` (`#94A3B8`).
- Word-level synchronization: Words highlight smoothly with a background highlight of `rgba(99, 102, 241, 0.15)` and text transition to `#4F46E5` during audio playback.

### 6. Inputs & Form Fields
- Minimalist inset fields with `#F8FAFC` background and `1px solid #E2E8F0`. 
- Focus transitions border to `#4F46E5` with a subtle 3px focus ring (`rgba(79, 70, 229, 0.15)`). Height set to 48dp to satisfy mobile touch targets.