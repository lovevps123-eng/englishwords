import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const read = path => readFileSync(join(root, path), 'utf8');
const listing = JSON.parse(read('zh-Hans/store-listing.json'));
const markdown = read('zh-Hans/store-listing.md');
const section = title => {
  const marker = `## ${title}\n\n`;
  assert(markdown.includes(marker), `Missing section: ${title}`);
  return markdown.split(marker)[1].split('\n## ')[0].trim();
};
const limits = {name: 30, subtitle: 30, promotionalText: 170, keywords: 100};
for (const [field, limit] of Object.entries(limits)) {
  const length = [...listing[field]].length;
  assert(length > 0 && length <= limit, `${field}: ${length}/${limit}`);
  console.log(`${field}: ${length}/${limit}`);
}
assert.equal(section('名称').split('\n')[0], listing.name);
assert.equal(section('副标题'), listing.subtitle);
assert.equal(section('推广文本'), listing.promotionalText);
assert.equal(section('关键词'), listing.keywords);
const descriptionLength = [...section('描述')].length;
assert(descriptionLength > 0 && descriptionLength <= 4000);
console.log(`description: ${descriptionLength}/4000`);
assert.equal(listing.status, 'local_draft_not_submitted');
assert.equal(listing.supportUrl, 'https://senior.dafang-edu.com/support');
assert.equal(listing.privacyPolicyUrl, 'https://senior.dafang-edu.com/privacy');
assert.equal(listing.copyright, null);
assert.equal(listing.reviewCredentialsIncluded, false);

const manifest = JSON.parse(read('screenshots/manifest.json'));
const imageFiles = readdirSync(join(root, 'screenshots')).filter(name => /\.jpe?g$/i.test(name));
assert.equal(manifest.screenshots.length, 5);
assert.deepEqual(imageFiles.sort(), manifest.screenshots.map(item => item.file).sort());
for (const {file, sha256} of manifest.screenshots) {
  const path = join(root, 'screenshots', file);
  assert.equal(createHash('sha256').update(readFileSync(path)).digest('hex'), sha256, file);
  const properties = execFileSync('/usr/bin/sips', ['-g', 'pixelWidth', '-g', 'pixelHeight', '-g', 'hasAlpha', '-g', 'format', path], {encoding: 'utf8'});
  assert.match(properties, /pixelWidth: 1320\b/);
  assert.match(properties, /pixelHeight: 2868\b/);
  assert.match(properties, /hasAlpha: no\b/);
  assert.match(properties, /format: jpeg\b/);
  console.log(`${file}: 1320x2868, JPEG, opaque, SHA-256 OK`);
}

const textFiles = [
  'README.md', 'verification.md', 'privacy-review.md', 'zh-Hans/store-listing.md',
  'zh-Hans/store-listing.json', 'zh-Hans/privacy-policy.draft.md', 'zh-Hans/support.draft.md',
  'screenshots/manifest.json'
];
for (const file of textFiles) {
  const text = read(file);
  assert(!/-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(text), `Private key in ${file}`);
  assert(!/eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/.test(text), `JWT in ${file}`);
  assert(!/"(?:password|access_token|refresh_token)"\s*:\s*"[^"\s]+"/.test(text), `Credential in ${file}`);
}
console.log('PASS: local draft checks only; publication blockers remain in privacy-review.md.');
