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
reopening the output channel; nothing is written to disk by OvalLSP
itself beyond its own [persistent parse cache](README.md#performance-tuning)
under `~/.cache/ovallsp/` (parsed declarations/types, keyed by workspace
and toolchain version — not your source code's contents, and not
transmitted anywhere).

## Runtime type observation (opt-in)

`OvalLSP: Run Tests with Type Observation` is entirely opt-in (disabled
until you explicitly run the command) and records, for methods actually
exercised by your own test run:

- class/module name, method identifier, parameter position, call count,
  and whether the call raised.

It never records argument values, return values, string contents, SQL,
environment variables, or file contents — the normalizer that builds
this evidence never calls `#inspect`/`#to_s` on anything it observes.
This data stays local (in-memory / the same local cache above) and is
never transmitted anywhere.

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
