import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { saveProjectFailure } from '../save-project-failure.mjs';
import { expectedQuoted, quotedCases, quotedManuscript } from '../grammar/quoted-cases.mjs';

const here = fileURLToPath(new URL('.', import.meta.url));
const root = fileURLToPath(new URL('../../../', import.meta.url));

function run(command, args, options) {
  const result = spawnSync(command, args, { encoding: 'utf8', ...options });
  if (result.error) throw result.error;
  assert.equal(result.status, 0, result.stdout + result.stderr);
  return result.stdout;
}

function parserProbe(work) {
  const planPath = resolve(root, process.env.CABAL_PLAN ?? 'dist-newstyle/cache/plan.json');
  const plan = JSON.parse(readFileSync(planPath, 'utf8'));
  const compiler = plan['compiler-id'];
  assert.match(compiler, /^ghc-[0-9]+\.[0-9]+\.[0-9]+$/);
  const ghc = process.env.GHC ?? compiler;
  assert.equal(run(ghc, ['--numeric-version']).trim(), compiler.slice(4), 'use the compiler selected by the project');
  const packageId = name => {
    const unit = plan['install-plan'].find(x => x['pkg-name'] === name &&
      (!x['component-name'] || x['component-name'] === 'lib'));
    assert.ok(unit, 'build the CLI and its parser library in the selected Cabal plan: ' + name);
    return unit.id;
  };
  const packages = ['base', 'bytestring', 'text', 'aeson', 'golem-parser', 'golem-syntax'].map(packageId);
  const store = join(process.env.CABAL_DIR ?? join(homedir(), '.cabal'), 'store');
  const candidates = readdirSync(store).filter(x => x.startsWith(compiler))
    .map(x => join(store, x, 'package.db')).filter(existsSync);
  const packageDb = process.env.GHC_PACKAGE_DB ?? candidates.find(x =>
    existsSync(join(x, packageId('aeson') + '.conf')));
  assert.ok(packageDb, 'the selected aeson unit must exist in the compiler store');
  const localDb = resolve(dirname(planPath), '..', 'packagedb', compiler);
  assert.ok(existsSync(localDb), 'build the CLI before comparing its parser AST');
  const executable = join(work, 'quoted-native');
  const built = spawnSync(ghc, ['-Wall', '-Werror', '-hide-all-packages',
    '-package-db', packageDb, '-package-db', localDb,
    ...packages.flatMap(id => ['-package-id', id]),
    '-outputdir', work, join(here, 'QuotedNative.hs'), '-o', executable], { encoding: 'utf8' });
  if (built.error) throw built.error;
  // Preserve toolchain diagnostics rather than hiding successful-link warnings.
  if (built.stdout) process.stdout.write(built.stdout);
  if (built.stderr) process.stderr.write(built.stderr);
  assert.equal(built.status, 0, built.stdout + built.stderr);
  return executable;
}

test('root ADR 0351 I1-I3: quoted names, kinds and values agree before and after fmt', async t => {
  const buildWork = mkdtempSync(join(tmpdir(), 'golem-quoted-probe-'));
  try {
    const probe = parserProbe(buildWork);
    for (const [index, args] of quotedCases.entries()) {
      await t.test('quoted fields ' + index, () => {
        const work = mkdtempSync(join(tmpdir(), 'golem-quoted-fields-'));
        const source = quotedManuscript(args);
        const file = join(work, 'a.gm');
        try {
          writeFileSync(file, source);
          const expected = expectedQuoted(args);
          assert.deepEqual(JSON.parse(run(probe, [file])), expected);
          run(process.env.GOLEM ?? 'golem', ['fmt', file], { cwd: work });
          assert.deepEqual(JSON.parse(run(probe, [file])), expected);
          const once = readFileSync(file);
          run(process.env.GOLEM ?? 'golem', ['fmt', file], { cwd: work });
          assert.deepEqual(readFileSync(file), once);
        } catch (error) {
          saveProjectFailure('arguments', work, source, error, 'quoted-fields-' + index, 'quoted-values.test.mjs');
          throw error;
        } finally {
          rmSync(work, { recursive: true, force: true });
        }
      });
    }
  } finally {
    rmSync(buildWork, { recursive: true, force: true });
  }
});
