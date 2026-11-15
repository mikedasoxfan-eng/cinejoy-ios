# Cinejoy for iOS

Platform: iOS 26 and iPadOS 26. SwiftUI. Native app chrome, not a reskinned site.
Mode: Operate (a media app people browse and watch in). Familiar platform
patterns first; the brand lives in artwork, the green tint and Liquid Glass.

Direction: cinematic artwork with quiet system chrome. Cinejoy's green is the
single action tint. System semantic backgrounds, San Francisco Dynamic Type,
SF Symbols and Apple's actual Liquid Glass take precedence over the desktop
style sheet drawn by Pixelsmith. There is no custom glass approximation.
The app icon is Cinejoy's official favicon artwork (Resources/Brand); it is not
redrawn or altered.

The movie artwork becomes the browse surface; a glass resume accessory keeps the
last title one tap away. Home, Browse, Library and Search are native tabs. Search
uses the system search-tab role. Tab bars minimize on downward scrolling.
Toolbars, prominent play controls and small grouped actions use system glass.
Movie posters and content surfaces remain solid artwork. Native sheets,
context menus, sharing, swipe actions, haptics and navigation stay familiar.

No registration, profile, login or remote personal-state synchronization.
Saved titles and playback positions are persisted only in Application Support.
WebKit sessions are ephemeral. Playback uses the existing Cinejoy player;
browsing, discovery, details, seasons and library UI are SwiftUI.
AirPlay and remote playback are disabled; there is no casting control or local
network permission prompt.

Content is real captured catalog metadata plus live extraction from Cinejoy's
public pages. No TMDB key, account credential, resolver key or crypto protocol
is embedded. A bundled snapshot gives immediate useful content while the live
catalog loads. Cached data is not presented as live trending data.

## Layout decisions

- Margins are 20 pt on content and 16 pt around hero cards. The gap between posters is 12 pt.
- Posters are always 2:3 and sized by role: 124 pt on shelves, and 104–180 pt adaptive
  columns in grids (three across on iPhone). Titles reserve two lines so rows align.
- The Home hero is about half the visible height (300–420 pt). It uses real wide
  art when the catalog has it; posters are never stretched into a fake backdrop.
- A shelf header is a link to the whole shelf (title + chevron). Shelves show up to 20 titles.
- Detail: full-bleed art under the glass navigation bar, fading into the system
  background, with the poster and title overlapping it. When only a poster exists, the
  art is that poster, blurred into an ambient field. Play reads "Resume" (with the
  episode label) when local history has a position, and shows progress below.
- Continue watching is a 16:9 row with progress on the art. It reads history in its
  own view so playback updates never redraw Home.

## Player

- Portrait: a glass top bar (close, title + status, Full Screen, options), a 16:9
  AVKit stage, then a panel with Save, Subtitles and Servers, plus Up Next (the current
  season, with the playing episode marked) or the overview.
- Landscape: the picture uses the full height. Close, Full Screen, options and save
  move to a leading glass rail outside the video frame, so they never cover AVKit's
  controls.
- Full Screen is an always-visible glass control. AVKit's inline controls auto-hide,
  so they are not the only route. The control presents the system
  AVPlayerViewController modally on the same AVPlayer (public API; no new item, no
  seek). AVKit's own close control or swipe-down returns the player inline with its
  time and playing state. AVKit's inline fullscreen button keeps working too.
- Picture in Picture is first-class in both presentations. Captions are hosted in the
  content overlay of whichever controller shows the video, and only while a
  caption track is on.
- The hidden public page is never part of the interface: no touches, no
  accessibility elements, no focus, and it is hidden once AVPlayer is ready. It
  becomes visible and interactive only when the user opens Servers.
- Never put accessibility modifiers on the AVKit representable itself. The stage
  is a labelled container (`native-player-stage`) so AVKit's own controls stay
  exposed.
- Loading states name their real phase ("Finding a stream…", "Starting video…").
  After 12 s the state says the server is slow and offers another server. At 45 s
  it becomes an error with Try again and Choose another server.

## Performance rules

- Never construct WebKit views in a view initializer or `@State` default. The two
  hidden catalog readers belong to the catalog store. They block images, media and
  fonts, and their reads are coalesced, cancellable and cached (episodes on disk).
- Views read high-frequency playback values only in leaf views. History is
  checkpointed every 10 s, and exactly on close, pause and background. All disk writes
  happen off the main thread.
- Artwork goes through `ImagePipeline`: sized TMDB renditions, a disk cache,
  off-main downsampling and synchronous memory hits.
- Measurements: os_log/os_signpost subsystem `local.cinejoy.glass`, category
  `performance` (PageRead intervals, reader queueing, player phase timings).

Verification: compile device and Simulator builds, inspect Simulator screenshots
in light, dark and accessibility text sizes. Hardware playback, fullscreen,
Picture in Picture and sideloading require an actual iOS 26 device. Do not
describe browser previews as native QA.
