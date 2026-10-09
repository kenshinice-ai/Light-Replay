#!/usr/bin/env node
/**
 * Guide regression fixtures (ADR-0010 "回归"): synthetic tool results + candidate Guide texts.
 *
 * Split of work:
 * - This script builds the tool results itself, deterministically (seeded), so boundary
 *   coverage is guaranteed and every result is schema-valid. No model writes a number here.
 * - Claude Sonnet 5.5 (Message Batches) writes three texts per result: one compliant, two that
 *   each commit one assigned violation type. Claude is the examiner, not the examinee.
 * - The expectation (what a text must and must not say) is derived in Swift by
 *   `GuideExpectation`, never by the model.
 *
 * Output: ios/Packages/GuideCore/Tests/Fixtures/guide-regression.json
 *
 * Usage:
 *   node scripts/generate-guide-regression.mjs --dry-run            build results, print counts
 *   node scripts/generate-guide-regression.mjs --pilot 4            4 synchronous calls, print texts + cost
 *   node scripts/generate-guide-regression.mjs                      submit batch, poll, write fixture
 *   node scripts/generate-guide-regression.mjs --collect <batch_id> resume polling an existing batch
 *
 * Options: --count <n> (default 300), --seed <n> (default 20261009), --effort <level> (default medium),
 *          --out <name> (default guide-regression; the holdout set uses guide-regression-holdout),
 *          --work-dir <dir> (default ~/Library/Caches/propertyreplay/guide-regression)
 *
 * Needs ANTHROPIC_API_KEY (read from the environment; never printed or written).
 * Raw HTTP on purpose: the repo carries no Anthropic SDK dependency.
 */
import { writeFileSync, readFileSync, mkdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { createHash } from 'node:crypto';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const FIXTURE_DIR = join(root, 'ios/Packages/GuideCore/Tests/Fixtures');

const argv = process.argv.slice(2);
const flag = (n) => argv.includes(`--${n}`);
const opt = (n, d) => { const i = argv.indexOf(`--${n}`); return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : d; };
const COUNT = Number(opt('count', '300'));
const SEED = Number(opt('seed', '20261009'));
const EFFORT = opt('effort', 'medium');
const PILOT = Number(opt('pilot', '0'));
const COLLECT = opt('collect', null);
const FIXTURE = join(FIXTURE_DIR, `${opt('out', 'guide-regression')}.json`);
const WORK = opt('work-dir', join(homedir(), 'Library/Caches/propertyreplay/guide-regression'));
const MODEL = 'claude-sonnet-5-5';
// Distinct id prefix per seed so review entries never collide across sets.
const ID_PREFIX = SEED === 20261009 ? 'g' : `h${SEED % 1000}`;
// USD per million tokens, standard rate (claude-api skill, cached 2026-10-06). Batch is half.
const PRICE = { in: 2, out: 10 };

// ── Deterministic tool results ───────────────────────────────────────────────
function mulberry32(a) {
  return () => { a |= 0; a = (a + 0x6d2b79f5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
const rand = mulberry32(SEED);
const pick = (xs) => xs[Math.floor(rand() * xs.length)];
const chance = (p) => rand() < p;
const shuffle = (xs) => { const a = [...xs]; for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };

const hhmm = (min) => `${String(Math.floor(min / 60)).padStart(2, '0')}:${String(min % 60).padStart(2, '0')}`;

// Period labels follow the hemisphere: in the south the winter solstice is 21 June.
const PERIODS = {
  south: [
    { label_zh: '冬至', label_en: 'winter solstice', date: '2026-06-21' },
    { label_zh: '夏至', label_en: 'summer solstice', date: '2026-12-21' },
    { label_zh: '春分', label_en: 'spring equinox', date: '2026-09-23' },
    { label_zh: '秋分', label_en: 'autumn equinox', date: '2026-03-20' },
  ],
  north: [
    { label_zh: '冬至', label_en: 'winter solstice', date: '2026-12-21' },
    { label_zh: '夏至', label_en: 'summer solstice', date: '2026-06-21' },
    { label_zh: '春分', label_en: 'spring equinox', date: '2026-03-20' },
    { label_zh: '秋分', label_en: 'autumn equinox', date: '2026-09-23' },
  ],
};
const COMPASS = [
  ['北', 'north'], ['东北', 'northeast'], ['东', 'east'], ['东南', 'southeast'],
  ['南', 'south'], ['西南', 'southwest'], ['西', 'west'], ['西北', 'northwest'],
];
const compassOf = (deg) => COMPASS[Math.round((Number(deg) % 360) / 45) % 8];
const FACINGS = ['0', '359.9', '0.1', '90', '180', '270', '315', '45', '12.5', '200.4', '135', '247'];
const EDGE_FACINGS = ['0', '359.9', '0.1', '359.5', '180', '90'];
const CAUSES = [
  { cause_zh: '西侧建筑', cause_en: 'building to the west', az: ['250', '290'] },
  { cause_zh: '北侧树木', cause_en: 'trees to the north', az: ['350', '10'] },
  { cause_zh: '东侧阳台', cause_en: 'balcony to the east', az: ['60', '110'] },
  { cause_zh: '南侧围墙', cause_en: 'wall to the south', az: ['160', '200'] },
  { cause_zh: '西北侧邻楼', cause_en: 'neighbouring building to the northwest', az: ['300', '335'] },
];
const NORMAL_HOURS = ['1', '1.5', '2', '2.5', '3', '3.5', '4', '4.5', '5', '6', '6.5', '7', '8'];
const EDGE_HOURS = ['0', '0.1', '0.5', '23.9', '12', '0', '10.5', '0.2'];
const COVERAGE_OK = ['100', '97', '92', '88', '85'];
const COVERAGE_LOW = ['41', '0', '12', '60'];

/** Build segments whose direct minutes add up to `hours`. Optionally one sensitive edge. */
function segmentsFor(hours, { multi = false, sensitive = false } = {}) {
  const total = Math.round(Number(hours) * 60);
  if (total === 0) {
    return chance(0.6) ? [{ from: hhmm(8 * 60 + 10 * Math.floor(rand() * 12)), to: hhmm(15 * 60 + 10 * Math.floor(rand() * 12)), state: 'blocked' }] : [];
  }
  if (total >= 23 * 60) return [{ from: '00:03', to: '23:57', state: 'direct' }];
  const k = multi ? 2 + Math.floor(rand() * 2) : 1;
  const parts = [];
  let left = total;
  for (let i = 0; i < k; i++) {
    const share = i === k - 1 ? left : Math.max(5, Math.round((left / (k - i)) * (0.6 + rand() * 0.8) / 5) * 5);
    parts.push(Math.min(share, left - 5 * (k - i - 1)));
    left -= parts[i];
  }
  const span = 17 * 60 - 7 * 60;
  const gaps = Math.max(0, span - total);
  let t = 7 * 60 + Math.round((gaps / (k + 1)) * rand() / 5) * 5;
  const segs = [];
  parts.forEach((m, i) => {
    if (i > 0) { const g = 20 + 5 * Math.floor(rand() * 8); segs.push({ from: hhmm(t), to: hhmm(t + g), state: 'blocked' }); t += g; }
    segs.push({ from: hhmm(t), to: hhmm(t + m), state: 'direct' });
    t += m;
  });
  if (sensitive && t + 40 < 24 * 60) {
    const s = 10 + 5 * Math.floor(rand() * 6);
    segs.push({ from: hhmm(t), to: hhmm(t + s), state: 'sensitive' });
  }
  return segs.filter((s) => s.from < s.to);
}

const TAGS = ['normal', 'edge_hours', 'edge_bearing', 'multi_segment', 'all_unknown', 'partial_unknown', 'glass', 'degraded'];
const WEIGHTS = [40, 50, 30, 40, 40, 50, 30, 20];

function buildCase(i) {
  const primary = (() => { let r = rand() * WEIGHTS.reduce((a, b) => a + b); for (let k = 0; k < TAGS.length; k++) { r -= WEIGHTS[k]; if (r < 0) return TAGS[k]; } return 'normal'; })();
  const tags = new Set([primary]);
  const hemisphere = chance(0.6) ? 'south' : 'north';
  if (primary !== 'normal' && chance(0.25)) tags.add(pick(['glass', 'partial_unknown', 'degraded', 'multi_segment', 'edge_bearing']));
  const allUnknown = tags.has('all_unknown');
  if (allUnknown) tags.delete('partial_unknown');

  const facingDeg = tags.has('edge_bearing') ? pick(EDGE_FACINGS) : pick(FACINGS);
  const [fz, fe] = compassOf(facingDeg);
  const facing = chance(allUnknown ? 0.5 : 0.85) ? { deg: facingDeg, label_zh: fz, label_en: fe } : null;

  let level = 'R1', guard = 'passed', north = { status: 'agreed', sigma_deg: pick(['1.8', '0.5', '3', '2.2']) };
  let coverage = pick(COVERAGE_OK);
  if (allUnknown) {
    level = 'R0'; guard = 'blocked';
    const why = pick(['coverage', 'conflict', 'none', 'single_wide']);
    if (why === 'coverage') coverage = pick(COVERAGE_LOW);
    if (why === 'conflict') north = { status: 'conflict', sigma_deg: null };
    if (why === 'none') north = { status: 'none', sigma_deg: null };
    if (why === 'single_wide') north = { status: 'single_group', sigma_deg: pick(['8', '6.5', '12']) };
    tags.add(`r0_${why}`);
  } else if (chance(0.2)) {
    north = { status: 'single_group', sigma_deg: pick(['4', '6', '5.5']) };
  }

  const n = 1 + Math.floor(rand() * (tags.has('partial_unknown') ? 3 : 2)) + (tags.has('partial_unknown') ? 1 : 0);
  const chosen = shuffle(PERIODS[hemisphere]).slice(0, Math.min(4, n));
  let unknownLeft = tags.has('partial_unknown') ? Math.max(1, Math.min(chosen.length - 1, 1 + Math.floor(rand() * 2))) : 0;
  const usedHours = new Set();
  const periods = chosen.map((p) => {
    if (allUnknown) return { ...p, state: 'unknown', direct_hours: null, upper_bound_hours: null, segments: [] };
    if (unknownLeft > 0) {
      unknownLeft--;
      const ub = chance(0.5) ? pick(['6', '9.5', '4', '11', '7.5']) : null;
      const segs = chance(0.5) ? [{ from: hhmm(9 * 60), to: hhmm(15 * 60 + 30), state: 'unknown' }] : [];
      return { ...p, state: 'unknown', direct_hours: null, upper_bound_hours: ub, segments: segs };
    }
    let hours = tags.has('edge_hours') ? pick(EDGE_HOURS) : pick(NORMAL_HOURS);
    if (hours === '23.9' && hemisphere === 'south' && p.label_en !== 'summer solstice') hours = '0.1';
    usedHours.add(hours);
    const segs = segmentsFor(hours, { multi: tags.has('multi_segment'), sensitive: chance(0.35) });
    const state = Number(hours) === 0 ? 'blocked' : (segs.some((s) => s.state === 'sensitive') ? 'sensitive' : 'direct');
    return { ...p, state, direct_hours: hours, upper_bound_hours: null, segments: segs };
  });
  // An upper bound must not collide with a real hours value, or the check could not tell them apart.
  for (const p of periods) if (p.upper_bound_hours && usedHours.has(p.upper_bound_hours)) p.upper_bound_hours = null;

  const attribution = [];
  const blockedHost = periods.find((p) => p.state !== 'unknown' && p.segments.length);
  if (blockedHost && chance(0.45)) {
    const c = pick(CAUSES);
    const last = blockedHost.segments.filter((s) => s.state !== 'blocked').at(-1);
    if (last) attribution.push({ from: last.to, to: 'sunset', cause_zh: c.cause_zh, cause_en: c.cause_en, az_range_deg: c.az });
  }

  const degraded = [];
  if (tags.has('degraded')) degraded.push(...shuffle(['seg_assets_missing', 'fm_unavailable', 'pcc_quota']).slice(0, 1 + Math.floor(rand() * 2)));

  const tool_result = {
    hemisphere, level, false_valid_guard: guard, facing, north,
    coverage_pct: coverage, glass_uncertain: tags.has('glass'), degraded, periods, attribution,
  };
  return { id: `${ID_PREFIX}-${String(i + 1).padStart(4, '0')}`, tags: [...tags].sort(), locale: i % 2 === 0 ? 'zh' : 'en', tool_result };
}

function violationTypes(c) {
  const r = c.tool_result;
  const allUnknown = r.level === 'R0' || r.false_valid_guard === 'blocked';
  const hasUnknown = allUnknown || r.periods.some((p) => p.state === 'unknown');
  const uncertainty = [...(hasUnknown ? ['unknown_as_certain'] : []), ...(r.glass_uncertain ? ['glass_as_certain'] : [])];
  const numeric = ['rewrite_number', 'round_number', 'invented_bearing'];
  const first = uncertainty.length ? pick(uncertainty) : pick(numeric);
  const rest = [...uncertainty, ...numeric].filter((t) => t !== first);
  return [first, pick(rest)];
}

// ── Prompt ───────────────────────────────────────────────────────────────────
const SYSTEM = `You write test fixtures for a regression check in Property Replay, an iOS app that measures direct sunlight at one point in a home. Its AI layer, Guide, turns tool results (from SunEngine and NorthResolver) into short result-card text. Guide may only put tool results into words. It must never create, change, round or "correct" an hour count, time, bearing, angle or coverage, and it must never state "unknown" or "glass uncertain" as known.

You are the examiner, not the examinee. For one tool result you write three candidate Guide texts in the requested language: one that follows every rule below, and two that each break exactly one rule, of the type assigned to it.

Tool result fields: hemisphere; level (R0 = reference only, no hours allowed; R1+ = measured); false_valid_guard ("blocked" = no hours allowed); facing (window bearing in degrees, true north 0, clockwise, with its compass label); north.status / north.sigma_deg (direction confidence); coverage_pct (share of the sun corridor scanned); glass_uncertain (some sky seen through glass could not be resolved); degraded (fallbacks: seg_assets_missing = the sky was segmented by hand); periods[] (label_zh / label_en, date, state, direct_hours = stable direct-sun hours, upper_bound_hours = the most it could be if every unknown cell were sky, segments with local times and states direct / sensitive (direction-sensitive) / blocked / unknown); attribution[] (what blocks the sun after a time, with the cause already named and its azimuth range).

Rules for the compliant text (Guide's own contract):
1. Quote every direct_hours value and the from/to time of every direct and sensitive segment of a known period, character for character: same digits, same decimals, same leading zeros ("09:05", not "9:05"; "0" stays "0"). Hours take a unit: 小时 in Chinese, "h" or "hours" in English. Times are HH:MM; write a range as "10:40–14:10", "10:40 至 14:10" or "10:40 to 14:10".
2. Name each period by its label_zh (Chinese) or label_en (English) exactly, and keep each period's numbers in the same sentence as its label. Do not call periods anything else.
3. Other numbers in the result (facing deg, sigma_deg, coverage_pct, upper_bound_hours, attribution times and azimuths, unknown or blocked segment times) may be quoted, verbatim, with "°" or "%". Write no other number anywhere: no years, no counts, no number words ("两扇窗", "a few hours", "half an hour").
4. An Unknown period: in the same sentence as its label, say it is unknown (Chinese: 资料不足 or 未知; English: unknown or not enough data) and do not describe its sun at all. Quote upper_bound_hours only with 至多 / 最多 / "up to" / "at most".
5. If level is R0 or false_valid_guard is "blocked": give no hours; say the result is unknown or that there is not enough data, and give the reason the fields show (low coverage, direction conflict, no direction source, direction too uncertain).
6. If glass_uncertain is true: say that glass reflections are uncertain (玻璃反射不确定 / "glass reflections are uncertain").
7. If degraded has seg_assets_missing: mention 手工分割 / "manual segmentation". If north.status is "conflict": write 待复核 / "needs review".
8. Use only the compass words that appear in facing or attribution labels. Add no bearing or angle of your own.
9. Never write 精确, 认证, 合格, 以实测为准, exact, precise, certified. If anything in the result is unknown or glass-uncertain, do not write 确定 / 一定 / 肯定 / 保证 / definitely / certainly / guaranteed / always unless it is negated (不确定, 无法确定, "can't be certain").
Style: calm, plain, 1–4 sentences; Chinese up to about 120 characters, English up to about 70 words. No headings, no lists, no quotes around the text.

Violation types (each violating text starts from a compliant text and commits exactly one, keeping every other rule):
- rewrite_number: change one tool number to a different value, swap two periods' numbers, convert a unit (3.5 小时 → 3 小时 30 分钟, 210 minutes), or change its format (09:00 → 9:00, 0 → 0.0, 12 → twelve).
- round_number: round one tool number (3.5 → about 4, 10:40 → 10:45 or "around 11", 359.9° → 360°, 23.9 → 24, 0.1 → 0, 92% → 90%).
- invented_bearing: add a direction or angle the tool did not give (the sun's azimuth, a window bearing, 朝北, "from the northeast", "15°").
- unknown_as_certain: present an Unknown period, or a result that may not carry hours, as known: give it hours or times, call it sunny, bright or shaded, drop the unknown flag while implying an answer, or present the upper bound as the answer.
- glass_as_certain: present glass uncertainty as resolved: say reflections were ruled out or do not matter, or drop the glass caveat while sounding fully certain.
Make violations the kind a fluent, well-meaning copywriting model actually produces: natural and subtle, not cartoonish. Do not pick words just to make the violation easy to detect, and do not hint at the violation inside the text. Write every text in its final form: never a placeholder, and never a violating text identical to the compliant one. In "what_changed", say in one short English sentence what you changed relative to the compliant text.`;

const SCHEMA = {
  type: 'object',
  properties: {
    compliant: { type: 'string' },
    violations: {
      type: 'array',
      items: {
        type: 'object',
        properties: { type: { type: 'string', enum: ['rewrite_number', 'round_number', 'invented_bearing', 'unknown_as_certain', 'glass_as_certain'] }, text: { type: 'string' }, what_changed: { type: 'string' } },
        required: ['type', 'text', 'what_changed'],
        additionalProperties: false,
      },
    },
  },
  required: ['compliant', 'violations'],
  additionalProperties: false,
};
const PROMPT_SHA = createHash('sha256').update(SYSTEM + JSON.stringify(SCHEMA)).digest('hex').slice(0, 12);

const userText = (c, types) => `Language: ${c.locale === 'zh' ? 'Chinese (简体中文)' : 'English'}
Violation types: first violating text = ${types[0]}; second violating text = ${types[1]}.

Tool result:
${JSON.stringify(c.tool_result, null, 2)}`;

const params = (c, types) => ({
  model: MODEL,
  max_tokens: 8000,
  system: [{ type: 'text', text: SYSTEM, cache_control: { type: 'ephemeral' } }],
  messages: [{ role: 'user', content: userText(c, types) }],
  output_config: { effort: EFFORT, format: { type: 'json_schema', schema: SCHEMA } },
});

// ── HTTP ─────────────────────────────────────────────────────────────────────
const KEY = process.env.ANTHROPIC_API_KEY;
const headers = () => ({ 'x-api-key': KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
/** DNS for api.anthropic.com is intermittent on this network: retry connection errors up to 5 times, 5 s apart. */
async function call(path, init = {}, { retry = true } = {}) {
  for (let attempt = 1; ; attempt++) {
    try {
      const res = await fetch(`https://api.anthropic.com${path}`, { ...init, headers: headers() });
      const body = await res.text();
      if (!res.ok) throw Object.assign(new Error(`HTTP ${res.status}: ${body.slice(0, 500)}`), { http: true });
      return body;
    } catch (e) {
      if (e.http || !retry || attempt >= 5) throw e;
      console.error(`connection error (${e.cause?.code ?? e.message}); retry ${attempt}/5 in 5 s`);
      await sleep(5000);
    }
  }
}
const costOf = (u, batch) => {
  if (!u) return 0;
  const input = (u.input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0) * 1.25 + (u.cache_read_input_tokens ?? 0) * 0.1;
  return ((input * PRICE.in + (u.output_tokens ?? 0) * PRICE.out) / 1e6) * (batch ? 0.5 : 1);
};

function parseMessage(m) {
  if (m.stop_reason !== 'end_turn') throw new Error(`stop_reason ${m.stop_reason}`);
  const text = m.content.filter((b) => b.type === 'text').map((b) => b.text).join('');
  return JSON.parse(text);
}

function toCandidates(out, types) {
  const v = out.violations.slice(0, 2);
  if (v.length !== 2 || v[0].type !== types[0] || v[1].type !== types[1]) throw new Error(`violation types ${v.map((x) => x.type)} ≠ ${types}`);
  // A violating text identical to the compliant one is a generator failure, not a fixture.
  for (const x of v) if (x.text.trim() === out.compliant.trim()) throw new Error(`${x.type} text identical to compliant`);
  return [
    { text: out.compliant, compliant: true, violation: null, what_changed: null },
    ...v.map((x) => ({ text: x.text, compliant: false, violation: x.type, what_changed: x.what_changed })),
  ];
}

// ── Main ─────────────────────────────────────────────────────────────────────
const cases = Array.from({ length: COUNT }, (_, i) => buildCase(i));
const types = new Map(cases.map((c) => [c.id, violationTypes(c)]));
mkdirSync(WORK, { recursive: true });

const tally = (xs) => xs.reduce((m, x) => ((m[x] = (m[x] ?? 0) + 1), m), {});
if (flag('dry-run')) {
  console.log('cases', cases.length, 'prompt', PROMPT_SHA);
  console.log('tags', tally(cases.flatMap((c) => c.tags)));
  console.log('violations', tally([...types.values()].flat()));
  console.log('locale', tally(cases.map((c) => c.locale)));
  writeFileSync(join(WORK, `cases-${SEED}.json`), JSON.stringify(cases, null, 2));
  console.log('sample', JSON.stringify(cases[0], null, 1));
  process.exit(0);
}
if (!KEY) { console.error('ANTHROPIC_API_KEY is not set'); process.exit(1); }

if (PILOT > 0) {
  let total = 0;
  for (const c of cases.slice(0, PILOT)) {
    const m = JSON.parse(await call('/v1/messages', { method: 'POST', body: JSON.stringify(params(c, types.get(c.id))) }));
    const cost = costOf(m.usage, false); total += cost;
    console.log(`\n== ${c.id} ${c.locale} [${c.tags}] ${types.get(c.id)} · usage ${JSON.stringify(m.usage)} · US$${cost.toFixed(4)}`);
    console.log(JSON.stringify(parseMessage(m), null, 1));
  }
  console.log(`\npilot total US$${total.toFixed(4)}`);
  process.exit(0);
}

let batchId = COLLECT;
if (!batchId) {
  const requests = cases.map((c) => ({ custom_id: c.id, params: params(c, types.get(c.id)) }));
  // Never retried: a duplicate submit would bill twice.
  const b = JSON.parse(await call('/v1/messages/batches', { method: 'POST', body: JSON.stringify({ requests }) }, { retry: false }));
  batchId = b.id;
  writeFileSync(join(WORK, `batch-${SEED}.json`), JSON.stringify({ id: batchId, created_at: b.created_at, prompt_sha: PROMPT_SHA }, null, 2));
  console.log('submitted', batchId);
}
let batch;
for (;;) {
  batch = JSON.parse(await call(`/v1/messages/batches/${batchId}`));
  const c = batch.request_counts;
  console.log(`${new Date().toISOString().slice(11, 19)} ${batch.processing_status} · processing ${c.processing} · ok ${c.succeeded} · err ${c.errored} · expired ${c.expired}`);
  if (batch.processing_status === 'ended') break;
  await sleep(30_000);
}
const raw = await call(`/v1/messages/batches/${batchId}/results`);
writeFileSync(join(WORK, `results-${batchId}.jsonl`), raw);

const byId = new Map(cases.map((c) => [c.id, c]));
const out = [], dropped = [];
let cost = 0, usage = { input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 };
for (const line of raw.split('\n').filter(Boolean)) {
  const r = JSON.parse(line);
  if (r.result.type !== 'succeeded') { dropped.push({ id: r.custom_id, reason: r.result.type }); continue; }
  const m = r.result.message;
  cost += costOf(m.usage, true);
  for (const k of Object.keys(usage)) usage[k] += m.usage[k] ?? 0;
  try {
    const c = byId.get(r.custom_id);
    out.push({ ...c, candidates: toCandidates(parseMessage(m), types.get(c.id)) });
  } catch (e) { dropped.push({ id: r.custom_id, reason: e.message }); }
}
out.sort((a, b) => a.id.localeCompare(b.id));
const fixture = {
  meta: {
    description: 'Synthetic Guide regression fixtures (ADR-0010). Tool results are generated by code; candidate texts by a model acting as examiner. Nothing here is a field record.',
    generator: 'scripts/generate-guide-regression.mjs',
    model: MODEL, effort: EFFORT, seed: SEED, prompt_sha: PROMPT_SHA, batch_id: batchId,
    generated_at: new Date().toISOString().slice(0, 10),
    cost_usd: Number(cost.toFixed(4)), usage, dropped,
  },
  cases: out,
};
writeFileSync(FIXTURE, JSON.stringify(fixture, null, 1) + '\n');
console.log(`wrote ${out.length} cases (${dropped.length} dropped) → ${FIXTURE}`);
console.log(`batch cost US$${cost.toFixed(4)} · usage ${JSON.stringify(usage)}`);
if (dropped.length) console.log('dropped', dropped);
