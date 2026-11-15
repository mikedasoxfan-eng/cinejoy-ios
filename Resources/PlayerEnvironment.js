(() => {
  // Keep the site's hls.js pipeline: its media fragments are served as image/png,
  // and the native-HLS fallback rejected the source in WebKit. hls.js enables
  // disableRemotePlayback before attaching ManagedMediaSource, but the site's
  // mount handler removes that attribute again. Enforce our no-AirPlay policy
  // before either handler runs, rather than repairing it on the polling timer.
  const Media = window.HTMLMediaElement;
  const state = {
    mse: typeof window.MediaSource === 'function',
    mms: typeof window.ManagedMediaSource === 'function',
    webkitMse: typeof window.WebKitMediaSource === 'function',
    setterGuard: false,
    removalGuard: false,
  };
  if (Media) {
    let owner = Media.prototype;
    let descriptor;
    while (owner && !(descriptor = Object.getOwnPropertyDescriptor(owner, 'disableRemotePlayback'))) {
      owner = Object.getPrototypeOf(owner);
    }
    if (descriptor?.get && descriptor?.set) {
      try {
        Object.defineProperty(Media.prototype, 'disableRemotePlayback', {
          configurable: true,
          enumerable: descriptor.enumerable,
          get: descriptor.get,
          set() { descriptor.set.call(this, true); },
        });
        state.setterGuard = true;
      } catch {}
    }
    const removeAttribute = Media.prototype.removeAttribute;
    if (typeof removeAttribute === 'function') {
      try {
        Media.prototype.removeAttribute = function(name) {
          if (String(name).toLowerCase() === 'disableremoteplayback') {
            this.disableRemotePlayback = true;
            return;
          }
          return removeAttribute.call(this, name);
        };
        state.removalGuard = true;
      } catch {}
    }
  }
  const probe = document.createElement('video');
  state.nativeHls = probe.canPlayType('application/vnd.apple.mpegurl') || 'no';
  window.__cinejoyPlayerEnvironment = state;
})();
