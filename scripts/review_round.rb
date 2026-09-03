#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"
require_relative "repo_files"

require "json"

# Opening and closing a review round, so that the two mechanical halves
# of the cadence stop being things to remember.
#
#   ruby scripts/review_round.rb start attack
#   ruby scripts/review_round.rb status
#   ruby scripts/review_round.rb close
#
# `CLAUDE.md`'s review cadence says a round closes when a reviewer that
# has not seen this change set, **using a method the previous round did
# not use**, reports nothing -- and that **a round reviews a fixed
# thing**, every addition between rounds resetting it. Both are checkable
# and neither was checked: the previous round's method is written in the
# task document where nothing read it, and "the tree did not move" was
# observed by the person who moved it.
#
# **What it can see, stated so nobody reads more into a green `close`.**
# The recorded fingerprint is `git write-tree` -- the *index*. A fix
# committed mid-round moves it, which is the case this exists for and the
# one 0.2.1 produced nine times. An edit left unstaged does not, and that
# is deliberate: the round's own heading is such an edit, and a check
# that refused its own writing would refuse every round. So this reports
# "nothing was committed under it", not "nobody typed".
#
# The state file lives in `core/tmp/`, which `.gitignore` excludes, for
# the same reason the rspec JSON report does: it is a fact about this
# working copy at this moment and belongs in no commit.
module ReviewRound
  # Overridable so the refusals can be pinned against a throwaway
  # repository rather than by damaging this one -- the same shape
  # `check_doc_links.rb` uses, and for the same reason.
  ROOT = ENV.fetch("OVALLSP_REVIEW_ROUND_ROOT", File.expand_path("..", __dir__))

  # The four `CLAUDE.md` defines. Read the change set, run the product
  # and compare answers, take one guarantee and try to break it,
  # re-derive the round's own claims.
  METHODS = %w[diff drive attack reproduce].freeze

  # How a round is written in a task document. The number and the method
  # are what this reads back; the em dash and the backticks are how every
  # round already recorded in `docs/design/tasks/` is spelled.
  HEADING = /^### Round (\d+) — `(\w+)`/

  TABLE = "| # | Finding | Disposition |\n|---|---|---|\n"

  Refused = Class.new(StandardError)

  module_function

  def state_path = File.join(ROOT, "core", "tmp", "review-round.json")

  def state
    return nil unless File.file?(state_path)

    JSON.parse(File.read(state_path, encoding: "UTF-8"))
  end

  # **The task document on the branch you are on**, found by listing the
  # directory rather than by trusting a number written down anywhere --
  # `AGENTS.md` says why, and the pointer it says that about had gone
  # stale three times.
  #
  # `RepoFiles.list` rather than the tracked set: a release's document is
  # often the newest file in the tree and uncommitted when its first
  # round opens (`024.147`).
  def latest_document
    documents = RepoFiles.list(ROOT, "docs/design/tasks/*.md")
    raise Refused, "no task document in docs/design/tasks/ to record a round in" if documents.empty?

    documents.max_by { |path| document_key(path) }
  end

  # `022.2` sorts after `022` and before `023`, which is the order the
  # directory has always been read in.
  def document_key(path)
    File.basename(path)[/\A(\d+)(?:\.(\d+))?/, 0].to_s.split(".").map(&:to_i)
  end

  def rounds_in(document)
    File.read(File.join(ROOT, document), encoding: "UTF-8").scan(HEADING).map { |n, m| [n.to_i, m] }
  end

  def git(*args)
    output = RepoFiles.capture(ROOT, args)
    raise Refused, "git #{args.join(' ')} failed: #{output.strip}" unless $?.success?

    output
  end

  def index_tree = git("write-tree").strip

  def start(method)
    raise Refused, "#{method.inspect} is not a review method: #{METHODS.join(', ')}" unless METHODS.include?(method)

    open = state
    if open
      raise Refused, "round #{open['round']} (`#{open['method']}`) is still open. " \
                     "Close it first: ruby scripts/review_round.rb close"
    end

    document = latest_document
    previous = rounds_in(document).max_by(&:first)
    if previous && previous[1] == method
      raise Refused, "round #{previous[0]} already used `#{method}`. A closing round whose method " \
                     "repeats the previous round's closes nothing -- pick another of #{METHODS.join(', ')}."
    end

    dirty = git("status", "--porcelain")
    unless dirty.strip.empty?
      raise Refused, "the tree is not clean, and a round reviews a fixed thing:\n#{dirty.rstrip}"
    end

    tree = index_tree
    number = (previous ? previous[0] : 0) + 1
    File.write(File.join(ROOT, document), "\n### Round #{number} — `#{method}`\n\n#{TABLE}", mode: "a")
    record(round: number, method: method, document: document, tree: tree)

    puts "review-round: round #{number} is open, method `#{method}`."
    puts "  recorded in #{document}, under a heading and an empty table."
    puts "  the index it reviews is #{tree}."
    puts "  findings go in that table; anything outliving the release goes to the register."
    0
  end

  def record(fields)
    FileUtils.mkdir_p(File.dirname(state_path))
    File.write(state_path, "#{JSON.pretty_generate(fields.transform_keys(&:to_s))}\n")
  end

  def close
    open = state or raise Refused, "no round is open. Start one: ruby scripts/review_round.rb start <method>"

    now = index_tree
    if now != open["tree"]
      warn "review-round: this round read a moving tree and closes nothing."
      warn "  round #{open['round']} (`#{open['method']}`) opened on #{open['tree']}; the index is now #{now}."
      warn "  Start a fresh round on the tree as it stands."
      return 1
    end

    File.unlink(state_path)
    puts "review-round: round #{open['round']} (`#{open['method']}`) is closable -- nothing was " \
         "committed under it."
    puts "  Its findings are in #{open['document']}. If it reported nothing, the loop is closed."
    0
  end

  def status
    open = state
    unless open
      puts "review-round: no round is open."
      return 0
    end

    puts "review-round: round #{open['round']} is open, method `#{open['method']}`, " \
         "recorded in #{open['document']}."
    puts(if index_tree == open["tree"]
           "  the index is where it was when the round opened."
         else
           "  the index has changed since the round opened -- this round closes nothing."
         end)
    0
  end

  USAGE = <<~TEXT
    usage: ruby scripts/review_round.rb <command>

      start <method>   open the next round; method is one of #{METHODS.join(', ')}
      status           which round is open, and whether the index has changed
      close            close it, or refuse because the index moved under it

    A round closes when a reviewer that has not seen this change set, using
    a method the previous round did not use, reports nothing (CLAUDE.md).
  TEXT

  def run(argv)
    case argv.first
    when "start" then argv[1] ? start(argv[1]) : (warn(USAGE) || 2)
    when "close" then close
    when "status" then status
    else
      warn USAGE
      2
    end
  rescue Refused => e
    warn "review-round: refused. #{e.message}"
    2
  end
end

exit ReviewRound.run(ARGV) if $PROGRAM_NAME == __FILE__
