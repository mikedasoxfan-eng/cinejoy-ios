(() => {
  let lastReport = 0;
  let resumed = false;
  let playFailure = '';
  const started = new WeakMap();
  const startupSources = new WeakMap();
  const resumeAt = __RESUME_SECONDS__;
  const style = document.createElement('style');
  style.textContent = 'html,body{background:#000!important}button[aria-label="Back"]{visibility:hidden!important}button[aria-label="Cast to Device"],button[aria-label^="View details for "],a[href^="/settings"],a[href^="/auth"]{display:none!important}';
  document.head.append(style);
  const sourceOf = video => video.currentSrc || video.getAttribute('src') || video.querySelector?.('source')?.src || '';
  const startupFor = (video, source) => {
    let sources = startupSources.get(video);
    if (!sources) startupSources.set(video, sources = new Map());
    if (!sources.has(source)) sources.set(source, {played: false, adjusted: false});
    return sources.get(source);
  };
  const bridgeStartupGap = (video, source) => {
    if (!source || video.paused || video.readyState >= 2) return;
    const startup = startupFor(video, source);
    if (startup.played || startup.adjusted) return;
    try {
      if (!video.buffered?.length) return;
      const start = video.buffered.start(0);
      const end = video.buffered.end(0);
      const gap = start - video.currentTime;
      // Some fMP4 video tracks begin after time zero. Seek only across a real,
      // small initial hole while the first play request is awaiting media.
      if (Number.isFinite(start) && Number.isFinite(end) && Number.isFinite(gap) &&
          gap > 0 && gap <= 3 && end > start) {
        video.currentTime = start;
        startup.adjusted = true;
      }
    } catch {}
  };
  const mediaSnapshot = video => {
    const env = window.__cinejoyPlayerEnvironment || {};
    const source = sourceOf(video);
    // Report only source kind and capabilities. Stream URLs remain private.
    const kind = source.startsWith('blob:') ? 'blob' : source.startsWith('https:') ? 'https' : source ? 'other' : 'none';
    let buffer = 0;
    let range = 'none';
    try {
      if (video.buffered?.length) {
        buffer = Math.max(0, video.buffered.end(video.buffered.length - 1) - video.currentTime);
        range = `${video.buffered.start(0)}:${video.buffered.end(0)}`;
      }
    } catch {}
    let testSnapshot = '';
    try { testSnapshot = window.__cinejoyPlayerDebug?.(video) || ''; } catch {}
    return `mse=${+!!env.mse} mms=${+!!env.mms} wkMse=${+!!env.webkitMse} native=${env.nativeHls || '?'} guards=${+!!env.setterGuard}${+!!env.removalGuard} src=${kind} remoteOff=${+!!video.disableRemotePlayback} buffered=${buffer.toFixed(1)} range=${range} visibility=${document.visibilityState || '?'} ${testSnapshot}`;
  };
  const report = video => {
    const seconds=Number.isFinite(video.currentTime)?video.currentTime:0;
    const duration=Number.isFinite(video.duration)?video.duration:0;
    // Let WebKit decode the initial media before seeking to a saved position.
    // A seek at metadata-only readiness can leave ManagedMediaSource pending.
    if(!resumed && resumeAt>0 && duration>0 && video.readyState>=2 && !video.seeking) {
      if(resumeAt<video.duration-20) {
        try { video.currentTime=resumeAt; resumed=true; } catch {}
      } else resumed=true;
    }
    if(Date.now()-lastReport<1000)return;
    lastReport=Date.now();
    window.webkit.messageHandlers.watch.postMessage({seconds:Number.isFinite(video.currentTime)?video.currentTime:seconds,duration,paused:video.paused,path:location.pathname,readyState:video.readyState,networkState:video.networkState,error:video.error?.code||0,playFailure,networkTrace:mediaSnapshot(video)+' '+(window.__cinejoyMediaTrace||[]).join(' | ')});
  };
  document.addEventListener('timeupdate',event=>{if(event.target instanceof HTMLVideoElement)report(event.target)},true);
  document.addEventListener('playing', event => {
    if (event.target instanceof HTMLVideoElement) {
      const source = sourceOf(event.target);
      if (source) startupFor(event.target, source).played = true;
    }
  }, true);
  setInterval(()=>{
    for(const dialog of document.querySelectorAll('[role="dialog"]')) {
      if(dialog.querySelector('h3')?.textContent?.trim()==='Good news!')dialog.querySelector('button[aria-label="Close"]')?.click();
    }
    const video=document.querySelector('video');
    if(video){
      video.disableRemotePlayback=true;
      video.setAttribute('x-webkit-airplay','deny');
      report(video);
      // A metadata-only preload may never reach HAVE_CURRENT_DATA until play()
      // requests media. Start once per source, preserving later user pauses.
      const source=sourceOf(video);
      if(source&&started.get(video)!==source){
        started.set(video,source);
        // The shipped template requests metadata only. Once a source is
        // attached and playback is requested, allow WebKit to preload media.
        video.preload='auto';
        // Use the player's action too, so its loading and playback state agree
        // with the media element when entering directly from the native app.
        if(video.paused)document.querySelector('button[aria-label="Play"]')?.click();
        playFailure='pending';
        video.play().then(()=>{playFailure=''}).catch(error=>{playFailure=error.name||'Error'});
      }
      bridgeStartupGap(video, source);
    }
  },1000);
})();
