# Privacy

[日本語版](PRIVACY.ja.md)

## Summary

OvalLSP does not collect telemetry, does not phone home, and does not
transmit your source code or workspace information anywhere. Everything
it does runs locally, on your own machine.

## Telemetry

None. OvalLSP has no telemetry integration of any kind (no crash
reporting service, no analytics SDK, no usage tracking). This has been
verified against the actual codebase, not just declared: neither the
Core Server (`core/`) nor the extension (`vscode/src/`) contains any
network client code, any telemetry/analytics library, or any outbound
HTTP/HTTPS call.

## Network access

OvalLSP itself makes no network requests at runtime. The only network
access anywhere in this project is:

- **At packaging time only** (building the VSIX, not something an
  end user's installed extension ever does): fetching Core Server's
  runtime gem dependencies (Prism, RBS) from RubyGems.org, so they can
  be bundled into the VSIX. This happens on the machine that builds the
  release, never on an end user's machine.
- **VS Code's own Marketplace update mechanism**, which is VS Code's
  behavior, not OvalLSP's — see your VS Code installation's own privacy
  documentation for that.

No auto-download or self-update mechanism exists beyond VS Code's own
Marketplace extension updates (see the main [README](README.md#server-startup-and-update-model)
for why: the Core Server ships inside the extension and updates
atomically with it, rather than through a separate downloader).

## What gets logged locally

The `OvalLSP: Show Logs` output channel and the Core Server's own stderr
output contain diagnostic messages about OvalLSP's own operation
(startup, indexing progress, errors, the version-compatibility
handshake). These logs stay on your machine (VS Code's own Output panel)
and are never transmitted anywhere. You can clear them by closing/
reopening the output channel.

The only thing OvalLSP itself writes to disk during ordinary use is its
own [persistent parse cache](README.md#troubleshooting) under
`$XDG_CACHE_HOME/ovallsp/`, or `~/.cache/ovallsp/` when that variable is
unset or empty, keyed by workspace, toolchain version and OvalLSP's own
version. Directories for combinations no longer in use are removed at
startup rather than accumulating for as long as the extension is
installed, which is what happened until 0.2.1; the eight most recently
used are kept. A workspace that has *disappeared* from disk is the one
exception, as of 0.2.3: its cache is held for thirty days after the last
time that workspace was opened, and removed at the first startup after
that. An unmounted volume and a deleted project look identical from here,
and the thirty days are how a project on an external drive keeps its
cache — the cost is that a deleted project's cache outlives it by up to a
month. Delete the directory yourself if that matters to you. **It
contains parts of your source code.** Alongside the parsed
declarations and types it stores each method's body text and each
parameter's default expression, verbatim — the body so a method's return
type can be inferred later without re-reading the file, the default
expression because the parser records it. It also stores each file's
absolute path. (Whether a file has changed is decided by a hash of it,
not by this text.) Nothing in it is transmitted anywhere, and
deleting that directory is safe at any time — it is rebuilt by
re-indexing.

Running type observation writes two more files, normally for the length
of that run only — see below for exactly when they outlive it.

## Runtime type observation (opt-in)

`OvalLSP: Run Tests with Type Observation` is entirely opt-in (disabled
until you explicitly run the command) and records, for methods actually
exercised by your own test run:

- the class/module name and method identifier;
- for each positional parameter, the set of **classes** seen at that
  position — the class names, never the objects;
- the set of classes the method **returned**, on the same terms;
- how many calls contributed. A call that raised still contributes its
  count and the classes it was given — only the return type is withheld,
  and nothing records that it raised;
- an identifier for the run, made from its start time, Core's process id
  and a random number;
- a digest of the **file** the observed method is in, plus that method's
  line number, used only to notice when the method may have been edited
  since; and the time the run finished.

It never records argument values, return values, string contents, SQL,
environment variables, or file contents — the normalizer that builds
this evidence never calls `#inspect`/`#to_s` on anything it observes.
The distinction that matters is class *names* versus the objects
themselves: `User` is recorded, the user is not.
The aggregated result is not written to the parse cache and does not
survive restarting the server. The only copy that touches disk is the
temporary run file described just below, and its lifetime is described
there.

Two temporary files exist for the length of an observation run, both
created with owner-only permissions in your system temp directory and
unlinked when the run ends — but not guaranteed to be. Deleting them is
deliberately allowed to fail quietly rather than replace an error already
being raised, so a temp directory that has gone read-only leaves
them; and a crash or a kill skips the deletion step entirely:

- the run's results, as described above;
- a log file, which is where **your test command's own standard output
  and standard error are redirected**. OvalLSP never reads that log; it
  exists because in `--stdio` mode file descriptor 1 is the live LSP
  transport, and the child's output must not land there. But it contains
  whatever your test suite prints, which in a Rails app routinely
  includes SQL, and can include anything else your code or your
  environment logs. The "never records" guarantee above is about what
  OvalLSP *extracts and keeps*; it is not a claim about your own suite's
  output, which is your program's, not ours.

Nothing from either file is transmitted anywhere.

## The Runtime Agent

The Runtime Agent (Rails route/model introspection) only starts in a
workspace you've explicitly marked as trusted in VS Code, and only ever
runs code that's already part of your own project (via your project's
own Bundler context) — it doesn't introduce any new network access or
external data flow beyond what your own application already does when
you run it yourself.

## Custom Core Server paths

If you set `ovallsp.server.path` to point at a Core Server build outside
the one this extension bundles, everything above still applies to
OvalLSP's own code — but you are responsible for whatever that custom
build itself does, since it's no longer the exact code this project
ships and reviews.

## Questions or concerns

See [SUPPORT.md](https://github.com/TERUZvxght/OvalLSP/blob/main/SUPPORT.md)
for how to reach out, or [SECURITY.md](https://github.com/TERUZvxght/OvalLSP/blob/main/SECURITY.md)
for security-specific concerns.
