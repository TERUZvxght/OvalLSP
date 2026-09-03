#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"
require_relative "repo_files"

require "yaml"

# `docs/DOCUMENTATION_MAP.md`'s trigger table, for the rows a machine can
# read.
#
#   ruby scripts/doc_triggers.rb            # against origin/main
#   ruby scripts/doc_triggers.rb --base X   # against another ref
#
# The table says what else must change when a given file does, and its
# "Checked by" column reads `—` on several rows: enforced by whoever
# remembers to open the document, which is the arrangement the map's own
# header says kept failing.
#
# **Only the rows whose left column is a set of files.** A revert, or a
# round finding the same place the previous one did, is a judgement no
# scanner makes and stays prose in the table.
#
# **And only the pairs nothing already checks.** A rule restating
# `check_protocol_doc.rb`, `design_doc_drift_spec` or
# `swallowed_failures_spec` would be a second and weaker implementation
# of a check that exists — which is the thing this repository has counted
# six of, each reader the only reader of its own result (`024.216`).
# `docs/doc_triggers.yml` says, per rule, what it adds.
#
# **One companion, not all of them.** A row lists several, and which
# apply varies with the change; requiring every one would fire on
# ordinary work, and a check with that error rate gets switched off
# (`024.150` measured three false positives in eleven and the check was
# removed). What this catches is the failure that actually happens:
# changing a trigger file and touching none of its companions.
module DocTriggers
  ROOT = File.expand_path("..", __dir__)
  RULES = File.join("docs", "doc_triggers.yml")
  DEFAULT_BASE = "origin/main"

  # Raised when the diff cannot be computed. A checker that cannot see
  # what it checks reports exactly what a working one reports when
  # nothing is wrong (`024.148`), so this is never a quiet pass.
  Unreadable = Class.new(StandardError)

  module_function

  def rules(root = ROOT)
    path = File.join(root, RULES)
    raise Unreadable, "#{RULES} does not exist" unless File.file?(path)

    YAML.safe_load(File.read(path, encoding: "UTF-8")) || []
  end

  def matches?(glob, path) = File.fnmatch?(glob, path, File::FNM_PATHNAME | File::FNM_DOTMATCH)

  # Everything this branch has touched: the committed range against the
  # base, **and** the working tree. `preflight` runs before the commit,
  # so a check reading only the committed range is blind in exactly the
  # window it runs in (`024.147`).
  def changed(root, base)
    committed = RepoFiles.capture(root, ["diff", "--name-only", "#{base}...HEAD"])
    raise Unreadable, "cannot diff against #{base}: #{committed.strip}" unless $?.success?

    working = RepoFiles.capture(root, %w[status --porcelain])
    raise Unreadable, "cannot read the working tree: #{working.strip}" unless $?.success?

    (committed.lines.map(&:strip) + working.lines.map { |line| status_path(line) }).reject(&:empty?).uniq
  end

  # `XY path`, or `XY old -> new` for a rename. The new name is the one
  # a rule is about; the old one no longer exists to be checked.
  def status_path(line)
    path = line[3..].to_s.strip
    path.include?(" -> ") ? path.split(" -> ").last.strip : path
  end

  def complaints(root, rules, base)
    touched = changed(root, base)

    rules.filter_map do |rule|
      triggers = rule["when"].select { |glob| touched.any? { |path| matches?(glob, path) } }
      next if triggers.empty?
      next if rule["then"].any? { |glob| touched.any? { |path| matches?(glob, path) } }

      "#{rule['id']}: #{triggers.join(', ')} changed and none of " \
        "#{rule['then'].join(', ')} did.\n      #{rule['note']}"
    end
  end

  def run(argv)
    base = argv.include?("--base") ? argv[argv.index("--base") + 1] : DEFAULT_BASE
    table = rules
    found = complaints(ROOT, table, base)

    # The census before the verdict: an empty rule set is consistent with
    # itself and reports what a full one reports when nothing is wrong.
    puts "doc-triggers: #{table.length} rule(s) read, against #{base}."

    if found.empty?
      puts "doc-triggers: every trigger this change touched had a companion change with it."
      return 0
    end

    warn "doc-triggers: #{found.length} rule(s) whose companion did not change:"
    found.each { |complaint| warn "  - #{complaint}" }
    warn "Change the companion, or change the rule in #{RULES} and the row in docs/DOCUMENTATION_MAP.md."
    1
  rescue Unreadable => e
    warn "doc-triggers: #{e.message}"
    warn "This check cannot see what it checks, which is not the same as finding nothing."
    2
  end
end

exit DocTriggers.run(ARGV) if $PROGRAM_NAME == __FILE__
