import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = fileURLToPath(new URL('.', import.meta.url));
const root = fileURLToPath(new URL('../../../', import.meta.url));

export function run(command, args, options) {
  const result = spawnSync(command, args, { encoding: 'utf8', ...options });
  if (result.error) throw result.error;
  assert.equal(result.status, 0, result.stdout + result.stderr);
  return result.stdout;
}

export function compileArgumentProbe(work) {
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
  const executable = join(work, 'argument-native');
  const built = spawnSync(ghc, ['-Wall', '-Werror', '-hide-all-packages',
    '-package-db', packageDb, '-package-db', localDb,
    ...packages.flatMap(id => ['-package-id', id]),
    '-outputdir', work, join(here, 'ArgumentNative.hs'), '-o', executable], { encoding: 'utf8' });
  if (built.error) throw built.error;
  // Preserve toolchain diagnostics rather than hiding successful-link warnings.
  if (built.stdout) process.stdout.write(built.stdout);
  if (built.stderr) process.stderr.write(built.stderr);
  assert.equal(built.status, 0, built.stdout + built.stderr);
  return executable;
}

