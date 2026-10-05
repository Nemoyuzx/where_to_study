/* Official QMplus page classification only; no inputs, storage or business requests. */
(() => {
  'use strict';
  // Moodle fatal_error and core exception dialogs use these explicit markers.
  // Ordinary course notifications, including alert-danger, are not fatal pages.
  function hasMoodleErrorPage(doc = document) {
    if (doc?.body?.id === 'page-error') return true;
    if (doc?.querySelector?.('[data-rel="fatalerror"], #region-main .errorbox .errorcode, main .errorbox .errorcode')) return true;
    const titles = doc?.querySelectorAll?.('.moodle-dialogue-exception h5, .modal.show .modal-title, .modal[aria-hidden="false"] .modal-title, [role="dialog"][aria-modal="true"] .modal-title') || [];
    return Array.from(titles).slice(0, 16).some(node => {
      const value = node.textContent;
      return typeof value === 'string' && value.length <= 128 && value.trim().toLowerCase() === 'generalexceptionmessage';
    });
  }
  function isMoodleGuestPage(doc = document) {
    const body = doc?.body;
    return !!body && (body.id === 'page-login-index' || body.classList?.contains('notloggedin') || body.classList?.contains('guestuser'));
  }
  function hasSafeOfficialSAMLLink(doc = document) {
    const links = doc?.querySelectorAll?.('a[href]') || [];
    for (const link of links) {
      const href = link.getAttribute?.('href');
      if (typeof href !== 'string' || href.length > 2048 || href.includes('?') || href.includes('#')) continue;
      try {
        const target = new URL(href, 'https://qmplus.qmul.ac.uk');
        if (target.origin === 'https://qmplus.qmul.ac.uk' && !target.username && !target.password &&
          target.pathname === '/auth/saml2/login.php' && !target.search && !target.hash) return true;
      } catch {}
    }
    return false;
  }
  function hasSafeOfficialLoginLink(doc = document) {
    const links = doc?.querySelectorAll?.('a[href]') || [];
    return Array.from(links).slice(0, 512).some(link => {
      const href = link.getAttribute?.('href');
      if (typeof href !== 'string' || href.length > 2048) return false;
      try {
        const target = new URL(href, 'https://qmplus.qmul.ac.uk');
        return target.origin === 'https://qmplus.qmul.ac.uk' && !target.username && !target.password &&
          target.pathname === '/login/index.php' && !target.search && !target.hash;
      } catch { return false; }
    });
  }
  function classifyQMplusPage(doc = document) {
    try {
      if (hasMoodleErrorPage(doc)) return 'error';
      if (isMoodleGuestPage(doc)) return 'guest';
      if (doc?.readyState === 'loading') return 'loading';
      const menu = doc?.querySelectorAll?.('.usermenu .userbutton') || [];
      if (doc?.body && menu.length > 0) return 'authenticated';
      return doc?.body?.id === 'page-site-index' &&
        (hasSafeOfficialSAMLLink(doc) || hasSafeOfficialLoginLink(doc)) ? 'guest' : 'unknown';
    } catch { return 'unknown'; }
  }
  try {
    if (window.top !== window || document.defaultView !== window ||
      location.origin !== 'https://qmplus.qmul.ac.uk') return 'unknown';
    return classifyQMplusPage();
  } catch { return 'unknown'; }
})()
