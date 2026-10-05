/* Official QMplus/Microsoft login-page helper. No network, storage, cookie or business bridge. */
(() => {
  'use strict';
  const qmOrigin = 'https://qmplus.qmul.ac.uk';
  const msOrigin = 'https://login.microsoftonline.com';
  const tenant = '569df091-b013-40e3-86ee-bd9cb9e25814';
  const msPagePaths = new Set([`/${tenant}/saml2`, `/${tenant}/login`]);
  const msFormPath = `/${tenant}/login`;
  const kmsiPath = '/kmsi';
  const reasons = Object.freeze({
    ready: 'READY', authenticated: 'AUTHENTICATED', loading: 'LOADING',
    invalidNonce: 'INVALID_NONCE', staleDocument: 'STALE_DOCUMENT',
    untrusted: 'UNTRUSTED_CONTEXT', unsupported: 'UNSUPPORTED_PAGE',
    chooser: 'ACCOUNT_CHOOSER', hint: 'ACCOUNT_HINT_REQUIRED', form: 'FORM_UNTRUSTED',
    interference: 'INTERFERENCE', absent: 'KNOWN_FORM_ABSENT',
    mismatch: 'ACCOUNT_MISMATCH', priorUsername: 'USERNAME_NOT_SUBMITTED', currentAccount: 'CURRENT_ACCOUNT_VERIFIED',
    attempted: 'ALREADY_ATTEMPTED', captcha: 'CAPTCHA_REQUIRED', mfa: 'MFA_REQUIRED'
  });
  if (Object.prototype.hasOwnProperty.call(globalThis, 'WTSQmAuth')) return 'AUTH_CONFLICT';

  let boundDocument = null;
  let boundNonce = '';
  let boundHref = '';
  let usernameAttempted = false;
  let passwordAttempted = false;
  let accountAttempted = false;
  let continueAttempted = false;
  let accountSelectedFor = '';
  let usernameSubmittedFor = '';
  const validNonce = value => typeof value === 'string' && /^[A-Za-z0-9_-]{8,64}$/.test(value);
  const accountKey = value => typeof value === 'string' && value.length <= 320 &&
    /^[^\s@]+@[^\s@]+$/.test(value.trim()) ? value.trim().toLowerCase() : '';
  const result = (stage, nonce, accountMatch, reason) => Object.freeze({
    v: 1, stage, document: validNonce(nonce) ? nonce : '',
    accountMatch: accountMatch === true, reason
  });

  function context() {
    try {
      if (window.top !== window || document.defaultView !== window) return 'untrusted';
      const url = new URL(location.href);
      if (url.protocol !== 'https:' || url.username || url.password ||
        (url.port && url.port !== '443') || url.origin !== location.origin) return 'untrusted';
      if (url.origin === qmOrigin) return 'qm';
      if (url.origin === msOrigin && msPagePaths.has(url.pathname)) return 'ms';
      // KMSI is a continuation-only surface. Never send credentials here.
      if (url.origin === msOrigin && url.pathname === kmsiPath) return 'kmsi';
      return 'unsupported';
    } catch { return 'untrusted'; }
  }

  function visible(node, minWidth = 1, minHeight = 1, requireHit = false) {
    if (!node || typeof node.getBoundingClientRect !== 'function' ||
      typeof node.getClientRects !== 'function' || node.getClientRects().length === 0) return false;
    const rect = node.getBoundingClientRect();
    if (!Number.isFinite(rect.width) || !Number.isFinite(rect.height) ||
      rect.width < minWidth || rect.height < minHeight) return false;
    for (let current = node; current; current = current.parentElement) {
      if (current.hidden || current.inert || current.getAttribute?.('aria-hidden') === 'true') return false;
      const style = window.getComputedStyle(current);
      if (!style || style.display === 'none' || ['hidden', 'collapse'].includes(style.visibility) ||
        !Number.isFinite(Number(style.opacity)) || Number(style.opacity) <= 0.01) return false;
    }
    if (requireHit) {
      const hit = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
      if (!hit || (hit !== node && !node.contains(hit))) return false;
    }
    return true;
  }

  function exactlyOne(selector) {
    const nodes = document.querySelectorAll(selector);
    return nodes.length === 1 ? nodes[0] : null;
  }

  function hasInterference(allowed) {
    const candidates = document.querySelectorAll(
      'input, textarea, [contenteditable="true"], [role="alert"], [role="dialog"], [aria-modal="true"]');
    for (const node of candidates) {
      if (allowed.has(node) || !visible(node)) continue;
      // Even a second same-origin editable control may be OTP, CAPTCHA, risk
      // confirmation or an account switch. Unknown visible UI is manual.
      return true;
    }
    return false;
  }

  function formAndSubmit(expectedPath = msFormPath) {
    const form = exactlyOne('form#i0281');
    const submit = exactlyOne('input#idSIButton9[type="submit"]');
    if (!form || !submit || form.id !== 'i0281' || submit.id !== 'idSIButton9' ||
      submit.type !== 'submit' || !form.contains(submit) || submit.disabled ||
      !visible(submit, 60, 20, true)) return null;
    try {
      const action = new URL(form.action, location.href);
      if (action.origin !== msOrigin || action.pathname !== expectedPath ||
        action.username || action.password || (action.port && action.port !== '443')) return null;
    } catch { return null; }
    return {form, submit};
  }

  function matchingDisplayName(key) {
    const displayName = exactlyOne('#displayName');
    return !!key && !!displayName && visible(displayName, 1, 1, true) &&
      accountKey(displayName.textContent) === key;
  }

  function hasIdentityAcknowledgement(key, acknowledgement) {
    // Only native knows the connection owner and saved-credential revision.
    // It may carry a successful identity ACK across real documents; inspect
    // never turns this boolean into retained authority for later calls.
    return !!key && (usernameSubmittedFor === key || accountSelectedFor === key || acknowledgement === true);
  }

  function challengeReason() {
    // Read-only semantic recognition. These controls are never filled or
    // clicked. Unknown inputs/alerts remain manual, not presumed MFA.
    const captcha = document.querySelectorAll('iframe[title], input[aria-label], [role="group"][aria-label], img[alt]');
    for (const node of Array.from(captcha).slice(0, 64)) {
      const label = node.getAttribute('aria-label') || node.getAttribute('title') || node.getAttribute('alt') || '';
      if (label.length <= 256 && /(?:\bcaptcha\b|\bsecurity image\b|图形验证码|圖片驗證碼|图像验证码)/i.test(label) && visible(node)) {
        return reasons.captcha;
      }
    }
    const codeFields = document.querySelectorAll('input[autocomplete="one-time-code"], input[name="otc"]');
    if (Array.from(codeFields).slice(0, 16).some(node => node instanceof HTMLInputElement &&
      ['text', 'tel', 'number'].includes(node.type) && visible(node, 40, 16))) return reasons.mfa;
    const headings = document.querySelectorAll('h1, h2, [role="heading"]');
    const approvalTitles = new Set(['approve sign in request', 'approve sign-in request',
      'check your authenticator app', 'open your authenticator app', '批准登录请求', '核准登入要求',
      'verify your identity', '验证您的身份', '驗證您的身分', '驗證您的身份']);
    return Array.from(headings).slice(0, 32).some(node => {
      const title = node.textContent;
      return typeof title === 'string' && title.length <= 128 && visible(node) &&
        approvalTitles.has(title.trim().toLowerCase());
    }) ? reasons.mfa : '';
  }

  function knownContinuation() {
    // Microsoft MSAL's public KMSI tests identify #kmsiTitle, Yes
    // #idSIButton9 and No #idBtn_Back. This does not authorize arbitrary Next,
    // consent, permissions, risk, device registration or terms buttons.
    const title = exactlyOne('#kmsiTitle');
    const verified = formAndSubmit(kmsiPath);
    const back = exactlyOne('input#idBtn_Back[type="button"]');
    const titleText = typeof title?.textContent === 'string' ? title.textContent.trim().toLowerCase() : '';
    if (!title || !visible(title) || !/^(?:stay signed in|keep me signed in|保持登录状态|保持登入狀態|保持登入|保持登录)[?？]?$/.test(titleText) ||
      !verified || !verified.form.contains(title) ||
      !back || back.disabled || !verified.form.contains(back) || !visible(back, 60, 20, true) ||
      document.querySelectorAll('#i0116, #i0118').length !== 0) return null;
    const allowed = new Set([verified.submit, back]);
    const checkbox = exactlyOne('input#KmsiCheckboxField[type="checkbox"]');
    if (checkbox && visible(checkbox)) {
      const label = exactlyOne('label[for="KmsiCheckboxField"]');
      const text = typeof label?.textContent === 'string' ? label.textContent.trim().toLowerCase() : '';
      // The optional display-preference checkbox is deliberately unchanged.
      // Only its explicit, bounded meaning may be ignored as interference.
      if (!verified.form.contains(checkbox) || !label || !visible(label) ||
        !["don't show this again", 'don’t show this again', '不再显示此消息', '不要再显示此消息',
          '不再显示此内容', '不要再顯示這個訊息', '不要再顯示此訊息'].includes(text)) return null;
      allowed.add(checkbox);
    }
    if (hasInterference(allowed) || Array.from(document.querySelectorAll('button, select, [role="button"]'))
      .some(node => !allowed.has(node) && visible(node))) return null;
    return {...verified, title, back, checkbox};
  }

  function knownField(selector, expectedID, expectedName, expectedType, form) {
    const field = exactlyOne(selector);
    if (!(field instanceof HTMLInputElement) || field.id !== expectedID ||
      field.name !== expectedName || field.type !== expectedType || !form.contains(field) ||
      field.disabled || field.readOnly || !visible(field, 80, 20)) return null;
    if (!visible(field, 80, 20, true)) {
      // Verified live Microsoft markup overlays its own hint DIV on an empty
      // input. Its hint can remain until the first keystroke; it is part of the
      // same known field, not an arbitrary overlay or a hidden password control.
      if (!ownedPlaceholderHit(field) || typeof field.focus !== 'function') return null;
      field.focus({preventScroll: true});
      const refreshed = formAndSubmit();
      if (exactlyOne(selector) !== field || !form.contains(field) || context() !== 'ms' ||
        field.disabled || field.readOnly || !visible(field, 80, 20) ||
        !refreshed || refreshed.form !== form ||
        boundDocument !== document || boundHref !== String(location.href) ||
        (!visible(field, 80, 20, true) && !ownedPlaceholderHit(field))) return null;
    }
    return field;
  }

  function ownedPlaceholderHit(field) {
    const rect = field.getBoundingClientRect();
    const hit = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
    const container = field.parentElement;
    return !!hit && !!container?.classList?.contains('placeholderContainer') &&
      !!hit.classList?.contains('placeholder') && hit.getAttribute('aria-hidden') === 'true' &&
      !!hit.parentElement?.classList?.contains('placeholderInnerContainer') &&
      hit.parentElement.parentElement === container;
  }

  function accountChoice(holder, key) {
    // Observed official picker: a DIV.table role-button carries the UPN in
    // data-test-id and displays it in its unique content cell. Never select
    // the other-account tile, the overflow menu, or a partial-name match.
    if (!key || !holder || holder.id !== 'tilesHolder' || !visible(holder) ||
      typeof holder.querySelectorAll !== 'function') return null;
    const matches = Array.from(holder.querySelectorAll('div.table[role="button"][data-test-id]')).filter(node => {
      if (node.tagName !== 'DIV' || node.getAttribute('role') !== 'button' ||
        !node.classList?.contains('table') || node.getAttribute('aria-disabled') === 'true' ||
        node.hasAttribute?.('disabled') || accountKey(node.getAttribute('data-test-id')) !== key ||
        !visible(node, 60, 20)) return false;
      const contents = node.querySelectorAll('div.table-cell.text-left.content');
      if (contents.length !== 1 || accountKey(contents[0].textContent) !== key ||
        !visible(contents[0])) return false;
      return true;
    });
    if (matches.length !== 1) return null;
    const node = matches[0], rect = node.getBoundingClientRect();
    const hit = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
    return visible(node, 60, 20, true) && !!hit && typeof hit.closest === 'function' &&
      hit.closest('button,a,[role="button"]') === node ? node : null;
  }

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
  function inspectUnsafe(nonce, accountHint, allowBind, identityAcknowledged) {
    if (!validNonce(nonce)) return result('manual', nonce, false, reasons.invalidNonce);
    if (boundDocument === null && allowBind) {
      boundDocument = document; boundNonce = nonce; boundHref = String(location.href);
    }
    if (boundDocument !== document || boundNonce !== nonce || boundHref !== String(location.href)) {
      return result('manual', nonce, false, reasons.staleDocument);
    }
    const site = context();
    if (site === 'untrusted') return result('manual', nonce, false, reasons.untrusted);
    if (site === 'qm') {
      const kind = classifyQMplusPage();
      if (kind === 'loading') return result('loading', nonce, false, reasons.loading);
      return kind === 'authenticated' ?
        result('authenticated', nonce, false, reasons.authenticated) :
        result('manual', nonce, false, reasons.unsupported);
    }
    if (site !== 'ms' && site !== 'kmsi') return result('manual', nonce, false, reasons.unsupported);
    const challenge = challengeReason();
    if (challenge) return result('challenge', nonce, false, challenge);
    if (document.readyState === 'loading') return result('loading', nonce, false, reasons.loading);
    const continuationTitle = exactlyOne('#kmsiTitle');
    if (continuationTitle && visible(continuationTitle)) {
      if (!knownContinuation()) return result('manual', nonce, false, reasons.interference);
      const hint = accountKey(accountHint);
      if (!matchingDisplayName(hint)) return result('manual', nonce, false, reasons.mismatch);
      if (continueAttempted) return result('manual', nonce, true, reasons.attempted);
      return result('continue', nonce, true, hasIdentityAcknowledgement(hint, identityAcknowledged) ?
        reasons.ready : reasons.currentAccount);
    }
    if (site === 'kmsi') return result('manual', nonce, false, reasons.unsupported);
    const chooser = exactlyOne('#tilesHolder');
    if (chooser && visible(chooser)) {
      if (hasInterference(new Set())) return result('manual', nonce, false, reasons.interference);
      const hint = accountKey(accountHint);
      if (!hint) return result('account', nonce, false, reasons.hint);
      if (!accountChoice(chooser, hint)) return result('manual', nonce, false, reasons.chooser);
      if (accountAttempted || usernameAttempted || passwordAttempted) return result('manual', nonce, true, reasons.attempted);
      return result('account', nonce, true, reasons.ready);
    }
    const verified = formAndSubmit();
    if (!verified) return result('manual', nonce, false, reasons.form);
    const username = knownField('input#i0116[name="loginfmt"][type="email"]',
      'i0116', 'loginfmt', 'email', verified.form);
    const password = knownField('input#i0118[name="passwd"][type="password"]',
      'i0118', 'passwd', 'password', verified.form);
    if (username && password) return result('manual', nonce, false, reasons.interference);
    if (username) {
      if (hasInterference(new Set([username, verified.submit]))) {
        return result('manual', nonce, false, reasons.interference);
      }
      // A prefilled different identity is an account-switch decision, not a
      // field to overwrite merely because the origin is Microsoft-owned.
      if (username.value && accountKey(username.value) !== accountKey(accountHint)) {
        return result('manual', nonce, false, reasons.mismatch);
      }
      return usernameAttempted || passwordAttempted ? result('manual', nonce, false, reasons.attempted) :
        result('username', nonce, false, reasons.ready);
    }
    if (password) {
      // In the observed official flow #i0116 is removed at the password stage,
      // not merely hidden. A hidden username + visible password is unverified.
      if (document.querySelectorAll('#i0116').length !== 0 ||
        hasInterference(new Set([password, verified.submit]))) {
        return result('manual', nonce, false, reasons.interference);
      }
      if (password.value) return result('manual', nonce, false, reasons.interference);
      const hint = accountKey(accountHint);
      const accountMatch = matchingDisplayName(hint);
      if (!accountMatch) return result('manual', nonce, false, reasons.mismatch);
      if (passwordAttempted) return result('manual', nonce, true, reasons.attempted);
      if (!hasIdentityAcknowledgement(hint, identityAcknowledged)) {
        // A valid official cookie may enter directly at the password screen.
        // Native may acknowledge this exact current-page identity only while
        // its owner, document and saved-credential revision are still current.
        return result('password', nonce, true, reasons.currentAccount);
      }
      return result('password', nonce, true, reasons.ready);
    }
    return result('manual', nonce, false, reasons.absent);
  }

  function inspectInternal(nonce, accountHint, allowBind, identityAcknowledged = false) {
    try { return inspectUnsafe(nonce, accountHint, allowBind, identityAcknowledged); }
    catch { return result('manual', nonce, false, reasons.untrusted); }
  }

  function setInputValue(field, value) {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
    if (typeof setter !== 'function') return false;
    setter.call(field, value);
    field.dispatchEvent(new Event('input', {bubbles: true}));
    field.dispatchEvent(new Event('change', {bubbles: true}));
    return field.value === value;
  }

  function fillAndSubmitUnsafe(options) {
    if (!options || typeof options !== 'object' || Array.isArray(options) ||
      Object.keys(options).some(key => !['document', 'stage', 'account', 'password', 'identityAcknowledged'].includes(key))) return 'REJECTED';
    const {document: nonce, stage, account, password, identityAcknowledged} = options;
    if (!validNonce(nonce) || boundDocument !== document || boundNonce !== nonce) return 'STALE_DOCUMENT';
    const key = accountKey(account);
    if (!key || !['account', 'username', 'password', 'continue'].includes(stage)) return 'REJECTED';
    if (Object.prototype.hasOwnProperty.call(options, 'identityAcknowledged') &&
      (typeof identityAcknowledged !== 'boolean' || !['password', 'continue'].includes(stage))) return 'REJECTED';
    if (stage !== 'password' && Object.prototype.hasOwnProperty.call(options, 'password')) return 'REJECTED';
    if (stage === 'password' && (typeof password !== 'string' || !password.length || password.length > 2048)) {
      return 'REJECTED';
    }
    const state = inspectInternal(nonce, account, false, identityAcknowledged);
    if (state.stage !== stage || state.reason !== reasons.ready ||
      (stage !== 'username' && !state.accountMatch)) return 'MANUAL_REQUIRED';
    if (stage === 'continue') {
      const verified = knownContinuation();
      if (!verified || !['ms', 'kmsi'].includes(context())) return 'MANUAL_REQUIRED';
      continueAttempted = true;
      const refreshed = knownContinuation();
      if (!refreshed || refreshed.form !== verified.form || refreshed.submit !== verified.submit ||
        refreshed.title !== verified.title || refreshed.back !== verified.back || refreshed.checkbox !== verified.checkbox ||
        !['ms', 'kmsi'].includes(context()) || boundDocument !== document || boundNonce !== nonce ||
        boundHref !== String(location.href) || challengeReason() || !matchingDisplayName(key) ||
        !hasIdentityAcknowledgement(key, identityAcknowledged)) return 'MANUAL_REQUIRED';
      try { verified.submit.click(); return 'CONTINUE_SUBMITTED'; }
      catch { return 'MANUAL_REQUIRED'; }
    }
    if (stage === 'account') {
      const holder = exactlyOne('#tilesHolder');
      const choice = accountChoice(holder, key);
      if (!choice || context() !== 'ms') return 'MANUAL_REQUIRED';
      accountAttempted = true;
      const refreshed = accountChoice(exactlyOne('#tilesHolder'), key);
      if (refreshed !== choice || context() !== 'ms' || boundDocument !== document || boundNonce !== nonce ||
        boundHref !== String(location.href) || challengeReason() || hasInterference(new Set())) return 'MANUAL_REQUIRED';
      try { choice.click(); accountSelectedFor = key; return 'ACCOUNT_SELECTED'; }
      catch { return 'MANUAL_REQUIRED'; }
    }
    const verified = formAndSubmit();
    if (!verified) return 'MANUAL_REQUIRED';
    const field = stage === 'username' ?
      knownField('input#i0116[name="loginfmt"][type="email"]', 'i0116', 'loginfmt', 'email', verified.form) :
      knownField('input#i0118[name="passwd"][type="password"]', 'i0118', 'passwd', 'password', verified.form);
    if (!field || context() !== 'ms') return 'MANUAL_REQUIRED';
    // Claim before mutating DOM so a failed click or re-entrant callback cannot
    // silently retry credentials on the same document/stage.
    if (stage === 'username') usernameAttempted = true;
    else passwordAttempted = true;
    try {
      if (!setInputValue(field, stage === 'username' ? account.trim() : password)) return 'MANUAL_REQUIRED';
      const refreshed = formAndSubmit();
      const currentField = refreshed && (stage === 'username' ?
        knownField('input#i0116[name="loginfmt"][type="email"]', 'i0116', 'loginfmt', 'email', refreshed.form) :
        knownField('input#i0118[name="passwd"][type="password"]', 'i0118', 'passwd', 'password', refreshed.form));
      if (context() !== 'ms' || boundDocument !== document || boundNonce !== nonce ||
        boundHref !== String(location.href) ||
        !refreshed || refreshed.form !== verified.form || refreshed.submit !== verified.submit ||
        currentField !== field || challengeReason() || hasInterference(new Set([field, verified.submit]))) return 'MANUAL_REQUIRED';
      if (stage === 'password') {
        if (!matchingDisplayName(key) || !hasIdentityAcknowledgement(key, identityAcknowledged)) return 'MANUAL_REQUIRED';
      }
      verified.submit.click();
      if (stage === 'username') usernameSubmittedFor = key;
      return stage === 'username' ? 'USERNAME_SUBMITTED' : 'PASSWORD_SUBMITTED';
    } catch { return 'MANUAL_REQUIRED'; }
  }

  function fillAndSubmit(options) {
    try { return fillAndSubmitUnsafe(options); }
    catch { return 'MANUAL_REQUIRED'; }
  }

  try {
    Object.defineProperty(globalThis, 'WTSQmAuth', {
      value: Object.freeze({inspect: (nonce, accountHint, identityAcknowledged = false) =>
        inspectInternal(nonce, accountHint, true, identityAcknowledged), fillAndSubmit}),
      writable: false, configurable: false, enumerable: false
    });
    return 'AUTH_INSTALLED';
  } catch { return 'AUTH_CONFLICT'; }
})();
