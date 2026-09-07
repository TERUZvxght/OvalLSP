#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"
require "json"
require "digest"
require "securerandom"
require "tmpdir"
require "fileutils"
require "rbconfig"
require "optparse"
require_relative "repo_files"
require_relative "test_environment"
require_relative "documented_counts"
require_relative "check_suites_ran"

module TestRunner
  ROOT = File.expand_path("..", __dir__)
  TIERS = %w[unit integration e2e meta].freeze
  class Error < StandardError; end

  class Runner
    def initialize(root: ROOT, progress: nil)
      @progress = progress
      @root = File.expand_path(root)
      @core = File.join(@root, "core")
    end

    def list
      manifest = JSON.parse(File.read(File.join(@core, "spec/tiers.json"), encoding: "UTF-8"))
      files = Dir.glob("spec/**/*_spec.rb", base: @core).sort
      raise Error, "manifest must classify every spec exactly once" unless manifest.keys.sort == files

      manifest.sort.map do |file, row|
        unless TIERS.include?(row["tier"]) && row["resources"].is_a?(Array) &&
               row["resources"].all? { |resource| resource.is_a?(String) } && [true, false].include?(row["parallel"])
          raise Error, "invalid manifest entry: #{file}"
        end
        row.merge("file" => file)
      end
    rescue JSON::ParserError, Errno::ENOENT, TypeError, NoMethodError
      raise Error, "missing or malformed manifest"
    end

    def selected(tier)
      raise Error, "unknown tier" unless (TIERS + ["full"]).include?(tier)
      rows = list.select { |row| tier == "full" || row.fetch("tier") == tier }
      raise Error, "0 spec files selected" if rows.empty?
      rows
    end

    # Recompute content, including untracked inputs. Generated reports, fixture
    # DBs and dependency installs are not source inputs and are ignored by git.
    def tree_digest
      files = if File.exist?(File.join(@root, ".git"))
                RepoFiles.list(@root)
              else
                Dir.glob("**/*", base: @root).reject { |path| path.start_with?("core/tmp/") }
              end
      digest = Digest::SHA256.new
      files.sort.each do |file|
        path = File.join(@root, file)
        next unless File.file?(path)
        digest << file << "\0" << Digest::SHA256.file(path).hexdigest << "\0"
      end
      digest.hexdigest
    end

    def runtime_digest
      inputs = [RUBY_ENGINE, RUBY_VERSION, RUBY_PLATFORM]
      %w[core/Gemfile core/Gemfile.lock vscode/package-lock.json].each do |file|
        path = File.join(@root, file)
        inputs << Digest::SHA256.file(path).hexdigest if File.file?(path)
      end
      inputs << TestEnvironment.bundler_version
      inputs << TestEnvironment.fixture_key(@root)
      prepared_lock = TestEnvironment.fixture_lock(root: @root)
      inputs << Digest::SHA256.file(prepared_lock).hexdigest if File.file?(prepared_lock)
      Digest::SHA256.hexdigest(inputs.join("\0"))
    end

    def shards(rows, workers, timings: {})
      raise Error, "workers must be positive" unless workers.is_a?(Integer) && workers.positive?
      parallel, serial = rows.partition { |row| row.fetch("parallel") }
      # Keep Unit's helper independent even when full is requested.
      groups = parallel.group_by { |row| row.fetch("tier") == "unit" }.values.flat_map do |group|
        buckets = Array.new([workers, group.length].min) { [] }
        costs = Hash.new(1.0).merge(timings)
        unless costs.values.all? { |cost| cost.is_a?(Numeric) && cost.finite? && cost >= 0 }
          raise Error, "invalid file timings"
        end
        group.sort_by { |row| [-costs[row.fetch("file")], row.fetch("file")] }.each do |row|
          bucket = buckets.min_by { |files| [files.sum { |file| costs[file] }, files.length] }
          bucket << row.fetch("file")
        end
        buckets.map { |files| { "files" => files, "parallel" => true } }
      end
      groups + serial.map { |row| { "files" => [row.fetch("file")], "parallel" => false } }
    end

    def child_command(files, seed, dry_run: false)
      unit = files.all? { |file| list.find { |row| row.fetch("file") == file }.fetch("tier") == "unit" }
      helper = File.join(ROOT, "core/spec", unit ? "unit_spec_helper.rb" : "spec_helper.rb")
      # A fixture repository used by runner tests has no product helper.
      helper = File.join(ROOT, "core/spec/unit_spec_helper.rb") unless File.file?(File.join(@core, "spec/spec_helper.rb"))
      args = [RbConfig.ruby]
      args << "-rbundler/setup" if File.file?(File.join(@core, "Gemfile"))
      args += ["-rrspec/core", "-e", "exit RSpec::Core::Runner.run(ARGV)", "--", "--options", File::NULL, "--require", helper,
               "--require", File.join(ROOT, "scripts/test_report_formatter.rb"),
               "--format", "TestReportFormatter", "--seed", seed.to_s]
      args << "--dry-run" if dry_run
      args + files
    end

    def start_child(files, seed, run_id, dir, index, dry_run: false)
      output = File.join(dir, "#{index}.json")
      worker_tmp = File.join(dir, "tmp-#{index}")
      FileUtils.mkdir_p(worker_tmp)
      env = { "BUNDLE_GEMFILE" => File.join(@core, "Gemfile"), "SPEC_OPTS" => nil, "TMPDIR" => worker_tmp,
              "OVALLSP_TEST_RUN_ID" => run_id }
      env["BUNDLE_GEMFILE"] = nil unless File.file?(env["BUNDLE_GEMFILE"])
      # stdout/stderr can contain arbitrary fixture data. Only the sanitized
      # formatter is retained; no raw subprocess transcript is ever written.
      pid = Process.spawn(env, *child_command(files, seed, dry_run: dry_run), "--out", output,
                          chdir: @core, out: File::NULL, err: File::NULL)
      { "pid" => pid, "files" => files, "output" => output }
    end

    def finish_child(child)
      _pid, status = Process.wait2(child.fetch("pid"))
      data = JSON.parse(File.read(child.fetch("output"), encoding: "UTF-8"))
      @progress&.call("worker finished: #{child.fetch('files').length} files, exit #{status.exitstatus || 'signal'}")
      data.merge("files" => child.fetch("files"), "exit_status" => status.exitstatus,
                 "signal" => status.termsig)
    rescue Errno::ENOENT, JSON::ParserError
      { "files" => child.fetch("files"), "pid" => child.fetch("pid"), "exit_status" => status&.exitstatus,
        "examples" => [], "errors_outside_of_examples_count" => 1 }
    end

    def census(tier, seed)
      rows = selected(tier)
      # The full universe comes from disk, independently of worker assignment.
      files = tier == "full" ? Dir.glob("spec/**/*_spec.rb", base: @core).sort : rows.map { |row| row.fetch("file") }
      Dir.mktmpdir("ovallsp-census") do |dir|
        result = finish_child(start_child(files, seed, SecureRandom.uuid, dir, "census", dry_run: true))
        unless result["exit_status"] == 0 && result["errors_outside_of_examples_count"] == 0 && !result.fetch("examples").empty?
          raise Error, "census failed: load/setup error or 0 examples"
        end
        examples = result.fetch("examples").map { |ex| ex.slice("id", "file_path", "full_description") }.sort_by { |ex| ex.fetch("id") }
        unless examples.map { |ex| ex.fetch("id") }.uniq.length == examples.length &&
               examples.map { |ex| ex.fetch("file_path").delete_prefix("./") }.uniq.sort == files
          raise Error, "census has duplicate IDs or a file contributed 0 examples"
        end
        examples
      end
    end

    def run(tier:, workers: 1, seed: 3501)
      rows = selected(tier)
      weights_path = File.join(@core, "tmp/tests/timings.json")
      weights = File.file?(weights_path) ? JSON.parse(File.read(weights_path)) : {}
      groups = shards(rows, workers, timings: weights)
      run_id = SecureRandom.uuid
      marker = File.join(@core, "tmp/tests/current-#{tier}.json")
      FileUtils.mkdir_p(File.dirname(marker))
      File.write(marker, JSON.generate({ "run_id" => run_id }))
      tree = tree_digest
      runtime = runtime_digest
      expected = census(tier, seed)
      results = []
      Dir.mktmpdir("ovallsp-test-run") do |dir|
        active = []
        begin
          groups.each_with_index do |group, index|
            if !group.fetch("parallel") || active.length >= workers
              active.each { |child| results << finish_child(child) }
              active.clear
            end
            child = start_child(group.fetch("files"), seed, run_id, dir, index)
            if group.fetch("parallel")
              active << child
            else
              results << finish_child(child)
            end
          end
          active.each { |child| results << finish_child(child) }
          active.clear
        ensure
          active.each do |child|
            begin
              Process.kill("TERM", child.fetch("pid"))
              Process.wait(child.fetch("pid"))
            rescue Errno::ESRCH, Errno::ECHILD
              # Already reaped after an earlier child failed to produce JSON.
            end
          end
        end
      end
      examples = results.flat_map { |result| result.fetch("examples") }.sort_by { |ex| ex.fetch("id") }
      durations = examples.group_by { |ex| ex.fetch("file_path").delete_prefix("./") }.transform_values do |group|
        group.sum { |ex| ex.fetch("run_time") }
      end
      File.write(weights_path, JSON.generate(weights.merge(durations)))
      { "schema" => 1, "run_id" => run_id, "tier" => tier, "workers" => workers, "seed" => seed,
        "tree_digest" => tree, "runtime_digest" => runtime, "timings" => weights, "file_durations" => durations, "expected" => expected, "shards" => results,
        "examples" => examples, "summary" => summary(examples), "checks" => aggregate_checks(tier, expected.length),
        "tree_unchanged" => tree == tree_digest }
    end

    def summary(examples)
      { "example_count" => examples.length, "failure_count" => examples.count { |ex| ex["status"] == "failed" },
        "pending_count" => examples.count { |ex| ex["status"] == "pending" } }
    end

    def aggregate_checks(tier, count)
      return {} unless tier == "full" && File.file?(File.join(@root, "docs/SUPPORT_MATRIX.md"))
      { "documented_counts" => DocumentedCounts.complaints(count, root: @root) }
    end

    # ID and the exact recorded reason: a permitted example that goes pending
    # for any other cause (missing gems, a new defect) must fail verify.
    PERMITTED_PENDINGS = {
      "./spec/ovallsp/diagnostics/bare_name_argument_type_spec.rb[1:1]" =>
        "correct for the workspace it can see; needs Module.nesting respected for a bare name — 024.19",
      "./spec/ovallsp/diagnostics/namespaced_argument_type_spec.rb[1:1]" =>
        "Key is declared only in sig/, with no Ruby class of that name to qualify it — 024.224",
      "./spec/ovallsp/diagnostics/reopened_foreign_class_spec.rb[1:1]" =>
        "the only fix found silences real typos; see 024.13",
      "./spec/ovallsp/diagnostics/shadowed_literal_spec.rb[1:1]" =>
        "rooting the name breaks 11 examples in 7 files; the identity belongs beside it — 024.47"
    }.freeze

    def permitted_pending?(example)
      PERMITTED_PENDINGS.key?(example.fetch("id")) &&
        PERMITTED_PENDINGS.fetch(example.fetch("id")) == example["pending_message"]
    end

    def verify(report)
      errors = []
      selected(report.fetch("tier"))
      marker = File.join(@core, "tmp/tests/current-#{report.fetch('tier')}.json")
      errors << "superseded run" unless JSON.parse(File.read(marker)).fetch("run_id") == report.fetch("run_id")
      errors << "invalid report schema" unless report.fetch("schema") == 1
      errors << "stale tree" unless report.fetch("tree_digest") == tree_digest && report.fetch("tree_unchanged") == true
      errors << "stale runtime/lock" unless report.fetch("runtime_digest") == runtime_digest
      tier, seed = report.fetch("tier"), report.fetch("seed")
      fresh = census(tier, seed)
      errors << "census mismatch" unless report.fetch("expected") == fresh
      expected_ids = fresh.map { |ex| ex.fetch("id") }
      examples = report.fetch("examples")
      ids = examples.map { |ex| ex.fetch("id") }
      errors << "missing, duplicate or unexpected examples" unless ids.sort == expected_ids.sort && !ids.empty?
      shard_results = report.fetch("shards")
      assigned = shards(selected(tier), report.fetch("workers"), timings: report.fetch("timings")).map { |shard| shard.fetch("files") }.sort
      errors << "missing or duplicate shard" unless shard_results.map { |shard| shard.fetch("files") }.sort == assigned
      errors << "aggregate differs from shards" unless shard_results.flat_map { |shard| shard.fetch("examples") }.sort_by { |ex| ex.fetch("id") } == examples.sort_by { |ex| ex.fetch("id") }
      shard_results.each do |shard|
        errors << "stale or unfinished worker" unless shard["run_id"] == report.fetch("run_id") && shard["exit_status"] == 0 && shard["signal"].nil? && shard["errors_outside_of_examples_count"] == 0
        shard_examples = shard.fetch("examples")
        errors << "shard summary mismatch" unless summary(shard_examples).all? { |key, value| shard.fetch("summary")[key] == value }
        errors << "wrong shard assignment" unless shard_examples.all? { |ex| shard.fetch("files").include?(ex.fetch("file_path").delete_prefix("./")) }
      end
      errors << "summary mismatch or failures" unless report.fetch("summary") == summary(examples) && summary(examples).fetch("failure_count").zero?
      examples.each do |ex|
        if ex.fetch("status") == "pending"
          next if permitted_pending?(ex)
        end
        errors << "non-passing example: #{ex.fetch('id')}" unless ex.fetch("status") == "passed"
      end
      checks = aggregate_checks(tier, fresh.length)
      errors << "aggregate checks failed or missing" unless report.fetch("checks") == checks && checks.values.all?(&:empty?)
      if tier == "full" && @root == ROOT
        errors.concat(CheckSuitesRan.complaints(report))
      end
      errors.uniq
    rescue KeyError, TypeError, NoMethodError, ArgumentError, Error, SystemCallError, JSON::ParserError
      ["invalid or unverifiable report"]
    end
  end

  def self.main(argv)
    command = argv.shift
    options = { tier: "full", workers: 1, seed: 3501 }
    parser = OptionParser.new do |opts|
      opts.on("--tier TIER") { |value| options[:tier] = value }
      opts.on("--workers N", Integer) { |value| options[:workers] = value }
      opts.on("--seed S", Integer) { |value| options[:seed] = value }
      opts.on("--format FORMAT") { |value| raise Error, "format must be json" unless value == "json" }
      opts.on("--report PATH") { |value| options[:report] = value }
    end
    parser.parse!(argv)
    raise Error, "unexpected arguments" unless argv.empty?
    runner = Runner.new(progress: ->(message) { warn "test-runner: #{message}" })
    case command
    when "list" then puts JSON.pretty_generate(runner.list)
    when "run"
      report = runner.run(**options.slice(:tier, :workers, :seed))
      path = options[:report] || "core/tmp/tests/#{options.fetch(:tier)}.json"
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(report))
      errors = runner.verify(report)
      puts "#{report.fetch('summary').fetch('example_count')} examples, #{report.fetch('summary').fetch('failure_count')} failures, #{report.fetch('summary').fetch('pending_count')} pending"
      errors.each { |error| warn "test-runner: #{error}" }
      return errors.empty? ? 0 : 1
    when "verify"
      raise Error, "--report is required" unless options[:report]
      errors = runner.verify(JSON.parse(File.read(options.fetch(:report), encoding: "UTF-8")))
      errors.each { |error| warn "test-runner: #{error}" }
      puts "test-runner: verified" if errors.empty?
      return errors.empty? ? 0 : 1
    else raise Error, "usage: test_runner.rb list|run|verify [options]"
    end
    0
  rescue Interrupt
    warn "test-runner: interrupted; workers stopped"
    1
  rescue Error => error
    warn "test-runner: #{error.message}"
    1
  rescue OptionParser::ParseError, JSON::ParserError, SystemCallError
    warn "test-runner: invalid input or unavailable environment; check arguments, manifest and test_environment.rb check"
    1
  end
end

exit TestRunner.main(ARGV) if $PROGRAM_NAME == __FILE__
