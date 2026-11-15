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
    currentTime: 0, duration: 8000, readyState: 1, paused: true, currentSrc: '', preload: 'metadata',
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
  let clock = 1000;
  vm.runInNewContext(source, {
    document, location: { pathname: '/watch/movie/27205' },
    window: {
      __cinejoyPlayerEnvironment: {mse: false, mms: true, nativeHls: 'maybe', setterGuard: true, removalGuard: true},
      webkit: { messageHandlers: { watch: { postMessage: value => messages.push(value) } } },
    },
    Date: {now: () => clock += 1001},
    setInterval: fn => { tick = fn; }, HTMLVideoElement: Object,
  });
  tick();
  assert.equal(playCount, 0, 'wait for an attached source');
  assert.equal(video.preload, 'metadata', 'leave the unattached template alone');
  assert.equal(video.currentTime, 0, 'metadata readiness must not seek the managed source');
  video.sourceElement = {src: 'blob:https://cinejoy.pk/test-source'};
  tick();
  await Promise.resolve();
  assert.equal(playCount, 1, 'start a managed source child without waiting for currentSrc or a decoded frame');
  assert.equal(video.preload, 'auto', 'request media rather than metadata before the first play');
  assert.equal(controlCount, 1, 'enter through the website playback action as well as the media element');
  assert.equal(video.currentTime, 0, 'starting playback still defers the saved seek until decoded data');
  video.currentSrc = video.sourceElement.src;
  tick();
  assert.equal(playCount, 1, 'currentSrc adopting the source child does not start it twice');
  assert.equal(video.currentTime, 0);
  const metadataReport = messages.at(-1);
  assert.equal(metadataReport.readyState, 1);
  assert.equal(metadataReport.paused, false);
  assert.equal(metadataReport.seconds, 0, 'metadata reports remain truthful and native UI can show Buffering');
  video.readyState = 2;
  tick();
  assert.equal(video.currentTime, 42, 'apply the saved seek once a decoded frame is available');
  assert.equal(messages.at(-1).seconds, 42, 'the first decoded report contains the actual resumed clock');
  video.currentTime = 50;
  tick();
  assert.equal(video.currentTime, 50, 'do not reapply the saved position after playback progresses');
  video.paused = true;
  tick();
  assert.equal(playCount, 1, 'the polling bridge must not undo a user pause');
  assert.equal(controlCount, 1);
  video.currentSrc = 'blob:https://cinejoy.pk/replacement-source';
  tick();
  assert.equal(playCount, 2, 'a replacement server source can start on the existing video element');
  assert.equal(video.disableRemotePlayback, true);
  assert.equal(video['x-webkit-airplay'], 'deny');
  assert.equal(messages[0].seconds, 0, 'do not report the saved position before it was really applied');
  assert.equal(messages[0].path, '/watch/movie/27205');
  assert.match(messages[0].networkTrace, /mse=0 mms=1 .*guards=11 src=none/);
  assert.equal(messages[0].networkTrace.includes('https://'), false, 'capability diagnostics contain no stream URL');
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

test('test-only diagnostics observe layout and managed buffers without exposing blob URLs', () => {
  const source = readFileSync(new URL('../Resources/PlayerDiagnostics.js', import.meta.url), 'utf8');
  const privateURL = 'blob:https://cinejoy.pk/private-source-token';
  const media = {readyState: 'open', streaming: true, sourceBuffers: [{
    updating: false, timestampOffset: 0,
    buffered: {length: 1, start: () => 0.125125, end: () => 4.010666666666666},
  }]};
  const urlAPI = {
    createObjectURL(object) { assert.equal(object, media); return privateURL; },
    revokeObjectURL(url) { assert.equal(url, privateURL); return 'revoked'; },
  };
  class Request { open() {} }
  const window = {};
  vm.runInNewContext(source, {
    window, URL: urlAPI, XMLHttpRequest: Request,
    getComputedStyle: () => ({display: 'block', visibility: 'visible', opacity: '1'}),
  });
  const url = urlAPI.createObjectURL(media);
  const video = {
    currentSrc: url, currentTime: 0.125125, seeking: true, paused: false,
    videoWidth: 640, videoHeight: 360, preload: 'metadata', playsInline: true,
    getBoundingClientRect: () => ({x: 0, y: 0, width: 844, height: 390}),
  };
  const snapshot = window.__cinejoyPlayerDebug(video);
  assert.match(snapshot, /t=0\.125125 seek=1 paused=0 decoded=640x360 preload=metadata inline=1/);
  assert.match(snapshot, /rect=0,0,844,390 css=block\/visible\/1/);
  assert.match(snapshot, /ms=open streaming=true sb=1 sb0=0\.125125:4\.010666666666666\/up0\/offset0/);
  assert.equal(snapshot.includes('private-source-token'), false);
  assert.equal(snapshot.includes('blob:'), false);
  assert.equal(urlAPI.revokeObjectURL(url), 'revoked');
  assert.equal(window.__cinejoyPlayerDebug(video).includes('ms=open'), false);
});
