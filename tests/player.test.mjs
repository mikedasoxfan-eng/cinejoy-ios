import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

test('native Play starts ready media once, resumes progress and respects a later pause', async () => {
  let tick;
  let playCount = 0;
  const messages = [];
  const video = {
    currentTime: 0, duration: 8000, readyState: 1, paused: true,
    setAttribute(name, value) { this[name] = value; },
    async play() { playCount++; this.paused = false; },
  };
  const document = {
    createElement: () => ({}), head: { append() {} }, addEventListener() {},
    querySelectorAll: () => [], querySelector: () => video,
  };
  const source = readFileSync(new URL('../Resources/PlayerIntegration.js', import.meta.url), 'utf8')
    .replace('__RESUME_SECONDS__', '42');
  vm.runInNewContext(source, {
    document, location: { pathname: '/watch/movie/27205' },
    window: { webkit: { messageHandlers: { watch: { postMessage: value => messages.push(value) } } } },
    setInterval: fn => { tick = fn; }, HTMLVideoElement: Object,
  });
  tick();
  assert.equal(playCount, 0, 'wait for playable data');
  assert.equal(video.currentTime, 42);
  video.readyState = 2;
  tick();
  await Promise.resolve();
  assert.equal(playCount, 1, 'start after native Play');
  video.paused = true;
  tick();
  assert.equal(playCount, 1, 'the polling bridge must not undo a user pause');
  assert.equal(video.disableRemotePlayback, true);
  assert.equal(video['x-webkit-airplay'], 'deny');
  assert.equal(messages[0].seconds, 42);
  assert.equal(messages[0].path, '/watch/movie/27205');
});
