import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../Resources/NativeCaptionObserver.js', import.meta.url), 'utf8');
function observe(tracks, elements = []) {
  const messages = [];
  const listEvents = {};
  const documentEvents = {};
  let pending;
  let clock = 10_000;
  tracks.addEventListener = (name, action) => { listEvents[name] = action; };
  tracks.removeEventListener = () => {};
  const window = {webkit: {messageHandlers: {captions: {postMessage: value => messages.push(JSON.parse(JSON.stringify(value)))}}}};
  vm.runInNewContext(source, {
    window,
    document: {querySelector: () => ({textTracks: tracks, querySelectorAll: () => elements}), addEventListener: (name, action) => { documentEvents[name] = action; }},
    MutationObserver: class {observe() {}}, TextEncoder,
    Date: {now: () => clock}, setTimeout: action => { pending = action; return 1; }, setInterval() {},
  });
  const flush = () => { const action = pending; pending = undefined; clock += 1000; action?.(); };
  flush();
  return {messages, flush, refresh: () => JSON.parse(JSON.stringify(window.__cinejoyRefreshCaptions())), change: () => listEvents.change(), load: () => documentEvents.load({target: {tagName: 'TRACK'}})};
}

test('hands the provider choice back even with hidden tracks, unchanged cues, or captions Off', () => {
  const first = {kind: 'captions', label: 'English', mode: 'hidden', cues: [{startTime: 1, endTime: 3, text: 'First'}]};
  const second = {kind: 'captions', label: 'French', mode: 'hidden', cues: [{startTime: 1, endTime: 3, text: 'Second'}]};
  const elements = [{default: true, track: first}, {default: false, track: second}];
  const observer = observe([first, second], elements);
  const original = observer.messages[0];
  assert.equal(original.selectedID, original.tracks[0].id);
  elements[0].default = false; elements[1].default = true;
  const changed = observer.refresh();
  assert.equal(changed.selectedID, original.tracks[1].id);
  assert.deepEqual(changed.tracks, original.tracks, 'selection changes need no cue reload');
  elements[1].default = false;
  assert.equal(observer.refresh().selectedID, null, 'Off is explicit rather than selecting the first loaded track');
  first.mode = 'showing';
  assert.equal(observer.refresh().selectedID, original.tracks[0].id, 'in-band showing tracks also hand back their choice');
  assert.equal(observer.refresh().selectedID, original.tracks[0].id, 'explicit return works even when no message changed');
});

test('exports loaded ordinary TextTrack cues, labels and language without source URLs', () => {
  const loaded = {
    kind: 'captions', label: 'English', language: 'en', mode: 'hidden',
    src: 'https://private.example/caption?token=private-token',
    cues: [{startTime: 4, endTime: 6, text: '<i>Second line</i>'}, {startTime: 1, endTime: 3, text: 'First line'}],
  };
  const tracks = [loaded, {kind: 'subtitles', label: 'Not loaded', cues: null},
    {kind: 'metadata', label: 'Not captions', cues: [{startTime: 0, endTime: 100, text: 'metadata'}]}];
  const observer = observe(tracks);
  assert.equal(observer.messages.length, 1);
  const message = observer.messages[0];
  assert.equal(message.tracks.length, 1);
  assert.equal(message.tracks[0].label, 'English');
  assert.equal(message.tracks[0].language, 'en');
  assert.deepEqual(message.tracks[0].cues, [{start: 1, end: 3, text: 'First line'}, {start: 4, end: 6, text: '<i>Second line</i>'}]);
  assert.equal(JSON.stringify(message).includes('private-token'), false);
  assert.equal(JSON.stringify(message).includes('https://'), false);
  assert.equal(loaded.mode, 'hidden', 'observation must not change selected/loading modes');
  observer.change(); observer.flush();
  assert.equal(observer.messages.length, 1, 'unchanged loaded cues are not resent');
  loaded.cues.push({startTime: 7, endTime: 8, text: 'Newly loaded'});
  observer.load(); observer.flush();
  assert.equal(observer.messages[1].tracks[0].id, message.tracks[0].id, 'track identity survives cue updates');
  tracks.splice(0);
  observer.change(); observer.flush();
  assert.deepEqual(observer.messages.at(-1).tracks, [], 'removing the video tracks clears native captions');
});

test('limits total cues and UTF-8 message size while ignoring invalid/unloaded cues', () => {
  for (const text of ['x', '界🙂'.repeat(100)]) {
    const tracks = [{kind: 'subtitles', label: 'Loaded', language: 'en',
      cues: Array.from({length: 20_001}, (_, i) => ({startTime: i, endTime: i + 1, text}))}];
    const message = observe(tracks).messages[0];
    assert.equal(message.truncated, true);
    assert.ok(message.tracks.reduce((sum, track) => sum + track.cues.length, 0) <= 20_000);
    assert.ok(Buffer.byteLength(JSON.stringify(message), 'utf8') <= 1_000_000);
  }
  const message = observe([{kind: 'captions', label: 'Invalid', cues: [
    {startTime: NaN, endTime: 1, text: 'bad'}, {startTime: 2, endTime: 1, text: 'bad'},
    {startTime: -1, endTime: 1, text: 'bad'}, {startTime: 0, endTime: 1, text: '   '},
  ]}]).messages[0];
  assert.deepEqual(message.tracks, []);
});
