# frozen_string_literal: true

require_relative "utf8"
require_relative "deferred_findings"

require "optparse"
require "shellwords"

# Browsing and changing the issue register without opening it.
#
#   ruby scripts/issues.rb list [--status=open] [--target=0.4.0] [--kind=defect]
#   ruby scripts/issues.rb show 024.243
#   ruby scripts/issues.rb grep "gem index"
#   ruby scripts/issues.rb stats
#   ruby scripts/issues.rb check
#
# **Why a tool and not an editor.** The register is 25,000 lines across
# two files, every entry carries four enforced fields, a number may never
# be reused, the index is generated, resolving means moving an entry
# between files *and* dropping a marker from two documents, and a
# `String#sub` whose replacement holds a backtick pastes the preceding
# file in at the anchor. That last one happened twice and took the file
# from 11,555 lines to 25,878 (`024.225`). None of those are things a
# person should be holding in their head while writing prose.
#
# **It is not a second store.** Every read goes through
# `DeferredFindings`, which is what the specs read, so this cannot
# disagree with them about what an entry says. There is no cache and no
# database: the Markdown is the register, and this is a lens on it.
module Issues
  ROOT = ENV.fetch("OVALLSP_ISSUES_ROOT", File.expand_path("..", __dir__))

  Entry = Struct.new(:number, :title, :meta, :body, :archived, keyword_init: true) do
    def status = meta["status"].to_s
    def kind = meta["kind"].to_s
    def target = meta["target"].to_s
    def released_in = meta["released-in"].to_s
    def visible? = meta["user-visible"].to_s == "yes"
    def open? = status == "open"

    # Sorts the way a reader expects: 024.9 before 024.10, and the R
    # series after the numbered one.
    def sort_key
      rest = number.sub("024.", "")
      [rest.start_with?("R") ? 1 : 0, *rest.delete("R").split(".").map(&:to_i)]
    end
  end

  module_function

  def live_path = File.join(ROOT, DeferredFindings::LIVE)
  def archive_path = File.join(ROOT, DeferredFindings::ARCHIVE)

  def read(path) = File.exist?(path) ? File.read(path, encoding: "UTF-8") : ""

  # One entry list built from both files, tagged with which it came from.
  # `DeferredFindings.register` concatenates them for the checks; here the
  # provenance matters, because "where does this entry live" is half of
  # what the mutating subcommands have to get right.
  def all
    [[live_path, false], [archive_path, true]].flat_map do |path, archived|
      markdown = read(path)
      meta = DeferredFindings.entries(markdown)
      blocks_of(markdown).filter_map do |block|
        number = DeferredFindings.number_of(block) or next
        Entry.new(number: number, title: DeferredFindings.title_of(block),
                  meta: meta.fetch(number, {}), body: block, archived: archived)
      end
    end
  end

  def blocks_of(markdown) = markdown.split(/^(?=## 024\.)/).drop(1)

  def find(number)
    all.find { |e| e.number == number }
  end

  # --- browsing -------------------------------------------------------

  def filtered(opts)
    entries = all
    entries = entries.select { |e| e.status == opts[:status] } if opts[:status]
    entries = entries.select { |e| e.target == opts[:target] } if opts[:target]
    entries = entries.select { |e| e.kind == opts[:kind] } if opts[:kind]
    entries = entries.select(&:visible?) if opts[:visible]
    entries.sort_by(&:sort_key)
  end

  def list(opts)
    rows = filtered(opts)
    rows.each do |e|
      flags = [e.kind, e.target.empty? ? nil : "-> #{e.target}", e.visible? ? "user-visible" : nil].compact
      puts format("%-10s %-7s %-46s %s", e.number, e.status, flags.join(" "), truncate(e.title, 70))
    end
    puts
    puts "#{rows.length} entr#{rows.length == 1 ? 'y' : 'ies'}#{describe(opts)}."
    0
  end

  def describe(opts)
    parts = %i[status target kind].filter_map { |k| "#{k} #{opts[k]}" if opts[k] }
    parts << "user-visible" if opts[:visible]
    parts.empty? ? "" : " matching #{parts.join(', ')}"
  end

  def truncate(text, width) = text.length > width ? "#{text[0, width - 1]}…" : text

  def show(number, opts)
    entry = find(number)
    unless entry
      retired = DeferredFindings.retired_numbers(read(live_path))
      if retired.include?(number)
        warn "#{number} was retired. Its number stays resolvable and its row is in the register's " \
             "\"Retired numbers\" table; the entry itself is gone."
        return 3
      end
      warn "no entry #{number}. `ruby scripts/issues.rb list` shows what there is."
      return 3
    end

    puts "#{entry.number} #{entry.title}"
    puts "  in: #{entry.archived ? 'archive' : 'live register'}"
    entry.meta.each { |k, v| puts format("  %-14s %s", "#{k}:", v) }
    puts "  published:     #{published_in(entry.number).join(', ')}" unless published_in(entry.number).empty?
    puts
    puts opts[:full] ? entry.body : first_paragraphs(entry.body, 3)
    0
  end

  def first_paragraphs(block, count)
    after_meta = block.split(/^```$/, 3).last.to_s
    after_meta.split(/\n\n+/).reject { |p| p.strip.empty? }.first(count).join("\n\n")
  end

  # Which language's KNOWN_LIMITATIONS carries this entry's paragraph.
  def published_in(number)
    { "en" => "docs/KNOWN_LIMITATIONS.md", "ja" => "docs/KNOWN_LIMITATIONS.ja.md" }.filter_map do |lang, path|
      lang if DeferredFindings.documents?(read(File.join(ROOT, path)), number)
    end
  end

  def grep(pattern, opts)
    regexp = Regexp.new(pattern, opts[:case_sensitive] ? nil : Regexp::IGNORECASE)
    hits = all.select { |e| e.title.match?(regexp) || e.body.match?(regexp) }
    hits.sort_by(&:sort_key).each do |e|
      line = e.body.lines.find { |l| l.match?(regexp) && !l.start_with?("## ") }
      puts format("%-10s %-7s %s", e.number, e.status, truncate(e.title, 62))
      puts "             #{truncate(line.strip, 84)}" if line
    end
    puts
    puts "#{hits.length} entr#{hits.length == 1 ? 'y' : 'ies'} matching /#{pattern}/."
    0
  end

  def stats
    entries = all
    open = entries.select(&:open?)
    puts "#{entries.length} entries: #{open.length} open, #{entries.length - open.length} resolved."
    puts
    puts "open by target:"
    open.group_by { |e| e.target.empty? ? "(none)" : e.target }
        .sort_by { |target, group| [-group.length, target] }
        .each { |target, group| puts format("  %-14s %d", target, group.length) }
    puts
    puts "open by kind:"
    open.group_by(&:kind).sort_by { |_, g| -g.length }.each { |kind, g| puts format("  %-14s %d", kind, g.length) }
    puts
    visible = open.select(&:visible?)
    unpublished = visible.reject { |e| published_in(e.number).include?("en") }
    puts "user-visible and open: #{visible.length}, of which #{unpublished.length} unpublished"
    unpublished.each { |e| puts "  #{e.number} #{truncate(e.title, 68)}" }
    0
  end

  USAGE = <<~TEXT
    usage: ruby scripts/issues.rb <command> [options]

      list [--status=S] [--target=V] [--kind=K] [--visible]   one line per entry
      show <024.N> [--full]                                   one entry
      grep <pattern> [--case-sensitive]                       entries whose text matches
      stats                                                   counts, and what is unpublished
      check                                                   run every register guard
      intake                                                  what has been noticed but not driven
      intake add "<title>" --where=W --detail=D               record something noticed
      retarget <024.N> --to=V --why="..."                     move an entry to another release
      next-number                                             the next free number, never a retired one

    Every read goes through the same reader the specs use, so this cannot
    disagree with them about what an entry says.
  TEXT

  def run(argv)
    command = argv.shift
    opts = {}
    parser = OptionParser.new do |o|
      o.on("--status=S") { |v| opts[:status] = v }
      o.on("--target=V") { |v| opts[:target] = v }
      o.on("--kind=K") { |v| opts[:kind] = v }
      o.on("--visible") { opts[:visible] = true }
      o.on("--full") { opts[:full] = true }
      o.on("--case-sensitive") { opts[:case_sensitive] = true }
      o.on("--where=W") { |v| opts[:where] = v }
      o.on("--detail=D") { |v| opts[:detail] = v }
      o.on("--to=V") { |v| opts[:to] = v }
      o.on("--why=W") { |v| opts[:why] = v }
      o.on("--root=PATH") { |v| opts[:root] = v }
    end
    rest = parser.parse(argv)

    case command
    when "list" then list(opts)
    when "show" then rest.first ? show(rest.first, opts) : (warn(USAGE) || 2)
    when "grep" then rest.first ? grep(rest.first, opts) : (warn(USAGE) || 2)
    when "stats" then stats
    when "intake" then rest.first == "add" ? intake_add(rest[1].to_s, opts) : intake_list
    when "retarget" then rest.first ? retarget(rest.first, opts) : (warn(USAGE) || 2)
    when "next-number" then (puts next_number) || 0
    when "check" then check
    else
      warn USAGE
      command.nil? ? 2 : 2
    end
  rescue RefusedWrite => e
    warn "issues: refused. #{e.message}"
    2
  rescue DeferredFindings::UnknownKey => e
    warn "the register does not parse: #{e.message}"
    2
  end

# --- the write primitive ---------------------------------------------

# **Every mutating subcommand goes through this and nothing else.**
#
# It takes a path and a block that is handed the file's *lines* and
# returns the new lines. Not a string, and never a pattern with a
# replacement: `String#sub` expands backreferences in the replacement,
# and `\`` means "everything before the match", so a replacement
# holding an escaped backtick pastes the preceding file in at the
# anchor. That happened twice and took the register from 11,555 lines
# to 25,878 (`024.225`), and the line count was the only symptom.
#
# So the primitive:
#
# - works on an Array of lines, where there is no replacement string
#   for anything to expand in;
# - is told what the line delta should be, and refuses a write whose
#   delta is not what the caller intended -- which is the symptom
#   `024.225` had and nothing was watching;
# - re-parses the register afterwards and restores the file if it no
#   longer parses;
# - writes through a temp file and renames, so an interrupted run
#   leaves the old file rather than half of a new one.
class RefusedWrite < StandardError; end

def rewrite(path, expect_delta:, why:, expect_entries: 0)
  shape_before = shape_of(File.read(path, encoding: "UTF-8"))
  before = File.readlines(path, encoding: "UTF-8")
  after = yield(before.dup)
  raise RefusedWrite, "#{why}: the edit returned #{after.class}, not an Array of lines" unless after.is_a?(Array)

  delta = after.length - before.length
  unless delta == expect_delta
    raise RefusedWrite,
          "#{why}: expected the file to change by #{expect_delta} line(s) and it changed by #{delta}. " \
          "Refusing. This is the shape `024.225` had, where a scripted edit pasted the file into itself " \
          "and only the line count showed it."
  end

  atomic_write(path, after.join)
  verify_shape!(path, before, shape_before, expect_entries, why)
  delta
end

def atomic_write(path, content)
  tmp = "#{path}.issues-tmp-#{Process.pid}"
  File.write(tmp, content)
  File.rename(tmp, path)
ensure
  File.unlink(tmp) if tmp && File.exist?(tmp)
end

# **What the file must still be afterwards.** The first version of this
# only re-parsed the yaml blocks, and an adversarial test walked straight
# past it: a junk line inserted *outside* a block is not a key the
# metadata reader ever sees, so it parsed clean and the edit was allowed.
# Two stronger things are asserted now.
#
# - **Every heading parses.** `headings` reads `## 024.N` lines and
#   `entries` reads the strict grammar; a heading with no entry behind it
#   is precisely what a broken edit leaves, and comparing the two sets
#   finds it whatever the damage looked like.
# - **The entry set changed by exactly what the caller intended.** A
#   retarget changes no numbers; adding one changes one. Anything else is
#   the edit having done something nobody asked for.
#
# A file that fails either is put back. Leaving it for someone to find is
# how a register ends up 25,878 lines long (`024.225`).
def shape_of(markdown)
  { headings: DeferredFindings.headings(markdown).sort,
    entries: DeferredFindings.entries(markdown).keys.sort }
rescue DeferredFindings::UnknownKey
  nil
end

def verify_shape!(path, previous_lines, shape_before, expect_entries, why)
  after = shape_of(File.read(path, encoding: "UTF-8"))
  problem =
    if after.nil?
      "the register no longer parses"
    elsif (orphans = after[:headings] - after[:entries]).any?
      "#{orphans.length} heading(s) have no metadata behind them: #{orphans.first(3).join(', ')}"
    elsif shape_before && (moved = after[:entries].length - shape_before[:entries].length) != expect_entries
      "the entry count changed by #{moved}, and #{expect_entries} was intended"
    end
  return unless problem

  atomic_write(path, previous_lines.join)
  raise RefusedWrite, "#{why}: #{problem}. The file has been put back."
end

# --- allocating a number ---------------------------------------------

# The next free number, which is never a retired one. A retired entry
# keeps its number resolvable precisely so a citation of it still
# means something; handing it to a new issue would make every old
# citation point at the wrong thing.
def next_number
  markdown = DeferredFindings.register(ROOT)
  used = DeferredFindings.headings(markdown).filter_map { |n| n[/\A024\.(\d+)\z/, 1]&.to_i }
  retired = DeferredFindings.retired_numbers(markdown).filter_map { |n| n[/\A024\.(\d+)\z/, 1]&.to_i }
  "024.#{((used + retired).max || 0) + 1}"
end

# --- intake ------------------------------------------------------------

INTAKE_HEADING = "## Intake"
INTAKE_EMPTY = "<!-- intake: none -->"
ISSUES_DOC = File.join("docs", "ISSUES.md")

# An issue that has been *noticed*, not driven. It goes here and not in
# the register, because every register field is enforced and an entry
# opened before those are known is an entry corrected later, in a file
# where a correction costs a re-index.
def intake_add(title, opts)
  where = opts[:where] or raise RefusedWrite, "--where is required: say what found it"
  detail = opts[:detail] or raise RefusedWrite, "--detail is required: say what was seen"

  path = File.join(ROOT, ISSUES_DOC)
  entry = [
    "- **#{title}**\n",
    "  - found by: #{where}\n",
    "  - #{detail}\n",
    "  - unverified: not yet driven against the tree\n"
  ]

  added = rewrite(path, expect_delta: entry.length, why: "intake add") do |lines|
    at = lines.index { |l| l.start_with?(INTAKE_HEADING) } or
      raise RefusedWrite, "#{ISSUES_DOC} has no #{INTAKE_HEADING} section"
    insert = lines[at..].index { |l| l.strip == INTAKE_EMPTY || l.start_with?("## Index") }
    raise RefusedWrite, "cannot find where the intake list ends" unless insert

    lines.insert(at + insert, *entry)
  end

  puts "issues: added to intake (#{added} lines). It is not in the register and has no number:"
  puts "  #{title}"
  puts "Drive it with a control before promoting it -- see docs/ISSUES.md, \"The rule\"."
  0
end

def intake_list
  body = File.read(File.join(ROOT, ISSUES_DOC), encoding: "UTF-8")
  section = body.split(/^#{Regexp.escape(INTAKE_HEADING)}$/, 2).last.to_s.split(/^## /, 2).first.to_s
  items = section.lines.select { |l| l.start_with?("- **") }
  items.each { |l| puts "  #{l.strip.delete_prefix('- ')}" }
  puts items.empty? ? "  (nothing in intake)" : "\n#{items.length} untriaged."
  0
end

# --- retargeting -------------------------------------------------------

# Changing which release owes an entry. The reason is required and is
# written into the entry, because `024.276` is 54 entries retargeted
# with two pasted sentences between them -- and because
# `repeated_paragraphs` will refuse a shared one anyway.
def retarget(number, opts)
  to = opts[:to] or raise RefusedWrite, "--to is required: name the release"
  why = opts[:why] or raise RefusedWrite, "--why is required, and it must be this entry's own reason"

  entry = find(number) or raise RefusedWrite, "no entry #{number}"
  raise RefusedWrite, "#{number} is #{entry.status}, not open" unless entry.open?
  raise RefusedWrite, "#{number} already targets #{to}" if entry.target == to

  path = entry.archived ? archive_path : live_path
  note = ["\n", "**Retargeted to #{to}.** #{why}\n"]

  rewrite(path, expect_delta: note.length, why: "retarget #{number}") do |lines|
    at = lines.index { |l| l.start_with?("## #{number} ") } or
      raise RefusedWrite, "cannot find #{number}'s heading"
    target_line = (at..).find { |i| lines[i]&.start_with?("target: ") } or
      raise RefusedWrite, "#{number} has no target: line"
    raise RefusedWrite, "#{number}'s target line is past its own entry" if lines[target_line + 1..]&.first.nil?

    lines[target_line] = "target: #{to}\n"
    stop = (at + 1...lines.length).find { |i| lines[i].start_with?("## 024.") } || lines.length
    lines.insert(stop, *note)
  end

  puts "issues: #{number} now targets #{to}."
  reindex_and_check
end

def reindex_and_check
  system("ruby", "scripts/reindex_findings.rb", chdir: ROOT, out: File::NULL)
  system("ruby", "scripts/issue_index.rb", chdir: ROOT, out: File::NULL)
  check
end

  # --- checking -------------------------------------------------------

  # Delegates rather than reimplements: these are the repository's own
  # guards, and a second implementation of them here would be a second
  # thing to keep right.
  CHECKS = [
    ["register index current", %w[ruby scripts/reindex_findings.rb --check]],
    ["issue index current", %w[ruby scripts/issue_index.rb --check]],
    ["resolved findings archived", %w[ruby scripts/archive_resolved_findings.rb --check]]
  ].freeze

  def check
    failures = CHECKS.reject do |name, command|
      ok = system(*command, chdir: ROOT, out: File::NULL)
      puts format("  %-28s %s", name, ok ? "ok" : "FAILED")
      ok
    end
    if failures.empty?
      puts "issues: the register's own guards all pass."
      0
    else
      warn "issues: #{failures.length} check(s) failed. Run the command shown to see why."
      1
    end
  end
end

exit Issues.run(ARGV) if $PROGRAM_NAME == __FILE__
