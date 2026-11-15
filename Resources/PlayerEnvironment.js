(() => {
  // The site's supported native-HLS fallback uses Apple's media pipeline.
  // Prefer it where available instead of its managed MediaSource path, which
  // stalled at metadata in iOS WebKit while playlists returned HTTP 200.
  const probe = document.createElement('video');
  if (!probe.canPlayType('application/vnd.apple.mpegurl')) return;
  for (const name of ['ManagedMediaSource', 'MediaSource']) {
    try { Object.defineProperty(window, name, {value: undefined, configurable: true}); } catch {}
  }
})();
