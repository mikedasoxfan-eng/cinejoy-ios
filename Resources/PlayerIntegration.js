(() => {
  let lastReport = 0;
  let resumed = false;
  const started = new WeakSet();
  const resumeAt = __RESUME_SECONDS__;
  const style = document.createElement('style');
  style.textContent = 'html,body{background:#000!important}button[aria-label="Back"]{visibility:hidden!important}button[aria-label="Cast to Device"],button[aria-label^="View details for "],a[href^="/settings"],a[href^="/auth"]{display:none!important}';
  document.head.append(style);
  const report = video => {
    if(!Number.isFinite(video.currentTime)||!Number.isFinite(video.duration)||video.duration<=0)return;
    if(!resumed && resumeAt>0 && video.readyState>=1) {
      resumed=true;
      if(resumeAt<video.duration-20)video.currentTime=resumeAt;
    }
    if(Date.now()-lastReport<1000)return;
    lastReport=Date.now();
    window.webkit.messageHandlers.watch.postMessage({seconds:video.currentTime,duration:video.duration,paused:video.paused,path:location.pathname});
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
      // Opening this screen follows the native Play action. Start once after
      // the source is ready, while preserving subsequent user pauses.
      if(video.readyState>=2&&!started.has(video)){
        started.add(video);
        video.play().catch(()=>{});
      }
    }
  },1000);
})();
