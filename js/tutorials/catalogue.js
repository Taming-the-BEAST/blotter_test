// Reads the server-rendered cards and filter controls into plain data.
// The only module that reads data-* attributes. No imports.

const SEP = '|';

function list(value) {
  return (value || '').split(SEP).map(v => v.trim()).filter(Boolean);
}

function lc(value) {
  return (value || '').toLowerCase();
}

// One item per `.tutorial-card` element.
export function buildCatalogue(root) {
  const items = [];
  for (const el of root.querySelectorAll('.tutorial-card')) {
    const d = el.dataset;
    const packages = list(d.packages);
    const domains = list(d.domains);
    const keywords = list(d.keywords);
    const title = d.title || '';
    const tags = [...keywords, ...packages].join(' ');
    const other = [d.authors, domains.join(' '), d.workflow, d.beastPkg ? 'beast ' + d.beastPkg : ''].join(' ');
    items.push({
      el,
      slug: d.slug || '',
      title,
      titleSort: lc(title),
      date: d.date || '',
      beastPkg: d.beastPkg || '',
      workflow: d.workflow || '',
      packages,
      domains,
      keywords,
      deprecated: d.status === 'deprecated',
      text: {
        title: lc(title),
        tags: lc(tags),
        desc: lc(d.desc),
        other: lc(other),
        all: lc([title, tags, d.desc, other].join(' ')),
      },
    });
  }
  return items;
}

// Known option values per facet, for URL whitelisting and counts.
// Workflow/domain/package come from the rendered filter buttons; BEAST
// versions from the cards themselves.
export function knownOptions(root, items) {
  const fromButtons = facet => [...root.querySelectorAll(`[data-filter="${facet}"]`)]
    .map(b => b.dataset.value)
    .filter(v => v && v !== 'all');
  const beast = [...new Set(items.map(i => i.beastPkg || 'none'))];
  return {
    beast,
    workflow: fromButtons('workflow'),
    domain: fromButtons('domain'),
    package: [...new Set([...fromButtons('package'), ...items.flatMap(i => i.packages)])],
  };
}
