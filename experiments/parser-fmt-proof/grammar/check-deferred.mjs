// The full grammar model of root ADR 0351, with the choices that
// docs/roadmap.md defers. Strict generation must report exactly the listed
// choices: a choice that is not listed fails, and so does a listed choice
// that is now supported or whose text changed, so the list only shrinks.
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const [grammar, list, output] = process.argv.slice(2);
if (!grammar || !list || !output) {
  console.error('usage: node check-deferred.mjs Golem.hpeg deferred-choices.txt Generated.lean');
  process.exit(2);
}
const here = fileURLToPath(new URL('.', import.meta.url));
const generate = join(here, 'generate.mjs');
const strict = spawnSync(process.execPath, [generate, grammar, output], { encoding: 'utf8' });
const lines = strict.stderr.split('\n').filter(line => line !== '');
const other = lines.filter(line => !line.startsWith('unsupported '));
// The source path and line number are left out: moving a choice keeps it
// deferred, changing its text does not.
const reported = lines.filter(line => line.startsWith('unsupported '))
  .map(line => line.replace(/^unsupported (\S+) choice (\d+) at .*?:\d+: /, '$1 choice $2: '));
const deferred = readFileSync(list, 'utf8').split('\n')
  .filter(line => line !== '' && !line.startsWith('#'));
const missing = reported.filter(line => !deferred.includes(line));
const stale = deferred.filter(line => !reported.includes(line));
const problems = [
  ...other,
  ...missing.map(line => `unsupported and not deferred: ${line}`),
  ...stale.map(line => `deferred but not reported (remove it from the list): ${line}`),
];
if (new Set(deferred).size !== deferred.length) problems.push('the list repeats a choice');
if (problems.length) {
  console.error(problems.join('\n'));
  process.exit(1);
}
if (reported.length > 0) {
  const fragment = spawnSync(process.execPath, [generate, '--fragment', grammar, output], { encoding: 'utf8' });
  if (fragment.status !== 0) {
    console.error(fragment.stderr);
    process.exit(1);
  }
}
console.log(`grammar: ${reported.length} deferred choices, as listed in ${list}`);
