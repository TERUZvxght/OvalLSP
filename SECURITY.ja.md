# Security Policy

[English version](SECURITY.md)

## 脆弱性の報告

OvalLSPにセキュリティ上の脆弱性を発見した場合は、公開issueを開かず、
非公開で報告してください。このリポジトリのGitHub Private Vulnerability
Reporting(Securityタブ → "Report a vulnerability")を利用するか、
それが利用できない場合はメンテナーへ直接連絡してください。

以下を含めてください:

- 脆弱性の内容と想定される影響
- 再現手順(関連する場合、最小限のRuby/Railsプロジェクトfixture)
- OvalLSP拡張機能のバージョン・Core Serverのバージョン・環境
  (`OvalLSP: Show Version Information`の出力があると助かります)

できる限り速やかに報告を確認し、内容を把握次第対応の見通しをお伝え
します。対応が完了する前に脆弱性を公開しないようお願いします。

## 脅威モデル

OvalLSPはローカル開発ツールです — stdio経由でVS Codeと通信する言語
サーバーであり、自身のネットワークリスナーは持ちません。ここで実際に
重要な脅威モデルは「リモート攻撃者がネットワーク経由でプロセスに到達
すること」ではなく、以下です:

1. **信頼できないworkspace**(他人のリポジトリを開く、悪意あるPRを
   チェックアウトする)を開いただけで、Coreプロセス自体や開発者の
   マシンが侵害されないこと。
2. **信頼できないplugin**(サードパーティ製OvalLSP plugin)がCoreの
   内部状態やLSPプロトコルストリーム自体を乗っ取れないこと。
3. **ログ・エラーメッセージ経由の秘密情報漏洩**を最小化すること
   (Coreは対象Railsアプリ自身の例外テキストをそのままログに書くことが
   多いため)。

完全な脅威モデルと緩和策の一覧は
[docs/SECURITY_CHECKLIST.md](docs/SECURITY_CHECKLIST.md)を参照 — 要約:

- Rails Runtime Agent(対象アプリケーション自身のコードを実行しうる)
  は、VS Codeでworkspaceが明示的に**信頼済み**とマークされた場合のみ
  起動する — それ以外(欠如・`false`・信頼シグナル自体の不在)は
  fail-closed。
- Pluginは実際にOSプロセスレベルで隔離されたforkで実行され、Coreの
  生きたLSP transportや内部index objectへのアクセスは一切ない。
  プロセス境界を越えるのは、プレーンでMarshal可能なデータのみ。
- Runtime(最も高い権限を持つ)pluginは、信頼されていないworkspaceでは
  一切ロードされない。
- ログ出力は、どこかに書き込まれる前にredaction pipeline(bearer
  token、Basic認証、DB接続文字列、既知のベンダーキー形式、ラベル付き
  credential)を通る。
- Agent↔Core、plugin↔Coreはそれぞれ厳密なprotocol versionの一致を
  要求し、不一致は許容せず拒否する。

## スコープ

本ポリシーは、このリポジトリのOvalLSP Core Server(`core/`)とVS Code
拡張機能(`vscode/`)を対象とします。あなた自身のRailsアプリケーション
のコードや、このリポジトリで保守していないサードパーティpluginの
脆弱性は対象外です。
