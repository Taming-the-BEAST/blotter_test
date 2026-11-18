// Pagefind full-text search: lazy loading, stale-result guard, cache and
// excerpt sanitising. No imports.

const MAX_RESULTS = 50;
const CACHE_SIZE = 30;

// Slug of a tutorial's main page: /tutorials/<slug>/ or /tutorials/<slug>/index.html.
// Anything else (LICENSE pages, sub-pages, other sites) gives ''.
export function slugFromUrl(url) {
  const path = String(url || '').split(/[?#]/)[0];
  const m = /\/tutorials\/([^/]+)\/(?:index\.html)?$/.exec(path);
  return m ? decodeURIComponent(m[1]) : '';
}

// Turn a Pagefind excerpt (HTML with <mark>) into a DocumentFragment that
// contains only text nodes and <mark> elements. The excerpt is parsed in an
// inert document (no scripts run, nothing loads) and rebuilt node by node.
export function sanitiseExcerpt(html, doc = document) {
  const frag = doc.createDocumentFragment();
  const parsed = new DOMParser().parseFromString(`<body>${html || ''}</body>`, 'text/html');
  const walk = (node, inMark) => {
    for (const child of node.childNodes) {
      if (child.nodeType === 3) {
        if (inMark) {
          const mark = doc.createElement('mark');
          mark.textContent = child.textContent;
          frag.appendChild(mark);
        } else {
          frag.appendChild(doc.createTextNode(child.textContent));
        }
      } else if (child.nodeType === 1) {
        walk(child, inMark || child.nodeName === 'MARK');
      }
    }
  };
  walk(parsed.body, false);
  return frag;
}

// createFulltext(url) -> { status, load(), search(q) }
// status: 'idle' | 'loading' | 'ready' | 'unavailable'
// search(q) resolves to Map<slug, {rank, excerpt}>, or null when a newer
// search (or cancel()) superseded it.
export function createFulltext(url, knownSlugs) {
  let pagefind = null;
  let loading = null;
  let seq = 0;
  const cache = new Map();

  const api = {
    status: 'idle',

    load() {
      if (loading) return loading;
      api.status = 'loading';
      loading = import(url)
        .then(async mod => {
          await mod.init();
          pagefind = mod;
          api.status = 'ready';
          return true;
        })
        .catch(() => {
          api.status = 'unavailable';
          return false;
        });
      return loading;
    },

    // Invalidate any search in flight.
    cancel() {
      seq++;
    },

    async search(q) {
      const mySeq = ++seq;
      if (cache.has(q)) {
        const hit = cache.get(q);
        cache.delete(q);
        cache.set(q, hit);
        return hit;
      }
      const ok = await api.load();
      if (!ok || mySeq !== seq) return null;

      let found;
      try {
        found = await pagefind.search(q);
      } catch (e) {
        return null;
      }
      if (mySeq !== seq || !found) return null;

      let data;
      try {
        data = await Promise.all(found.results.slice(0, MAX_RESULTS).map(r => r.data()));
      } catch (e) {
        return null;
      }
      if (mySeq !== seq) return null;

      const hits = new Map();
      data.forEach((d, i) => {
        const slug = slugFromUrl(d.url);
        if (!slug || hits.has(slug)) return;
        if (knownSlugs && !knownSlugs.has(slug)) return;
        hits.set(slug, { rank: i, excerpt: d.excerpt || '' });
      });

      cache.set(q, hits);
      if (cache.size > CACHE_SIZE) cache.delete(cache.keys().next().value);
      return hits;
    },
  };
  return api;
}
