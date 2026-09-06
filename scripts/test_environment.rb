#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"
require "json"
require "digest"
require "fileutils"
require "tmpdir"
require "open3"
require "rbconfig"
require "optparse"
require "bundler/version"
require_relative "repo_files"

module TestEnvironment
  ROOT = File.expand_path("..", __dir__)
  class Error < StandardError; end
  module_function

  def bundler_version
    lock = File.join(ROOT, "core/Gemfile.lock")
    File.read(lock)[/BUNDLED WITH\s+([\d.]+)/, 1] || Bundler::VERSION
  end

  # Independent of the product's BundleEnvironment: a defect in that
  # module must not make the environment probe say Rails is unavailable.
  def clean_env
    env = {}
    ENV.each_key do |key|
      env[key] = nil if key.start_with?("BUNDLE_", "BUNDLER_") || %w[RUBYOPT RUBYLIB].include?(key)
    end
    %w[GEM_HOME GEM_PATH PATH].each do |key|
      original = ENV["BUNDLER_ORIG_#{key}"]
      env[key] = original == "BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL" ? nil : original if original
    end
    env
  end

  def probe_result(env, *command, chdir: ROOT, failure: "command")
    _out, stderr, status = Open3.capture3(env, *command, chdir: chdir)
    text = stderr.dup.force_encoding(Encoding::UTF_8).scrub
    kind = if status.success?
             nil
           elsif text.match?(/Operation not permitted|Permission denied|EACCES|EPERM/i)
             "permission"
           elsif text.match?(/GemNotFound|MissingSpec|cannot load such file|Could not find/i)
             "dependency"
           else
             failure
           end
    { "ok" => status.success?, "kind" => kind, "exit_status" => status.exitstatus }
  rescue Errno::EACCES, Errno::EPERM
    { "ok" => false, "kind" => "permission" }
  rescue SystemCallError
    { "ok" => false, "kind" => "dependency" }
  end

  def probe(env, *command, chdir: ROOT)
    probe_result(env, *command, chdir: chdir).fetch("ok")
  end

  def check(root: ROOT, profile: "full")
    raise Error, "profile must be unit or full" unless %w[unit full].include?(profile)
    checks = []
    add = ->(name, ok, remedy) { checks << { "name" => name, "ok" => ok, "remedy" => ok ? nil : remedy } }
    add.call("Ruby", Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.4"), "use a supported Ruby (docs/DEVELOPMENT.md)")
    core = File.join(root, "core")
    lock = File.join(core, "Gemfile.lock")
    locked_bundler = File.file?(lock) && File.read(lock)[/BUNDLED WITH\s+([\d.]+)/, 1]
    add.call("Bundler", !!locked_bundler && probe(clean_env, RbConfig.ruby, "-e", 'gem "bundler", ARGV.fetch(0)', locked_bundler), "install the Bundler version in core/Gemfile.lock")
    bundle_ok = File.file?(lock) && probe({ "BUNDLE_GEMFILE" => File.join(core, "Gemfile"), "BUNDLE_FROZEN" => "true" },
      RbConfig.ruby, "-rbundler/setup", "-e", 'require "rspec"; require "prism"; require "rbs"', chdir: core)
    add.call("core bundle", bundle_ok, "install the locked Core bundle in a bootstrap environment")
    if profile == "full"
      gems = probe(clean_env, RbConfig.ruby, "-e", 'gem "rails", "~> 8.1"; gem "sqlite3", ">= 2.1"; require "rails"; require "sqlite3"')
      add.call("Rails/sqlite3", gems, "install Rails ~> 8.1 and sqlite3 >= 2.1 as local gems")
      node = probe({}, "node", "-e", 'process.exit(Number(process.versions.node.split(".")[0]) >= 20 ? 0 : 1)')
      add.call("Node", node, "install Node 20 or later")
      inspection = probe_result({}, "ps", "-p", Process.pid.to_s, "-o", "pid=")
      if !inspection.fetch("ok") && (Process.kill(0, Process.pid) rescue false)
        inspection = { "ok" => true, "kind" => nil }
      end
      checks << inspection.merge("name" => "process inspection", "remedy" => inspection.fetch("ok") ? nil : "full E2E needs permission to inspect child processes")
      modules = File.join(root, "vscode/node_modules")
      client = %w[vscode-languageclient vscode-languageserver-protocol vscode-languageserver-types].all? { |name| File.file?(File.join(modules, name, "package.json")) }
      add.call("node_modules", client, "run npm ci in vscode during bootstrap")
      tags = RepoFiles.capture(root, ["tag", "--list", "v*"])
      add.call("release tags", $?.success? && !tags.strip.empty?, "fetch release tags in a network-enabled checkout")
    end
    { "profile" => profile, "ruby" => RUBY_VERSION, "bundler" => bundler_version,
      "ok" => checks.all? { |row| row.fetch("ok") }, "checks" => checks }
  end

  def fixture_key(root)
    source = File.join(root, "core/spec/fixtures/rails_real")
    inputs = [RUBY_ENGINE, RUBY_VERSION, RUBY_PLATFORM, bundler_version]
    %w[Gemfile Gemfile.lock].each do |name|
      path = File.join(source, name)
      inputs << (File.file?(path) ? Digest::SHA256.file(path).hexdigest : "absent")
    end
    Digest::SHA256.hexdigest(inputs.join("\0"))
  end

  def fixture_lock(root: ROOT)
    File.join(root, "core/tmp/test_environment", fixture_key(root), "Gemfile.lock")
  end

  def prepare(root: ROOT, profile: "full", offline: false)
    result = check(root: root, profile: profile)
    raise Error, "environment unavailable; run check --profile #{profile}" unless result.fetch("ok")
    FileUtils.mkdir_p(File.join(root, "core/tmp/tests"))
    return result.merge("prepared" => true, "offline" => offline) if profile == "unit"

    source = File.join(root, "core/spec/fixtures/rails_real")
    target = fixture_lock(root: root)
    FileUtils.mkdir_p(File.dirname(target))
    # Resolve only here, always locally. Online installation is an explicit
    # bootstrap step, never a side effect of executing a test.
    Dir.mktmpdir("ovallsp-prepare") do |dir|
      FileUtils.cp(File.join(source, "Gemfile"), dir)
      lock = File.file?(target) ? target : File.join(source, "Gemfile.lock")
      FileUtils.cp(lock, dir) if File.file?(lock)
      env = clean_env.merge("BUNDLE_VERSION" => bundler_version, "BUNDLE_GEMFILE" => File.join(dir, "Gemfile"),
                           "BUNDLE_APP_CONFIG" => File.join(dir, ".bundle"), "BUNDLE_USER_HOME" => File.join(dir, "bundle-home"))
      unless File.file?(File.join(dir, "Gemfile.lock"))
        resolved = probe_result(env, "bundle", "lock", "--local", chdir: dir, failure: "lock")
        raise Error, "fixture preparation: #{resolved.fetch('kind')} failure" unless resolved.fetch("ok")
      end
      checked = probe_result(env.merge("BUNDLE_FROZEN" => "true"), "bundle", "check", chdir: dir, failure: "lock")
      raise Error, "fixture preparation: #{checked.fetch('kind')} failure" unless checked.fetch("ok")
      with_fixture(source: source, lock: File.join(dir, "Gemfile.lock")) do |app|
        boot_env = clean_env.merge("BUNDLE_GEMFILE" => File.join(app, "Gemfile"), "BUNDLE_FROZEN" => "true",
                                   "BUNDLE_USER_HOME" => File.join(dir, "bundle-home"))
        boot = probe_result(boot_env, RbConfig.ruby, "-r./config/environment", "-e", "exit 0", chdir: app, failure: "boot")
        raise Error, "fixture preparation: #{boot.fetch('kind')} failure" unless boot.fetch("ok")
      end
      # No credentials, home paths or machine-specific source paths belong in a lock.
      text = File.read(File.join(dir, "Gemfile.lock"), encoding: "UTF-8")
      if text.include?(Dir.home) || text.match?(%r{(?:/Users/|/home/|://[^/\s]+@)})
        raise Error, "fixture lock contains private source data"
      end
      File.write(File.join(dir, "prepared.json"), JSON.generate(result.merge("key" => fixture_key(root))))
      %w[Gemfile.lock prepared.json].each do |name|
        # Atomic replacement; concurrent prepare never exposes a partial lock.
        temp = File.join(File.dirname(target), ".#{Process.pid}-#{name}")
        FileUtils.cp(File.join(dir, name), temp)
        File.rename(temp, File.join(File.dirname(target), name))
      end
    end
    result.merge("prepared" => true, "offline" => offline, "key" => fixture_key(root))
  rescue SystemCallError
    raise Error, "preparation denied or unavailable; no environment success recorded"
  end

  def copy_fixture(source:, lock:, destination:)
    raise Error, "run test_environment.rb prepare --profile full --offline first" unless File.file?(lock)
    FileUtils.mkdir_p(destination)
    # Copy source files, never a previous run's DB, log, cache or bundle config.
    Dir.children(source).sort.each do |name|
      next if %w[Gemfile.lock .bundle log tmp db].include?(name)
      FileUtils.cp_r(File.join(source, name), destination)
    end
    FileUtils.mkdir_p(File.join(destination, "db"))
    Dir.glob(File.join(source, "db", "**", "*.rb")).each do |file|
      relative = file.delete_prefix(source + "/")
      FileUtils.mkdir_p(File.dirname(File.join(destination, relative)))
      FileUtils.cp(file, File.join(destination, relative))
    end
    FileUtils.cp(lock, File.join(destination, "Gemfile.lock"))
    File.realpath(destination)
  end

  def with_fixture(source:, lock:)
    Dir.mktmpdir("ovallsp-rails-fixture") do |dir|
      copy_fixture(source: source, lock: lock, destination: dir)
      yield dir
    end
  end

  def main(argv)
    command = argv.shift
    options = { profile: "full", offline: false }
    parser = OptionParser.new do |opts|
      opts.on("--profile PROFILE") { |value| options[:profile] = value }
      opts.on("--offline") { options[:offline] = true }
    end
    parser.parse!(argv)
    raise Error, "unexpected arguments" unless argv.empty?
    result = case command
             when "check" then check(profile: options.fetch(:profile))
             when "prepare" then prepare(**options)
             else raise Error, "usage: test_environment.rb check|prepare --profile unit|full [--offline]"
             end
    puts JSON.pretty_generate(result)
    result.fetch("ok") ? 0 : 1
  rescue Error => error
    puts JSON.generate({ "ok" => false, "error" => error.message })
    1
  rescue OptionParser::ParseError, SystemCallError
    puts JSON.generate({ "ok" => false, "error" => "invalid arguments or inaccessible environment" })
    1
  end
end

exit TestEnvironment.main(ARGV) if $PROGRAM_NAME == __FILE__
