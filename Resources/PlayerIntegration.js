(() => {
  let lastReport = 0;
  let resumed = false;
  let playFailure = '';
  const started = new WeakMap();
  const resumeAt = __RESUME_SECONDS__;
  const style = document.createElement('style');
  style.textContent = 'html,body{background:#000!important}button[aria-label="Back"]{visibility:hidden!important}button[aria-label="Cast to Device"],button[aria-label^="View details for "],a[href^="/settings"],a[href^="/auth"]{display:none!important}';
  document.head.append(style);
  const mediaSnapshot = video => {
    const env = window.__cinejoyPlayerEnvironment || {};
    const source = video.currentSrc || video.getAttribute('src') || video.querySelector?.('source')?.src || '';
    // Report only source kind and capabilities. Stream URLs remain private.
    const kind = source.startsWith('blob:') ? 'blob' : source.startsWith('https:') ? 'https' : source ? 'other' : 'none';
    let buffer = 0;
    try { if (video.buffered?.length) buffer = Math.max(0, video.buffered.end(video.buffered.length - 1) - video.currentTime); } catch {}
    return `mse=${+!!env.mse} mms=${+!!env.mms} wkMse=${+!!env.webkitMse} native=${env.nativeHls || '?'} guards=${+!!env.setterGuard}${+!!env.removalGuard} src=${kind} remoteOff=${+!!video.disableRemotePlayback} buffered=${buffer.toFixed(1)}`;
  };
  const report = video => {
    const seconds=Number.isFinite(video.currentTime)?video.currentTime:0;
    const duration=Number.isFinite(video.duration)?video.duration:0;
    if(!resumed && resumeAt>0 && duration>0 && video.readyState>=1) {
      resumed=true;
      if(resumeAt<video.duration-20)video.currentTime=resumeAt;
    }
    if(Date.now()-lastReport<1000)return;
    lastReport=Date.now();
    window.webkit.messageHandlers.watch.postMessage({seconds:Number.isFinite(video.currentTime)?video.currentTime:seconds,duration,paused:video.paused,path:location.pathname,readyState:video.readyState,networkState:video.networkState,error:video.error?.code||0,playFailure,networkTrace:mediaSnapshot(video)+' '+(window.__cinejoyMediaTrace||[]).join(' | ')});
  };
  document.addEventListener('timeupdate',event=>{if(event.target instanceof HTMLVideoElement)report(event.target)},true);
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
      const source=video.currentSrc||video.getAttribute('src')||video.querySelector?.('source')?.src;
      if(source&&started.get(video)!==source){
        started.set(video,source);
        // Use the player's action too, so its loading and playback state agree
        // with the media element when entering directly from the native app.
        if(video.paused)document.querySelector('button[aria-label="Play"]')?.click();
        playFailure='pending';
        video.play().then(()=>{playFailure=''}).catch(error=>{playFailure=error.name||'Error'});
      }
    }
  },1000);
})();
