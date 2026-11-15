import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

test('media engines remain available and the site cannot undo the no-AirPlay policy', () => {
  const source = readFileSync(new URL('../Resources/PlayerEnvironment.js', import.meta.url), 'utf8');
  for (const hasOrdinaryMse of [true, false]) {
    class Media {
      attributes = new Map();
      get disableRemotePlayback() { return this.attributes.has('disableremoteplayback'); }
      set disableRemotePlayback(value) {
        if (value) this.attributes.set('disableremoteplayback', '');
        else this.attributes.delete('disableremoteplayback');
      }
      removeAttribute(name) { this.attributes.delete(name.toLowerCase()); }
      canPlayType() { return 'maybe'; }
    }
    const MediaSource = hasOrdinaryMse ? class {} : undefined;
    const ManagedMediaSource = class {};
    const window = { MediaSource, ManagedMediaSource, HTMLMediaElement: Media };
    vm.runInNewContext(source, {window, document: {createElement: () => new Media()}});
    assert.equal(window.MediaSource, MediaSource);
    assert.equal(window.ManagedMediaSource, ManagedMediaSource, 'iPhone may expose only ManagedMediaSource');
    const video = new Media();
    video.disableRemotePlayback = true; // hls.js attaches MMS with remote playback disabled.
    video.removeAttribute('disableRemotePlayback'); // The site's mount handler attempts this.
    assert.equal(video.disableRemotePlayback, true);
    video.disableRemotePlayback = false;
    assert.equal(video.disableRemotePlayback, true);
    video.attributes.set('src', 'test');
    video.removeAttribute('src');
    assert.equal(video.attributes.has('src'), false, 'normal source cleanup remains available');
    assert.equal(window.__cinejoyPlayerEnvironment.mse, hasOrdinaryMse);
    assert.equal(window.__cinejoyPlayerEnvironment.mms, true);
    assert.equal(window.__cinejoyPlayerEnvironment.setterGuard, true);
    assert.equal(window.__cinejoyPlayerEnvironment.removalGuard, true);
  }
});

test('native Play starts metadata-only media, resumes progress and respects a later pause', async () => {
  let tick;
  let playCount = 0;
  let controlCount = 0;
  const messages = [];
  const video = {
    currentTime: 0, duration: 8000, readyState: 1, paused: true, currentSrc: '',
    getAttribute() { return this.currentSrc; },
    querySelector() { return this.sourceElement; },
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
    window: {
      __cinejoyPlayerEnvironment: {mse: false, mms: true, nativeHls: 'maybe', setterGuard: true, removalGuard: true},
      webkit: { messageHandlers: { watch: { postMessage: value => messages.push(value) } } },
    },
    setInterval: fn => { tick = fn; }, HTMLVideoElement: Object,
  });
  tick();
  assert.equal(playCount, 0, 'wait for an attached source');
  assert.equal(video.currentTime, 42);
  video.sourceElement = {src: 'blob:https://cinejoy.pk/test-source'};
  tick();
  await Promise.resolve();
  assert.equal(playCount, 1, 'start a managed source child without waiting for currentSrc or a decoded frame');
  assert.equal(controlCount, 1, 'enter through the website playback action as well as the media element');
  video.currentSrc = video.sourceElement.src;
  tick();
  assert.equal(playCount, 1, 'currentSrc adopting the source child does not start it twice');
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
  assert.match(messages[0].networkTrace, /mse=0 mms=1 .*guards=11 src=none/);
  assert.equal(messages[0].networkTrace.includes('https://'), false, 'capability diagnostics contain no stream URL');
});
