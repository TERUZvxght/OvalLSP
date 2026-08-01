import * as assert from 'assert';
import * as fs from 'fs';
import * as path from 'path';
import {
  STATUS_ERROR_TEXT,
  STATUS_LABELS,
  documentSelectorFor,
  statusPresentation
} from '../../clientPresentation';

// `extension.ts` imports `vscode`, so nothing in it can be unit-tested.
// These two decisions were extracted out of it for that reason (024.17);
// what follows is what a user would notice if either were wrong.
describe('documentSelectorFor', () => {
  it('matches Ruby by language id, so a file mapped to Ruby by the user is covered', () => {
    const ruby = documentSelectorFor('/w').find((f) => f.language === 'ruby');

    assert.ok(ruby, 'no filter matches Ruby by language id');
    assert.strictEqual(ruby.scheme, 'file');
  });

  // VS Code assigns no built-in language id to `.erb`, so a language-id
  // filter would match nothing in a plain install and controller-to-view
  // propagation would be unreachable. The pair is the point: one filter
  // by language, one by extension.
  it('matches ERB by extension, not by language id', () => {
    const erb = documentSelectorFor('/w').find((f) => f.pattern.endsWith('.erb'));

    assert.ok(erb, 'no filter matches .erb');
    assert.strictEqual(erb.language, undefined, '.erb must not be matched by language id');
  });

  // A multi-root workspace runs one client per folder. An unscoped
  // selector makes every client answer for every folder's files.
  it('scopes every filter to the folder it was built for', () => {
    const filters = documentSelectorFor('/projects/api');

    assert.ok(filters.length > 0);
    for (const filter of filters) {
      assert.ok(
        filter.pattern.startsWith('/projects/api/'),
        `filter is not scoped to the folder: ${filter.pattern}`
      );
    }
  });
});

describe('statusPresentation', () => {
  it('hides the item when no client serves the active editor', () => {
    assert.deepStrictEqual(statusPresentation({ hasClient: false }), { visible: false });
  });

  // The distinction that matters: no client is not a problem, a client
  // that failed to answer is. Hiding on failure would read as "fine".
  it('shows an error rather than hiding when the client fails to answer', () => {
    assert.deepStrictEqual(statusPresentation({ hasClient: true, failed: true }), {
      visible: true,
      text: STATUS_ERROR_TEXT
    });
  });

  it('renders each state the server reports', () => {
    for (const [state, label] of Object.entries(STATUS_LABELS)) {
      assert.deepStrictEqual(statusPresentation({ hasClient: true, state }), {
        visible: true,
        text: label
      });
    }
  });

  // A state the server added and nobody mapped here shows its own name.
  // Reporting a configuration error for it would be a lie, and hiding
  // would lose it entirely.
  it('renders an unrecognised state by name, not as an error', () => {
    const shown = statusPresentation({ hasClient: true, state: 'reindexing' });

    assert.deepStrictEqual(shown, { visible: true, text: 'OvalLSP: reindexing' });
    assert.notStrictEqual(shown.text, STATUS_ERROR_TEXT);
  });

  it('treats a missing state as a failure rather than showing an empty label', () => {
    assert.deepStrictEqual(statusPresentation({ hasClient: true }), {
      visible: true,
      text: STATUS_ERROR_TEXT
    });
  });
});

// The extraction is only worth anything if `extension.ts` actually calls
// it. 024.10's first attempt left the original copy in place, so this
// asserts the source, the way `versionPairing.test.ts` does.
describe('extension.ts uses the extracted decisions', () => {
  const source = fs.readFileSync(path.join(__dirname, '../../../src/extension.ts'), 'utf8');

  it('builds its documentSelector from documentSelectorFor', () => {
    assert.ok(
      /documentSelector:\s*documentSelectorFor\(/.test(source),
      'extension.ts still builds its documentSelector inline'
    );
  });

  it('drives the status bar from statusPresentation', () => {
    assert.ok(source.includes('statusPresentation('), 'extension.ts does not call statusPresentation');
    assert.ok(
      !source.includes('STATUS_LABELS['),
      'extension.ts still indexes STATUS_LABELS itself instead of asking statusPresentation'
    );
  });
});
