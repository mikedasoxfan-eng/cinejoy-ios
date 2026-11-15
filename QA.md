# Verification of the delivered IPA

The current IPA is build 2 from source `911766e`, built by GitHub run
`43729958578`. It replaces the icon with Cinejoy's official favicon artwork.
The 1024px opaque preview was inspected and the compiled iPhone/iPad icons were
confirmed changed. Native playback Swift sources remain identical to the tested
`cb69a8a` candidate from successful Simulator run `43726453372`. Functional tests
were not repeated for this icon-only update.

## Passed

- Eleven local Node regression checks for real catalog extraction, episode paths,
  no-AirPlay policy, public master observation and loaded-caption cue handling.
- Swift HLS parsing, MIME correction and range checks on the Mac runner.
- ARM64 device build, iOS 26 minimum, packaged resources, background audio,
  narrowly scoped loopback transport, no local-network permission and unsigned IPA.
- Both focused native Simulator tests passed with zero failures: movie playback
  advanced, landscape controls were usable, progress resumed from the saved
  position, history was cleared with confirmation, Season 2 loaded correctly,
  and the selected TV episode really played. AVPlayer external playback was false.
- Codemagic native run `6af9c78c90e83b09c4fa9acd` passed Home capture,
  browsing/sharing/save persistence, real Arrival search/no-results, and appearance.
  Its native iPad Home capture also exported without the setup banner.

## Limits retained for review

Movie and TV streaming timed out on Codemagic's runner while the same native
playback flow passed on GitHub's Simulator. The cause of that difference has not
been isolated. The delivered IPA retains that tested native playback implementation. Streaming remains
dependent on the public website and provider availability.

Native quality caps, provider controls and loaded-caption rendering are included;
external subtitle selection and Picture in Picture have not been verified on a
physical iPhone. Re-signing/install is left to the user's sideloading tool.

The screenshot gallery contains actual, unchanged Simulator PNGs. Landscape
captures use the whole display rather than the app-element crop. Simulator QA
is bounded evidence, not a guarantee for every upstream title or network.
