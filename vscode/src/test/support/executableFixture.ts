import { execFileSync } from 'child_process';
import * as fs from 'fs';

/**
 * Writes an executable test fixture and runs it once before any test
 * measures anything through it.
 *
 * macOS charges the *first* execution of a newly written executable a
 * one-off cost -- it scans a file it has never seen before. Measured on
 * this repository's own fixtures: 2.62 s the first time, 0.04 s on every
 * run after. Tests that write a brand-new script into a brand-new
 * temporary directory pay that cost in full, inside whatever timeout the
 * code under test imposes -- `SystemProcessTreeInspector`'s snapshot
 * timeout is 1 s, and mocha's own default is 2 s. Either one turns a cold
 * file into a reported defect in the product.
 *
 * It flakes rather than fails, because the cost depends on machine load:
 * four of six consecutive runs of `coreProcess.test.ts` failed this way,
 * in three different combinations, while the same tests passed alone.
 *
 * Warming puts the cost outside the window under test. It lives here, in
 * one place, because two suites need it and a rule copied into a second
 * caller is a rule that will be right in one of them.
 */
export function installExecutableFixture(fixturePath: string, script: string): string {
  fs.writeFileSync(fixturePath, script, { mode: 0o755 });
  try {
    execFileSync(fixturePath, { stdio: 'ignore' });
  } catch {
    // A fixture that exits non-zero, or writes somewhere it cannot yet,
    // is warm all the same -- warming is about the file, not its output.
  }
  return fixturePath;
}
