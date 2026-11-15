(() => {
  // Hiding the notice leaves its modal event boundary active. Dismiss it through
  // the site's own control before sending events to the season selector.
  for (const dialog of document.querySelectorAll('[role="dialog"]')) {
    if (dialog.querySelector('h3')?.textContent?.trim() === 'Good news!') {
      dialog.querySelector('button[aria-label="Close"]')?.click();
      return;
    }
  }
  const wanted = 'Season __SEASON__';
  const heading = [...document.querySelectorAll('h2 button')].find(button => /^Season \d+$/.test(button.textContent.trim()));
  if (heading?.textContent.trim() === wanted) return;
  // The public page uses a virtual wheel on phone widths and a menu on desktop.
  // Wheel labels repeat; prefer the occurrence nearest the currently selected row.
  const wheel = document.querySelector('[role="dialog"] .wheel');
  const current = wheel?.querySelector('button[aria-current="true"]');
  const rows = [...(wheel?.querySelectorAll('button.row') || [])]
    .filter(button => button.querySelector('.label')?.textContent.trim() === wanted)
    .sort((a, b) => Math.abs(a.offsetTop - (current?.offsetTop || 0)) - Math.abs(b.offsetTop - (current?.offsetTop || 0)));
  const choice = rows[0] || [...document.querySelectorAll('button')].find(button => button.querySelector('.menu-item-label')?.textContent.trim() === wanted);
  if (choice) choice.click();
  else if (heading?.getAttribute('aria-expanded') !== 'true') heading?.click();
})();
