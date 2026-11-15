# Cinejoy iOS verification

The current device package is iOS 26+, version 1.0.0, build 5, from source
`d950205`, GitHub run `43739198707`. It is unsigned ARM64 for Sideloadly.
SHA-256: `83c79ba4af34fd62fc0d101ce4ab920c8f7242c784126d32fbbada30344ccff2`.
The official favicon PNG is unchanged byte for byte.

## Verified

- All 13 local behavioral Node checks pass: real catalog extraction, exact episode
  paths, caption cue export and bounds, public-master observation, no AirPlay,
  and keeping the hidden website player paused and silent during native playback.
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

Native QA is separate because first-boot migration and test-runner preparation
can take several minutes. Focus branches isolate interface, fullscreen and TV
handoff checks; interface iterations finish after iPhone captures.

## Limits

No physical iPhone test or Sideloadly installation was performed by the agent.
Device smoothness, PiP, lock-screen controls and selecting external subtitles on
specific providers remain hardware checks. Streaming and live catalog metadata
depend on the public website and provider availability. Simulator evidence does
not guarantee every title or network. No app account or AirPlay was added.
