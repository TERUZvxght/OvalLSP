import * as assert from 'assert';
import * as fs from 'fs';
import * as path from 'path';
import {
  STATUS_ERROR_TEXT,
  STATUS_LABELS,
  documentSelectorFor,
  resolveStatus,
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
    // Every file under the folder, not `**/*.rb`: the language id is the
    // point, and `Gemfile`, `Rakefile` and `*.rake` carry it without
    // carrying the extension. Narrowing the glob leaves every other
    // assertion here true.
    assert.strictEqual(ruby.pattern, '/w/**/*');
  });

  // VS Code assigns no built-in language id to `.erb`, so a language-id
  // filter would match nothing in a plain install and controller-to-view
  // propagation would be unreachable. The pair is the point: one filter
  // by language, one by extension.
  it('matches ERB by extension, not by language id', () => {
    const erb = documentSelectorFor('/w').find((f) => f.pattern.endsWith('.erb'));

    assert.ok(erb, 'no filter matches .erb');
    assert.strictEqual(erb.language, undefined, '.erb must not be matched by language id');
    // `file`, not `untitled`: an unsaved buffer has no path for the
    // controller-to-view link to run through, and getting this wrong
    // attaches the client to no .erb file on disk at all.
    assert.strictEqual(erb.scheme, 'file');
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

describe('resolveStatus', () => {
  it('reports no client when the folder has none', async () => {
    assert.deepStrictEqual(await resolveStatus(undefined), { hasClient: false });
  });

  it('reports the state the server answered with', async () => {
    const client = { sendRequest: async <T>() => ({ state: 'ready-rails' }) as T };

    assert.deepStrictEqual(await resolveStatus(client), { hasClient: true, state: 'ready-rails' });
  });

  // The distinction the whole feature turns on: a client that threw is
  // not the same as no client, and reporting it as "no client" hides a
  // crashed server behind an empty status bar. Splitting this decision
  // from its rendering is how it went untested the first time.
  it('reports a failed request as a client that did not answer, not as no client', async () => {
    const client = {
      sendRequest: async <T>(): Promise<T> => {
        throw new Error('connection closed');
      }
    };

    assert.deepStrictEqual(await resolveStatus(client), { hasClient: true, failed: true });
  });

  it('asks for ovallsp/status', async () => {
    const asked: string[] = [];
    const client = {
      sendRequest: async <T>(method: string) => {
        asked.push(method);
        return { state: 'indexing' } as T;
      }
    };

    await resolveStatus(client);

    assert.deepStrictEqual(asked, ['ovallsp/status']);
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
      text: '$(error) OvalLSP: Configuration error'
    });
    // The literal, once: comparing against the symbol is true of any
    // value, including the empty string, which would put the item on
    // screen showing nothing -- the "reads as fine" failure this text
    // exists to prevent.
    assert.strictEqual(STATUS_ERROR_TEXT, '$(error) OvalLSP: Configuration error');
  });

  // The literal strings, not `STATUS_LABELS[state]`. Comparing the render
  // against the same table it renders from is true of any table: with
  // `indexing` relabelled and `agent-unavailable` deleted outright, that
  // form still passed, and a deleted key falls through to the raw-state
  // branch -- the status bar reads "OvalLSP: agent-unavailable".
  it('renders each state the server reports', () => {
    const expected: Record<string, string> = {
      indexing: '$(sync~spin) OvalLSP: Indexing',
      'ready-static': '$(check) OvalLSP: Ready (static)',
      'ready-rails': '$(check) OvalLSP: Ready (Rails)',
      'agent-unavailable': '$(warning) OvalLSP: Agent unavailable'
    };

    for (const [state, text] of Object.entries(expected)) {
      assert.deepStrictEqual(statusPresentation({ hasClient: true, state }), { visible: true, text });
    }
    assert.deepStrictEqual(Object.keys(STATUS_LABELS).sort(), Object.keys(expected).sort());
  });

  // The other half of the same contract: the four states are the Core's
  // to define, and a state added there with no label here degrades to its
  // own raw name. Read out of `server.rb` rather than restated, because a
  // restated list is what went stale.
  it('labels exactly the states the Core emits', () => {
    const serverSource = fs.readFileSync(
      path.join(__dirname, '../../../../core/lib/ovallsp/server.rb'),
      'utf8'
    );
    const statusBody = serverSource.slice(serverSource.indexOf('def status_result'));
    const emitted = (statusBody.slice(0, statusBody.indexOf('\n    end')).match(/"[a-z-]+"/g) ?? [])
      .map((quoted) => quoted.slice(1, -1));

    assert.ok(emitted.length > 0, 'found no states in server.rb -- has status_result been renamed?');
    assert.deepStrictEqual([...new Set(emitted)].sort(), Object.keys(STATUS_LABELS).sort());
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
// it. 024.10's first attempt exported the strings and left the *choice*
// between them at the call site, where a reviewer swapped it with the
// suite green -- an extraction the call site does not use is worse than
// none, because the tests then describe code nobody runs. Asserting on
// source is how `versionPairing.test.ts` covers the same shape.
describe('extension.ts uses the extracted decisions', () => {
  const source = fs.readFileSync(path.join(__dirname, '../../../src/extension.ts'), 'utf8');

  it('builds its documentSelector from documentSelectorFor', () => {
    assert.ok(
      /documentSelector:\s*documentSelectorFor\(/.test(source),
      'extension.ts still builds its documentSelector inline'
    );
  });

  it('drives the status bar from resolveStatus and statusPresentation', () => {
    // Both identifiers somewhere inside the polling function -- not the
    // two literally nested in one expression, which an ordinary
    // `const outcome = await resolveStatus(client)` refactor would break
    // while changing no behaviour. Textual *order* is not asserted for
    // the same reason: today's nested form puts the renderer first.
    const start = source.indexOf('function startStatusPolling');
    assert.ok(start >= 0, 'extension.ts no longer has a startStatusPolling function');
    const pollBody = source.slice(start, source.indexOf('\nfunction ', start + 1));
    assert.ok(pollBody.includes('resolveStatus('), 'startStatusPolling does not call resolveStatus');
    assert.ok(pollBody.includes('statusPresentation('), 'startStatusPolling does not call statusPresentation');
    assert.ok(
      !source.includes('STATUS_LABELS['),
      'extension.ts still indexes STATUS_LABELS itself instead of asking statusPresentation'
    );
    assert.ok(
      !/hasClient:\s*(true|false)/.test(source),
      'extension.ts still decides hasClient itself; that decision belongs in resolveStatus'
    );
  });
});
