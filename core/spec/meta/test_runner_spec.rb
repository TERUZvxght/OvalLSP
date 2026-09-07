# frozen_string_literal: true

require "json"
require "open3"
require_relative "../../../scripts/test_runner"
require_relative "../../../scripts/test_environment"

# Task 063's CLI contract is the oracle. All mutations of reports and
# fixtures below are contained in example_tmpdir, never the checkout.
RSpec.describe "test runner" do
  def runner_fixture
    dir = example_tmpdir("ovallsp-runner")
    FileUtils.mkdir_p(File.join(dir, "core/spec"))
    File.write(File.join(dir, "core/spec/a_spec.rb"), 'RSpec.describe("a") { it("one") { expect(1).to eq(1) } }')
    File.write(File.join(dir, "core/spec/b_spec.rb"), 'RSpec.describe("b") { it("two") { expect(2).to eq(2) } }')
    File.write(File.join(dir, "core/spec/tiers.json"), JSON.generate({
      "spec/a_spec.rb" => { "tier" => "unit", "resources" => [], "parallel" => true },
      "spec/b_spec.rb" => { "tier" => "integration", "resources" => ["files"], "parallel" => true }
    }))
    dir
  end

  let(:root) { runner_fixture }
  let(:runner) { TestRunner::Runner.new(root: root) }

  it "lists every file once with its tier and resource boundary" do
    expect(TestRunner::Runner.new.list).not_to be_empty
    expect(runner.list.map { |row| [row.fetch("file"), row.fetch("tier")] }).to eq(
      [["spec/a_spec.rb", "unit"], ["spec/b_spec.rb", "integration"]]
    )
  end

  it "refuses a manifest that omits a spec instead of shrinking the suite" do
    File.write(File.join(root, "core/spec/c_spec.rb"), "")
    expect { runner.list }.to raise_error(TestRunner::Error, /manifest/)
  end

  it "refuses an unknown tier or invalid parallel metadata" do
    path = File.join(root, "core/spec/tiers.json")
    rows = JSON.parse(File.read(path))
    rows.fetch("spec/a_spec.rb")["tier"] = "fast"
    File.write(path, JSON.generate(rows))
    expect { runner.list }.to raise_error(TestRunner::Error, /manifest/)
  end

  it "runs the same example IDs and statuses serially and in separate workers" do
    serial = runner.run(tier: "full", workers: 1, seed: 3501)
    parallel = runner.run(tier: "full", workers: 2, seed: 3501)
    identities = ->(report) { report.fetch("examples").map { |ex| [ex.fetch("id"), ex.fetch("status")] }.sort }
    expect(identities.call(serial)).to eq(identities.call(parallel))
    expect(identities.call(parallel).length).to eq(2)
    expect(parallel.fetch("shards").map { |shard| shard.fetch("pid") }.uniq.length).to eq(2)
    expect(runner.verify(parallel)).to eq([])
  end

  it "runs only the requested tier" do
    report = runner.run(tier: "unit", workers: 2, seed: 3501)
    expect(report.fetch("examples").map { |ex| ex.fetch("file_path") }).to eq(["./spec/a_spec.rb"])
    expect(runner.verify(report)).to eq([])
  end

  %w[missing_shard missing_example duplicate stale worker_exit zero setup pending failed summary].each do |fault|
    it "rejects #{fault} even when the report claims success" do
      report = runner.run(tier: "full", workers: 2, seed: 3501)
      case fault
      when "missing_shard" then report.fetch("shards").pop
      when "missing_example"
        report.fetch("shards").first.fetch("examples").clear
        report.fetch("examples").shift
        report.fetch("expected").shift # a truncated report cannot define its own universe
      when "duplicate" then report.fetch("examples") << report.fetch("examples").first.dup
      when "stale" then File.open(File.join(root, "core/spec/a_spec.rb"), "a") { |file| file.puts "\n# changed" }
      when "worker_exit" then report.fetch("shards").first["exit_status"] = 9
      when "zero" then report["examples"] = []; report["expected"] = []
      when "setup" then report.fetch("shards").first["errors_outside_of_examples_count"] = 1
      when "pending" then report.fetch("examples").first.merge!("status" => "pending", "pending_message" => "NOT YET missing gems")
      when "failed" then report.fetch("examples").first["status"] = "failed"
      when "summary" then report.fetch("summary")["failure_count"] = 1
      end
      expect(runner.verify(report)).not_to be_empty
    end
  end

  it "rejects a shard from an older run of the identical tree" do
    old = runner.run(tier: "full", workers: 2, seed: 3501)
    current = runner.run(tier: "full", workers: 2, seed: 3501)
    current.fetch("shards")[0] = old.fetch("shards")[0]
    expect(runner.verify(current)).not_to be_empty
  end

  it "rejects an entire older report and a report preceding a failed census" do
    old = runner.run(tier: "full", workers: 1, seed: 3501)
    runner.run(tier: "full", workers: 1, seed: 3501)
    expect(runner.verify(old)).not_to be_empty
    File.write(File.join(root, "core/spec/a_spec.rb"), 'raise "setup failure"')
    expect { runner.run(tier: "full", workers: 1, seed: 3501) }.to raise_error(TestRunner::Error)
    expect(runner.verify(old)).not_to be_empty
  end

  it "reports a real load error and a real example failure as unsuccessful runs" do
    File.write(File.join(root, "core/spec/a_spec.rb"), 'RSpec.describe("broken") { it("fails") { raise "failure" } }')
    report = runner.run(tier: "unit", workers: 1, seed: 3501)
    expect(runner.verify(report)).not_to be_empty
    File.write(File.join(root, "core/spec/a_spec.rb"), 'raise "setup failed"')
    expect { runner.run(tier: "unit", workers: 1, seed: 3501) }.to raise_error(TestRunner::Error, /census/)
  end

  it "rejects an actual pending, setup failure, crashed worker and empty file" do
    path = File.join(root, "core/spec/a_spec.rb")
    [
      'RSpec.describe("pending") { it("skips") { skip "NOT YET missing dependency" } }',
      'RSpec.describe("setup") { before(:all) { raise "setup error" }; it("never runs") {} }',
      'RSpec.describe("crash") { it("exits") { exit! 7 } }'
    ].each do |source|
      File.write(path, source)
      report = runner.run(tier: "unit", workers: 1, seed: 3501)
      expect(runner.verify(report)).not_to be_empty
    end
    File.write(path, "# no examples")
    expect { runner.run(tier: "unit", workers: 1, seed: 3501) }.to raise_error(TestRunner::Error, /census/)
  end

  it "accepts a permitted pending only when its recorded reason matches exactly" do
    file = "spec/ovallsp/diagnostics/bare_name_argument_type_spec.rb"
    id = "./#{file}[1:1]"
    reason = TestRunner::Runner::PERMITTED_PENDINGS.fetch(id)
    FileUtils.mkdir_p(File.join(root, "core/spec/ovallsp/diagnostics"))
    File.write(File.join(root, "core", file),
               "RSpec.describe(\"bare name\") { it(\"waits\") { pending(#{reason.inspect}); raise \"not yet\" } }")
    rows = JSON.parse(File.read(File.join(root, "core/spec/tiers.json")))
    rows[file] = { "tier" => "unit", "resources" => [], "parallel" => true }
    File.write(File.join(root, "core/spec/tiers.json"), JSON.generate(rows))
    report = runner.run(tier: "unit", workers: 1, seed: 3501)
    example = report.fetch("examples").find { |ex| ex.fetch("id") == id }
    expect(example.fetch("status")).to eq("pending")
    expect(runner.verify(report)).to eq([])
    example["pending_message"] = "NOT YET a different excuse — 024.19"
    expect(runner.verify(report)).to include("non-passing example: #{id}")
  end

  it "rejects a permitted reason recorded under an unpermitted ID" do
    reason = TestRunner::Runner::PERMITTED_PENDINGS.fetch("./spec/ovallsp/diagnostics/bare_name_argument_type_spec.rb[1:1]")
    File.write(File.join(root, "core/spec/a_spec.rb"),
               "RSpec.describe(\"a\") { it(\"one\") { pending(#{reason.inspect}); raise \"not yet\" } }")
    report = runner.run(tier: "unit", workers: 1, seed: 3501)
    expect(runner.verify(report)).to include("non-passing example: ./spec/a_spec.rb[1:1]")
  end

  it "reclaims a crashed worker's cache even when at_exit cannot run" do
    File.write(File.join(root, "core/spec/a_spec.rb"), <<~'RUBY')
      RSpec.describe "abrupt exit" do
        it "exits" do
          File.write("tmp/crashed-cache.txt", ENV.fetch("XDG_CACHE_HOME"))
          exit! 7
        end
      end
    RUBY
    runner.run(tier: "unit", workers: 1, seed: 3501)
    cache = File.read(File.join(root, "core/tmp/crashed-cache.txt"))
    expect(File.exist?(cache)).to be(false)
  ensure
    # Also reclaim the deliberately leaked cache when running the named
    # mutation: this exact directory was created by the controlled child.
    FileUtils.remove_entry(cache) if cache && File.directory?(cache)
  end

  it "keeps serial resources out of concurrent shards" do
    path = File.join(root, "core/spec/tiers.json")
    rows = JSON.parse(File.read(path))
    rows.fetch("spec/b_spec.rb")["parallel"] = false
    File.write(path, JSON.generate(rows))
    groups = runner.shards(runner.list, 2)
    expect(groups.last).to eq({ "files" => ["spec/b_spec.rb"], "parallel" => false })
  end

  it "balances recorded file durations without splitting a file" do
    rows = %w[a b c d].map { |name| { "file" => name, "tier" => "unit", "parallel" => true } }
    groups = runner.shards(rows, 2, timings: { "a" => 100, "b" => 1, "c" => 1, "d" => 1 })
    expect(groups.map { |group| group.fetch("files") }).to eq([["a"], %w[b c d]])
  end

  it "never publishes home paths or credentials from child failure output" do
    File.write(File.join(root, "core/spec/a_spec.rb"), <<~'RUBY')
      RSpec.describe "private failure" do
        it("fails") { raise "#{Dir.home}/private token=fixture-credential" }
      end
    RUBY
    report = runner.run(tier: "unit", workers: 1, seed: 3501)
    expect(JSON.generate(report)).not_to include(Dir.home, "fixture-credential")
  end

  it "checks documented counts against the independent census outside the shards" do
    FileUtils.mkdir_p(File.join(root, "docs"))
    File.write(File.join(root, "docs/SUPPORT_MATRIX.md"), "2 examples")
    File.write(File.join(root, "docs/SUPPORT_MATRIX.ja.md"), "2 examples")
    File.write(File.join(root, "docs/RELEASE_CHECKLIST.md"), "`core/`: 2 examples")
    report = runner.run(tier: "full", workers: 2, seed: 3501)
    expect(runner.verify(report)).to eq([])
    File.write(File.join(root, "docs/SUPPORT_MATRIX.md"), "1 examples")
    stale = runner.run(tier: "full", workers: 2, seed: 3501)
    expect(stale.fetch("checks").fetch("documented_counts")).not_to be_empty
    expect(runner.verify(stale)).not_to be_empty
  end
end

RSpec.describe "unit helper hygiene" do
  it "loads no Core entrypoint and cleans cache and failed-example tmpdirs on exit" do
    Dir.mktmpdir("ovallsp-helper-probe") do |dir|
      spec = File.join(dir, "probe_spec.rb")
      record = File.join(dir, "record.json")
      File.write(spec, <<~'RUBY')
        RSpec.describe "isolated helper" do
          it "cleans after failure" do
            require "json"
            File.write(ENV.fetch("PROBE_RECORD"), JSON.generate({
              cache: ENV.fetch("XDG_CACHE_HOME"), tmp: example_tmpdir,
              eager: $LOADED_FEATURES.any? { |f| f.end_with?("/lib/ovallsp.rb") }
            }))
            raise "intentional failure"
          end
        end
      RUBY
      helper = File.expand_path("../unit_spec_helper.rb", __dir__)
      _out, status = Open3.capture2e({ "PROBE_RECORD" => record }, RbConfig.ruby, "-S", "rspec",
                                   "--options", File::NULL, "--require", helper, spec)
      expect(status.success?).to be(false)
      result = JSON.parse(File.read(record))
      expect(result.fetch("eager")).to be(false)
      expect(File.exist?(result.fetch("cache"))).to be(false)
      expect(File.exist?(result.fetch("tmp"))).to be(false)
    end
  end

  it "gives forked helpers separate caches and never removes the parent's cache" do
    Dir.mktmpdir("ovallsp-fork-helper") do |dir|
      record = File.join(dir, "record.json")
      helper = File.expand_path("../unit_spec_helper.rb", __dir__)
      program = <<~'RUBY'
        require "json"
        parent = ENV.fetch("XDG_CACHE_HOME")
        pid = fork do
          SuiteHygiene.activate
          File.write(ARGV.fetch(0), JSON.generate({ parent: parent, child: ENV.fetch("XDG_CACHE_HOME") }))
        end
        Process.wait(pid)
        data = JSON.parse(File.read(ARGV.fetch(0)))
        data["parent_alive"] = File.directory?(parent)
        data["child_gone"] = !File.exist?(data.fetch("child"))
        File.write(ARGV.fetch(0), JSON.generate(data))
      RUBY
      _out, status = Open3.capture2e(RbConfig.ruby, "-r", helper, "-e", program, record)
      expect(status.success?).to be(true)
      result = JSON.parse(File.read(record))
      expect(result.fetch("child")).not_to eq(result.fetch("parent"))
      expect(result.values_at("parent_alive", "child_gone")).to eq([true, true])
      expect(File.exist?(result.fetch("parent"))).to be(false)
    end
  end
end

RSpec.describe "test environment" do
  it "requires the production client dependencies without requiring TypeScript" do
    Dir.mktmpdir("ovallsp-client-deps") do |dir|
      %w[vscode-languageclient vscode-languageserver-protocol vscode-languageserver-types].each do |name|
        package = File.join(dir, "vscode/node_modules", name)
        FileUtils.mkdir_p(package)
        File.write(File.join(package, "package.json"), "{}")
      end
      check = TestEnvironment.check(root: dir, profile: "full")
      expect(check.fetch("checks").find { |row| row.fetch("name") == "node_modules" }.fetch("ok")).to be(true)
    end
  end
  it "distinguishes a permission failure from a boot failure without publishing child output" do
    denied = TestEnvironment.probe_result({}, RbConfig.ruby, "-e", 'warn "Operation not permitted token=private-value"; exit 1')
    boot = TestEnvironment.probe_result({}, RbConfig.ruby, "-e", 'raise "initializer failed"', failure: "boot")
    expect(denied.fetch("kind")).to eq("permission")
    expect(boot.fetch("kind")).to eq("boot")
    expect(JSON.generate([denied, boot])).not_to include("private-value", Dir.home)
  end

  it "does not label an absent Core bundle as a prepared environment" do
    Dir.mktmpdir("ovallsp-environment") do |dir|
      result = TestEnvironment.check(root: dir, profile: "unit")
      expect(result.fetch("ok")).to be(false)
      expect(result.fetch("checks").map { |row| row.fetch("name") }).to include("core bundle")
      expect { TestEnvironment.prepare(root: dir, profile: "unit", offline: true) }
        .to raise_error(TestEnvironment::Error)
    end
  end

  it "uses a copied fixture and a prepared lock without changing the source" do
    Dir.mktmpdir("ovallsp-rails-copy") do |dir|
      source = File.join(dir, "source")
      FileUtils.mkdir_p(File.join(source, "db"))
      File.write(File.join(source, "Gemfile"), "source fixture")
      File.write(File.join(source, "db/stale.sqlite3"), "must not copy")
      lock = File.join(dir, "prepared.lock")
      File.write(lock, "prepared dependencies")
      TestEnvironment.with_fixture(source: source, lock: lock) do |copy|
        expect(File.read(File.join(copy, "Gemfile.lock"))).to eq("prepared dependencies")
        expect(File.exist?(File.join(copy, "db/stale.sqlite3"))).to be(false)
        File.write(File.join(copy, "Gemfile"), "changed")
      end
      expect(File.read(File.join(source, "Gemfile"))).to eq("source fixture")
      expect(File.read(File.join(source, "db/stale.sqlite3"))).to eq("must not copy")
    end
  end

  it "prepares a local lock once and boots only a disposable application" do
    Dir.mktmpdir("ovallsp-prepare-fixture") do |dir|
      source = File.join(dir, "core/spec/fixtures/rails_real")
      FileUtils.mkdir_p(File.join(source, "config"))
      File.write(File.join(source, "Gemfile"), "source fixture")
      File.write(File.join(source, "config/environment.rb"), 'File.write("db/booted", "yes")')
      bin = File.join(dir, "bin")
      FileUtils.mkdir_p(bin)
      bundle = File.join(bin, "bundle")
      File.write(bundle, <<~SH)
        #!/bin/sh
        echo "$1" >> "$PREPARE_LOG"
        case "$1" in
          lock) [ "$2" = "--local" ] || exit 8; echo 'local fixture lock' > Gemfile.lock ;;
          check) [ "$BUNDLE_FROZEN" = "true" ] || exit 9 ;;
          *) exit 10 ;;
        esac
      SH
      File.chmod(0o755, bundle)
      allow(TestEnvironment).to receive(:check).with(root: dir, profile: "full").and_return({ "ok" => true })
      allow(TestEnvironment).to receive(:clean_env).and_return(TestEnvironment.clean_env.merge("PATH" => bin, "PREPARE_LOG" => File.join(dir, "bundle.log")))
      result = TestEnvironment.prepare(root: dir, profile: "full", offline: true)
      expect(result.fetch("prepared")).to be(true)
      TestEnvironment.prepare(root: dir, profile: "full", offline: true)
      expect(File.readlines(File.join(dir, "bundle.log"), chomp: true)).to eq(%w[lock check check])
      expect(File.read(TestEnvironment.fixture_lock(root: dir))).to eq("local fixture lock\n")
      expect(File.exist?(File.join(source, "Gemfile.lock"))).to be(false)
      expect(File.exist?(File.join(source, "db/booted"))).to be(false)
    end
  end
end

RSpec.describe "preflight full suite wiring" do
  require_relative "../../../scripts/preflight"

  it "uses one runner invocation and verifies its aggregate instead of rerunning Rails" do
    commands = Preflight::CHECKS.map(&:command)
    expect(commands.count { |command| command.include?("scripts/test_runner.rb") && command.include?("run") }).to eq(1)
    expect(commands.flatten).not_to include("spec/integration/real_rails_spec.rb", "spec/e2e/capabilities_spec.rb")
    expect(commands).to include(%w[ruby scripts/test_runner.rb verify --report core/tmp/tests/full.json])
  end

  it "prepares the CI fixture and validates its manifest before the existing full run" do
    steps = CiWorkflow.job("core").fetch("steps")
    suite = steps.index { |step| step["name"] == "Run full test suite" }
    %w[scripts/test_environment.rb scripts/test_runner.rb].each do |script|
      before = steps.first(suite).find { |step| step["run"].to_s.include?(script) }
      expect(CiWorkflow.executed?(before)).to be(true)
    end
  end
end
