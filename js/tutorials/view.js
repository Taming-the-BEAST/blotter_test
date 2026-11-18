// Renders derived state onto the server-rendered listing. No imports:
// helpers that depend on other modules are passed in by main.js.

function plural(n, word) {
  return `${n} ${word}${n === 1 ? '' : 's'}`;
}

export function statusText(summary, state, ftStatus, searching) {
  const { total, metaCount, textOnlyCount, deprecatedHidden } = summary;
  let text = plural(total, 'tutorial');
  if (state.q.trim()) {
    if (searching) {
      text += ' - searching tutorial text...';
    } else if (ftStatus === 'unavailable') {
      text += ' (titles and tags only - text search unavailable)';
    } else if (textOnlyCount > 0) {
      text += ` - ${metaCount} in titles/tags, ${textOnlyCount} in tutorial text`;
    }
  }
  if (deprecatedHidden > 0) text += ` (+${deprecatedHidden} deprecated)`;
  return text;
}

// Reorder grid children only when the order actually changed.
function applyOrder(grid, order) {
  const current = [...grid.children].filter(el => el.classList.contains('tutorial-card'));
  const wanted = order.map(i => i.el);
  if (current.length === wanted.length && current.every((el, k) => el === wanted[k])) return;
  const frag = document.createDocumentFragment();
  wanted.forEach(el => frag.appendChild(el));
  grid.appendChild(frag);
}

export function render(ui, items, state, derived, opts) {
  const { visible, order, counts, excerpts, sort, summary } = derived;

  // Cards: visibility, order, excerpts
  for (const item of items) {
    item.el.hidden = !visible.has(item);
    const slot = item.el.querySelector('.tutorial-fulltext-excerpt');
    if (!slot) continue;
    const excerpt = excerpts.get(item);
    if (excerpt) {
      if (slot.dataset.excerpt !== excerpt) {
        slot.replaceChildren(opts.sanitiseExcerpt(excerpt));
        slot.dataset.excerpt = excerpt;
      }
      slot.hidden = false;
    } else if (!slot.hidden) {
      slot.hidden = true;
      slot.replaceChildren();
      delete slot.dataset.excerpt;
    }
  }
  applyOrder(ui.grid, order);

  // Search box
  if (ui.q.value !== state.q) ui.q.value = state.q;
  ui.clear.hidden = state.q === '';
  if (ui.tryRow) ui.tryRow.hidden = state.q.trim() !== '';

  // Facet buttons
  for (const btn of ui.filterButtons) {
    const facet = btn.dataset.filter;
    const value = btn.dataset.value;
    const selected = state[facet];
    const active = value === 'all' ? selected.size === 0 : selected.has(value);
    btn.classList.toggle('active', active);
    btn.setAttribute('aria-pressed', active ? 'true' : 'false');
    if (value === 'all') continue;
    const n = counts[facet] && counts[facet].has(value) ? counts[facet].get(value) : 0;
    const dead = !active && n === 0;
    btn.classList.toggle('filter-dead', dead);
    btn.title = `${n} tutorial${n === 1 ? '' : 's'}`;
    // A selected package is never hidden behind "Show all".
    if (active && btn.classList.contains('package-extra')) btn.classList.remove('d-none');
  }

  // Sort
  const relevanceOpt = ui.sort.querySelector('option[value="relevance"]');
  if (relevanceOpt) relevanceOpt.hidden = relevanceOpt.disabled = !state.q.trim();
  if (ui.sort.value !== sort) ui.sort.value = sort;

  // Deprecated toggle
  if (ui.legacy) ui.legacy.checked = state.showDeprecated;

  // Status and empty state
  // The status is a live region: main.js debounces writes so screen readers
  // are not interrupted on every keystroke.
  opts.setStatus(statusText(summary, state, opts.ftStatus, opts.searching));
  if (ui.empty) ui.empty.hidden = summary.total > 0;
}
