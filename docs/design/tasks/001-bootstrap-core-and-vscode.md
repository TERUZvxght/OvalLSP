# Task 001: Core ServerとVS Code Clientの最小接続

## Goal

VS Code拡張がworkspace folderごとにRuby製Core Serverをstdioで起動し、LSP initialize、document open/change/close、shutdownを正常に処理する。解析機能は固定Hoverだけでよい。

## In scope

- monorepo skeleton
- Ruby `ovallsp --stdio`
- Content-Length LSP reader/writer
- initialize/initialized/shutdown/exit
- didOpen/didChange/didClose
- in-memory DocumentStore
- fixed hover response
- TypeScript VS Code extension
- integration tests

## Out of scope

- Prism
- Bundler environment resolver
- Rails Agent
- completion
- semantic index
- packaging/release

## Required interfaces

```ruby
module Ovallsp
  class Server
    def initialize(input:, output:, logger:); end
    def run; end
  end

  class DocumentStore
    def open(uri:, text:, version:, language_id:); end
    def change(uri:, version:, changes:); end
    def close(uri:); end
    def fetch(uri:); end
  end
end
```

## Behavior

1. Serverはstdoutへprotocol message以外を書かない。
2. incremental didChangeを適用する。
3. UTF-16 positionを正しくoffsetへ変換する。
4. unknown requestへMethodNotFoundを返す。
5. notification例外でserverを終了しない。
6. shutdown後のexitで正常終了する。

## Tests

- framing reader handles split reads
- framing writer uses byte length
- full and incremental document changes
- emojiを含むUTF-16 position
- initialize handshake
- VS Code extension starts client

## Commands

```bash
bundle exec rspec
cd vscode && npm test
```

## Acceptance criteria

- [ ] Extension Development HostでRuby fileを開ける
- [ ] Hoverに`OvalLSP connected`と表示される
- [ ] document versionが更新される
- [ ] stdout contamination testが通る
- [ ] shutdownで子プロセスが残らない
