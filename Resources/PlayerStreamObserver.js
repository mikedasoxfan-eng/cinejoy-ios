(() => {
  // Observe the public HLS master requested by the site's own player. Resolver
  // code, keys and account state remain inside the original website.
  const seen = new Set();
  const observe = value => {
    try {
      const url = new URL(String(value), location.href);
      const host = url.hostname.toLowerCase();
      if (url.protocol !== 'https:' || !(host === 'lightspeed.st' || host.endsWith('.lightspeed.st')) ||
          !/(?:^|\/)master\.m3u8$/i.test(url.pathname) || seen.has(url.href)) return;
      seen.add(url.href);
      window.webkit.messageHandlers.stream.postMessage(url.href);
    } catch {}
  };
  const open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url, ...rest) {
    observe(url);
    return Reflect.apply(open, this, [method, url, ...rest]);
  };
  const fetch = window.fetch;
  window.fetch = function(input, ...rest) {
    observe(typeof input === 'string' || input instanceof URL ? input : input?.url);
    return Reflect.apply(fetch, this, [input, ...rest]);
  };
})();
