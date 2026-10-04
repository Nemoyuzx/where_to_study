/* Official QMplus, read-only. No credentials/session markers leave this page. */
(() => {
  'use strict';
  const origin = 'https://qmplus.qmul.ac.uk';
  const maxBytes = 512 * 1024;
  const text = (v, n = 512) => typeof v === 'string'
    ? v.replace(/<[^>]*>/g, '').replace(/(?:sesskey|access_token|refresh_token|id_token|password|authorization)\s*[=:]\s*[^\s&<>"']+/ig, '[redacted]').trim().slice(0, n).replace(/[\uD800-\uDBFF]$/, '') : '';
  const id = v => /^[1-9]\d{0,15}$/.test(String(v)) && Number.isSafeInteger(Number(v)) ? String(v) : null;
  const epoch = v => Number.isSafeInteger(Number(v)) && Number(v) > 0 && Number(v) < 7258118400
    ? new Date(Number(v) * 1000).toISOString() : null;
  const safeURL = (value, paths = ['/course/view.php', '/mod/assign/view.php', '/mod/quiz/view.php']) => {
    try {
      const u = new URL(value, origin);
      if (u.origin !== origin || u.username || u.password || !paths.includes(u.pathname)) return null;
      const courseID = id(u.searchParams.get('id'));
      return courseID ? `${origin}${u.pathname}?id=${courseID}` : null;
    } catch { return null; }
  };
  function currentTermStatus(c, now = Date.now()) {
    const marker = String(c.fullname || c.name || '').match(/(20\d{2})\s*[\/-]\s*(\d{2}|20\d{2})/);
    const year = Number(new Intl.DateTimeFormat('en', {timeZone: 'Europe/London', year: 'numeric'}).format(now));
    const month = Number(new Intl.DateTimeFormat('en', {timeZone: 'Europe/London', month: 'numeric'}).format(now));
    const academicYear = month >= 8 ? year : year - 1;
    if (marker && Number(marker[1]) !== academicYear) return 'other';
    const start = Number(c.startdate || 0) * 1000, end = Number(c.enddate || 0) * 1000;
    if (start > now || (end > 0 && end <= now)) return 'other';
    if (marker || (start > 0 && end > now && now - start < 370 * 86400000)) return 'current';
    return 'unknown';
  }
  function londonDate(value) {
    const m = String(value).match(/(\d{1,2})\s+(January|February|March|April|May|June|July|August|September|October|November|December)\s+(20\d{2}),?\s+(\d{1,2}):(\d{2})(?:\s*(AM|PM))?/i);
    if (!m) return null;
    const months = 'january february march april may june july august september october november december'.split(' ');
    let hour = Number(m[4]);
    if (m[6]) {
      if(hour<1 || hour>12) return null;
      hour = hour % 12 + (m[6].toUpperCase() === 'PM' ? 12 : 0);
    }
    const parts = [Number(m[3]), months.indexOf(m[2].toLowerCase()), Number(m[1]), hour, Number(m[5])];
    if (hour > 23 || parts[4] > 59) return null;
    const wall = Date.UTC(...parts), d = new Date(wall);
    if (d.getUTCDate() !== parts[2] || d.getUTCMonth() !== parts[1]) return null;
    const fmt = new Intl.DateTimeFormat('en-GB', {timeZone: 'Europe/London', year:'numeric', month:'numeric', day:'numeric', hour:'numeric', minute:'numeric', second:'numeric', hourCycle:'h23'});
    let result = wall;
    for (let i = 0; i < 3; i++) {
      const p = Object.fromEntries(fmt.formatToParts(result).map(v => [v.type, v.value]));
      const represented = Date.UTC(Number(p.year), Number(p.month)-1, Number(p.day), Number(p.hour), Number(p.minute), Number(p.second));
      if (represented === wall) {
        for (const alternative of [result-3600000,result+3600000]) {
          const a = Object.fromEntries(fmt.formatToParts(alternative).map(v=>[v.type,v.value]));
          if (Date.UTC(Number(a.year),Number(a.month)-1,Number(a.day),Number(a.hour),Number(a.minute),Number(a.second))===wall) return null;
        }
        return new Date(result).toISOString();
      }
      result += wall - represented;
    }
    return null; // DST gap/ambiguous unverified times remain unknown.
  }
  function timingTexts(dateTexts) {
    const values = {due_at:null,opens_at:null,closes_at:null,cutoff_at:null,time_limit_seconds:null};
    for (const raw of dateTexts) {
      const re=/(Opened|Due|Closes|Closed|This quiz opened on|This quiz will close on|This quiz closed on|Cut.off date|Extension due date)\s*:?\s*(.*?)(?=(?:Opened|Due|Closes|Closed|Cut.off date|Extension due date)\s*:|This quiz (?:opened on|will close on|closed on)|$)/ig;
      for (const match of String(raw).matchAll(re)) {
        const time=londonDate(match[2]); if(!time) continue;
        if (/opened/i.test(match[1])) values.opens_at=time;
        else if (/close/i.test(match[1])) values.closes_at=time;
        else if (/cut.off/i.test(match[1])) values.cutoff_at=time;
        else values.due_at=time;
      }
      const duration=String(raw).match(/Time limit\s*:\s*(\d+)\s*(minutes?|mins?|hours?|hrs?|seconds?|secs?)\b/i);
      if(duration) values.time_limit_seconds=Number(duration[1])*(/^(?:hour|hr)/i.test(duration[2])?3600:/^min/i.test(duration[2])?60:1);
    }
    return values;
  }
  globalThis.WTSQmProtocol = Object.freeze({currentTermStatus, londonDate, safeURL, timingTexts});
  globalThis.WTSQmSync = async function(options = {}) {
    const fetched = new Date().toISOString();
    const result = {schema_version:1, source:'qmplus', fetched_at:fetched, ok:true, partial:false, courses:[], activities:[], warnings:[]};
    const fail = code => ({...result, ok:false, error_code:code});
    if (location.origin !== origin) return fail('QM_ORIGIN_REQUIRED');
    if (!globalThis.M?.cfg?.sesskey || document.body?.classList.contains('notloggedin')) return fail('QM_LOGIN_REQUIRED');
    if (globalThis.__wtsQmFlight) return fail('QM_SYNC_BUSY');
    const job = {cancelled:false, controller:null};
    globalThis.__wtsQmFlight = job;
    globalThis.WTSQmCancel = () => { job.cancelled = true; job.controller?.abort(); };
    const started = Date.now();
    const warn = code => { result.partial = true; if (result.warnings.length < 40 && !result.warnings.includes(code)) result.warnings.push(code); };
    const check = () => { if (job.cancelled || Date.now() - started > 120000) throw new Error('QM_CANCELLED_OR_TIMEOUT'); };
    async function request(url, body) {
      check();
      const u = new URL(url, origin);
      if (u.origin !== origin || !['/lib/ajax/service.php','/mod/assign/view.php','/mod/quiz/view.php'].includes(u.pathname)) throw new Error('QM_PATH_REJECTED');
      const controller = new AbortController(); job.controller = controller;
      const timer = setTimeout(() => controller.abort(), Math.min(20000, 120000 - (Date.now()-started)));
      try {
        const response = await fetch(u.href, {method:body?'POST':'GET', credentials:'same-origin', redirect:'error', cache:'no-store', headers:body?{'Content-Type':'application/json'}:{}, body:body?JSON.stringify(body):undefined, signal:controller.signal});
        if (!response.ok) { controller.abort(); await response.body?.cancel().catch(()=>{}); throw new Error('QM_HTTP_' + response.status); }
        const declared = Number(response.headers.get('content-length'));
        if (declared > 4 * 1024 * 1024) { controller.abort(); await response.body?.cancel().catch(()=>{}); throw new Error('QM_RESPONSE_TOO_LARGE'); }
        let size = 0; const chunks = [];
        const reader = response.body.getReader();
        try { while (true) { const r = await reader.read(); if (r.done) break; size += r.value.byteLength; if (size > 4*1024*1024) throw new Error('QM_RESPONSE_TOO_LARGE'); chunks.push(r.value); } }
        catch(e) { controller.abort(); await reader.cancel().catch(()=>{}); throw e; }
        finally { reader.releaseLock(); }
        const bytes = new Uint8Array(size); let offset = 0;
        chunks.forEach(c => { bytes.set(c, offset); offset += c.byteLength; });
        return new TextDecoder('utf-8', {fatal:true}).decode(bytes);
      } finally { clearTimeout(timer); job.controller = null; }
    }
    async function ajax(method, args) {
      const allowed = ['core_course_get_enrolled_courses_by_timeline_classification','core_courseformat_get_state'];
      if (!allowed.includes(method)) throw new Error('QM_METHOD_REJECTED');
      const u = new URL('/lib/ajax/service.php', origin); u.searchParams.set('sesskey', M.cfg.sesskey); u.searchParams.set('info', method);
      const a = JSON.parse(await request(u.href, [{index:0,methodname:method,args}]));
      if (!Array.isArray(a) || !a[0] || a[0].error) throw new Error('QM_API_REJECTED');
      return a[0].data;
    }
    const list = []; const seen = new Set();
    try {
      let offset = 0;
      for (let p = 0; p < 4; p++) {
        const data = await ajax('core_course_get_enrolled_courses_by_timeline_classification', {classification:'allincludinghidden',limit:50,offset,sort:'fullname ASC'});
        if (!Array.isArray(data?.courses)) throw new Error('QM_COURSE_FORMAT');
        for (const c of data.courses) {
          if (!c || !id(c.id) || typeof c.fullname!=='string' || !text(c.fullname)) { warn('QM_COURSE_PARTIAL'); continue; }
          if(seen.has(String(c.id)))continue;
          if(list.length>=100){warn('QM_COURSE_LIMIT');break;}
          seen.add(String(c.id));list.push(c);
        }
        const next = Number(data.nextoffset);
        if (!Number.isSafeInteger(next) || next <= offset) break;
        offset = next;
        if (list.length >= 100 || p === 3) { warn('QM_COURSE_LIMIT'); break; }
      }
      result.courses = list.slice(0,100).filter(c => /^EBU/i.test(text(c.fullname))).map(c => ({id:String(c.id),name:text(c.fullname),short_name:text(c.shortname),url:safeURL(c.viewurl||`/course/view.php?id=${c.id}`),start_at:epoch(c.startdate),end_at:epoch(c.enddate),current_term_status:currentTermStatus(c, options.now || Date.now())}));
      const selected = result.courses.filter(c => c.current_term_status === 'current');
      if (!selected.length) return result;
      // Discover the complete current-course catalogue before spending the
      // bounded flight on detail pages. Never request calendar or Timeline.
      const emitted = new Set();
      for (const c of selected) {
        check();
        let state;
        try {
          const raw = await ajax('core_courseformat_get_state',{courseid:Number(c.id)}); state=JSON.parse(typeof raw==='string'?raw:raw.data);
          if (!state || typeof state.cm !== 'object' || state.cm === null) throw new Error('QM_MODULE_FORMAT');
        }
        catch { check(); warn('QM_MODULE_PARTIAL'); continue; }
        const modules = Array.isArray(state.cm)?state.cm:Object.values(state.cm);
        for (const m of modules) {
          if (!m || typeof m !== 'object') { warn('QM_MODULE_PARTIAL'); continue; }
          if (!['assign','quiz'].includes(m.module)) continue;
          if(!id(m.id)) { warn('QM_MODULE_PARTIAL'); continue; }
          if (result.activities.length >= 500) { warn('QM_ACTIVITY_LIMIT'); break; }
          const url = safeURL(m.url||`/mod/${m.module}/view.php?id=${m.id}`);
          if (url !== `${origin}/mod/${m.module}/view.php?id=${m.id}`) { warn('QM_MODULE_PARTIAL'); continue; }
          if (emitted.has(url)) continue;
          emitted.add(url);
          const restricted = m.uservisible === false || m.accessvisible === false || m.visible === false || m.uservisible === 0;
          const item = {id:String(m.id),course_id:c.id,title:text(m.name),kind:m.module==='assign'?'assignment':'quiz',url,due_at:null,opens_at:null,closes_at:null,cutoff_at:null,time_limit_seconds:null,status:'unknown',detail_status:restricted?'restricted':'unavailable',raw_time_text:''};
          result.activities.push(item);
        }
      }
      for (const item of result.activities) {
          check();
          if (item.detail_status !== 'restricted') {
            try {
              const html = await request(item.url); const doc = new DOMParser().parseFromString(html,'text/html');
              const region = doc.querySelector('#region-main') || doc.querySelector('main');
              if (!region || doc.querySelector('form[action*="login"]')) throw new Error('QM_DETAIL_NOT_AVAILABLE');
              const clean = element => text(element?.textContent?.replace(/\s+/g,' '),1000);
              const dateTexts = Array.from(region.querySelectorAll('.activity-dates,[data-region="activity-dates"],.quizinfo')).flatMap(element => {
                // textContent joins adjacent quiz paragraphs without whitespace
                // ("25 minsGrade to pass"); preserve their semantic boundaries.
                const paragraphs=element.matches('.quizinfo')?element.querySelectorAll('p'):[];
                return paragraphs.length ? Array.from(paragraphs).map(clean) : [clean(element)];
              });
              for (const tr of region.querySelectorAll('.submissionstatustable tr')) {
                const cells = tr.querySelectorAll('th,td'); const label=clean(cells[0]), value=clean(cells[1]);
                if (/^submission status|^提交状态/i.test(label)) item.status=value || 'unknown';
                if (/^due date|^cut.off|^extension|^截止/i.test(label)) dateTexts.push(`${label}: ${value}`);
              }
              item.raw_time_text=text(dateTexts.join(' · '),1000);
              for (const [key,value] of Object.entries(timingTexts(dateTexts))) if(value!==null) item[key]=value;
              item.detail_status='available';
            } catch { check(); warn('QM_DETAIL_PARTIAL'); }
          }
      }
      return finishSnapshot();
    } catch (e) {
      if (result.courses.length && e.message === 'QM_CANCELLED_OR_TIMEOUT' && !job.cancelled) { warn('QM_SYNC_TIMEOUT_PARTIAL'); return finishSnapshot(); }
      return fail(/^[A-Z0-9_]+$/.test(e.message||'')?e.message:'QM_SYNC_FAILED');
    }
    finally { if (globalThis.__wtsQmFlight === job) { delete globalThis.__wtsQmFlight; delete globalThis.WTSQmCancel; } }
    function finishSnapshot() {
      if (new TextEncoder().encode(JSON.stringify(result)).byteLength > maxBytes && result.activities.length) {
        // Bound temporary allocations to logarithmic serialization passes,
        // rather than encoding the whole snapshot once for every dropped row.
        warn('QM_SNAPSHOT_LIMIT');
        const all=result.activities;let low=0,high=all.length,best=0;
        while(low<=high){
          const mid=Math.floor((low+high)/2);result.activities=all.slice(0,mid);
          if(new TextEncoder().encode(JSON.stringify(result)).byteLength<=maxBytes){best=mid;low=mid+1;}
          else high=mid-1;
        }
        result.activities=all.slice(0,best);
      }
      return new TextEncoder().encode(JSON.stringify(result)).byteLength > maxBytes ? fail('QM_SNAPSHOT_TOO_LARGE') : result;
    }
  };
})();
