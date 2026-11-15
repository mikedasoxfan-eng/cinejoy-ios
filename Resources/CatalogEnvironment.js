(() => {
  // These are the site's observed menu-layout queries. Catalog reading uses a
  // fixed desktop viewport, including on touch devices, to avoid the animated
  // phone wheel in a backing WebKit view. Other media queries retain their values.
  const menuQueries = new Map([
    ['(min-width: 1024px) and (hover: hover) and (pointer: fine)', true],
    ['(hover: none) and (pointer: coarse), (max-width: 640px)', false],
  ]);
  const nativeMatchMedia = window.matchMedia.bind(window);
  window.matchMedia = query => {
    const result = nativeMatchMedia(query);
    if (menuQueries.has(query)) Object.defineProperty(result, 'matches', { value: menuQueries.get(query) });
    return result;
  };
  document.addEventListener('DOMContentLoaded', () => {
    const style = document.createElement('style');
    style.textContent = '[role=dialog][aria-labelledby=notice-title]{display:none!important}';
    document.head.append(style);
  });
})();
