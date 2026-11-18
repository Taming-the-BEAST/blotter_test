// Tutorial listing: entry point.
// One update path: event -> mutate state -> derive() -> render() -> URL.
//
// Modules are loaded with the same ?v= query as this file, so a new site
// build busts the browser cache for all of them. The other modules have no
// imports of their own (they stay importable from node --test).

const v = new URL(import.meta.url).search;

const FT_MIN_CHARS = 3;
const FT_DEBOUNCE_MS = 250;
const URL_TYPING_MS = 300;
const STATUS_MS = 300;

async function start() {
  const root = document.querySelector('.tutorial-index');
  if (!root) return;

  const [match, stateMod, catalogue, fulltextMod, view] = await Promise.all([
    import('./match.js' + v),
    import('./state.js' + v),
    import('./catalogue.js' + v),
    import('./fulltext.js' + v),
    import('./view.js' + v),
  ]);

  const ui = {
    grid: document.getElementById('tutorial-grid'),
    form: document.getElementById('tl-search-form'),
    q: document.getElementById('tl-q'),
    clear: document.getElementById('tl-clear'),
    tryRow: document.getElementById('tl-try'),
    sort: document.getElementById('tl-sort'),
    legacy: document.getElementById('show-legacy'),
    status: document.getElementById('tl-status'),
    empty: document.getElementById('tl-empty'),
    reset: document.getElementById('tl-reset'),
    showAll: document.getElementById('package-show-all'),
    filterButtons: [...root.querySelectorAll('[data-filter][data-value]')],
  };
  if (!ui.grid || !ui.q || !ui.sort || !ui.status) return;

  const items = catalogue.buildCatalogue(root);
  const options = catalogue.knownOptions(root, items);
  const fulltext = fulltextMod.createFulltext(
    root.dataset.pagefindUrl || '/pagefind/pagefind.js',
    new Set(items.map(i => i.slug)),
  );

  let state = stateMod.parseURL(location.search, options).state;

  // ---- status line (debounced live region) ----
  let statusTimer = null;
  let firstStatus = true;
  function setStatus(text) {
    clearTimeout(statusTimer);
    if (firstStatus) {
      ui.status.textContent = text;
      firstStatus = false;
      return;
    }
    statusTimer = setTimeout(() => {
      if (ui.status.textContent !== text) ui.status.textContent = text;
    }, STATUS_MS);
  }

  // ---- full-text search ----
  let ftTimer = null;
  let searching = false;

  function scheduleFulltext() {
    clearTimeout(ftTimer);
    const q = match.normaliseQuery(state.q);
    if (q.length < FT_MIN_CHARS) {
      fulltext.cancel();
      searching = false;
      state.fulltext = { q: '', status: fulltext.status, hits: null };
      return;
    }
    if (state.fulltext.q === q && state.fulltext.hits) return;
    if (fulltext.status === 'unavailable') return;
    searching = true;
    ftTimer = setTimeout(async () => {
      const hits = await fulltext.search(q);
      if (hits === null) {
        // Superseded by a newer search, or Pagefind is unavailable.
        if (fulltext.status === 'unavailable' && match.normaliseQuery(state.q) === q) {
          searching = false;
          update({ history: 'none' });
        }
        return;
      }
      if (match.normaliseQuery(state.q) !== q) return;
      searching = false;
      state.fulltext = { q, status: fulltext.status, hits };
      update({ history: 'none' });
    }, FT_DEBOUNCE_MS);
  }

  // ---- URL / history ----
  let urlTimer = null;
  function syncURL(mode) {
    // 'none' (async full-text results, popstate) must not cancel a pending
    // typing update, or the query would never reach the URL.
    if (mode === 'none') return;
    const qs = stateMod.toURL(state);
    const url = location.pathname + (qs ? '?' + qs : '') + location.hash;
    if (url === location.pathname + location.search + location.hash) return;
    clearTimeout(urlTimer);
    if (mode === 'push') {
      history.pushState(null, '', url);
    } else if (mode === 'typing') {
      urlTimer = setTimeout(() => {
        const now = stateMod.toURL(state);
        history.replaceState(null, '', location.pathname + (now ? '?' + now : '') + location.hash);
      }, URL_TYPING_MS);
    } else if (mode === 'replace') {
      history.replaceState(null, '', url);
    }
  }

  // ---- the single update path ----
  function update({ history: mode = 'push' } = {}) {
    const derived = match.derive(items, state, { options });
    view.render(ui, items, state, derived, {
      sanitiseExcerpt: html => fulltextMod.sanitiseExcerpt(html),
      ftStatus: fulltext.status,
      searching,
      setStatus,
    });
    syncURL(mode);
  }

  function setQuery(q, mode) {
    state.q = q;
    scheduleFulltext();
    update({ history: mode });
  }

  // ---- events ----
  ui.form.addEventListener('submit', e => {
    e.preventDefault();
    ui.q.blur();
    ui.grid.scrollIntoView({ behavior: 'smooth', block: 'start' });
  });

  ui.q.addEventListener('input', () => setQuery(ui.q.value, 'typing'));
  ui.q.addEventListener('focus', () => { fulltext.load(); }, { once: true });
  ui.q.addEventListener('keydown', e => {
    if (e.key === 'Escape' && ui.q.value) {
      e.preventDefault();
      setQuery('', 'push');
    }
  });

  ui.clear.addEventListener('click', () => {
    setQuery('', 'push');
    ui.q.focus();
  });

  // "/" focuses the search box unless the user is typing somewhere.
  document.addEventListener('keydown', e => {
    if (e.key !== '/' || e.ctrlKey || e.metaKey || e.altKey) return;
    const t = e.target;
    if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;
    e.preventDefault();
    ui.q.focus();
  });

  root.addEventListener('click', e => {
    const chip = e.target.closest('.keyword-chip');
    if (chip) {
      setQuery(chip.dataset.keyword || '', 'push');
      return;
    }
    const btn = e.target.closest('[data-filter][data-value]');
    if (btn) {
      const facet = btn.dataset.filter;
      const value = btn.dataset.value;
      const set = new Set(state[facet]);
      if (value === 'all') set.clear();
      else if (set.has(value)) set.delete(value);
      else set.add(value);
      state[facet] = set;
      update({ history: 'push' });
    }
  });

  ui.sort.addEventListener('change', () => {
    state.sort = ui.sort.value;
    state.sortExplicit = true;
    update({ history: 'push' });
  });

  if (ui.legacy) {
    ui.legacy.addEventListener('change', () => {
      state.showDeprecated = ui.legacy.checked;
      update({ history: 'push' });
    });
  }

  if (ui.reset) {
    ui.reset.addEventListener('click', () => {
      const keepSort = { sort: state.sort, sortExplicit: state.sortExplicit };
      state = { ...stateMod.createState(), ...keepSort, fulltext: state.fulltext };
      scheduleFulltext();
      update({ history: 'push' });
      ui.q.focus();
    });
  }

  if (ui.showAll) {
    ui.showAll.addEventListener('click', () => {
      const expanded = ui.showAll.getAttribute('aria-expanded') === 'true';
      root.querySelectorAll('.package-extra').forEach(el => {
        const selected = state.package.has(el.dataset.value);
        el.classList.toggle('d-none', expanded && !selected);
      });
      ui.showAll.setAttribute('aria-expanded', expanded ? 'false' : 'true');
      ui.showAll.textContent = expanded ? `Show all (${ui.showAll.dataset.total})` : 'Show fewer';
    });
  }

  window.addEventListener('popstate', () => {
    const ft = state.fulltext;
    state = stateMod.parseURL(location.search, options).state;
    state.fulltext = ft;
    scheduleFulltext();
    update({ history: 'none' });
  });

  // ---- start ----
  if (match.normaliseQuery(state.q).length >= FT_MIN_CHARS) fulltext.load();
  scheduleFulltext();
  update({ history: 'replace' });   // also rewrites legacy URLs to the canonical form
  // Reveal the controls only once the first render has succeeded.
  root.querySelectorAll('[data-tl-control]').forEach(el => { el.hidden = false; });
}

start().catch(() => {
  // On any failure leave the no-JS page as it is: controls stay hidden and
  // all current tutorials stay visible.
});
