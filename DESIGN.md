# Cinejoy for iOS

Platform: iOS 26 and iPadOS 26. SwiftUI. Native app chrome, not a reskinned site.

Direction: cinematic artwork with quiet system chrome. Cinejoy's green is the
single action tint. System semantic backgrounds, San Francisco Dynamic Type,
SF Symbols and Apple's actual Liquid Glass take precedence over the desktop
style sheet drawn by Pixelsmith. There is no custom glass approximation.

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

Verification: compile device and Simulator builds, inspect Simulator screenshots
in light, dark and accessibility text sizes. Hardware playback and sideloading
require an actual iOS 26 device. Do not describe browser previews as native QA.
