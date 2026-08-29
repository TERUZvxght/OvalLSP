# frozen_string_literal: true

# Enumerated with `RepoFiles`, not `git ls-files` — `024.147`. A file you
# have just written is untracked until `git add`, and `preflight` runs
# before the commit, so a check that lists only tracked files is blind to
# exactly the file being worked on.
require_relative "../../../scripts/repo_files"

require "tmpdir"

# Ruby hands back a String in `Encoding.default_external`, which is
# whatever the invoking shell's locale says. Under `LC_ALL=C`, a cron
# job, or a CI step with no locale set, that is **US-ASCII** -- and the
# first `String#[]`, `#scan` or `#include?` against a byte above 127
# raises `invalid byte sequence in US-ASCII`.
#
# This tree is substantially non-ASCII: the Japanese documents, the
# Japanese halves of KNOWN_LIMITATIONS, SUPPORT_MATRIX and CONTRIBUTING,
# and the Japanese failure messages the suite prints. So a script here
# meets it as soon as anyone runs it outside an interactive shell.
#
# **The shape is what makes it worth a check.** The script does not read
# the file wrongly -- it *crashes*, on exactly the input a check exists
# to report. `preflight.rb`'s first version died with this while printing
# a suite failure whose message contained Japanese: the gate built to
# catch a failure, killed by one.
#
# Found four separate times before it was fixed once: `generate_sbom.rb`
# (Task 023.8, running the release gate under a locale-less shell),
# `preflight.rb`, `documented_counts.rb`, and a hand-run probe. Each fix
# was correct, local, and no help at all to the fifth call site.
# `CLAUDE.md`'s rule says the third occurrence buys a countermeasure
# rather than a third fix; this is the fourth.
RSpec.describe "scripts and the invoking shell's locale" do
  SCRIPT_ENCODING_ROOT = File.expand_path("../../..", __dir__)

  # `utf8.rb` is the fix itself, so it does not require itself.
  SCRIPT_ENCODING_EXEMPT = %w[scripts/utf8.rb].freeze

  def self.scripts
    RepoFiles.list(SCRIPT_ENCODING_ROOT, "scripts/*.rb")
             .reject { |rel| SCRIPT_ENCODING_EXEMPT.include?(rel) }
  end

  it "every script sets the encoding before it reads anything" do
    missing = self.class.scripts.reject do |rel|
      File.read(File.join(SCRIPT_ENCODING_ROOT, rel), encoding: "UTF-8").include?('require_relative "utf8"')
    end

    expect(missing).to be_empty,
                       "these do not `require_relative \"utf8\"`: #{missing.join(", ")}. " \
                       "Without it they crash under LC_ALL=C on any non-ASCII byte they read."
  end

  it "requires it before anything else that reads or shells out" do
    late = self.class.scripts.filter_map do |rel|
      lines = File.readlines(File.join(SCRIPT_ENCODING_ROOT, rel), encoding: "UTF-8")
      at = lines.index { |l| l.include?('require_relative "utf8"') }
      next if at.nil?

      before = lines[0...at].join
      rel if before.match?(/File\.read|IO\.popen|Open3\./)
    end

    expect(late).to be_empty, "these read or shell out before requiring utf8: #{late.join(", ")}"
  end

  it "finds scripts to check, so an empty list cannot pass" do
    expect(self.class.scripts.length).to be >= 10
  end

  # The countermeasure has to actually work, not merely be present. This
  # runs a real script file under a bare locale against the most
  # non-ASCII document in the tree, which is what broke every one of the
  # four.
  #
  # A **file**, not `ruby -e`: a `.rb` file's source encoding is UTF-8
  # whatever the locale says, while `-e` source is read in the locale's
  # encoding, so a `-e` probe fails for a reason that has nothing to do
  # with what is being tested. The first version of this example did
  # exactly that.
  it "survives a locale-less shell reading a Japanese document" do
    Dir.mktmpdir do |dir|
      probe = File.join(dir, "probe.rb")
      File.write(probe, <<~RUBY, encoding: "UTF-8")
        # frozen_string_literal: true

        require_relative "#{File.join(SCRIPT_ENCODING_ROOT, "scripts/utf8")}"

        document = "#{File.join(SCRIPT_ENCODING_ROOT, "docs/KNOWN_LIMITATIONS.ja.md")}"
        text = File.read(document)
        piped = IO.popen(["cat", document], &:read)
        needle = [0xE5, 0x88, 0xB6, 0xE9, 0x99, 0x90].pack("C*").force_encoding(Encoding::UTF_8)

        print [text.scan(/^# /).length.positive?, piped.include?(needle),
               text.encoding, piped.encoding].join(",")
      RUBY

      out = IO.popen({ "LC_ALL" => "C", "LANG" => "C" }, ["ruby", probe], err: %i[child out], &:read)

      expect($?).to be_success, out
      expect(out).to eq("true,true,UTF-8,UTF-8")
    end
  end

  # `utf8.rb` sets two things, and until 0.2.16 only the first was pinned:
  # deleting `Encoding.default_external = ...` failed the example above,
  # deleting `Encoding.default_internal = nil` failed nothing. Nothing in
  # this tree sets an internal encoding, so the probe above cannot tell
  # the line's presence from its absence -- `024.208`, an unpinned line
  # that happens to be correct, which this project counts as a defect in
  # its own right.
  #
  # The distinguishing fixture is an inherited `RUBYOPT`, which is how an
  # internal encoding actually arrives: a wrapper script, a CI step or a
  # shell profile exporting `-E`. With an internal encoding in force,
  # `File.read` and `IO.popen` transcode on the way in, and a UTF-8
  # needle no longer compares against what they return. Measured both
  # ways before this example was written: with line 32 the probe prints
  # `true,true,UTF-8,UTF-8`; without it, the same command raises
  # `Encoding::CompatibilityError: incompatible character encodings:
  # EUC-JP and UTF-8` at the `include?`.
  it "survives an inherited internal encoding, not only a bare locale" do
    Dir.mktmpdir do |dir|
      probe = File.join(dir, "internal.rb")
      File.write(probe, <<~RUBY, encoding: "UTF-8")
        # frozen_string_literal: true

        require_relative "#{File.join(SCRIPT_ENCODING_ROOT, "scripts/utf8")}"

        document = "#{File.join(SCRIPT_ENCODING_ROOT, "docs/KNOWN_LIMITATIONS.ja.md")}"
        text = File.read(document)
        piped = IO.popen(["cat", document], &:read)
        needle = [0xE5, 0x88, 0xB6, 0xE9, 0x99, 0x90].pack("C*").force_encoding(Encoding::UTF_8)

        print [text.scan(/^# /).length.positive?, piped.include?(needle),
               text.encoding, piped.encoding].join(",")
      RUBY

      env = { "LC_ALL" => "C", "LANG" => "C", "RUBYOPT" => "-E UTF-8:EUC-JP" }
      out = IO.popen(env, ["ruby", probe], err: %i[child out], &:read)

      expect($?).to be_success, out
      expect(out).to eq("true,true,UTF-8,UTF-8")
    end
  end

  # And it must fail without the fix, or the example above proves only
  # that Ruby works. Same probe, same locale, no `require_relative`.
  it "would fail without it, which is why the require is not decoration" do
    Dir.mktmpdir do |dir|
      probe = File.join(dir, "unprotected.rb")
      File.write(probe, <<~RUBY, encoding: "UTF-8")
        document = "#{File.join(SCRIPT_ENCODING_ROOT, "docs/KNOWN_LIMITATIONS.ja.md")}"
        print IO.popen(["cat", document], &:read).scan(/^# /).length
      RUBY

      out = IO.popen({ "LC_ALL" => "C", "LANG" => "C" }, ["ruby", probe], err: %i[child out], &:read)

      expect($?).not_to be_success, "the unprotected probe survived a bare locale: #{out}"
      expect(out).to include("invalid byte sequence in US-ASCII")
    end
  end
end
