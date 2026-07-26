#!/usr/bin/env ruby
# frozen_string_literal: true

# Verifies a packaged, unpacked VSIX's bundled Core can actually answer a
# *real* semantic LSP request -- not merely complete initialize/shutdown
# (the existing smoke test embedded in make-final-review-bundle.sh, which
# this script deliberately does not modify or replace).
#
# Two gaps this closes, both found reviewing packaging/release readiness:
#
# 1. The existing smoke only proves the process starts and stops cleanly;
#    it never proves Prism/RBS actually parse and produce real evidence
#    inside the packaged Core. A cross-Ruby-ABI native-extension mismatch
#    (ADR-0005) or a vendoring step that silently produced an empty/broken
#    gem tree could both still pass a bare initialize/shutdown check.
# 2. Running this test from an ordinary shell risks the *runner's own*
#    Bundler context leaking into the child (Task 022.2's own finding,
#    applied here to a sibling spawn site): if this script itself is ever
#    invoked via `bundle exec` (from core/'s own Gemfile), the VSIX's Core
#    would inherit that BUNDLE_GEMFILE/BUNDLE_PATH/BUNDLE_APP_CONFIG/
#    BUNDLER_VERSION/GEM_HOME/GEM_PATH and RUBYOPT/RUBYLIB's Bundler
#    injections, and a smoke test that passes only because it accidentally
#    resolved gems through the *runner's* Bundle graph is not proving the
#    packaged VSIX is self-contained at all.
#
# Usage: ruby scripts/vsix_semantic_smoke.rb <path-to-unpacked-vsix-extension-dir>
# (the directory containing core/bin/ovallsp, i.e. `<vsix>/extension`)

require "json"
require "open3"
require "tmpdir"
require "timeout"
require "fileutils"

def fail!(message)
  warn "vsix-semantic-smoke: FAILED: #{message}"
  exit 1
end

extension_root = ARGV[0] or fail!("usage: vsix_semantic_smoke.rb <unpacked-vsix-extension-dir>")
core_root = File.join(extension_root, "core")
core_bin = File.join(core_root, "bin", "ovallsp")
bundle_environment_lib = File.join(core_root, "lib", "ovallsp", "bundle_environment.rb")

File.file?(core_bin) or fail!("no core/bin/ovallsp found under #{extension_root}")
File.file?(bundle_environment_lib) or fail!("no core/lib/ovallsp/bundle_environment.rb found under #{extension_root}")

# Loaded from the *VSIX's own* copy, not this repo's core/ -- the whole
# point is to isolate the child using exactly the logic the packaged VSIX
# itself ships, not this monorepo's possibly-different one.
require_relative File.join(core_root, "lib", "ovallsp", "bundle_environment")

# A fully isolated temp workspace -- this smoke test's own Ruby content,
# unrelated to any real project's Gemfile/gems, so nothing here can
# accidentally resolve through an ambient Bundle graph either.
workspace = Dir.mktmpdir("vsix-semantic-smoke-workspace")
begin
  fixture_path = File.join(workspace, "app.rb")
  File.write(fixture_path, <<~RUBY)
    # frozen_string_literal: true

    class App
      def call
        name = "ok"
        name
      end
    end
  RUBY

  # Ovallsp::BundleEnvironment.base strips this *runner* process' own
  # Bundler/RubyGems pollution (BUNDLE_*, BUNDLER_*, bundle-exec-derived
  # GEM_HOME/GEM_PATH, RUBYOPT/RUBYLIB's Bundler injections) into an
  # override Hash of explicit nils/cleaned values -- merged onto a full
  # copy of this process' own ENV, so the child gets everything else
  # (PATH, HOME, ...) inherited normally, with only the Bundler-owned
  # keys actually cleared. See Task 022.2 for why this is the correct
  # mechanism (a bare `Bundler.with_unbundled_env` mutates global ENV,
  # unsafe to use even in a single-purpose script like this one, and
  # `Bundler.unbundled_env` alone doesn't strip GEM_HOME/GEM_PATH).
  clean_env = ENV.to_h.merge(Ovallsp::BundleEnvironment.base(env: ENV))

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def read_one_message(io)
    headers = {}
    while (line = io.gets)
      line = line.chomp("\r\n")
      break if line.empty?

      name, value = line.split(":", 2)
      headers[name.strip] = value.strip
    end
    length = Integer(headers.fetch("Content-Length"))
    JSON.parse(io.read(length), symbolize_names: true)
  end

  # The server can (and does) interleave unsolicited notifications --
  # `textDocument/publishDiagnostics` after `didOpen`, in particular --
  # with the responses this script is actually waiting for. Reads and
  # discards anything that isn't a response to `expected_id` rather than
  # assuming the very next frame on the wire is always the one asked for.
  def read_response(io, expected_id)
    loop do
      message = read_one_message(io)
      return message if message[:id] == expected_id
    end
  end

  initialize_request = frame(jsonrpc: "2.0", id: 1, method: "initialize", params: { processId: nil, rootUri: nil, capabilities: {} })
  initialized_notification = frame(jsonrpc: "2.0", method: "initialized", params: {})
  did_open = frame(
    jsonrpc: "2.0", method: "textDocument/didOpen",
    params: { textDocument: { uri: "file://#{fixture_path}", languageId: "ruby", version: 1, text: File.read(fixture_path) } }
  )
  hover_request = frame(
    jsonrpc: "2.0", id: 2, method: "textDocument/hover",
    params: { textDocument: { uri: "file://#{fixture_path}" }, position: { line: 5, character: 4 } }
  )
  shutdown_request = frame(jsonrpc: "2.0", id: 3, method: "shutdown", params: nil)
  exit_notification = frame(jsonrpc: "2.0", method: "exit", params: nil)

  stdin, stdout, stderr, wait_thread = Open3.popen3(
    clean_env, "ruby", core_bin, "--stdio", chdir: workspace, pgroup: true
  )

  begin
    stdin.write(initialize_request)
    initialize_response = Timeout.timeout(15) { read_response(stdout, 1) }
    initialize_response.dig(:result, :capabilities, :hoverProvider) == true or
      fail!("initialize response did not advertise hoverProvider: #{initialize_response.inspect}")

    stdin.write(initialized_notification)
    stdin.write(did_open)
    stdin.write(hover_request)

    hover_response = Timeout.timeout(15) { read_response(stdout, 2) }
    value = hover_response.dig(:result, :contents, :value)
    value == "String" or fail!("expected real semantic hover \"String\", got: #{hover_response.inspect}")

    puts "vsix-semantic-smoke: real semantic hover verified (#{value.inspect})"

    stdin.write(shutdown_request)
    Timeout.timeout(15) { read_response(stdout, 3) } # the shutdown response itself
    stdin.write(exit_notification)
    stdin.close

    status = Timeout.timeout(10) { wait_thread.value }
    status.success? or fail!("Core did not exit cleanly after shutdown/exit (status: #{status.inspect})")

    puts "vsix-semantic-smoke: clean shutdown/exit verified"
  ensure
    # Belt-and-braces: if anything above raised (including the Timeouts),
    # make sure no child process is left behind before this script exits.
    if wait_thread.alive?
      begin
        Process.kill("TERM", -wait_thread.pid)
      rescue Errno::ESRCH
        nil
      end
      begin
        Timeout.timeout(2) { wait_thread.value }
      rescue Timeout::Error
        begin
          Process.kill("KILL", -wait_thread.pid)
        rescue Errno::ESRCH
          nil
        end
      end
    end
    stdin.close unless stdin.closed?
    stdout.close unless stdout.closed?
    stderr_output = begin
      stderr.read
    rescue StandardError
      nil
    end
    stderr.close unless stderr.closed?
    warn "vsix-semantic-smoke: Core stderr:\n#{stderr_output}" if stderr_output && !stderr_output.empty?
  end

  # No leftover process holding the workspace root open, group-wide.
  begin
    Process.kill(0, -wait_thread.pid)
    fail!("Core's process group (#{wait_thread.pid}) is still alive after exit")
  rescue Errno::ESRCH
    puts "vsix-semantic-smoke: no leftover child process (verified via kill(0) on the process group)"
  end
ensure
  FileUtils.rm_rf(workspace)
end

puts "vsix-semantic-smoke: PASS"
