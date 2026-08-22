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

  # *The regex this used to grep with, the scrubbing helper it needed,
  # and the two comments explaining both were deleted in 0.2.14. They had
  # been dead since the switch to a Prism visitor: nothing referenced
  # them, and one of them documented a regex-backtracking hazard as if it
  # governed the live check, which reads the AST. `024.126`'s note that a
  # revert leaves prose behind, arriving from a rewrite instead.*

  # **Parsed, not grepped, and this file is no longer exempt.** It used to
  # scan lines and skip `spec_helper.rb` *and itself*, because its own
  # example description and failure message spell the call it hunts -- so
  # a real violation added to this file would have been invisible.
  #
  # Reading the AST removes the reason for the exemption: a call inside a
  # string or a comment is not a call. That is the durable form, and
  # `046` records the class -- a text scanner matches its own prose,
  # exempts itself, and stops checking a file that can hold the real
  # thing.
  class BlocklessMktmpdir < Prism::Visitor
    attr_reader :hits

    def initialize(path)
      @path = path
      @hits = []
      super()
    end

    def visit_call_node(node)
      if node.name == :mktmpdir && node.receiver.is_a?(Prism::ConstantReadNode) &&
         node.receiver.name == :Dir && node.block.nil?
        @hits << "#{@path}:#{node.location.start_line}"
      end
      super
    end
  end

  it "never calls Dir.mktmpdir without a block (spec_helper's example_tmpdir instead)" do
    # `spec_helper.rb` defines the replacement, so it is the one file that
    # legitimately makes the call.
    exempt = [File.join(spec_root, "spec_helper.rb")]

    offenders = Dir.glob(File.join(spec_root, "**", "*.rb")).sort.flat_map do |path|
      next [] if exempt.include?(path)

      visitor = BlocklessMktmpdir.new(path.delete_prefix("#{spec_root}/"))
      Prism.parse(File.read(path, encoding: "UTF-8")).value.accept(visitor)
      visitor.hits
    end

    # The check that the change above did not simply stop looking: this
    # file spells `Dir.mktmpdir` twice in prose, and a *real* one added
    # here must still be caught.
    planted = Prism.parse("Dir.mktmpdir\n").value
    planted_visitor = BlocklessMktmpdir.new("planted")
    planted.accept(planted_visitor)
    expect(planted_visitor.hits).not_to be_empty

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
