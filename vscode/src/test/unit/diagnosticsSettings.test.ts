import * as assert from 'assert';
import * as fs from 'fs';
import * as path from 'path';

// Task 064's approved public contract: demotion/suppression of existing checks.
describe('diagnostic settings public contract', () => {
  const manifest = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../../../package.json'), 'utf8'));
  const settings = manifest.contributes.configuration.properties;
  const schema = settings['ovallsp.diagnostics.severities'];

  it('exposes no mode switch or unresolved-constant opt-in', () => {
    assert.strictEqual(settings['ovallsp.diagnostics.mode'], undefined);
    assert.strictEqual(schema.additionalProperties, false);
    assert.deepStrictEqual(Object.keys(schema.properties).sort(), [
      'argument-count', 'argument-type', 'syntax-error', 'unassigned-ivar', 'unknown-method', 'unknown-route-helper'
    ]);
  });

  it('permits only canonical demotions or none for each check', () => {
    assert.deepStrictEqual(schema.default, {});
    assert.strictEqual(schema.type, 'object');
    assert.strictEqual(schema.scope, 'resource');
    for (const [code, value] of Object.entries(schema.properties) as [string, { type: string; enum: string[] }][]) {
      assert.strictEqual(value.type, 'string');
      assert.deepStrictEqual(value.enum, code === 'syntax-error'
        ? ['error', 'warning', 'information', 'hint', 'none']
        : ['warning', 'information', 'hint', 'none']);
    }
  });
});
