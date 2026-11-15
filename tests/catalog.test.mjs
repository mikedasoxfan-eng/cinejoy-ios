import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { gunzipSync } from 'node:zlib';
import vm from 'node:vm';
import { parseHTML } from 'linkedom';

const source = readFileSync(new URL('../Resources/CatalogExtraction.js', import.meta.url), 'utf8');
const extract = (html, pathname = '/') => {
  const { document } = parseHTML(html);
  return JSON.parse(vm.runInNewContext(source, {
    document, location: { origin: 'https://cinejoy.pk', pathname }, URL,
  }));
};

test('real captured home produces named shelves and deduplicated movie/TV titles', () => {
  const html = gunzipSync(readFileSync(new URL('fixtures/home.html.gz', import.meta.url))).toString('utf8');
  const page = extract(html);
  assert.ok(page.titles.length > 50, `received ${page.titles.length} titles`);
  assert.ok(page.shelves.length > 3, `received ${page.shelves.length} shelves`);
  assert.equal(new Set(page.titles.map(x => `${x.kind}:${x.tmdbID}`)).size, page.titles.length);
  assert.ok(page.titles.some(x => x.name === 'Inception' && x.tmdbID === 27205));
  assert.ok(page.titles.some(x => x.kind === 'tv'));
  for (const title of page.titles) {
    assert.ok(title.path.startsWith(title.kind === 'tv' ? '/series/' : '/movie/'));
    assert.ok(title.poster.startsWith('https://'));
  }
});

test('movie detail recommendations do not become TV episodes', () => {
  const html = gunzipSync(readFileSync(new URL('fixtures/movie.html.gz', import.meta.url))).toString('utf8');
  const page = extract(html, '/movie/27205-inception-2010');
  assert.equal(page.episodes.length, 0);
  assert.ok(page.titles.length > 5);
});

test('episode links retain exact season/episode paths and descriptions', () => {
  const page = extract('<html><body><div>Seasons 5</div><a href="/watch/tv/1396/2/3"><img src="https://image.tmdb.org/t/p/w300/a.jpg" alt="Bit by a Dead Bee"><h3>Bit by a Dead Bee</h3><p>Walt and Jesse face the aftermath.</p></a></body></html>');
  assert.deepEqual(page.seasons, [1, 2, 3, 4, 5]);
  assert.equal(page.episodes[0].path, '/watch/tv/1396/2/3');
  assert.equal(page.episodes[0].number, '3');
  assert.equal(page.episodes[0].name, 'Bit by a Dead Bee');
});

test('public-list, account and provider links never become titles', () => {
  const page = extract('<html><body><a href="/list/example">A list</a><a href="/settings">Settings</a><a href="/provider/8">Netflix</a></body></html>');
  assert.deepEqual(page.titles, []);
});

test('bundled catalog has real usable data and no credentials or resolver URLs', () => {
  const text = readFileSync(new URL('../Resources/CatalogSeed.json', import.meta.url), 'utf8');
  const page = JSON.parse(text);
  assert.ok(page.shelves.length >= 4);
  assert.ok(page.shelves.flatMap(x => x.titles).length >= 100);
  assert.doesNotMatch(text, /api_key|cinejoy_token|Bearer |master\.m3u8|\/g\?/);
});
