# Cinejoy iOS verification

The current device package is iOS 26+, version 1.0.0, build 8, from source
`c1fa078`, GitHub run `43756417223`. It is unsigned ARM64 for Sideloadly.
SHA-256: `aca0eb3f788c4850493bac9ef74aac3ef7e667554be8e57a5d63ce80420a7192`.
The official favicon PNG is unchanged byte for byte.

## Verified

- All 15 local behavioral Node checks pass: real catalog extraction, exact episode
  paths, caption cue export, selection/Off handoff and bounds, public-master observation, no AirPlay,
  and keeping the hidden website player paused and silent during native playback.
  The selected language is prioritized within the cue/UTF-8 budget so other
  loaded tracks cannot crowd it out.
- Device Release compilation, Swift HLS parser/MIME/range checks, packaged
  resources, iOS minimum, ARM64 platform, background audio, unsigned package,
  loopback-only media transport and no local-network permission pass.
- Native interface run `43737165020` on `08730a5`: **5 tests, zero failures**.
  Home, light-mode hero visibility, browsing, share sheet, save persistence after
  relaunch, local/live search, no-results, settings and appearance passed.
  It exported 21 unchanged native captures including light, dark and large text.
- Earlier native run `43733774750` also passed iPad Home. The latest iPhone
  iteration does not re-boot an iPad for every screenshot change.
- Earlier native movie/history test in run `43733772806` passed real playback,
  landscape, saved progress and resume. TV Season 2 and its selected episode passed.
- Build 4's focused TV run reached Season 2 and real episode playback. It failed
  at the test's next-episode scrolling: the test scrolled episode 2 above the
  viewport. Its failure screenshot and full accessibility hierarchy are retained.

## Subtitle verification

Native run `43754753592`, source `23a5b44`, iPhone 17 Pro:

- **`testNativeCaptionRenderer` passed (52.989 seconds).** A local synthetic
  video exercised the production AVPlayer/session/overlay/coordinator paths:
  inline display, markup/entity cleanup, multiline cues, paused seeking,
  portrait/landscape fullscreen, fullscreen Off/On, paused return at the same
  15-second clock, inline Off/On and advancing caption time after Resume.
- The separate live Inception check loaded **1,738 English cues**, automatically
  selected them and returned to actual native playback. Its retained diagnostics
  show `AVPlayer status=1 control=2 time=10`, one player item and
  `captionSelected=true`.
- The live test then failed at its final native-menu query because both the
  info panel and the open menu contain a Subtitles button. Its selector is now
  scoped to the menu collection view. That final menu step has **not been rerun**;
  the overall two-test workflow is not recorded as a complete pass.
- Eight original PNGs and provenance are in `dist/Cinejoy-Subtitle-Review`.
  Synthetic video captures are labelled; the live provider capture is separate.
- Build 8 retains the tested native rendering code and adds selected-track
  export priority, covered by the behavioral Node regression. Its Release
  package excludes the Debug QA screen and synthetic movie.

Real-site REA captures also observed the English SRT becoming a blob-backed
default TextTrack. This supports the bridge's selected-ID mapping, including
the site's hidden TextTrack mode. Native captions now stay within the fitted
video picture rather than the fullscreen letterbox.

## Playback verification limits

The earlier native fullscreen candidate opened and played in portrait and
landscape, but paused on return. Build 5 replaces that dismissal with an owned
native container and a visible glass return control, preserving the state sampled
before dismissal. It compiled cleanly. The strict build-5 attempt
`43739200828` stalled on the public provider's HLS startup before it reached
fullscreen, so a complete build-5 fullscreen round trip is **not recorded as
passed**.

TV Season 2 and its first episode played in build-5 run `43739203162`. That test
then matched both the underlying detail-screen episode button and the visible
player's button; it failed on ambiguity before switching episodes. The selector
is now scoped to the player panel in `19b35f2`, with no production source change.
The final live episode/provider check is run `43740628326`.

## Faster testing loop

Pushes build/upload the IPA without Simulator. Manual runs perform native QA.
`tools/Get-IPA.ps1` downloads as soon as the IPA artifact exists, verifies it and
writes `dist/Cinejoy-latest.ipa` for Sideloadly.

Measured fresh-Mac builds: the revised player in run `43736599976` compiled in
41 seconds and built/packaged in 50 seconds. Build 5 compiled in 45 seconds and
built/packaged in 53 seconds. Runner times vary; these are measurements, not a
latency guarantee. Codemagic compilation caching is configured but its warm-build
speed has not been measured in this pass.

Build 6 compiled in 54 seconds and built/packaged in 63 seconds. A parallel
Simulator first boot delayed a separate manual QA run's device stage by several
minutes; the default now starts Simulator only after uploading the IPA.
Build 7 compiled in 54 seconds and built/packaged in 67 seconds.
Build 8 compiled in 63 seconds and built/packaged in 75 seconds.

Native QA is separate because first-boot migration and test-runner preparation
can take several minutes. Focus branches isolate interface, fullscreen and TV
handoff checks; interface iterations finish after iPhone captures.

## Limits

No physical iPhone test or Sideloadly installation was performed by the agent.
Device smoothness, PiP (including its subtitles), lock-screen controls and
other subtitle languages/providers remain separate checks. Streaming and live catalog metadata
depend on the public website and provider availability. Simulator evidence does
not guarantee every title or network. No app account or AirPlay was added.
