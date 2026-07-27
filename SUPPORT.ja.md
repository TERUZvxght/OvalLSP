# Support

[English version](SUPPORT.md)

**現在、このリポジトリはバグ報告・機能要望を含むあらゆるissueを
受け付けていません — GitHub Issuesは無効化されています。** 理由は
[CONTRIBUTING.ja.md](CONTRIBUTING.ja.md)を参照してください。状況が
変わり次第、本文書を更新します。

OvalLSPは現在**Preview**(Pre-Release)段階にあり、macOS Apple Silicon +
Ruby 3.4.xに限定されています。実際に検証済みの内容は
[docs/SUPPORT_MATRIX.ja.md](docs/SUPPORT_MATRIX.ja.md)を、意図的に
scope外としている内容は
[docs/KNOWN_LIMITATIONS.ja.md](docs/KNOWN_LIMITATIONS.ja.md)を参照。

## 自己解決のためのトラブルシューティング

1. `OvalLSP: Show Version Information`と`OvalLSP: Show Environment
   Diagnostics`を実行する。
2. [docs/SUPPORT_MATRIX.ja.md](docs/SUPPORT_MATRIX.ja.md)で、お使いの
   platform/Ruby/Railsの組合せがこのPreviewの対象かどうか確認する。
3. [vscode/README.ja.md](vscode/README.ja.md)のトラブルシューティング
   節で、よくあるケース(Rubyが見つからない、Rails機能が動かない、
   キャッシュの問題)を確認する。

## セキュリティ関連の問題

Issuesが無効化されていても、セキュリティ脆弱性は非公開で報告できます
— [SECURITY.ja.md](SECURITY.ja.md)を参照してください。

## Previewのスコープ

このPreviewは意図的に単一のplatformのみを最初の対象としています。
Apple Silicon以外への拡張(Linux/Windows/Intel Mac、Ruby/Railsの
バージョンマトリクス等)のロードマップは、`docs/RELEASE_CHECKLIST.md`
にPreview公開後の非blocker作業として別途記録されています。
