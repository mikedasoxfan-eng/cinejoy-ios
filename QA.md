# Native QA ledger

Target: iOS/iPadOS 26. Account-free app. AirPlay/casting disabled.

## Iteration 1 — actual iPhone Simulator captures

Inspected `dist/previews-first/home-dark.png`, `home-light.png`, and the larger-text
capture. Native device IPA and Simulator build succeeded. Found and corrected:

- Long featured-title text could exceed the screen because the artwork proposed
  an unconstrained width. Constrain artwork and text to the container geometry.
- The tint remained system blue. Bind the named adaptive green asset explicitly
  and configure it as the build's global accent.
- An empty tab accessory still drew a glass strip. Enable the resume accessory
  only when an unfinished viewing record exists, with an iOS 26.0 fallback.
- Prominent play labels need explicit contrasting ink on the adaptive accent.

## Iteration 2 — native navigation and persistence

The first XCUITest traversed Home, Browse, movie details, saving, Library and
Search successfully. It found that the system hides normal toolbar controls
while search is presented. End search presentation on submit and make the test
submit before opening Settings. Expanded verification to a full app relaunch.

The public site's season menu was also inspected live through REA. Options are
label + episode count; the adapter now selects the inner label, with a fixture
test. Real public-page extraction tests pass (six cases).

## Iterations 3–5 — contrast, large text and full flows

Reviewed the native iPhone screenshots for Browse, movie details, Saved Library,
Search, Settings, TV episodes and empty History, plus iPad Home. Verified the
refined Home captures in light mode and accessibility large text: the title is
visible, the buttons have contrasting labels, and the large-text actions stack
without splitting words. These are Simulator captures, not web mockups.

The expanded five-case UI run passed native navigation, saved-title persistence
across a full app relaunch, appearance selection and history deletion. It exposed
three failures: video remained paused at zero, a subsequent app launch could not
terminate that player session, and season 2 retained season 1 episodes. Those
failures are recorded rather than treated as successful playback.

The next revision starts ready video after the native Play action and exposes
actual elapsed time to accessibility. The test requires an advancing video clock
and resumed progress. It also closes the player during failure cleanup. New
history is created only after playback advances. Settings explicitly applies its
selected appearance to the presented sheet. Episode play overlays use dark glass
for contrast over light artwork. A live search now requests Arrival, which is
absent from the bundled catalog, so cached results cannot falsely pass that test.

The device archive audit also verifies the audio background mode, ARM64 iOS
platform, bundled resources, disabled casting, and lack of local-network usage.

## Current verification matrix

| Surface or feature | Required evidence |
|---|---|
| Home and live refresh | Native light/dark/large-text captures; real catalog adapter |
| Browse movies and TV | Native tab and grid captures |
| Movie detail | Artwork, overview, Play, Save, sharing controls |
| TV detail / seasons | Live episode read; native season picker switches to season 2 |
| Search | Native results, live query, and no-results state |
| Saved library | Save and verify after full relaunch |
| History / resume | Real playback generates local progress and a resume accessory |
| Settings | Native sheet, adaptive appearance, history deletion confirmation |
| Player | Real title reaches playback; close works; casting control absent |
| iPad | Native screenshot on an iPad Simulator |
| IPA | ARM64 Mach-O, minimum iOS version, resources, no local-network permission |

Later test output and screenshots determine the final statuses. A successful
compile does not establish successful streaming. Physical-device sideloading,
hardware decoding and picture-in-picture remain separate from Simulator QA.

Catalog and artwork originate in Cinejoy's public pages and TMDB. Fixtures and
the bundled snapshot contain public descriptive metadata, not user accounts,
API credentials, media files or stream-resolver results.
