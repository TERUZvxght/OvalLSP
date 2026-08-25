#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "utf8"
require_relative "repo_files"
require "open3"
require "tmpdir"
require "timeout"
require "rbconfig"
require "ripper"

# Re-runs every interpreter session pasted into tracked content and compares
# what Ruby says now against what is written beside it (`024.220`).
#
#   ruby scripts/check_interpreter_sessions.rb            # the whole tree
#   ruby scripts/check_interpreter_sessions.rb --count    # just the totals
#   ruby scripts/check_interpreter_sessions.rb --file P   # one file
#
# `CLAUDE.md` requires a claim about Ruby's semantics to be taken from Ruby,
# run, and pasted "so the next reader can see what the expectation rests on
# rather than trusting that somebody checked". The rule works -- several defects
# were found by obeying it, and one, `0.2.8`'s `class << self` spec, was found
# only because somebody asked the interpreter instead of believing the spec.
#
# Every one of those sessions was inert text until this existed. A
# mis-transcribed result, a session edited out of agreement with the code beside
# it, and a session that stops being true on a later Ruby all read exactly like
# a correct one -- and being believed is the whole point of pasting them.
#
# **What the first run found is worth recording, because it is not what the
# entry expected.** Of 72 sessions, 50 carry a recorded answer and every one of
# them reproduces. Not one was a false claim. So this does not close a defect;
# it stops one arriving, and it makes the session the *cheap* way to state a
# behavioural claim, because prose stating the same thing is checked by nobody.
# Two rounds of review inside 0.2.16 each found a false claim about a macro's
# behaviour written as prose in the same bullet list, which is the same-place
# rule's trigger and is why this was built now rather than later.
#
# ## Running text out of the repository
#
# This executes code it reads from tracked files, which is the shape of the
# incident that deleted the maintainer's installed applications: every call site
# was individually plausible and containment was an emergent property of all of
# them being right at once. So containment is here, at the one place that runs:
#
# - each session runs with a fresh `Dir.mktmpdir` as its working directory, so
#   a relative path it writes cannot land in the repository;
# - each is bounded by a timeout;
# - a session whose text contains a spelling that writes, deletes, spawns a
#   process or opens a socket is **refused, and refusing fails the run**. It is
#   not skipped -- a checker that passes over what it will not handle reports
#   exactly what a working checker reports when everything is fine.
module InterpreterSessions
  RUBY = RbConfig.ruby
  TIMEOUT_SECONDS = 25

  # Spellings that reach outside the session. A match refuses rather than
  # skips: the point is that a person decides, not that the session is assumed
  # harmless.
  HAZARDS = /
    \bFileUtils\b | \bFile\.(?:delete|unlink|write|rename|open)\b | \bDir\.(?:delete|rmdir|mkdir)\b |
    \bIO\.(?:write|popen|binwrite)\b | \bsystem\b | \bexec\b | \bspawn\b |
    \bProcess\.(?:kill|spawn|exec)\b | \bNet:: | \bSocket\b | \bTCPSocket\b
  /x

  # Command execution is decided by Ripper rather than by a pattern, because
  # the pattern was wrong the first time it ran and wrong in the expensive
  # direction: it refused the one session in this tree that is *about*
  # backticks -- `024.225`, whose subject is a backslash-backtick inside a
  # replacement string. A backtick in a string is text; a backtick that opens a
  # command is a different token, and Ruby already tells them apart.
  #
  #   $ ruby -rripper -e '
  #   p Ripper.lex(%q{p "x \\` y"}).map { |t| t[1] }.include?(:on_backtick)
  #   p Ripper.lex(%q{`echo hi`}).map { |t| t[1] }.include?(:on_backtick)
  #   '
  #   # => false
  #   # => true
  #   # ruby 3.4.10
  COMMAND_TOKENS = %i[on_backtick].freeze

  # Lexing also removes the other half of the same mistake: a hazard *named*
  # inside a string or a comment is not a hazard, and this checker's own
  # sessions talk about these names.
  NON_CODE_TOKENS = %i[on_tstring_content on_comment on_embdoc on_embdoc_beg on_embdoc_end].freeze

  # A warning is the interpreter commenting on the code, not the session's
  # answer, and one session deliberately redefines `method_missing` to
  # demonstrate a parse question. Dropped from the comparison rather than
  # pasted into a doc comment.
  WARNING_LINE = /\A-e:\d+: warning:/

  Session = Struct.new(:file, :line, :flags, :code, :expected, :closed, keyword_init: true)

  module_function

  # `RepoFiles.list` rather than `git ls-files`, which cannot see a file until
  # it is committed -- so a session pasted into a new file would go unchecked
  # exactly while it is being written, which is when it is most likely wrong.
  # `untracked_visibility_spec.rb` caught this script doing it the old way.
  def tracked_files
    RepoFiles.list(File.expand_path("..", __dir__)).select { |f| f.end_with?(".rb", ".md") }
  end

  # A session opens at `$ ruby [flags] -e '`, continues over lines carrying the
  # same comment prefix as the opener, and closes on the first of those whose
  # text ends the literal. What follows, while the prefix holds, is the
  # recorded answer: `# => value` lines, and a `# ruby X.Y.Z` line which is a
  # note about which interpreter answered rather than part of the answer.
  def extract(path)
    lines = File.readlines(path, encoding: "UTF-8")
    found = []
    i = 0
    while i < lines.length
      match = lines[i].match(/\A(?<prefix>.*?)\$ ruby (?<flags>(?:--[\w-]+ )*)-e '/)
      unless match
        i += 1
        next
      end
      session, i = read_one(lines, i, match)
      found << session
    end
    found
  end

  def read_one(lines, start, match)
    prefix = match[:prefix]
    body = []
    first = lines[start][match.end(0)..].to_s.rstrip
    closed = false
    if first.end_with?("'")
      body << first.sub(/'\z/, "")
      closed = true
    elsif !first.empty?
      body << first
    end

    cursor = start + 1
    while !closed && cursor < lines.length
      text = strip_prefix(lines[cursor], prefix)
      break if text.nil?

      if text.rstrip == "'"
        closed = true
      elsif text.rstrip.end_with?("'")
        body << text.rstrip.sub(/'\z/, "")
        closed = true
      else
        body << text
      end
      cursor += 1
    end

    expected = []
    while closed && cursor < lines.length
      text = strip_prefix(lines[cursor], prefix)
      break if text.nil?

      stripped = text.rstrip
      break if stripped.strip.empty?
      break unless stripped.start_with?("#")
      # The version note says which interpreter answered; it is not output.
      if stripped =~ /\A#\s*ruby\s+[\d.]/
        cursor += 1
        next
      end

      expected << stripped.sub(/\A#\s*(?:=>)?\s?/, "")
      cursor += 1
    end

    [Session.new(file: nil, line: start + 1, flags: match[:flags].to_s.split,
                 code: body.join("\n"), expected: expected, closed: closed),
     cursor]
  end

  def strip_prefix(raw, prefix)
    return nil unless raw.start_with?(prefix)

    raw[prefix.length..]
  end

  # Whitespace-collapsed, because a recorded answer is wrapped to fit the
  # comment it lives in and the wrap is formatting rather than output. Seven of
  # the tree's sessions are wrapped that way; comparing line by line would have
  # reported all seven and taught the next reader to disbelieve this check.
  def normalise(lines)
    lines.reject { |l| l =~ WARNING_LINE }.join(" ").gsub(/\s+/, " ").strip
  end

  # The environment a session must NOT inherit.
  #
  # Found by the spec that drives this script, and it is the third instance of
  # one lesson in one session: **confirm you invoked the implementation you
  # think you did.** Run from a shell, every session reproduced. Run from
  # inside `rspec`, two failed -- both `gem "activesupport"`, which resolves
  # against the system gems outside a bundle and raises "not part of the
  # bundle" inside one, because bundler's own variables reach the child. A
  # checker whose answer depends on who invoked it is not a checker.
  #
  # `RUBYLIB` and `RUBYOPT` carry bundler's `-rbundler/setup`; the `BUNDLE_`
  # and `BUNDLER_` families carry the gemfile and the paths. Cleared by name
  # rather than by prefix scan for `RUBYOPT`/`RUBYLIB`, and by prefix for the
  # rest, because bundler adds keys across versions.
  def clean_env
    env = { "RUBYOPT" => nil, "RUBYLIB" => nil }
    ENV.each_key { |k| env[k] = nil if k.start_with?("BUNDLE_", "BUNDLER_") }
    env
  end

  def run(session)
    Dir.mktmpdir("interpreter-session-") do |dir|
      Timeout.timeout(TIMEOUT_SECONDS) do
        out, err, = Open3.capture3(clean_env, RUBY, *session.flags, "-e", session.code, chdir: dir)
        return (out + err).lines.map(&:chomp).reject { |l| l.strip.empty? }
      end
    end
  rescue Timeout::Error
    ["<timed out after #{TIMEOUT_SECONDS}s>"]
  end

  # The hazard, or nil. Asked of the code with strings and comments removed,
  # so a name written inside a literal is text rather than a call.
  #
  # A session Ripper cannot lex is its own answer: it is refused, because a
  # checker that cannot see what it is checking reports exactly what a working
  # one reports when nothing is wrong.
  def reaches_outside(code)
    tokens = Ripper.lex(code)
    return "unlexable (Ripper returned nothing)" if tokens.nil? || tokens.empty?

    command = tokens.find { |(_, type, _, _)| COMMAND_TOKENS.include?(type) }
    return "a shell command (#{command[2]})" if command

    executable = tokens
                 .reject { |(_, type, _, _)| NON_CODE_TOKENS.include?(type) }
                 .map { |(_, _, value, _)| value }.join(" ")
    executable[HAZARDS]
  end

  def check(files)
    problems = []
    total = 0
    compared = 0

    files.each do |path|
      extract(path).each do |session|
        total += 1
        where = "#{path}:#{session.line}"

        unless session.closed
          problems << "#{where}\n    could not parse: the `-e` literal never closes."
          next
        end
        if (hazard = reaches_outside(session.code))
          problems << "#{where}\n    refused: the session reaches outside itself (#{hazard.inspect}). " \
                      "A person decides whether to run this, not this script."
          next
        end
        # A session with no recorded answer states nothing a reader could rely
        # on, so there is nothing to re-run. Counted, not failed: several
        # demonstrate a *shape* of code that the prose around them describes.
        next if session.expected.empty?

        compared += 1
        want = normalise(session.expected)
        got = normalise(run(session))
        next if want == got

        problems << "#{where}\n    written: #{want}\n    ruby now says: #{got}"
      end
    end

    [total, compared, problems]
  end
end

if $PROGRAM_NAME == __FILE__
  count_only = ARGV.delete("--count")
  file_index = ARGV.index("--file")
  files = if file_index
            [ARGV[file_index + 1]]
          else
            InterpreterSessions.tracked_files
          end

  total, compared, problems = InterpreterSessions.check(files)

  if count_only
    puts "check-interpreter-sessions: sessions=#{total} compared=#{compared}"
    exit(problems.empty? ? 0 : 1)
  end

  if problems.empty?
    puts "check-interpreter-sessions: #{total} session(s), #{compared} with a recorded answer, all reproduce."
    exit 0
  end

  puts "check-interpreter-sessions: #{problems.length} problem(s) in #{total} session(s):"
  problems.each { |p| puts "  - #{p}" }
  puts
  puts "A session is evidence only while it reproduces. Re-run it and paste what Ruby says now,"
  puts "or fix the code the session was pasted to justify."
  exit 1
end
