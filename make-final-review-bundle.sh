#!/usr/bin/env bash

set -Eeuo pipefail

BASELINE_COMMIT="${BASELINE_COMMIT:-87579a13303f}"
OUTPUT_NAME="${1:-}"
REQUIRED_COMMANDS=(git zip unzip ruby bundle node npm gitleaks)

fail() {
  echo "error: $*" >&2
  exit 1
}

for command_name in "${REQUIRED_COMMANDS[@]}"; do
  command -v "$command_name" >/dev/null 2>&1 ||
    fail "${command_name} が見つかりません"
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$REPO_ROOT" ]] || fail "Gitリポジトリ内で実行してください"

cd "$REPO_ROOT"

SHORT_SHA="$(git rev-parse --short=12 HEAD)"
OUTPUT_NAME="${OUTPUT_NAME:-ovallsp-final-review-${SHORT_SHA}.zip}"

case "$OUTPUT_NAME" in
  /*) OUTPUT_PATH="$OUTPUT_NAME" ;;
  *)  OUTPUT_PATH="$REPO_ROOT/$OUTPUT_NAME" ;;
esac

# trackedな変更が残った状態では、レビュー対象を確定できないため停止する。
git diff --quiet ||
  fail "未コミットのtracked変更があります"
git diff --cached --quiet ||
  fail "staged済みの未コミット変更があります"

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ovallsp-review.XXXXXX")"
PACKAGE_ROOT="$WORK_ROOT/ovallsp-final-review"
META_DIR="$PACKAGE_ROOT/review-metadata"
LOG_DIR="$META_DIR/logs"
ARTIFACT_DIR="$PACKAGE_ROOT/release-artifacts"
BUNDLE_CACHE="$WORK_ROOT/bundle"
BUNDLE_CONFIG="$WORK_ROOT/bundle-config"
NPM_CACHE="$WORK_ROOT/npm-cache"
VSIX_UNPACKED="$WORK_ROOT/vsix-unpacked"
CODE_EXTENSIONS="$WORK_ROOT/code-extensions"
CODE_USER_DATA="$WORK_ROOT/code-user-data"

mkdir -p \
  "$PACKAGE_ROOT" \
  "$META_DIR" \
  "$LOG_DIR" \
  "$ARTIFACT_DIR"

cleanup() {
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$@"
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    fail "shasum または sha256sum が必要です"
  fi
}

run_logged() {
  local name="$1"
  shift

  local log="$LOG_DIR/${name}.log"

  {
    echo "\$ $*"
    echo
    "$@"
  } >"$log" 2>&1 || {
    local status=$?
    echo
    echo "FAILED: ${name} (exit=${status})" >&2
    tail -n 80 "$log" >&2 || true
    exit "$status"
  }

  echo "PASS: ${name}"
}

run_logged_in() {
  local name="$1"
  local directory="$2"
  shift 2

  local log="$LOG_DIR/${name}.log"

  {
    echo "directory: $directory"
    echo "\$ $*"
    echo
    (
      cd "$directory"
      "$@"
    )
  } >"$log" 2>&1 || {
    local status=$?
    echo
    echo "FAILED: ${name} (exit=${status})" >&2
    tail -n 80 "$log" >&2 || true
    exit "$status"
  }

  echo "PASS: ${name}"
}

npm_has_script() {
  local script_name="$1"

  (
    cd "$REPO_ROOT/vscode"
    node -e '
      const pkg = require("./package.json");
      process.exit(pkg.scripts && pkg.scripts[process.argv[1]] ? 0 : 1);
    ' "$script_name"
  )
}

run_npm_script_required() {
  local script_name="$1"

  npm_has_script "$script_name" ||
    fail "vscode/package.json に必須script '${script_name}' がありません"

  run_logged_in \
    "vscode-${script_name//:/-}" \
    "$REPO_ROOT/vscode" \
    npm run "$script_name"
}

run_npm_script_optional() {
  local script_name="$1"

  if npm_has_script "$script_name"; then
    run_logged_in \
      "vscode-${script_name//:/-}" \
      "$REPO_ROOT/vscode" \
      npm run "$script_name"
  fi
}

assert_rspec_json_clean() {
  local json_path="$1"
  local suite_name="$2"

  ruby -rjson -e '
    path, suite = ARGV
    # `File.read` without an explicit encoding uses the process' own
    # external encoding, which follows the shell locale (LANG/LC_ALL) --
    # under a locale-less shell (LANG unset, as on this machine), that
    # defaults to US-ASCII, and reading RSpec's own JSON output (which
    # commonly contains this codebase's em dashes and other non-ASCII
    # punctuation, both in test descriptions and in the source lines
    # RSpec echoes back in failure messages) then raises
    # Encoding::InvalidByteSequenceError before JSON.parse ever runs.
    # Found by actually running this release-gate script end to end
    # (Task 023.8) -- fixed by reading as UTF-8 explicitly rather than
    # depending on the invoking shell's ambient locale.
    data = JSON.parse(File.read(path, encoding: "UTF-8"))
    summary = data.fetch("summary")

    failures = summary.fetch("failure_count", 0)
    pending  = summary.fetch("pending_count", 0)
    examples = summary.fetch("example_count", 0)

    puts "#{suite}: examples=#{examples}, failures=#{failures}, pending=#{pending}"

    unless failures.zero? && pending.zero? && examples.positive?
      warn "#{suite} did not complete cleanly"
      exit 1
    end
  ' "$json_path" "$suite_name"
}

echo "== Git metadata =="

git status --short --branch \
  >"$META_DIR/git-status-before.txt"

git log \
  --oneline \
  --decorate \
  --graph \
  -n 150 \
  >"$META_DIR/git-log.txt"

git submodule status --recursive \
  >"$META_DIR/git-submodules.txt" 2>&1 || true

if git cat-file -e "${BASELINE_COMMIT}^{commit}" 2>/dev/null; then
  git diff \
    --stat \
    "${BASELINE_COMMIT}..HEAD" \
    >"$META_DIR/diff-since-${BASELINE_COMMIT}.stat.txt"

  git diff \
    --binary \
    "${BASELINE_COMMIT}..HEAD" \
    >"$META_DIR/diff-since-${BASELINE_COMMIT}.patch"
else
  echo "Baseline commit not present: $BASELINE_COMMIT" \
    >"$META_DIR/baseline-not-found.txt"
fi

{
  echo "Repository: $(basename "$REPO_ROOT")"
  echo "Commit: $(git rev-parse HEAD)"
  echo "Branch: $(git branch --show-current || true)"
  echo "Generated UTC: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "Baseline: $BASELINE_COMMIT"
} >"$META_DIR/summary.txt"

{
  echo "Ruby:"
  ruby --version

  echo
  echo "RubyGems:"
  gem --version

  echo
  echo "Bundler:"
  bundle --version

  echo
  echo "Node:"
  node --version

  echo
  echo "npm:"
  npm --version

  echo
  echo "OS:"
  uname -a
} >"$META_DIR/environment.txt"

echo "== Secret scan (full history) =="

run_logged \
  secret-scan \
  gitleaks detect \
  --source "$REPO_ROOT" \
  --log-opts="--all" \
  --report-format json \
  --report-path "$META_DIR/gitleaks-report.json" \
  --exit-code 1

echo "== Ruby dependencies =="

export BUNDLE_PATH="$BUNDLE_CACHE"
export BUNDLE_APP_CONFIG="$BUNDLE_CONFIG"

run_logged_in \
  core-bundle-install \
  "$REPO_ROOT/core" \
  bundle install --jobs 4 --retry 3

run_logged_in \
  core-bundle-check \
  "$REPO_ROOT/core" \
  bundle check

run_logged_in \
  core-bundle-list \
  "$REPO_ROOT/core" \
  bundle list

echo "== Ruby syntax =="

run_logged \
  ruby-syntax \
  bash -c '
    set -euo pipefail

    find core/lib core/spec scripts \
      -type f \
      -name "*.rb" \
      -print0 |
    while IFS= read -r -d "" file; do
      ruby -c "$file"
    done
  '

echo "== Core full RSpec =="

run_logged_in \
  core-rspec \
  "$REPO_ROOT/core" \
  bundle exec rspec \
    --format json \
    --out "$LOG_DIR/core-rspec.json"

assert_rspec_json_clean \
  "$LOG_DIR/core-rspec.json" \
  "Core RSpec"

echo "== Mandatory real Rails integration =="

run_logged_in \
  core-real-rails \
  "$REPO_ROOT/core" \
  bundle exec rspec \
    spec/integration/real_rails_spec.rb \
    --format json \
    --out "$LOG_DIR/core-real-rails.json"

assert_rspec_json_clean \
  "$LOG_DIR/core-real-rails.json" \
  "Real Rails integration"

echo "== SBOM reproducibility =="

run_logged_in \
  sbom-generation \
  "$REPO_ROOT" \
  env \
    "BUNDLE_GEMFILE=$REPO_ROOT/core/Gemfile" \
    bundle exec ruby scripts/generate_sbom.rb

git diff --quiet -- docs/SBOM.md ||
  fail "SBOM再生成後にdocs/SBOM.mdへ差分が発生しました"

echo "== VS Code dependencies =="

run_logged_in \
  vscode-npm-ci \
  "$REPO_ROOT/vscode" \
  npm ci --cache "$NPM_CACHE"

(
  cd "$REPO_ROOT/vscode"
  node -e '
    const pkg = require("./package.json");
    console.log(JSON.stringify(pkg.scripts || {}, null, 2));
  '
) >"$META_DIR/npm-scripts.json"

run_logged_in \
  vscode-npm-ls \
  "$REPO_ROOT/vscode" \
  npm ls --depth=0

echo "== VS Code compile and tests =="

run_npm_script_required compile
run_npm_script_required test

# 存在する場合は個別suiteも必ず実行する。
run_npm_script_optional test:unit
run_npm_script_optional test:integration
run_npm_script_optional test:extension
run_npm_script_optional test:smoke

echo "== Fresh VSIX package =="

PACKAGE_MARKER="$WORK_ROOT/package-start.marker"
touch "$PACKAGE_MARKER"

run_npm_script_required package

VSIX_PATH="$(
  find "$REPO_ROOT/vscode" \
    -maxdepth 3 \
    -type f \
    -name '*.vsix' \
    -newer "$PACKAGE_MARKER" \
    -print |
  head -n 1
)"

[[ -n "$VSIX_PATH" ]] ||
  fail "npm run package後に新しいVSIXが生成されませんでした"

VSIX_COPY="$ARTIFACT_DIR/$(basename "$VSIX_PATH")"
cp -p "$VSIX_PATH" "$VSIX_COPY"

unzip -t "$VSIX_COPY" \
  >"$LOG_DIR/vsix-integrity.log"

unzip -l "$VSIX_COPY" \
  >"$META_DIR/vsix-contents.txt"

mkdir -p "$VSIX_UNPACKED"
unzip -q "$VSIX_COPY" -d "$VSIX_UNPACKED"

VSIX_CORE_BIN="$(
  find "$VSIX_UNPACKED" \
    -type f \
    -path '*/core/bin/ovallsp' \
    -print |
  head -n 1
)"

[[ -n "$VSIX_CORE_BIN" ]] ||
  fail "VSIX内にcore/bin/ovallspがありません"

echo "== Apple Silicon target confirmation =="

# Task 023.5/023.8: a generic (targetless) VSIX must never be treated as
# a release candidate for this Preview -- `vsce package --target
# darwin-arm64` names the artifact accordingly, so checking the filename
# itself is a cheap, direct confirmation the packaging script's own
# --target flag actually took effect.
case "$(basename "$VSIX_COPY")" in
  ovallsp-darwin-arm64-*.vsix) echo "PASS: vsix-target-darwin-arm64" ;;
  *) fail "生成されたVSIX '$(basename "$VSIX_COPY")' がdarwin-arm64ターゲット名になっていません(汎用VSIXは配布しない)" ;;
esac

echo "== Package contents inspection =="

# Task 023.6/023.7/023.8: regression guard for the native-extension
# build-log leak (mkmf.log/gem_make.out/Makefile embedding this machine's
# own absolute path) found and fixed in copy-core.js. Checks this
# machine's own $HOME specifically -- not a broad /Users|/home pattern --
# to avoid false-positiving on the `rbs` gem's own bundled stdlib
# documentation, which contains an unrelated example path in a comment.
if grep -rlF "$HOME" "$VSIX_UNPACKED" >"$LOG_DIR/package-contents-inspection.log" 2>&1; then
  fail "パッケージ済みVSIXにこのビルドマシン自身の絶対パスが含まれています。詳細: $LOG_DIR/package-contents-inspection.log"
fi
echo "PASS: package-contents-inspection"

echo "== Expanded semantic smoke (documentSymbol/definition/stderr allowlist) =="

# Task 023.4's own vsix_semantic_smoke.rb -- deliberately kept separate
# from (and never replacing) the hand-rolled hover-only smoke test below,
# per that script's own header comment. Exercises documentSymbol and
# definition (not just hover) and enforces the stderr forbidden-pattern/
# allowlist check.
run_logged \
  vsix-expanded-semantic-smoke \
  ruby "$REPO_ROOT/scripts/vsix_semantic_smoke.rb" "$VSIX_UNPACKED/extension"

echo "== Bundled Core smoke =="

run_logged \
  vsix-bundled-core-smoke \
  ruby -rjson -rtimeout -e '
    bin, output_path = ARGV

    def send_message(io, message)
      json = JSON.generate(message)

      io.write(
        "Content-Length: #{json.bytesize}\r\n" \
        "\r\n" \
        "#{json}"
      )
      io.flush
    end

    def read_message(io)
      headers = {}

      loop do
        line = io.gets
        raise EOFError, "Core closed stdout while reading LSP headers" unless line

        line = line.sub(/\r?\n\z/, "")
        break if line.empty?

        key, value = line.split(":", 2)
        raise "Malformed LSP header: #{line.inspect}" unless key && value

        headers[key.downcase] = value.strip
      end

      length = Integer(headers.fetch("content-length"))
      body = io.read(length)

      unless body && body.bytesize == length
        raise EOFError,
              "Core closed stdout while reading LSP body " \
              "(expected=#{length}, actual=#{body&.bytesize || 0})"
      end

      JSON.parse(body)
    end

    def wait_for_response(io, id)
      Timeout.timeout(10) do
        loop do
          message = read_message(io)
          return message if message["id"] == id
        end
      end
    end

    def terminate_process_group(pid)
      begin
        Process.kill("TERM", -pid)
      rescue Errno::ESRCH
      end

      sleep 0.5

      begin
        Process.kill("KILL", -pid)
      rescue Errno::ESRCH
      end

      begin
        Process.wait(pid)
      rescue Errno::ECHILD
      end
    end

    output = File.open(output_path, "wb")

    server_stdin_read, server_stdin_write = IO.pipe
    server_stdout_read, server_stdout_write = IO.pipe

    pid = Process.spawn(
      RbConfig.ruby,
      bin,
      "--stdio",
      in: server_stdin_read,
      out: server_stdout_write,
      err: output,
      pgroup: true
    )

    server_stdin_read.close
    server_stdout_write.close

    status = nil

    begin
      Timeout.timeout(20) do
        send_message(
          server_stdin_write,
          {
            "jsonrpc" => "2.0",
            "id" => 1,
            "method" => "initialize",
            "params" => {
              "processId" => nil,
              "rootUri" => nil,
              "workspaceFolders" => nil,
              "capabilities" => {},
              "clientInfo" => {
                "name" => "ovallsp-release-smoke",
                "version" => "1"
              }
            }
          }
        )

        initialize_response = wait_for_response(server_stdout_read, 1)

        if initialize_response["error"]
          raise(
            "initialize failed: " +
            JSON.generate(initialize_response["error"])
          )
        end

        unless initialize_response["result"].is_a?(Hash)
          raise(
            "initialize returned an invalid result: " +
            initialize_response.inspect
          )
        end

        send_message(
          server_stdin_write,
          {
            "jsonrpc" => "2.0",
            "method" => "initialized",
            "params" => {}
          }
        )

        send_message(
          server_stdin_write,
          {
            "jsonrpc" => "2.0",
            "id" => 2,
            "method" => "shutdown",
            "params" => nil
          }
        )

        shutdown_response = wait_for_response(server_stdout_read, 2)

        if shutdown_response["error"]
          raise(
            "shutdown failed: " +
            JSON.generate(shutdown_response["error"])
          )
        end

        send_message(
          server_stdin_write,
          {
            "jsonrpc" => "2.0",
            "method" => "exit",
            "params" => nil
          }
        )

        server_stdin_write.close
        _, status = Process.wait2(pid)
      end
    rescue StandardError => e
      output.puts
      output.puts("Bundled Core LSP smoke failed:")
      output.puts("#{e.class}: #{e.message}")
      output.puts(e.backtrace.join("\n"))
      output.flush

      terminate_process_group(pid)

      warn
      warn "Bundled Core LSP smoke failed."
      warn "#{e.class}: #{e.message}"
      warn "captured output:"
      warn "--------------------"

      begin
        warn File.binread(output_path)
      rescue StandardError => read_error
        warn(
          "Could not read captured output: " \
          "#{read_error.class}: #{read_error.message}"
        )
      end

      warn "--------------------"
      exit 1
    ensure
      [
        server_stdin_read,
        server_stdin_write,
        server_stdout_read,
        server_stdout_write
      ].each do |io|
        begin
          io.close unless io.closed?
        rescue IOError
        end
      end

      output.close unless output.closed?
    end

    unless status&.success?
      warn
      warn "Bundled Core exited unsuccessfully."
      warn "exit status: #{status&.exitstatus.inspect}"
      warn "captured output:"
      warn "--------------------"

      begin
        warn File.binread(output_path)
      rescue StandardError => e
        warn "Could not read captured output: #{e.class}: #{e.message}"
      end

      warn "--------------------"
      exit(status&.exitstatus || 1)
    end

    exit 0
  ' \
  "$VSIX_CORE_BIN" \
  "$LOG_DIR/vsix-core-process-output.log"

echo "== VS Code isolated install =="

if command -v code >/dev/null 2>&1; then
  EXTENSION_ID="$(
    cd "$REPO_ROOT/vscode"
    node -e '
      const pkg = require("./package.json");
      console.log(`${pkg.publisher}.${pkg.name}`);
    '
  )"

  run_logged \
    vscode-clean-install \
    code \
      --extensions-dir "$CODE_EXTENSIONS" \
      --user-data-dir "$CODE_USER_DATA" \
      --install-extension "$VSIX_COPY" \
      --force

  code \
    --extensions-dir "$CODE_EXTENSIONS" \
    --user-data-dir "$CODE_USER_DATA" \
    --list-extensions \
    --show-versions \
    >"$LOG_DIR/vscode-installed-extensions.log"

  grep -Fq "$EXTENSION_ID" \
    "$LOG_DIR/vscode-installed-extensions.log" ||
    fail "隔離環境へのVSIXインストールを確認できませんでした"

  run_logged \
    vscode-clean-uninstall \
    code \
      --extensions-dir "$CODE_EXTENSIONS" \
      --user-data-dir "$CODE_USER_DATA" \
      --uninstall-extension "$EXTENSION_ID"
else
  echo "code CLIがないため隔離インストール検証を実施できませんでした" \
    >"$LOG_DIR/vscode-clean-install-skipped.log"
fi

echo "== Optional benchmark artifact =="

if [[ -f "$REPO_ROOT/core/tmp/cold_index_benchmark_report.json" ]]; then
  cp -p \
    "$REPO_ROOT/core/tmp/cold_index_benchmark_report.json" \
    "$META_DIR/cold-index-benchmark-report.json"
fi

echo "== Collect source files =="

should_exclude() {
  local path="$1"

  case "$path" in
    # Git・依存関係
    .git/*|*/.git/*)
      return 0
      ;;
    vscode/node_modules/*|*/node_modules/*)
      return 0
      ;;
    core/vendor/bundle/*|*/vendor/bundle/*|*/.bundle/*)
      return 0
      ;;

    # ビルド生成物
    vscode/out/*|vscode/dist/*)
      return 0
      ;;
    */coverage/*|*/.cache/*)
      return 0
      ;;
    */log/*|*.log)
      return 0
      ;;
    core/tmp/*|*/tmp/cache/*|*/tmp/pids/*|*/tmp/sockets/*)
      return 0
      ;;

    # 既存成果物
    *.zip|*.vsix|*.gem|*.tar|*.tar.gz|*.tgz)
      return 0
      ;;
    docs.zip|rslsp-followup-tasks.zip|tree.txt|'tree(1).txt')
      return 0
      ;;
    rslsp-task022-review-*.zip|ovallsp-final-review-*.zip)
      return 0
      ;;

    # OS生成物
    .DS_Store|*/.DS_Store|__MACOSX/*|*/__MACOSX/*)
      return 0
      ;;

    # 秘密情報
    .env|.env.*|*/.env|*/.env.*)
      return 0
      ;;
    config/master.key|*/config/master.key)
      return 0
      ;;
    config/credentials/*.key|*/config/credentials/*.key)
      return 0
      ;;
    *.pem|*.p12|*.pfx)
      return 0
      ;;
    *.sqlite3|*.sqlite3-*|*.db)
      return 0
      ;;
  esac

  return 1
}

copy_source_file() {
  local path="$1"
  local destination="$PACKAGE_ROOT/source/$path"

  [[ -e "$path" || -L "$path" ]] || return 0

  mkdir -p "$(dirname "$destination")"

  if [[ -L "$path" ]]; then
    cp -P "$path" "$destination"
  else
    cp -p "$path" "$destination"
  fi
}

while IFS= read -r -d '' path; do
  should_exclude "$path" && continue
  copy_source_file "$path"
done < <(
  git ls-files \
    --cached \
    --others \
    --exclude-standard \
    -z
)

git status --short --branch \
  >"$META_DIR/git-status-after.txt"

# テストや生成処理がtrackedソースを変更していないことを保証する。
git diff --quiet ||
  fail "検証処理後にtrackedファイルへ差分が発生しました"
git diff --cached --quiet ||
  fail "検証処理後にstaged差分が発生しました"

echo "== Build manifests =="

(
  cd "$PACKAGE_ROOT"

  find . \
    \( -type f -o -type l \) \
    -print |
    LC_ALL=C sort
) >"$META_DIR/file-list.txt"

(
  cd "$PACKAGE_ROOT"

  find . \
    -type f \
    ! -path './review-metadata/SHA256SUMS.txt' \
    -print0 |
  LC_ALL=C sort -z |
  xargs -0 shasum -a 256
) >"$META_DIR/SHA256SUMS.txt"

rm -f "$OUTPUT_PATH"

echo "== Create ZIP =="

(
  cd "$WORK_ROOT"

  zip \
    -q \
    -r \
    -9 \
    -y \
    "$OUTPUT_PATH" \
    "$(basename "$PACKAGE_ROOT")"
)

echo
echo "Created:"
ls -lh "$OUTPUT_PATH"

echo
echo "SHA-256:"
sha256_file "$OUTPUT_PATH"

echo
echo "ZIP integrity:"
unzip -t "$OUTPUT_PATH" | tail -n 3

echo
echo "Review bundle is ready:"
echo "$OUTPUT_PATH"