# frozen_string_literal: true

# Found by an independent review (round 19) of Task 022.2, while checking
# the whole change set for resource-lifecycle gaps of the shape rounds
# 9-18 kept finding in lib/. This one was in spec/ and had never been
# looked at: `Dir.mktmpdir` removes the directory it creates only when it
# is given a block. Four call sites needed the path to outlive an
# expression rather than a block and so used the blockless form, which
# removes nothing, ever -- leaking one directory per example, on every
# developer's and CI machine, for the life of the machine. Measured on
# this project's own machine before the fix: 301 stale `ovallsp-*`
# directories in TMPDIR, growing by roughly five per full suite run.
#
# `ExampleTmpdir#example_tmpdir` (spec/spec_helper.rb) is the fix -- the
# block form's guarantee, restored without the block, with RSpec's own
# `after` hook as the `ensure`. This example is what stops it decaying
# back: a blockless `Dir.mktmpdir` leaves no failing test behind, only a
# slowly filling temp directory nobody looks at, so nothing else in this
# suite would ever notice it being reintroduced -- the same
# "the fix shipped, its own regression test didn't guard it" shape rounds
# 12, 14 and 18 were each re-opened for.
RSpec.describe "spec suite tmpdir hygiene" do
  let(:spec_root) { File.expand_path("..", __dir__) }

  # `Dir.mktmpdir` immediately followed by a `do` or `{` block (allowing
  # for an argument list in between) is the self-cleaning form and is
  # always fine. Anything else returns a path nothing will ever remove.
  #
  # The argument list is matched *possessively* (`?+`) on purpose: an
  # ordinary `?` lets the engine give the parentheses back and then
  # satisfy the negative lookahead against the `(` it just released, so
  # `Dir.mktmpdir("x") do |d|` -- the correct form -- would be reported
  # as an offender.
  let(:blockless_mktmpdir) { /Dir\.mktmpdir(?:\([^)]*\))?+(?!\s*(?:do\b|\{))/ }

  # Scrubbed rather than read as text: spec/fixtures/ holds deliberately
  # malformed sources, so a byte sequence that isn't valid in the default
  # external encoding must not be the thing that decides whether this
  # rule runs.
  def source_lines(path)
    File.binread(path).force_encoding(Encoding::UTF_8).scrub.lines
  end

  it "never calls Dir.mktmpdir without a block (spec_helper's example_tmpdir instead)" do
    exempt = [File.join(spec_root, "spec_helper.rb"), __FILE__] # define/describe the helper itself

    offenders = Dir.glob(File.join(spec_root, "**", "*.rb")).sort.flat_map do |path|
      next [] if exempt.include?(path)

      source_lines(path).filter_map.with_index(1) do |line, number|
        next if line.lstrip.start_with?("#")

        "#{path.delete_prefix("#{spec_root}/")}:#{number}: #{line.strip}" if line.match?(blockless_mktmpdir)
      end
    end

    expect(offenders).to be_empty, lambda {
      "Dir.mktmpdir without a block never removes the directory it creates. Use " \
        "`example_tmpdir(\"prefix\")` (spec/spec_helper.rb), which is removed after the example.\n" +
        offenders.join("\n")
    }
  end

  it "removes a directory example_tmpdir handed out, once the example that asked for it has finished" do
    # Self-check on the helper the rule above points everyone at: proving
    # the rule has somewhere correct to send them is part of the rule.
    dir = example_tmpdir("ovallsp-tmpdir-hygiene")
    expect(Dir.exist?(dir)).to be(true)

    remove_example_tmpdirs # what RSpec's own `after` hook calls

    expect(Dir.exist?(dir)).to be(false)
  end
end
