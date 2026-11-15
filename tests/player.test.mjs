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

test('after native takeover the hidden website player stays paused, muted and silent', async () => {
  let tick;
  let plays = 0;
  let pauses = 0;
  let clicks = 0;
  const messages = [];
  const window = { webkit: { messageHandlers: { watch: { postMessage: value => messages.push(value) } } } };
  const video = {
    currentTime: 5, duration: 8000, readyState: 4, paused: false, muted: false,
    currentSrc: 'blob:https://cinejoy.pk/source-a',
    getAttribute() { return this.currentSrc; }, setAttribute() {},
    async play() { plays++; this.paused = false; },
    pause() { pauses++; this.paused = true; },
  };
  const source = readFileSync(new URL('../Resources/PlayerIntegration.js', import.meta.url), 'utf8')
    .replace('__RESUME_SECONDS__', '0');
  vm.runInNewContext(source, {
    document: {
      createElement: () => ({}), head: { append() {} }, addEventListener() {},
      querySelectorAll: () => [], querySelector: selector => selector === 'video' ? video : { click() { clicks++; } },
    },
    location: { pathname: '/watch/movie/27205' }, window,
    setInterval: fn => { tick = fn; }, HTMLVideoElement: Object, Date: { now: () => Date.now() + messages.length * 2000 },
  });
  window.__cinejoyNativeTakeover = true;
  tick();
  assert.equal(video.paused, true, 'a playing website element is paused once AVPlayer owns playback');
  assert.equal(video.muted, true);
  assert.equal(pauses, 1);
  assert.equal(plays, 0, 'never autoplays behind the native player');
  assert.equal(clicks, 0);
  assert.equal(messages.length, 0, 'no progress traffic from the hidden page');
  video.currentSrc = 'blob:https://cinejoy.pk/source-b';
  tick();
  assert.equal(plays, 0, 'a source change while taken over does not start the website element');
  // Provider controls hand the page back; the already-owned source is not auto-started.
  window.__cinejoyNativeTakeover = false;
  tick();
  await Promise.resolve();
  assert.equal(plays, 0, 'returning to provider controls leaves the website paused until the user plays');
  assert.equal(video.disableRemotePlayback, true);
  assert.equal(messages.length, 1, 'progress reporting resumes for the visible website player');
});

test('pending initial playback crosses only a small actual buffered-start gap once per source', () => {
  const script = readFileSync(new URL('../Resources/PlayerIntegration.js', import.meta.url), 'utf8')
    .replace('__RESUME_SECONDS__', '0');
  const setup = ({start, end = 3.8, ready = 1, current = 0, length = 1}) => {
    let tick;
    let clock = 1000;
    let plays = 0;
    const listeners = {};
    const messages = [];
    const range = {start, end, length};
    const video = {
      currentTime: current, duration: 8888, readyState: ready, paused: true,
      currentSrc: 'blob:https://cinejoy.pk/test-source',
      buffered: {get length() { return range.length; }, start: () => range.start, end: () => range.end},
      getAttribute() { return this.currentSrc; }, setAttribute() {},
      play() { plays++; this.paused = false; return new Promise(() => {}); },
    };
    vm.runInNewContext(script, {
      document: {
        visibilityState: 'visible', createElement: () => ({}), head: {append() {}},
        addEventListener: (name, fn) => { listeners[name] = fn; },
        querySelectorAll: () => [], querySelector: selector => selector === 'video' ? video : {click() {}},
      },
      window: {webkit: {messageHandlers: {watch: {postMessage: message => messages.push(message)}}}},
      location: {pathname: '/watch/movie/27205'}, HTMLVideoElement: Object,
      Date: {now: () => clock += 1001}, setInterval: fn => { tick = fn; },
    });
    return {tick: () => tick(), video, range, listeners, messages, plays: () => plays};
  };

  const gap = setup({start: 0.125125});
  gap.tick();
  assert.equal(gap.video.currentTime, 0.125125);
  assert.equal(gap.plays(), 1);
  assert.match(gap.messages[0].networkTrace, /range=0\.125125:3\.8 visibility=visible/);
  assert.equal(gap.messages[0].seconds, 0, 'report the actual clock before the real seek');
  gap.tick();
  assert.equal(gap.messages[1].seconds, 0.125125, 'report the actual clock after the seek');
  gap.video.currentTime = 0;
  gap.tick();
  assert.equal(gap.video.currentTime, 0, 'do not repeat the startup seek on the same source');
  gap.video.currentSrc = 'blob:https://cinejoy.pk/replacement-source';
  gap.tick();
  assert.equal(gap.video.currentTime, 0.125125, 'a new source gets its own initial-gap check');

  for (const settings of [
    {start: 0}, {start: 0.125125, length: 0}, {start: 3.1},
    {start: 0.125125, ready: 2}, {start: Infinity}, {start: 0.125125, end: 0},
    {start: 0.125125, current: 42},
  ]) {
    const run = setup(settings);
    run.tick();
    assert.equal(run.video.currentTime, settings.current || 0, JSON.stringify(settings));
  }

  const played = setup({start: 0});
  played.tick();
  played.listeners.playing({target: played.video});
  played.range.start = 0.5;
  played.tick();
  assert.equal(played.video.currentTime, 0, 'never normalize the clock after real playback began');
  const paused = setup({start: 0});
  paused.tick();
  paused.video.paused = true;
  paused.range.start = 0.5;
  paused.tick();
  assert.equal(paused.video.currentTime, 0, 'preserve a user pause while the initial request is pending');
  assert.equal(paused.plays(), 1);
});
