(() => {
  const absolute = value => { try { return new URL(value, location.origin).href; } catch { return ''; } };
  const artwork = img => absolute(img?.currentSrc || img?.src || img?.getAttribute('data-src') || '');
  const titleFrom = a => {
    const match = (a.getAttribute('href') || '').match(/^\/(movie|series)\/(\d+)(?:-|$)/);
    if (!match) return null;
    const heading = a.querySelector('h3,h2');
    const name = a.getAttribute('aria-label') || heading?.textContent?.trim() || a.querySelector('img')?.alt;
    if (!name) return null;
    const text = a.innerText || '';
    const year = text.match(/\b(19|20)\d{2}\b/)?.[0] || '';
    const rating = text.match(/\b\d\.\d\b/)?.[0] || '';
    const poster = artwork(a.querySelector('img'));
    return {tmdbID:Number(match[2]),kind:match[1]==='series'?'tv':'movie',name,year,poster,backdrop:poster.replace(/\/t\/p\/[^/]+\//,'/t/p/w780/'),overview:a.querySelector('p')?.textContent?.trim()||'',rating,path:a.getAttribute('href')};
  };
  const collect = node => {
    const seen = new Set();
    return [...node.querySelectorAll('a[href]')].map(titleFrom).filter(x=>x&&!seen.has(x.kind+':'+x.tmdbID)&&seen.add(x.kind+':'+x.tmdbID));
  };
  const titles = collect(document);
  const names = new Set();
  const shelves = [];
  for (const heading of document.querySelectorAll('h2')) {
    const name = heading.textContent.trim();
    if (!name || names.has(name)) continue;
    let root = heading.parentElement;
    let row = [];
    for(let depth=0;root&&depth<4;depth++,root=root.parentElement) {
      row=collect(root);
      if(row.length>=3)break;
    }
    if(row.length>=3&&row.length<titles.length) { names.add(name);shelves.push({name,titles:row}); }
  }
  if(!shelves.length&&titles.length)shelves.push({name:'Discover',titles});
  const episodes = [...document.querySelectorAll('a[href^="/watch/tv/"]')].map(a=>({
    name:a.querySelector('h3')?.textContent?.trim()||a.querySelector('img')?.alt||'Episode',
    number:a.getAttribute('href').split('/').at(-1),overview:a.querySelector('p')?.textContent?.trim()||'',
    image:artwork(a.querySelector('img')),path:a.getAttribute('href')
  }));
  const count=Number(document.body.innerText.match(/Seasons\s+(\d+)/)?.[1]||0);
  const seasons=count>0&&count<=100?Array.from({length:count},(_,i)=>i+1):[...new Set([...document.querySelectorAll('button')].map(b=>b.textContent.trim().match(/^Season (\d+)$/)?.[1]).filter(Boolean).map(Number))];
  return JSON.stringify({titles,shelves,episodes,seasons});
})();
