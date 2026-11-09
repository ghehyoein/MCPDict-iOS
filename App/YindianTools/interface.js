// Localize interface controls only. Character, pronunciation and source labels
// retain the upstream text; the analysis algorithm and option values are intact.
(() => {
  let catalog;
  try { catalog = JSON.parse(window.YindianBridge.getInterfaceTexts()); } catch { return; }
  function translate(element) {
    if (element.matches('.language-color-label, .char-choice-items, .all-chars, .position-chips, .reading-chips, tbody, #dialogSubtitle, #dialogTitle, #summaryDialect')) return;
    for (const attribute of ['placeholder', 'aria-label']) {
      const value = element.getAttribute(attribute);
      if (value && catalog[value] && catalog[value] !== value) element.setAttribute(attribute, catalog[value]);
    }
    for (const child of element.childNodes) {
      if (child.nodeType === Node.TEXT_NODE) {
        const raw = child.nodeValue, key = raw.trim();
        if (catalog[key] && catalog[key] !== key) child.nodeValue = raw.replace(key, catalog[key]);
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
