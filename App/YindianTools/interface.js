// Localize interface controls only. Character, pronunciation and source labels
// retain the upstream text; the analysis algorithm and option values are intact.
(() => {
  let catalog;
  try { catalog = JSON.parse(window.YindianBridge.getInterfaceTexts()); } catch { return; }
  const label = key => catalog[key === '讀音' ? '發音' : key] ||
    (key.startsWith('今音') && catalog[key.slice(2)] ? (catalog['今音'] || '今音') + ' ' + catalog[key.slice(2)] : key);
  function translate(element) {
    if (element.tagName === 'TBODY') {
      element.querySelectorAll('.status-tag,.inline-detail-button,.empty-row').forEach(translate);
      element.querySelectorAll('.reading-split').forEach(node => {
        const match = node.textContent.match(/^聲 (.*?) · 韻 (.*?) · 調 (.*)$/);
        if (match) node.textContent = `${label('聲母')} ${match[1]} · ${label('韻母')} ${match[2]} · ${label('聲調')} ${match[3]}`;
      });
      return;
    }
    if (element.matches('.language-color-label, .char-choice-items, .all-chars, .position-chips, .reading-chips, #dialogSubtitle, #dialogTitle, #summaryDialect')) return;
    for (const attribute of ['placeholder', 'aria-label']) {
      const value = element.getAttribute(attribute);
      if (value && catalog[value] && catalog[value] !== value) element.setAttribute(attribute, catalog[value]);
    }
    for (const child of element.childNodes) {
      if (child.nodeType === Node.TEXT_NODE) {
        const raw = child.nodeValue, key = raw.trim();
        if (label(key) !== key) child.nodeValue = raw.replace(key, label(key));
      } else if (child.nodeType === Node.ELEMENT_NODE && !['SCRIPT','STYLE'].includes(child.tagName)) translate(child);
    }
  }
  const observer = new MutationObserver(() => {
    observer.disconnect(); translate(document.body);
    observer.observe(document.body, {childList:true, subtree:true, characterData:true});
  });
  translate(document.body);
  observer.observe(document.body, {childList:true, subtree:true, characterData:true});
})();
