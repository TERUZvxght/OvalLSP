# Third-Party Notices

[日本語版](THIRD_PARTY_NOTICES.ja.md)

This extension bundles the following third-party packages, generated
from [docs/SBOM.md](https://github.com/TERUZvxght/OvalLSP/blob/main/docs/SBOM.md)
(Japanese; `scripts/generate_sbom.rb`, verified against the actual
packaged VSIX contents by `scripts/verify_sbom_against_vsix.rb`). Each package's own
license file ships alongside it inside `core/vendor/bundle/` (RubyGems)
or `node_modules/` (npm) in this VSIX — this document is a summary index,
not a substitute for those.

Scope: only what this packaged VSIX actually ships and runs. Development-
only tooling (RSpec, `@vscode/vsce`, TypeScript, Mocha, ...) is not
bundled and is not listed here.

## RubyGems (vendored into `core/vendor/bundle`)

| Package | Version | License |
|---|---|---|
| [logger](https://github.com/ruby/logger) | 1.7.0 | Ruby |
| [prism](https://github.com/ruby/prism) | 1.9.0 | MIT |
| [rbs](https://github.com/ruby/rbs) | 4.0.3 | BSD-2-Clause |
| [tsort](https://github.com/ruby/tsort) | 0.2.0 | Ruby |

## npm (bundled in `node_modules`)

| Package | Version | License |
|---|---|---|
| [balanced-match](https://github.com/juliangruber/balanced-match) | 1.0.2 | MIT |
| [brace-expansion](https://github.com/juliangruber/brace-expansion) | 2.1.2 | MIT |
| [minimatch](https://github.com/isaacs/minimatch) | 5.1.9 | ISC |
| [semver](https://github.com/npm/node-semver) | 7.8.5 | ISC |
| [vscode-jsonrpc](https://github.com/microsoft/vscode-languageserver-node) | 8.2.0 | MIT |
| [vscode-languageclient](https://github.com/microsoft/vscode-languageserver-node) | 9.0.1 | MIT |
| [vscode-languageserver-protocol](https://github.com/microsoft/vscode-languageserver-node) | 3.17.5 | MIT |
| [vscode-languageserver-types](https://github.com/microsoft/vscode-languageserver-node) | 3.17.5 | MIT |

## Notes on license terms

- MIT, ISC, and BSD-2-Clause all permit redistribution provided the
  copyright and permission notice is preserved — each package's own
  `LICENSE`/`LICENSE.txt` file (bundled as described above) satisfies
  this.
- The Ruby license (used by `logger` and `tsort`, both part of Ruby's own
  standard library) is dual-licensed with the GPL; both are compatible
  with this project's MIT license for redistribution purposes.
- OvalLSP itself (this extension and its Core Server) is MIT-licensed —
  see [LICENSE](LICENSE).

This file is regenerated whenever `docs/SBOM.md` changes (any dependency
version bump); it must never drift from what's actually bundled in the
VSIX — see `scripts/verify_sbom_against_vsix.rb`.
