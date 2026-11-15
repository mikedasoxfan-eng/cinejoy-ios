# Cinejoy for iOS 26

Native SwiftUI discovery, title details, episode lists, search and an on-device
library. Uses real iOS 26 Liquid Glass, a minimizing tab bar, a dedicated search
tab, glass playback controls and a resume accessory. No accounts or cloud library.

The native catalog reads Cinejoy's public rendered pages. Its existing public
player resolves the stream inside WebKit; playback then uses native AVKit through
a loopback-only HLS transport that corrects the provider's media MIME. The stream
resolver is not copied. A bundled
snapshot of 131 real titles provides immediate content while live data loads.
This is an independent personal-use client, not an official Cinejoy release.

Loaded subtitle cues transfer from the public player into native overlays. A
track selected through **Find subtitles** carries back to native playback;
fullscreen has its own Subtitles menu with an Off option.

## Build an IPA

On a Mac with Xcode 26 or newer:

```sh
brew install xcodegen
bash tools/build.sh
```

The output is `dist/Cinejoy-unsigned.ipa`. Re-sign it with your usual sideloading
tool, then install on iOS 26 or later. The source bundle identifier is
`local.cinejoy.glass`; your signing tool may replace it. No Apple signing identity
or provisioning profile is stored in this project.

Pushing to `main` runs the fast device-only path. A manual GitHub Actions run
also performs Simulator QA. The IPA uploads before Simulator starts, so it can
be downloaded immediately. The first measured fast run uploaded its IPA in
86 seconds after the push (59 seconds compiling, 71 seconds building and packaging).

On Windows, download the latest push build directly for Sideloadly:

```powershell
.\tools\Get-IPA.ps1
```

This waits only for the IPA artifact, verifies its device architecture and
resources, and writes `dist/Cinejoy-latest.ipa`. Drop that file into Sideloadly.
Use `-RunId <id>` to select a specific build. No signing credentials are handled
by the downloader.

On a persistent Mac, subsequent `bash tools/build.sh` calls reuse DerivedData,
unchanged source timestamps and the compiled HLS checks. The exact verified
favicon PNG is included in source, so code edits do not rerun its Swift renderer.
Codemagic's IPA workflow retains this cache between runs; GitHub's current
hosted workflow starts with a fresh Mac. `dist/build-metrics.json` and the build
log record actual compile and package times.

For parallel native review without changing workflow permissions, dispatch the
same workflow at a `qa/player*` branch for movie/fullscreen/TV checks, or a
`qa/interface*` branch for iPhone discovery, library, live search and appearance
captures. Both branches can point to the exact same app commit. Manual dispatch
at `main` runs the entire suite. On a Mac, `CINEJOY_QA_FOCUS=player` or
`CINEJOY_QA_FOCUS=interface` selects the same subsets.
`qa/fullscreen*` and `qa/handoff*` isolate fullscreen and episode switching.
Full manual QA also captures iPad; interface iterations finish after iPhone
captures so a second device's first boot does not delay visual review.
Simulator boot starts after the device IPA is uploaded. First-boot migration
contends with compilation on a fresh hosted Mac, so overlap is opt-in through
`CINEJOY_PREWARM_SIMULATOR=1`.

## Build with Codemagic

`codemagic.yaml` provides a separate macOS build route. Add this repository in
[Codemagic](https://codemagic.io/apps) and choose its YAML configuration:

- `ios-ipa` builds the unsigned iPhone IPA and its package-verification report.
- `ios-simulator-qa` also runs the native UI tests and exports iPhone/iPad captures.
- `ios-player-qa` isolates real movie playback, resume, and TV episode checks for faster diagnosis.

These workflows use an M2 Mac with Xcode 26.6 and start manually. Download
`Cinejoy-unsigned.ipa` from the build artifacts and re-sign it for your device.
Codemagic requires a service sign-in; this project supplies no Apple certificate
or App Store Connect credentials. The app itself remains account-free.

## Validate

```sh
npm ci
npm test
bash tools/preview.sh
```

The DOM-extraction tests use retained public-page HTML fixtures generated locally
from the REA captures; no account credentials are present. Simulator captures
cover light/dark appearance and accessibility text. Movie/TV playback, resume and history passed native Simulator checks. Physical
Picture in Picture and sideloading remain separate checks; see [QA.md](QA.md) for
the recorded provider timeouts and verification limits.
AirPlay and remote playback are disabled, and the casting control is removed.

## Data

- Local favorites and watch history: Application Support, `Cinejoy/library.json`.
- Appearance preference: UserDefaults.
- WebKit sessions: nonpersistent, separate from Safari and website accounts.
- Catalog artwork/metadata: TMDB through the public Cinejoy catalog.
- No app account, token, password, account migration or personal-state sync.

The catalog adapter depends on the public website's current markup. If Cinejoy
changes it, update `Resources/CatalogExtraction.js`. The app never embeds the
website's API key or account credentials.
