#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"

# Verifies docs/SBOM.md actually matches what a packaged, unpacked VSIX
# contains -- not just what scripts/generate_sbom.rb computed from
# Gemfile.lock/package-lock.json/ovallsp.gemspec in isolation. Compares
# both ecosystems' *sets* of package names (missing entries and stale/
# extra entries are both failures) so the SBOM can never silently drift
# from the artifact it claims to describe.
#
# Usage: ruby scripts/verify_sbom_against_vsix.rb <path-to-unpacked-vsix-extension-dir>
# (the directory containing core/ and node_modules/, i.e. `<vsix>/extension`)

require "set"

def fail!(message)
  warn "verify-sbom: FAILED: #{message}"
  exit 1
end

extension_root = ARGV[0] or fail!("usage: verify_sbom_against_vsix.rb <unpacked-vsix-extension-dir>")
repo_root = File.expand_path("..", __dir__)
sbom_path = File.join(repo_root, "docs", "SBOM.md")

File.file?(sbom_path) or fail!("#{sbom_path} does not exist -- run scripts/generate_sbom.rb first")

sbom_rows = File.readlines(sbom_path)
                .grep(/^\| (RubyGems|npm) \|/)
                .map { |line| line.split("|").map(&:strip) }
                .map { |(_, ecosystem, name, _version, _license)| [ecosystem, name] }

sbom_rubygems = sbom_rows.select { |(ecosystem, _)| ecosystem == "RubyGems" }.map { |(_, name)| name }.to_set
sbom_npm = sbom_rows.select { |(ecosystem, _)| ecosystem == "npm" }.map { |(_, name)| name }.to_set

vendor_root = File.join(extension_root, "core", "vendor", "bundle")
Dir.exist?(vendor_root) or fail!("no core/vendor/bundle found under #{extension_root} -- was this VSIX packaged with vendoring?")

actual_rubygems = Dir.glob(File.join(vendor_root, "ruby", "*", "gems", "*"))
                      .map { |path| File.basename(path) }
                      # Strip the trailing `-<version>` gem-directory
                      # suffix, keeping only the gem name -- a version is
                      # not part of the *set* comparison this script does
                      # (docs/SBOM.md's own version column is compared by
                      # eye at review time, not mechanically here).
                      .map { |dir| dir.sub(/-[0-9][^-]*(-[a-z0-9_]+)?$/, "") }
                      .to_set

missing_from_sbom = actual_rubygems - sbom_rubygems
extra_in_sbom = sbom_rubygems - actual_rubygems

fail!("gems vendored in the VSIX but missing from docs/SBOM.md: #{missing_from_sbom.to_a.sort.join(", ")}") unless missing_from_sbom.empty?
fail!("gems listed in docs/SBOM.md but not actually vendored in the VSIX: #{extra_in_sbom.to_a.sort.join(", ")}") unless extra_in_sbom.empty?

puts "verify-sbom: RubyGems set matches (#{actual_rubygems.size} packages)"

node_modules_root = File.join(extension_root, "node_modules")
Dir.exist?(node_modules_root) or fail!("no node_modules found under #{extension_root}")

# Every package actually present, at every nesting level -- npm hoists
# what it can but leaves a dependency nested under its own parent's
# `node_modules/` when two packages need conflicting versions of the same
# transitive dependency (e.g. `vscode-languageclient/node_modules/
# minimatch`, a different `minimatch` version than the one hoisted to the
# top level). That's exactly as real a part of what ships in the VSIX as
# anything hoisted, and exactly what `package-lock.json`'s own `packages`
# keys (which `scripts/generate_sbom.rb` reads) already reflect -- so the
# comparison here has to walk every `node_modules` directory found
# anywhere under the extension root, not just the top-level one, and
# expand scoped packages (`@scope/name`) as a two-level entry.
def npm_package_names_in(node_modules_dir)
  Dir.children(node_modules_dir).flat_map do |entry|
    next [] if entry.start_with?(".")

    full = File.join(node_modules_dir, entry)
    next [] unless File.directory?(full)

    entry.start_with?("@") ? Dir.children(full).map { |scoped| "#{entry}/#{scoped}" } : [entry]
  end
end

actual_npm = Dir.glob(File.join(extension_root, "**", "node_modules"))
                .flat_map { |dir| npm_package_names_in(dir) }
                .to_set

missing_from_sbom_npm = actual_npm - sbom_npm
extra_in_sbom_npm = sbom_npm - actual_npm

fail!("npm packages in the VSIX but missing from docs/SBOM.md: #{missing_from_sbom_npm.to_a.sort.join(", ")}") unless missing_from_sbom_npm.empty?
fail!("npm packages listed in docs/SBOM.md but not actually in the VSIX: #{extra_in_sbom_npm.to_a.sort.join(", ")}") unless extra_in_sbom_npm.empty?

puts "verify-sbom: npm set matches (#{actual_npm.size} packages)"
puts "verify-sbom: PASS"
