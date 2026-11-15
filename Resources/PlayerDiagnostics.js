(() => {
  // Test-only observation. Keep response status and hostname, never stream URLs,
  // query strings, response bodies, cookies, or authorization headers.
  const trace = [];
  const mediaHosts = new Set();
  window.__cinejoyMediaTrace = trace;
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
