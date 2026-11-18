// Run with: node --test js/tutorials/tests/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { versionKey, tokenize, metaScore, matchesFacets, derive, effectiveSort } from '../match.js';
import { createState } from '../state.js';
import { statusText } from '../view.js';

function item(o) {
  const title = o.title || 'T';
  const tags = [...(o.keywords || []), ...(o.packages || [])].join(' ');
  const other = [o.authors || '', (o.domains || []).join(' '), o.workflow || '', o.beastPkg ? 'beast ' + o.beastPkg : ''].join(' ');
  return {
    el: null,
    slug: o.slug || title,
    title,
    titleSort: title.toLowerCase(),
    date: o.date || '',
    beastPkg: o.beastPkg || '',
    workflow: o.workflow || '',
    packages: o.packages || [],
    domains: o.domains || [],
    keywords: o.keywords || [],
    deprecated: !!o.deprecated,
    text: {
      title: title.toLowerCase(),
      tags: tags.toLowerCase(),
      desc: (o.desc || '').toLowerCase(),
      other: other.toLowerCase(),
      all: [title, tags, o.desc || '', other].join(' ').toLowerCase(),
    },
  };
}

const items = [
  item({ slug: 'sky', title: 'Skyline plots', packages: ['BDSKY'], domains: ['epidemiology'], workflow: 'Basic workflow', beastPkg: '2.7', date: '20250301', keywords: ['coalescent'] }),
  item({ slug: 'sc', title: 'Structured coalescent', packages: ['MultiTypeTree'], domains: ['phylogeography'], workflow: 'Advanced analysis', beastPkg: '2.7', date: '20250801' }),
  item({ slug: 'intro', title: 'Introduction to BEAST2', packages: [], domains: ['macroevolution'], workflow: 'Getting started', beastPkg: '', date: '20250101', desc: 'simple introductory tutorial' }),
  item({ slug: 'old', title: 'StarBeast old', packages: ['StarBEAST2'], workflow: 'Advanced analysis', beastPkg: '2.10', date: '20200101', deprecated: true }),
];

test('versionKey orders 2.10 above 2.7 and missing last', () => {
  assert.ok(versionKey('2.10') > versionKey('2.7'));
  assert.equal(versionKey(''), -1);
  assert.equal(versionKey('none'), -1);
});

test('tokenize lowercases and collapses whitespace', () => {
  assert.deepEqual(tokenize('  Molecular   CLOCK '), ['molecular', 'clock']);
});

test('metaScore: all tokens must match; title match ranks highest', () => {
  assert.equal(metaScore(items[0], ['skyline', 'nomatch']), -1);
  assert.ok(metaScore(items[1], ['coalescent']) > metaScore(items[0], ['coalescent']) - 4);
  assert.ok(metaScore(items[0], ['bdsky']) >= 4);
});

test('domains are searchable (#5)', () => {
  assert.ok(metaScore(items[1], ['phylogeography']) >= 0);
});

test('facets: OR within, AND across; beast "none" for missing', () => {
  const s = createState();
  s.package = new Set(['BDSKY', 'MultiTypeTree']);
  assert.ok(matchesFacets(items[0], s));
  assert.ok(matchesFacets(items[1], s));
  s.domain = new Set(['epidemiology']);
  assert.ok(matchesFacets(items[0], s));
  assert.ok(!matchesFacets(items[1], s));
  const b = createState();
  b.beast = new Set(['none']);
  assert.ok(matchesFacets(items[2], b));
  assert.ok(!matchesFacets(items[0], b));
});

test('derive: deprecated matches counted separately while their section is closed', () => {
  const d = derive(items, createState(), { options: {} });
  assert.equal(d.summary.total, 3);
  assert.equal(d.summary.currentCount, 3);
  assert.equal(d.summary.deprecatedMatches, 1);
  assert.equal(d.summary.deprecatedHidden, 1);
  assert.ok([...d.visible].some(i => i.slug === 'old'));   // rendered in the deprecated section
  const s = createState(); s.showDeprecated = true;
  const open = derive(items, s, { options: {} });
  assert.equal(open.summary.total, 4);
  assert.equal(open.summary.deprecatedHidden, 0);
  const q = createState(); q.q = 'starbeast';
  assert.equal(derive(items, q, { options: {} }).summary.deprecatedMatches, 1);
  q.q = 'skyline';
  assert.equal(derive(items, q, { options: {} }).summary.deprecatedMatches, 0);
});

test('derive: disjunctive counts ignore the own facet', () => {
  const s = createState();
  s.package = new Set(['BDSKY']);
  const d = derive(items, s, { options: { package: ['BDSKY', 'MultiTypeTree'], domain: ['epidemiology', 'phylogeography'] } });
  assert.equal(d.counts.package.get('MultiTypeTree'), 1);   // other packages still count
  assert.equal(d.counts.domain.get('phylogeography'), 0);   // other facets apply
});

test('derive: full-text hits widen results only for the current query (#1)', () => {
  const s = createState();
  s.q = 'mcmc';
  s.package = new Set(['MultiTypeTree']);
  s.fulltext = { q: 'mcmc', hits: new Map([['sky', { rank: 0, excerpt: 'x' }], ['sc', { rank: 1, excerpt: 'y' }]]) };
  let d = derive(items, s, { options: {} });
  assert.deepEqual([...d.visible].map(i => i.slug), ['sc']);
  s.package = new Set();                       // removing the facet shows all text hits
  d = derive(items, s, { options: {} });
  assert.deepEqual([...d.visible].map(i => i.slug).sort(), ['sc', 'sky']);
  s.q = 'mcmc chain';                          // stale hits are ignored
  d = derive(items, s, { options: {} });
  assert.equal(d.visible.size, 0);
});

test('derive: relevance puts metadata hits before text-only hits', () => {
  const s = createState();
  s.q = 'coalescent';
  s.fulltext = { q: 'coalescent', hits: new Map([['intro', { rank: 0, excerpt: '' }]]) };
  const d = derive(items, s, { options: {} });
  const order = d.order.filter(i => d.visible.has(i)).map(i => i.slug);
  assert.deepEqual(order, ['sc', 'sky', 'intro']);
  assert.equal(d.summary.metaCount, 2);
  assert.equal(d.summary.textOnlyCount, 1);
});

test('effectiveSort: explicit sort sticks (#25); relevance only with a query', () => {
  const s = createState();
  assert.equal(effectiveSort(s), 'updated');
  s.q = 'x';
  assert.equal(effectiveSort(s), 'relevance');
  s.sort = 'title'; s.sortExplicit = true;
  assert.equal(effectiveSort(s), 'title');
  s.q = ''; s.sort = 'relevance';
  assert.equal(effectiveSort(s), 'updated');
});

test('derive: beast sort newest first, missing last', () => {
  const s = createState(); s.showDeprecated = true; s.sort = 'beast'; s.sortExplicit = true;
  const d = derive(items, s, { options: {} });
  assert.deepEqual(d.order.map(i => i.slug), ['old', 'sky', 'sc', 'intro']);
});

test('deprecated scope: counts and status follow the deprecated section', () => {
  const opts = { options: { package: ['StarBEAST2', 'BDSKY'] } };
  const closed = createState();
  let d = derive(items, closed, opts);
  assert.equal(d.counts.package.get('StarBEAST2'), 0);         // only the deprecated item has it
  assert.equal(statusText(d.summary, closed, 'ready', false), '3 tutorials (+1 deprecated)');
  const open = createState(); open.showDeprecated = true;
  d = derive(items, open, opts);
  assert.equal(d.counts.package.get('StarBEAST2'), 1);
  assert.equal(statusText(d.summary, open, 'ready', false), '4 tutorials');
  const q = createState(); q.q = 'starbeast';
  d = derive(items, q, opts);
  assert.equal(d.summary.total, 0);
  assert.equal(d.summary.metaCount, 0);                          // deprecated match not counted while closed
  assert.equal(d.summary.deprecatedMatches, 1);
});

test('diacritics are folded in queries', () => {
  assert.deepEqual(tokenize('M\u00fcller  Pe\u010derska'), ['muller', 'pecerska']);
});
