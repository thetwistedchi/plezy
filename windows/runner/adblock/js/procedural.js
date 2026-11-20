// Procedural and action cosmetic filters (uBlock Origin syntax), applied in
// the page: `example.com##div:has-text(Sponsored)`, `##.ad:remove()`,
// `##.x:upward(2)`, `##body:style(overflow: auto !important)` and so on.
// FILTERS is a list of {selector:[{type,arg}], action?:{type,arg}} from
// adblock-rust. Written for Plezy Retrowave's browser.
(function (FILTERS) {
  'use strict';
  const toMatcher = (arg) => {
    if (typeof arg !== 'string') return () => false;
    const m = /^\/(.+)\/([imsu]*)$/.exec(arg);
    if (m) {
      try {
        const re = new RegExp(m[1], m[2]);
        return (s) => re.test(s);
      } catch (_) {
        return () => false;
      }
    }
    return (s) => s.includes(arg);
  };
  const unquote = (s) => {
    s = s.trim();
    if ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'"))) return s.slice(1, -1);
    return s;
  };
  const splitPair = (arg, sep) => {
    // name<sep>value where either part may be a quoted string or /regex/
    let depth = 0, quote = '';
    for (let i = 0; i < arg.length; i++) {
      const c = arg[i];
      if (quote) { if (c === quote && arg[i - 1] !== '\\') quote = ''; continue; }
      if (c === '"' || c === "'") { quote = c; continue; }
      if (c === '/' && (i === 0 || arg[i - 1] === sep || /\s/.test(arg[i - 1]))) depth ^= 1;
      if (c === sep && !depth) return [arg.slice(0, i), arg.slice(i + 1)];
    }
    return [arg, ''];
  };
  const uniq = (list) => Array.from(new Set(list));
  const ops = {
    'css-selector': (els, arg, first) => {
      if (first) {
        try { return Array.from(document.querySelectorAll(arg)); } catch (_) { return []; }
      }
      const out = [];
      const a = arg.trim();
      for (const el of els) {
        try {
          if (a.startsWith('+')) {
            const n = el.nextElementSibling;
            if (n && n.matches(a.slice(1).trim())) out.push(n);
          } else if (a.startsWith('~')) {
            for (let n = el.nextElementSibling; n; n = n.nextElementSibling) if (n.matches(a.slice(1).trim())) out.push(n);
          } else {
            out.push(...el.querySelectorAll(':scope ' + a));
          }
        } catch (_) {}
      }
      return uniq(out);
    },
    'has-text': (els, arg) => {
      const m = toMatcher(arg);
      return els.filter((el) => m(el.textContent || ''));
    },
    'min-text-length': (els, arg) => {
      const n = parseInt(arg, 10) || 0;
      return els.filter((el) => (el.textContent || '').length >= n);
    },
    'matches-attr': (els, arg) => {
      const [name, value] = splitPair(arg, '=');
      const nameM = toMatcher(unquote(name));
      const valueM = value ? toMatcher(unquote(value)) : null;
      return els.filter((el) => {
        for (const attr of el.attributes) {
          if (nameM(attr.name) && (!valueM || valueM(attr.value))) return true;
        }
        return false;
      });
    },
    upward: (els, arg) => {
      const n = /^\d+$/.test(String(arg).trim()) ? parseInt(arg, 10) : 0;
      const out = [];
      for (const el of els) {
        let p = el;
        if (n > 0) {
          for (let i = 0; i < n && p; i++) p = p.parentElement;
        } else {
          try { p = el.parentElement ? el.parentElement.closest(arg) : null; } catch (_) { p = null; }
        }
        if (p && p !== document.documentElement && p !== document.body) out.push(p);
      }
      return uniq(out);
    },
    xpath: (els, arg, first) => {
      const roots = first ? [document] : els;
      const out = [];
      for (const root of roots) {
        try {
          const r = document.evaluate(arg, root, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
          for (let i = 0; i < r.snapshotLength; i++) {
            const node = r.snapshotItem(i);
            if (node && node.nodeType === 1) out.push(node);
          }
        } catch (_) {}
      }
      return uniq(out);
    },
  };
  const css = (pseudo) => (els, arg) => {
    const [prop, value] = splitPair(arg, ':');
    const m = toMatcher(unquote(value));
    const name = prop.trim();
    return els.filter((el) => {
      try { return m(getComputedStyle(el, pseudo).getPropertyValue(name)); } catch (_) { return false; }
    });
  };
  ops['matches-css'] = css(null);
  ops['matches-css-before'] = css('::before');
  ops['matches-css-after'] = css('::after');

  const select = (steps) => {
    let els = [];
    let first = true;
    for (const step of steps) {
      // A page condition, not an element step.
      if (step.type === 'matches-path') {
        if (!toMatcher(step.arg)(location.pathname + location.search)) return [];
        continue;
      }
      const op = ops[step.type];
      if (!op) return [];
      if (first && step.type !== 'css-selector' && step.type !== 'xpath') {
        els = Array.from(document.querySelectorAll('*'));
        first = false;
      }
      els = op(els, step.arg, first);
      first = false;
      if (!els.length) break;
    }
    return els;
  };
  const done = new WeakMap();
  const apply = (el, action, key) => {
    let seen = done.get(el);
    if (!seen) done.set(el, (seen = new Set()));
    const type = action ? action.type : 'hide';
    if (type !== 'remove-attr' && type !== 'remove-class' && seen.has(key)) return;
    seen.add(key);
    switch (type) {
      case 'remove': el.remove(); break;
      case 'style': {
        const prev = (el.getAttribute('style') || '').trim();
        el.setAttribute('style', prev ? prev.replace(/;?$/, '; ') + action.arg : action.arg);
        break;
      }
      case 'remove-attr': el.removeAttribute(action.arg); break;
      case 'remove-class': el.classList.remove(action.arg); break;
      default: el.style.setProperty('display', 'none', 'important');
    }
  };
  const run = () => {
    FILTERS.forEach((f, i) => {
      if (!f || !Array.isArray(f.selector)) return;
      for (const el of select(f.selector)) apply(el, f.action, i);
    });
  };
  let timer = 0;
  const schedule = () => {
    if (!timer) timer = setTimeout(() => { timer = 0; run(); }, 150);
  };
  const start = () => {
    run();
    new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'id'] });
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
  else start();
})
