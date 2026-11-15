(() => {
  const MAX_BYTES = 1_000_000;
  const MAX_CUES = 20_000;
  const identities = new WeakMap();
  const encoder = new TextEncoder();
  let nextID = 1;
  let lastPayload = '';
  let lastScan = 0;
  let timer;
  let observedTracks;
  const bytes = value => encoder.encode(JSON.stringify(value)).byteLength;
  const identity = track => {
    if (!identities.has(track)) identities.set(track, `caption-${nextID++}`);
    return identities.get(track);
  };
  const scan = () => {
    timer = undefined;
    lastScan = Date.now();
    const video = document.querySelector('video');
    const tracks = video?.textTracks;
    if (tracks && tracks !== observedTracks) {
      for (const event of ['addtrack', 'removetrack', 'change']) observedTracks?.removeEventListener?.(event, schedule);
      observedTracks = tracks;
      for (const event of ['addtrack', 'removetrack', 'change']) tracks.addEventListener?.(event, schedule);
    }
    // Cinejoy marks its chosen external <track> as default, even when the
    // website draws the cues itself and all TextTracks have hidden mode.
    const selectedElement = Array.from(video?.querySelectorAll?.('track') || []).find(element => element.default);
    const selectedTrack = selectedElement?.track || Array.from(tracks || []).find(track => track.mode === 'showing');
    const message = {tracks: [], selectedID: selectedTrack ? identity(selectedTrack) : null, truncated: false};
    let allocation = 128;
    let cueCount = 0;
    for (const track of Array.from(tracks || [])) {
      if (track.kind !== 'captions' && track.kind !== 'subtitles') continue;
      let loaded;
      try { loaded = track.cues; } catch { continue; }
      if (!loaded?.length) continue;
      const record = {
        id: identity(track),
        label: String(track.label || track.language || 'Subtitles').slice(0, 256),
        language: String(track.language || '').slice(0, 64),
        cues: [],
      };
      const overhead = bytes(record) + 2;
      if (allocation + overhead > MAX_BYTES || cueCount >= MAX_CUES) { message.truncated = true; break; }
      allocation += overhead;
      for (const cue of Array.from(loaded)) {
        const start = Number(cue.startTime);
        const end = Number(cue.endTime);
        const text = typeof cue.text === 'string' ? cue.text : '';
        if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || end <= start || !text.trim()) continue;
        const value = {start, end, text};
        const cost = bytes(value) + 1;
        if (cueCount >= MAX_CUES || allocation + cost > MAX_BYTES) { message.truncated = true; break; }
        record.cues.push(value);
        allocation += cost;
        cueCount++;
      }
      if (record.cues.length) {
        record.cues.sort((a, b) => a.start - b.start || a.end - b.end);
        message.tracks.push(record);
      }
      if (message.truncated) break;
    }
    const payload = JSON.stringify(message);
    if (payload !== lastPayload && encoder.encode(payload).byteLength <= MAX_BYTES) {
      try {
        const handler = window.webkit?.messageHandlers?.captions;
        if (!handler) return message;
        handler.postMessage(message);
        lastPayload = payload;
      } catch {}
    }
    return message;
  };
  function schedule() {
    if (timer !== undefined) return;
    timer = setTimeout(scan, Math.max(0, 1000 - (Date.now() - lastScan)));
  }
  // The site loads selected external SRT/VTT into ordinary hidden TextTracks.
  // Observe those already-loaded cues; never refetch a caption URL or alter mode.
  document.addEventListener('load', event => {
    if (event.target?.tagName === 'TRACK') schedule();
  }, true);
  const observer = new MutationObserver(records => {
    if (records.some(record => record.target?.matches?.('track,video') ||
        Array.from(record.addedNodes || []).some(node => node.matches?.('track,video') || node.querySelector?.('track,video')))) schedule();
  });
  observer.observe(document, {subtree: true, childList: true, attributes: true, attributeFilter: ['src', 'label', 'srclang', 'default']});
  setInterval(schedule, 1000);
  // Returning from the provider picker explicitly flushes its current choice.
  window.__cinejoyRefreshCaptions = scan;
  schedule();
})();
