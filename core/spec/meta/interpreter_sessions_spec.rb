# frozen_string_literal: true

require "open3"

# `024.220`. `CLAUDE.md` requires a claim about Ruby's semantics to be taken
# from Ruby, run, and pasted "so the next reader can see what the expectation
# rests on rather than trusting that somebody checked". The rule works. What it
# produced was 72 sessions of inert text: a mis-transcribed result, a session
# edited out of agreement with the code beside it, and a session that stops
# being true on a later Ruby all read exactly like a correct one.
#
# `scripts/check_interpreter_sessions.rb` re-runs each of them.
#
# **It fails on a session it cannot parse rather than skipping it.** A checker
# that passes over what it does not understand reports exactly what a working
# checker reports when everything is fine, which this register records happening
# twice already.
RSpec.describe "interpreter sessions" do
  # Namespaced: a constant written inside `RSpec.describe` lands on Object, and
  # the file that loads last silently gives its value to the other one.
  SESSIONS_ROOT = File.expand_path("../../..", __dir__)

  # Every fixture below is a *deliberately wrong* session, and this file is
  # tracked content, so spelling one the way a real one is spelled makes it a
  # finding about the spec that tests the finder. It did, on the first run.
  # `024.126` is the entry; `spec/support/unspellable.rb` is the helper for
  # paths and register numbers, and it joins with a separator, so an opener is
  # assembled here instead. Nothing contiguous survives in the source.
  #
  # `body` is the program, `answer` the lines recorded beside it.
  def session_fixture(body, answer)
    opener = ["$", "ruby", "-e", "'"].join(" ")
    lines = ["#   #{opener}"]
    body.each { |l| lines << "#   #{l}" }
    lines << "#   '"
    answer.each { |l| lines << "#   # =#{'>'} #{l}" }
    "#{lines.join("\n")}\n"
  end

  it "every session pasted into tracked content still produces what is written beside it" do
    output, status = Open3.capture2e(
      RbConfig.ruby, File.join(SESSIONS_ROOT, "scripts", "check_interpreter_sessions.rb"), chdir: SESSIONS_ROOT
    )
    expect(status).to be_success, output
  end

  # The count is the assertion that this ran over the tree rather than over an
  # empty list. A checker that finds nothing to check passes, and so does one
  # whose glob broke -- the same shape as a green suite that did not run.
  it "found the sessions rather than an empty list" do
    output, status = Open3.capture2e(
      RbConfig.ruby, File.join(SESSIONS_ROOT, "scripts", "check_interpreter_sessions.rb"), "--count", chdir: SESSIONS_ROOT
    )
    expect(status).to be_success, output
    expect(output[/\bsessions=(\d+)/, 1].to_i).to be >= 60
  end

  # And that a wrong expectation is actually caught, which nothing above shows:
  # both examples pass whether the comparison is real or a stub that always
  # agrees. This drives the checker at a file whose recorded answer is false.
  it "fails on a session whose recorded output is wrong" do
    Dir.mktmpdir("session-check-") do |dir|
      File.write(File.join(dir, "wrong.rb"), session_fixture(["p [1, 2].sum"], ["7"]))
      output, status = Open3.capture2e(
        RbConfig.ruby, File.join(SESSIONS_ROOT, "scripts", "check_interpreter_sessions.rb"),
        "--file", File.join(dir, "wrong.rb"), chdir: SESSIONS_ROOT
      )
      expect(status).not_to be_success, output
      expect(output).to include("3").and include("7")
    end
  end

  # The other half of "cannot fail": a session it cannot parse must fail rather
  # than be skipped. Written as a session whose quote never closes.
  it "fails on a session it cannot parse rather than passing over it" do
    Dir.mktmpdir("session-check-") do |dir|
      opener = ["$", "ruby", "-e", "'"].join(" ")
      File.write(File.join(dir, "unparseable.rb"), "#   #{opener}\n#   p 1\n# then prose, and no closing quote\n")
      output, status = Open3.capture2e(
        RbConfig.ruby, File.join(SESSIONS_ROOT, "scripts", "check_interpreter_sessions.rb"),
        "--file", File.join(dir, "unparseable.rb"), chdir: SESSIONS_ROOT
      )
      expect(status).not_to be_success, output
      expect(output).to match(/could not|unparseable|never closes/i)
    end
  end

  # Sessions are executed, so the checker is code that runs text out of the
  # repository. It refuses rather than runs anything that writes, deletes,
  # spawns or opens a socket -- the `/Applications` incident is what a
  # destructive line in a plausible-looking fixture costs.
  it "refuses a session that would touch the machine rather than running it" do
    Dir.mktmpdir("session-check-") do |dir|
      # Assembled too, so the hazard name is not a literal here either. The
      # path is inside this example's own tmpdir rather than fabricated: the
      # fixture is never run -- the point is that it is refused -- but a
      # destructive line pointed at a made-up absolute path is exactly what
      # emptied the maintainer's `/Applications`, and "it never runs" is the
      # reasoning that incident disproved.
      removal = ["File", "Utils"].join + ".rm_rf(#{File.join(dir, "not-created").dump})"
      File.write(File.join(dir, "hazard.rb"), session_fixture([%(require "fileutils"), removal, "p :done"], [":done"]))
      output, status = Open3.capture2e(
        RbConfig.ruby, File.join(SESSIONS_ROOT, "scripts", "check_interpreter_sessions.rb"),
        "--file", File.join(dir, "hazard.rb"), chdir: SESSIONS_ROOT
      )
      expect(status).not_to be_success, output
      expect(output).to match(/refus/i)
    end
  end
end
