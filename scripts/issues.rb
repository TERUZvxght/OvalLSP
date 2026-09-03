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

  # The two documents a user-visible finding is published in. One
  # constant because `close` has to open the same two files this reads,
  # and a second spelling of the pair is a second thing to keep right.
  LIMITATION_DOCS = { "en" => File.join("docs", "KNOWN_LIMITATIONS.md"),
                      "ja" => File.join("docs", "KNOWN_LIMITATIONS.ja.md") }.freeze

  # Which language's KNOWN_LIMITATIONS carries this entry's paragraph.
  def published_in(number)
    LIMITATION_DOCS.filter_map do |lang, path|
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
      promote <n> --kind=K --target=V --area=A --direction=D  intake item n becomes an entry
                  [--user-visible=yes|no --note="..."]
      close <024.N> --released-in=V [--drop-paragraphs]       resolve an entry
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
      o.on("--area=A") { |v| opts[:area] = v }
      o.on("--direction=D") { |v| opts[:direction] = v }
      o.on("--user-visible=V") { |v| opts[:user_visible] = v }
      o.on("--note=N") { |v| opts[:note] = v }
      o.on("--released-in=V") { |v| opts[:released_in] = v }
      o.on("--drop-paragraphs") { opts[:drop_paragraphs] = true }
      o.on("--root=PATH") { |v| opts[:root] = v }
    end
    rest = parser.parse(argv)

    case command
    when "list" then list(opts)
    when "show" then rest.first ? show(rest.first, opts) : (warn(USAGE) || 2)
    when "grep" then rest.first ? grep(rest.first, opts) : (warn(USAGE) || 2)
    when "stats" then stats
    when "intake" then rest.first == "add" ? intake_add(rest[1].to_s, opts) : intake_list
    when "promote" then rest.first ? promote(rest.first, opts) : (warn(USAGE) || 2)
    when "close" then rest.first ? close(rest.first, opts) : (warn(USAGE) || 2)
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

# The line `intake add` writes to say the item has not been driven yet.
# `promote` drops it, because promoting *is* the claim that it has been
# driven -- carrying the line into the entry would publish the opposite.
# One constant rather than two spellings: the writer and the reader of a
# marker have to agree about it, and this repository has counted six
# readers of one grammar written six ways (`024.216`).
INTAKE_UNVERIFIED = "unverified: not yet driven against the tree"

# A bullet in the intake list. The detail lines under it are indented,
# which is what `intake add` writes and what tells one item from the
# next.
INTAKE_BULLET = /\A- \*\*(.+)\*\*\s*\z/
INTAKE_DETAIL = /\A[ \t]+\S/

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
    "  - #{INTAKE_UNVERIFIED}\n"
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

# Where the intake list starts and stops, as line indices.
def intake_section(lines)
  at = lines.index { |l| l.start_with?(INTAKE_HEADING) } or
    raise RefusedWrite, "#{ISSUES_DOC} has no #{INTAKE_HEADING} section"
  stop = ((at + 1)...lines.length).find { |i| lines[i].start_with?("## ") } || lines.length
  [at, stop]
end

# Every intake item as `[line index, title, detail lines]`, in the order
# they are written.
#
# **One enumeration, because `promote` takes a position in this list.**
# Listing the items and finding the n-th are the same question asked
# twice; two scans of one text is the shape `CLAUDE.md`'s countermeasure
# section prescribes replacing with one both readers use, and here the
# cost of disagreeing is promoting whichever item the other reader would
# not have shown.
def intake_items(lines)
  at, stop = intake_section(lines)
  ((at + 1)...stop).filter_map do |i|
    title = lines[i][INTAKE_BULLET, 1] or next

    detail = ((i + 1)...stop).take_while { |j| lines[j].match?(INTAKE_DETAIL) }.map { |j| lines[j] }
    [i, title, detail]
  end
end

def intake_list
  items = intake_items(File.readlines(File.join(ROOT, ISSUES_DOC), encoding: "UTF-8"))
  items.each_with_index { |(_, title, _), n| puts format("  %2d. %s", n + 1, title) }
  puts items.empty? ? "  (nothing in intake)" : "\n#{items.length} untriaged. Promote one by its number."
  0
end

# --- promoting an intake item into the register ------------------------

# **Opening an entry is four decisions and two files**, and
# `docs/ISSUES.md`'s "The rule" is the order they are made in: drive it,
# then its kind, then its release, then whether a user meets it.
#
# What this does *not* decide is any of them. Every one is a required
# option, because a default here is an assertion about the product made
# by a script -- and `024.130` is what a published assertion nobody drove
# costs. The one thing it takes off a person is the mechanics: allocating
# a number never used before, writing the legend's shape, taking the item
# out of intake, and re-running the three guards.
VISIBILITY = %w[yes no].freeze

def promote(position, opts)
  kind = opts[:kind] or
    raise RefusedWrite, "--kind is required: #{DeferredFindings::KNOWN_KINDS.join(', ')}"
  unless DeferredFindings::KNOWN_KINDS.include?(kind)
    raise RefusedWrite, "--kind #{kind.inspect} is not one of #{DeferredFindings::KNOWN_KINDS.join(', ')}"
  end

  target = opts[:target] or
    raise RefusedWrite, "--target is required: the release its fix is routed to, or `unscheduled`"
  area = opts[:area] or raise RefusedWrite, "--area is required: where to go and look, each path backticked"
  direction = opts[:direction] or raise RefusedWrite, "--direction is required: what the fix would be"
  visible = visibility_for(kind, opts)

  index = Integer(position, exception: false)
  raise RefusedWrite, "the position is a number; `ruby scripts/issues.rb intake` lists them" if index.nil?

  issues_path = File.join(ROOT, ISSUES_DOC)
  item = intake_items(File.readlines(issues_path, encoding: "UTF-8"))[index - 1] if index.positive?
  raise RefusedWrite, "intake has no item #{index}. `ruby scripts/issues.rb intake` lists what there is" if item.nil?

  _, title, detail = item
  number = next_number
  entry = entry_lines(number, title, kind, target, area, direction, visible, opts[:note], detail)

  # The register first. If the second write refuses, the entry exists and
  # the item is still in intake -- visible, and repairable by deleting one
  # of the two. The other order loses the intake text, which nothing else
  # holds.
  rewrite(live_path, expect_delta: entry.length, expect_entries: 1, why: "promote #{number}") do |lines|
    lines + entry
  end

  rewrite(issues_path, expect_delta: -(1 + detail.length), why: "promote #{number}") do |lines|
    at, _, again = intake_items(lines)[index - 1]
    raise RefusedWrite, "intake item #{index} moved while it was being promoted" unless again == detail

    lines.slice!(at, 1 + detail.length)
    lines
  end

  puts "issues: #{number} #{title}"
  puts "  #{kind}, target #{target}#{visible ? ", user-visible: #{visible}" : ''}"
  puts "  taken out of intake; #{ISSUES_DOC} no longer lists it."
  puts "Publish its user-visible half in both KNOWN_LIMITATIONS before committing." if visible == "yes"
  reindex_and_check
end

# `roadmap` is a plan and carries no user-visible half -- the legend says
# so, and `DeferredFindings.undocumented` excludes it for that reason.
# Every other kind declares one, and a `no` says why: an entry declaring
# `no` with no reason is what `deferred_findings_spec`'s "gives a reason
# with every `user-visible: no`" refuses, and writing one here would put
# the refusal a full suite run away from the command that caused it.
def visibility_for(kind, opts)
  return nil if kind == "roadmap"

  value = opts[:user_visible] or
    raise RefusedWrite, "--user-visible yes|no is required on a #{kind}: say whether a user meets it"
  raise RefusedWrite, "--user-visible is yes or no, not #{value.inspect}" unless VISIBILITY.include?(value)

  if value == "no" && opts[:note].to_s.strip.empty?
    raise RefusedWrite, "--note is required with --user-visible no: say why a user does not meet it"
  end

  value
end

# One entry, as lines, in the shape the register's legend states: the
# heading, the fenced block directly under it, the Area, the intake's own
# words, and the direction.
def entry_lines(number, title, kind, target, area, direction, visible, note, detail)
  meta = ["status: open\n", "kind: #{kind}\n"]
  meta << "user-visible: #{visible}\n" if visible
  meta.concat(folded("user-visible-note", note)) if visible == "no"
  meta << "target: #{target}\n"

  ["## #{number} #{title}\n", "\n", "```yaml\n", *meta, "```\n", "\n",
   "**Area:** #{area}\n", "\n", *body_lines(detail),
   "**Direction:** #{direction}\n", "\n", "---\n", "\n", "\n"]
end

# The intake item's own words, dedented into the entry. The line saying
# it has not been driven goes: promoting it is the claim that it has.
def body_lines(detail)
  kept = detail.map { |line| line.sub(/\A[ \t]+/) { "" } }.reject { |line| line.include?(INTAKE_UNVERIFIED) }
  kept.empty? ? [] : kept + ["\n"]
end

# A yaml folded scalar, which is how every note in the register is
# written and what `YAML.safe_load` reads back as one line.
def folded(key, text)
  ["#{key}: >-\n", *wrap(text.to_s.strip, 66).map { |line| "  #{line}\n" }]
end

def wrap(text, width)
  text.split(/\s+/).reject(&:empty?).each_with_object([]) do |word, lines|
    if lines.empty? || lines.last.length + 1 + word.length > width
      lines << word
    else
      lines[-1] = "#{lines.last} #{word}"
    end
  end
end

# --- closing an entry ---------------------------------------------------

# **Closing one is the operation this repository has the worst record
# with.** It sets two fields, moves the entry between two files, and
# leaves a paragraph in each language claiming a limitation the product
# no longer has -- which is `024.130` exactly: a limitation was published
# that the product did not have, in both languages, and nothing could see
# it because the guard matches the marker and the marker was still there.
#
# So the default is to refuse and print where the paragraphs are.
# `--drop-paragraphs` is the maintainer saying the sections may go.
def close(number, opts)
  released = opts[:released_in] or
    raise RefusedWrite, "--released-in is required: name the version that carries the fix, or `#{DeferredFindings::REVERTED}`"
  entry = find(number) or raise RefusedWrite, "no entry #{number}. `ruby scripts/issues.rb list` shows what there is"
  raise RefusedWrite, "#{number} is #{entry.status}, not open" unless entry.open?

  sections = limitation_sections(number)
  unless sections.empty? || opts[:drop_paragraphs]
    raise RefusedWrite, "#{number} is still published as a limitation:\n" +
                        sections.map { |s| "  #{s[:document]}:#{s[:first] + 1}  #{s[:heading]}" }.join("\n") +
                        "\nRewrite those sections by hand, or pass --drop-paragraphs to remove them."
  end

  sections.each { |section| drop_section(number, section) }

  path = entry.archived ? archive_path : live_path
  rewrite(path, expect_delta: 1, why: "close #{number}") do |lines|
    at = lines.index { |l| l.start_with?("## #{number} ") } or
      raise RefusedWrite, "cannot find #{number}'s heading"
    stop = ((at + 1)...lines.length).find { |i| lines[i].start_with?("## 024.") } || lines.length
    status = (at...stop).find { |i| lines[i].start_with?("status: ") } or
      raise RefusedWrite, "#{number} has no status: line of its own"

    lines[status] = "status: fixed\n"
    lines.insert(status + 1, "released-in: #{released}\n")
  end

  puts "issues: #{number} is fixed, released in #{released}."
  sections.each { |s| puts "  removed #{s[:document]}'s section #{s[:heading].inspect}" }
  system("ruby", "scripts/archive_resolved_findings.rb", chdir: ROOT, out: File::NULL)
  reindex_and_check
end

# The `##` section a finding's marker sits in, per language.
#
# **The section, not the paragraph.** A marker sits at the end of the
# sentence that documents the finding, and the heading above it makes the
# same claim with nothing else needed -- three times a body was removed
# and the heading left standing, which is what `check_bodyless_headings.rb`
# exists for. Removing the marker alone is worse than either: the
# limitation stays published and the guard that would report it goes
# quiet, which is this repository's commonest failure shape.
#
# A section that also publishes another finding is refused rather than
# removed. Two claims share it, and only one of them is being closed.
def limitation_sections(number)
  LIMITATION_DOCS.each_value.filter_map do |document|
    lines = File.readlines(File.join(ROOT, document), encoding: "UTF-8")
    at = lines.index { |line| DeferredFindings.anchors(line, number).any? } or next

    first = (0..at).reverse_each.find { |i| lines[i].start_with?("## ") }
    raise RefusedWrite, "#{document}:#{at + 1} documents #{number} under no heading" if first.nil?

    last = ((at + 1)...lines.length).find { |i| lines[i].start_with?("## ") } || lines.length
    others = DeferredFindings.anchored_numbers(lines[first...last].join) - [number]
    unless others.empty?
      raise RefusedWrite, "#{document}:#{first + 1} also publishes #{others.uniq.join(', ')}. " \
                          "Split the section by hand; removing it would unpublish those too."
    end

    { document: document, first: first, last: last, heading: lines[first].strip }
  end
end

def drop_section(number, section)
  rewrite(File.join(ROOT, section[:document]),
          expect_delta: -(section[:last] - section[:first]), why: "close #{number}") do |lines|
    lines.slice!(section[:first], section[:last] - section[:first])
    lines
  end
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
