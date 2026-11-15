(() => {
  const wanted = 'Season __SEASON__';
  const heading = [...document.querySelectorAll('h2 button')].find(button => /^Season \d+$/.test(button.textContent.trim()));
  if (heading?.textContent.trim() === wanted) return;
  const choice = [...document.querySelectorAll('button')].find(button => button.querySelector('.menu-item-label')?.textContent.trim() === wanted);
  if (choice) choice.click();
  else if (heading?.getAttribute('aria-expanded') !== 'true') heading?.click();
})();
