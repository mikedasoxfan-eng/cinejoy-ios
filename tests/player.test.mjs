import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

test('native Play starts metadata-only media, resumes progress and respects a later pause', async () => {
  let tick;
  let playCount = 0;
  let controlCount = 0;
  const messages = [];
  const video = {
    currentTime: 0, duration: 8000, readyState: 1, paused: true, currentSrc: '',
    getAttribute() { return this.currentSrc; },
    setAttribute(name, value) { this[name] = value; },
    async play() { playCount++; this.paused = false; },
  };
  const document = {
    createElement: () => ({}), head: { append() {} }, addEventListener() {},
    querySelectorAll: () => [], querySelector: selector => selector === 'video' ? video : { click() { controlCount++; } },
  };
  const source = readFileSync(new URL('../Resources/PlayerIntegration.js', import.meta.url), 'utf8')
    .replace('__RESUME_SECONDS__', '42');
  vm.runInNewContext(source, {
    document, location: { pathname: '/watch/movie/27205' },
    window: { webkit: { messageHandlers: { watch: { postMessage: value => messages.push(value) } } } },
    setInterval: fn => { tick = fn; }, HTMLVideoElement: Object,
  });
  tick();
  assert.equal(playCount, 0, 'wait for an attached source');
  assert.equal(video.currentTime, 42);
  video.currentSrc = 'blob:https://cinejoy.pk/test-source';
  tick();
  await Promise.resolve();
  assert.equal(playCount, 1, 'metadata-only preload must start without waiting for a decoded frame');
  assert.equal(controlCount, 1, 'enter through the website playback action as well as the media element');
  video.paused = true;
  tick();
  assert.equal(playCount, 1, 'the polling bridge must not undo a user pause');
  assert.equal(controlCount, 1);
  video.currentSrc = 'blob:https://cinejoy.pk/replacement-source';
  tick();
  assert.equal(playCount, 2, 'a replacement server source can start on the existing video element');
  assert.equal(video.disableRemotePlayback, true);
  assert.equal(video['x-webkit-airplay'], 'deny');
  assert.equal(messages[0].seconds, 42);
  assert.equal(messages[0].path, '/watch/movie/27205');
});
