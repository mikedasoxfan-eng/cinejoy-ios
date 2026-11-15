import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

test('public master observer preserves requests and only forwards the allowed HTTPS provider', () => {
  const messages = [];
  const requests = [];
  class XHR {
    open(...args) { requests.push({receiver: this, args}); return 'opened'; }
  }
  const window = {
    webkit: { messageHandlers: { stream: { postMessage: url => messages.push(url) } } },
    fetch: (...args) => { requests.push({args}); return 'fetched'; },
  };
  vm.runInNewContext(readFileSync(new URL('../Resources/PlayerStreamObserver.js', import.meta.url), 'utf8'), {
    window, XMLHttpRequest: XHR, URL, location: { href: 'https://cinejoy.pk/watch/movie/27205' },
  });
  const publicMaster = 'https://lightspeed.st/public-fixture/master.m3u8?sample=1';
  const xhr = new XHR();
  assert.equal(xhr.open('GET', publicMaster, true), 'opened');
  assert.equal(requests[0].receiver, xhr);
  assert.deepEqual(requests[0].args, ['GET', publicMaster, true]);
  assert.equal(window.fetch(publicMaster), 'fetched');
  window.fetch({ url: 'https://cdn.lightspeed.st/another/master.m3u8' });
  window.fetch('http://lightspeed.st/master.m3u8');
  window.fetch('https://lightspeed.st.example.com/master.m3u8');
  window.fetch('https://example.com/master.m3u8');
  window.fetch('https://lightspeed.st/a/segment.m4s');
  assert.deepEqual(messages, [publicMaster, 'https://cdn.lightspeed.st/another/master.m3u8']);
});
