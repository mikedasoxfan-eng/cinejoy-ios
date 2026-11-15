(() => {
  // Test-only observation. Keep response status and hostname, never stream URLs,
  // query strings, response bodies, cookies, or authorization headers.
  const trace = [];
  const mediaHosts = new Set();
  const mediaSources = new Map();
  window.__cinejoyMediaTrace = trace;
  // Associate the blob source with its MediaSource object without exposing URLs.
  const nativeCreateObjectURL = URL.createObjectURL;
  if (typeof nativeCreateObjectURL === 'function') {
    URL.createObjectURL = function(object) {
      const url = nativeCreateObjectURL.call(this, object);
      if (object && typeof object === 'object' && 'sourceBuffers' in object) mediaSources.set(url, object);
      return url;
    };
  }
  const nativeRevokeObjectURL = URL.revokeObjectURL;
  if (typeof nativeRevokeObjectURL === 'function') {
    URL.revokeObjectURL = function(url) {
      mediaSources.delete(url);
      return nativeRevokeObjectURL.call(this, url);
    };
  }
  window.__cinejoyPlayerDebug = video => {
    const values = [`t=${video.currentTime}`, `seek=${+!!video.seeking}`, `paused=${+!!video.paused}`,
      `decoded=${video.videoWidth || 0}x${video.videoHeight || 0}`, `preload=${video.preload}`, `inline=${+!!video.playsInline}`];
    try {
      const rect = video.getBoundingClientRect();
      const css = getComputedStyle(video);
      values.push(`rect=${rect.x},${rect.y},${rect.width},${rect.height}`, `css=${css.display}/${css.visibility}/${css.opacity}`);
    } catch {}
    const source = video.currentSrc || video.getAttribute('src') || video.querySelector('source')?.src;
    const media = mediaSources.get(source);
    if (media) {
      try {
        values.push(`ms=${media.readyState}`, `streaming=${String(media.streaming)}`, `sb=${media.sourceBuffers.length}`);
        for (let i = 0; i < Math.min(media.sourceBuffers.length, 4); i++) {
          const buffer = media.sourceBuffers[i];
          const ranges = [];
          for (let r = 0; r < Math.min(buffer.buffered.length, 2); r++) ranges.push(`${buffer.buffered.start(r)}:${buffer.buffered.end(r)}`);
          values.push(`sb${i}=${ranges.join(',') || 'none'}/up${+!!buffer.updating}/offset${buffer.timestampOffset}`);
        }
      } catch {}
    }
    return values.join(' ');
  };
  const observe = (url, status, type = '') => {
    try {
      const parsed = new URL(url, location.href);
      const playlist = /\.m3u8(?:$|\?)/i.test(parsed.pathname + parsed.search);
      if (playlist) mediaHosts.add(parsed.hostname);
      if (!playlist && !mediaHosts.has(parsed.hostname) &&
          !/^(video\/|audio\/|application\/(?:vnd\.apple\.mpegurl|x-mpegurl))/i.test(type)) return;
      trace.push(`${parsed.hostname}:${status}:${type.split(';')[0]}`);
      if (trace.length > 8) trace.shift();
    } catch {}
  };
  const nativeOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url, ...rest) {
    this.addEventListener('loadend', () => observe(url, this.status, this.getResponseHeader('content-type') || ''), {once: true});
    return nativeOpen.call(this, method, url, ...rest);
  };
  const nativeFetch = window.fetch;
  window.fetch = async (...args) => {
    const response = await nativeFetch(...args);
    observe(response.url, response.status, response.headers.get('content-type') || '');
    return response;
  };
})();
