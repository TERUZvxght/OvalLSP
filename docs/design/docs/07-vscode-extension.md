# 07. VS Code Extension

## 1. 責務

VS Code拡張はLanguage Clientと製品UIのみを担当する。

- Core Server executable探索/導入
- workspace folderごとのprocess起動
- LSP transport
- Workspace Trust確認
- status bar
- commands
- configuration
- output channels
- crash restart policy

意味解析、Rails reflection、ファイルindexをTypeScript側へ実装しない。

## 2. 技術構成

```text
TypeScript
vscode
vscode-languageclient/node
esbuild or tsup
vitest
@vscode/test-electron
```

## 3. Activation

```json
{
  "activationEvents": [
    "onLanguage:ruby",
    "workspaceContains:Gemfile"
  ]
}
```

実際のCore起動はRuby workspace判定後に行う。

判定候補:

- `.ruby-version`
- `Gemfile`
- `*.gemspec`
- `config/application.rb`

## 4. Language Client

workspace folderごとにLanguageClientを生成する。

server options:

```text
command: resolved Ruby command
args: [path/to/rslsp-core, "--stdio"]
cwd: workspace folder
```

環境解決は段階化する。

1. user configured command
2. mise
3. asdf
4. rbenv
5. chruby
6. system Ruby

MVPでは1とsystem Rubyだけでもよい。環境解決は独立moduleにする。

## 5. Status Bar

状態:

```text
RSLSP: Starting
RSLSP: Static
RSLSP: Rails loading
RSLSP: Ready
RSLSP: Rails stale
RSLSP: Rails failed
RSLSP: Crashed
```

クリック時にQuick Pick:

- Show status
- Restart Core
- Restart Rails Agent
- Open logs
- Clear caches
- Explain current symbol

## 6. Commands

```text
rslsp.restart
rslsp.restartRuntimeAgent
rslsp.showStatus
rslsp.showEvidence
rslsp.explainType
rslsp.clearCaches
rslsp.runObservation
rslsp.openLogs
```

## 7. Settings

```jsonc
{
  "rslsp.enabled": true,
  "rslsp.ruby.command": null,
  "rslsp.rails.enabled": true,
  "rslsp.rails.environment": "development",
  "rslsp.rails.bootTimeoutMs": 60000,
  "rslsp.runtimeObservation.enabled": false,
  "rslsp.diagnostics.strictness": "safe",
  "rslsp.completion.showUncertain": true,
  "rslsp.trace.server": "off",
  "rslsp.plugins.enabled": []
}
```

## 8. Workspace Trust

untrusted workspace:

- Core static serverは起動可能。
- Bundler command、Rails Agent、runtime plugin、observationを起動しない。
- Statusを`Static (untrusted workspace)`とする。
- trustを求める通知は一度だけ。

## 9. Ruby LSPとの共存

初期版は**置換利用**を前提とする。

理由:

- completion候補が重複する。
- definition結果の優先順位をVS Code側で完全制御できない。
- diagnosticsが重複する。
- 2つのRuby indexがCPU/メモリを消費する。

拡張はRuby LSPを自動無効化しない。検出時に設定案内を表示するだけにする。

将来、次の互換モードを検討できる。

- RSLSPはsemantic機能のみ
- Ruby LSPはformat/test/code lensのみ

ただしMVPの対象外。

## 10. Custom UI

### Explain Type

現在式についてWebviewではなくMarkdown hover/Outputで以下を表示する。

```text
Expression: user.company.orders.first
Type: Order | nil
Evidence:
1. user -> User (assignment, 100%)
2. User#company -> Company (Rails association, 98%)
3. Company#orders -> Relation[Order] (Rails association, 98%)
4. Relation[T]#first -> T | nil (built-in rule, 100%)
Runtime snapshot: generation 12, fresh
```

### Evidence decorations

常時表示しない。command実行時だけにする。

## 11. Crash policy

- Core crash: 10秒内最大3回まで自動再起動
- Rails Agent crash: Coreが管理。Extensionは状態通知のみ受ける
- crash loop: 自動停止しログを案内

## 12. Packaging

Core Ruby codeをVSIXへ同梱する方式と、gemとして導入する方式を分離する。

MVP推奨:

- VSIXにbootstrap Ruby scriptを同梱
- 実体はRubyGemsからversion固定で導入、または開発中はrepository path指定

release時にはsupply-chainとoffline利用を再検討する。
