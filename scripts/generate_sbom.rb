#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates docs/SBOM.md -- a dependency + license manifest for exactly what
# a packaged VSIX ships to an end user: core/'s own runtime gem dependencies
# (vendored into vscode/core/vendor/bundle by vscode/scripts/copy-core.js,
# per ADR-0004) and vscode/'s own npm production dependency closure --
# vscode-languageclient plus every one of *its* production-flagged
# transitive dependencies (vscode-jsonrpc, semver, a nested minimatch, ...),
# not just the one direct dependency named in package.json.
#
# Deliberately excludes development-only dependencies (rspec, benchmark,
# @vscode/vsce, mocha, typescript, ...) -- those never ship in the VSIX, so
# listing them in a *runtime* SBOM would misrepresent what end users
# actually receive and run. Run manually via `ruby scripts/generate_sbom.rb`
# whenever core/ovallsp.gemspec's, core/Gemfile.lock's, or
# vscode/package-lock.json's production dependency set changes; not run
# automatically by CI/tests (RELEASE_CHECKLIST.md item 8).

require "bundler"
require "json"

ROOT = File.expand_path("..", __dir__)

def gem_rows
  Bundler.with_unbundled_env do
    Dir.chdir(File.join(ROOT, "core")) do
      lockfile = Bundler::LockfileParser.new(Bundler.read_file("Gemfile.lock"))
      specs_by_name = lockfile.specs.each_with_object({}) { |spec, h| h[spec.name] = spec }

      direct_runtime_dep_names = Gem::Specification.load(File.join(ROOT, "core", "ovallsp.gemspec"))
                                                     .dependencies
                                                     .select { |d| d.type == :runtime }
                                                     .map(&:name)

      # The full *transitive* runtime closure, not just ovallsp.gemspec's
      # own direct dependencies -- a gem this project depends on directly
      # can itself have runtime dependencies of its own (rbs depends on
      # logger and tsort; see core/Gemfile.lock), and every one of those is
      # vendored into vendor/bundle by vscode/scripts/copy-core.js and
      # loaded at runtime exactly as much as prism/rbs themselves are.
      # Reading only the gemspec's direct list previously produced an SBOM
      # naming 2 gems (prism, rbs) against an actually-vendored set of 4
      # (prism, rbs, logger, tsort) -- found reviewing packaging/release
      # readiness. Walked via the *lockfile's* own dependency graph (each
      # spec's `#dependencies`), not gemspecs read off this machine's
      # installed gems, so the closure reflects exactly what
      # Gemfile.lock resolved and vendor/bundle actually contains,
      # regardless of what else happens to be installed locally.
      closure_names = []
      queue = direct_runtime_dep_names.dup
      until queue.empty?
        name = queue.shift
        next if closure_names.include?(name)

        closure_names << name
        spec = specs_by_name[name]
        next unless spec

        queue.concat(spec.dependencies.map(&:name))
      end

      closure_names
        .filter_map { |name| specs_by_name[name] }
        .sort_by(&:name)
        .map do |spec|
          installed = Gem::Specification.find_all_by_name(spec.name, spec.version).first
          # License metadata's source of truth is the *packaged* gemspec
          # (what actually ships in the VSIX), not whatever happens to be
          # installed on the machine generating this report -- an
          # `installed` lookup that finds nothing (or a locally-patched/
          # different-version install) must degrade to "unknown" rather
          # than silently reporting a different release's license or
          # raising.
          license = installed&.license || installed&.licenses&.first || "unknown"
          { name: spec.name, version: spec.version.to_s, license: license, ecosystem: "RubyGems" }
        end
    end
  end
end

def npm_rows
  # Explicit encoding, not the invoking shell's ambient locale. Found in
  # Task 023.8 by running the release gate under a shell with no locale
  # set: Ruby then reads the file as US-ASCII, and a single non-ASCII
  # byte anywhere in the lockfile makes `JSON.parse` raise on input that
  # is perfectly valid. The rationale used to be deferred to
  # `make-final-review-bundle.sh`, which 0.2.14 deleted.
  lock = JSON.parse(File.read(File.join(ROOT, "vscode", "package-lock.json"), encoding: "UTF-8"))

  # `package.json`'s own top-level `dependencies` names only the *direct*
  # production dependency (vscode-languageclient) -- but that package's own
  # production-flagged transitive dependencies (vscode-jsonrpc, semver, a
  # nested minimatch, ...) are exactly as real a part of what a packaged
  # VSIX ships (they land in node_modules/ and get bundled by
  # vscode/scripts/copy-core.js's sibling packaging step, `vsce package`).
  # Found missing by an independent review: reading only `package.json`'s
  # `dependencies` keys produced an SBOM listing 1 npm package when the
  # actual production install closure is 8. `package-lock.json`'s own
  # per-package `dev` flag is already exactly this closure -- npm sets
  # `dev: true` only on a package reachable exclusively through
  # devDependencies, so filtering on its absence needs no separate graph
  # walk.
  lock.fetch("packages", {})
      .select { |key, entry| key.start_with?("node_modules/") && !entry["dev"] }
      .map do |key, entry|
        { name: key.sub(%r{.*node_modules/}, ""), version: entry["version"], license: entry["license"] || "unknown",
          ecosystem: "npm" }
      end
      .sort_by { |row| [row[:name], row[:version]] }
end

def render(rows)
  lines = []
  lines << "# Software Bill of Materials"
  lines << ""
  lines << "Auto-generated by `scripts/generate_sbom.rb` -- do not edit by hand."
  lines << "Regenerate after any change to `core/ovallsp.gemspec`, `core/Gemfile.lock`,"
  lines << "or `vscode/package-lock.json` (any production dependency, direct or"
  lines << "transitive -- not just `package.json`'s own top-level `dependencies`)."
  lines << ""
  lines << "Scope: only what a packaged VSIX actually ships and runs --"
  lines << "core/'s runtime gem dependencies (vendored per ADR-0004) and the full"
  lines << "production install closure of vscode/'s npm dependencies (per"
  lines << "package-lock.json's own `dev` flag, direct and transitive)."
  lines << "Development-only tooling (rspec, @vscode/vsce, typescript, mocha, ...)"
  lines << "is intentionally excluded."
  lines << ""
  lines << "| Ecosystem | Package | Version | License |"
  lines << "|---|---|---|---|"
  rows.each do |row|
    lines << "| #{row[:ecosystem]} | #{row[:name]} | #{row[:version]} | #{row[:license]} |"
  end
  lines << ""
  "#{lines.join("\n")}\n"
end

rows = gem_rows + npm_rows
# Overridable so a spec can prove `--check` actually fires. Pointing it
# at a throwaway copy is the only safe way to plant a divergence: the
# alternative is mutating the tracked `docs/SBOM.md` and restoring it,
# which leaves the tree modified whenever the example fails.
out_path = ENV.fetch("SBOM_PATH", File.join(ROOT, "docs", "SBOM.md"))
rendered = render(rows)

# `--check` renders and compares without writing, so the suite can hold
# this gate. It could not before: the script writes `docs/SBOM.md` in
# place, and a spec that ran it would mutate a tracked file and leave it
# mutated if the example failed.
#
# Until 0.2.14 the only thing enforcing this was a step in
# `make-final-review-bundle.sh`, which nothing invoked -- so a
# `docs/SBOM.md` that had drifted from its own generator was caught by
# nothing. 046's C7.
if ARGV.include?("--check")
  current = File.exist?(out_path) ? File.read(out_path) : nil
  if current == rendered
    puts "sbom --check: docs/SBOM.md matches a fresh render (#{rows.size} packages)."
    exit 0
  end

  warn("sbom --check: docs/SBOM.md does not match what this script would generate.")
  if current.nil?
    warn("  docs/SBOM.md does not exist.")
  else
    a = current.split("\n")
    b = rendered.split("\n")
    (0...[a.length, b.length].max).each do |i|
      next if a[i] == b[i]

      warn("  line #{i + 1}:")
      warn("    file:      #{a[i].inspect}")
      warn("    generated: #{b[i].inspect}")
    end
  end
  warn("sbom --check: run `ruby scripts/generate_sbom.rb` and commit the result. " \
       "The SBOM states what a packaged VSIX ships to a user; a stale one is a false claim about that.")
  exit 1
end

File.write(out_path, rendered)
puts "wrote #{out_path} (#{rows.size} packages)"
