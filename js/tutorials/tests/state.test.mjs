// Run with: node --test js/tutorials/tests/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseURL, toURL, createState } from '../state.js';
import { slugFromUrl } from '../fulltext.js';

const known = {
  beast: ['2.7', 'none'],
  workflow: ['Basic workflow', 'Advanced analysis'],
  domain: ['epidemiology'],
  package: ['BDSKY', 'starbeast3'],
};

test('round trip of a full state', () => {
  const qs = 'q=Skyline+plots&beast=2.7%2Cnone&workflow=Basic+workflow&package=BDSKY&deprecated=1&sort=title';
  const { state, canonical } = parseURL(qs, known);
  assert.equal(state.q, 'Skyline plots');
  assert.deepEqual([...state.beast], ['2.7', 'none']);
  assert.ok(state.showDeprecated);
  assert.equal(state.sort, 'title');
  assert.ok(state.sortExplicit);
  assert.equal(parseURL(canonical, known).canonical, canonical);
});

test('legacy aliases: search, legacy=1, sort=date/beastversion (#7)', () => {
  let r = parseURL('search=Coalescent&legacy=1&sort=beastversion', known);
  assert.equal(r.state.q, 'Coalescent');
  assert.ok(r.state.showDeprecated);
  assert.equal(r.state.sort, 'beast');
  assert.equal(r.canonical, 'q=Coalescent&deprecated=1&sort=beast');
  r = parseURL('sort=date', known);
  assert.equal(r.state.sort, 'updated');
});

test('unknown and hostile values are dropped, never thrown (#6)', () => {
  const r = parseURL('package=%22%5D&workflow=%22&domain=a%5C&sort=%22&beast=9.9', known);
  assert.equal(r.state.package.size, 0);
  assert.equal(r.state.workflow.size, 0);
  assert.equal(r.state.domain.size, 0);
  assert.equal(r.state.beast.size, 0);
  assert.equal(r.state.sortExplicit, false);
  assert.equal(r.canonical, '');
});

test('package lookup is case-insensitive and maps to the canonical name', () => {
  const r = parseURL('package=StarBeast3,bdsky', known);
  assert.deepEqual([...r.state.package].sort(), ['BDSKY', 'starbeast3']);
});

test('repeated params are accepted', () => {
  const r = parseURL('workflow=Basic+workflow&workflow=Advanced+analysis', known);
  assert.equal(r.state.workflow.size, 2);
});

test('defaults give an empty query string', () => {
  assert.equal(toURL(createState()), '');
});

test('slugFromUrl accepts only main tutorial pages', () => {
  assert.equal(slugFromUrl('/tutorials/Skyline-plots/'), 'Skyline-plots');
  assert.equal(slugFromUrl('/web-testing/tutorials/Skyline-plots/index.html'), 'Skyline-plots');
  assert.equal(slugFromUrl('/tutorials/Skyline-plots/LICENSE.html'), '');
  assert.equal(slugFromUrl('/tutorials/'), '');
  assert.equal(slugFromUrl('/news/x/'), '');
});
