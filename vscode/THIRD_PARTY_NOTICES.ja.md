# Third-Party Notices

[English version](THIRD_PARTY_NOTICES.md)

この拡張機能は以下のサードパーティパッケージを同梱しています。一覧は
[docs/SBOM.md](https://github.com/TERUZvxght/OvalLSP/blob/main/docs/SBOM.md)
(`scripts/generate_sbom.rb`が生成し、`scripts/verify_sbom_against_vsix.rb`
で実際にpackageされたVSIXの内容と照合済み)から生成しています。各
パッケージ自身のlicenseファイルは、このVSIX内の`core/vendor/bundle/`
(RubyGems)または`node_modules/`(npm)にそれぞれ同梱されています —
本文書は要約用のindexであり、それらの代替ではありません。

スコープ: このpackage済みVSIXが実際に同梱・実行するものに限定してい
ます。開発専用のtooling(RSpec、`@vscode/vsce`、TypeScript、Mocha等)は
同梱されておらず、ここには記載していません。

## RubyGems (`core/vendor/bundle`にvendoring)

| パッケージ | バージョン | ライセンス |
|---|---|---|
| [logger](https://github.com/ruby/logger) | 1.7.0 | Ruby |
| [prism](https://github.com/ruby/prism) | 1.9.0 | MIT |
| [rbs](https://github.com/ruby/rbs) | 4.0.3 | BSD-2-Clause |
| [tsort](https://github.com/ruby/tsort) | 0.2.0 | Ruby |

## npm (`node_modules`に同梱)

| パッケージ | バージョン | ライセンス |
|---|---|---|
| [balanced-match](https://github.com/juliangruber/balanced-match) | 1.0.2 | MIT |
| [brace-expansion](https://github.com/juliangruber/brace-expansion) | 2.1.2 | MIT |
| [minimatch](https://github.com/isaacs/minimatch) | 5.1.9 | ISC |
| [semver](https://github.com/npm/node-semver) | 7.8.5 | ISC |
| [vscode-jsonrpc](https://github.com/microsoft/vscode-languageserver-node) | 8.2.0 | MIT |
| [vscode-languageclient](https://github.com/microsoft/vscode-languageserver-node) | 9.0.1 | MIT |
| [vscode-languageserver-protocol](https://github.com/microsoft/vscode-languageserver-node) | 3.17.5 | MIT |
| [vscode-languageserver-types](https://github.com/microsoft/vscode-languageserver-node) | 3.17.5 | MIT |

## ライセンス条項に関する注記

- MIT・ISC・BSD-2-Clauseはいずれも、著作権表示と許諾表示を保持する
  限り再配布を許可しています — 各パッケージ自身の`LICENSE`/
  `LICENSE.txt`ファイル(上記の通り同梱)がこれを満たします。
- Ruby license(`logger`と`tsort`が使用、いずれもRuby自身の標準
  ライブラリの一部)は2-clause BSD licenseとのデュアルライセンスです
  (同梱の`COPYING`/`LICENSE.txt`自身がそう明記しています)。いずれを
  選んでも本プロジェクトのMIT licenseとの再配布上の互換性があります。
- OvalLSP自体(この拡張機能とそのCore Server)はMIT licenseです —
  [LICENSE](LICENSE)を参照。

このファイルは`docs/SBOM.md`が変更されるたび(依存のversion更新等)に
再生成されます。実際にVSIXへ同梱されている内容から決して乖離しては
ならず、`scripts/verify_sbom_against_vsix.rb`で検証されています。
