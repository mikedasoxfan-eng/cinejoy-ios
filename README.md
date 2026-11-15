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

The GitHub Actions workflow builds the same device IPA and captures Simulator
screenshots. Download the `Cinejoy-IPA` artifact from the successful run.

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
