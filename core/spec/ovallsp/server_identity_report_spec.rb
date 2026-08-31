# frozen_string_literal: true

require_relative "../support/workspace_identity_report"

# 024.275: two examples in `server_workspace_identity_spec.rb` failed in a
# full-suite run and have never failed since -- twelve runs alone, three
# full suites, and a refuted hypothesis. The entry's own instruction is
# the whole of the remaining work: *the next run that reproduces it
# captures the failure message before anything else*, because both runs
# that recorded a message were runs that passed, so the `got` side has
# never been seen.
#
# An instruction addressed to whoever is watching is not a countermeasure.
# This is: the report is built into the assertion, so a failure carries
# the state that tells the hypotheses apart whether or not anybody
# remembered to look.
#
# These examples pin what the report says. Without them the helper could
# quietly stop naming the thing the entry is waiting for, and the next
# reproduction would be as uninformative as the last one.
RSpec.describe WorkspaceIdentityReport do
  around do |example|
    Dir.mktmpdir do |parent|
      @real = File.join(parent, "real")
      @link = File.join(parent, "link")
      FileUtils.mkdir_p(@real)
      File.symlink(@real, @link)
      example.run
    end
  end

  # The two readings the entry says have never been told apart:
  # `File.directory?` answering false for a symlink whose target still
  # exists, and the root simply never being adopted.
  it "says whether each path exists, is a directory, and is a symlink" do
    report = described_class.for(expected: @link, got: @real, paths: { real: @real, link: @link })

    expect(report).to include("exists=true")
    expect(report).to include("directory=true")
    expect(report).to include("symlink=true")
    expect(report).to match(/->\s*#{Regexp.escape(@real)}/)
  end

  # A symlink whose target has gone is the first reading, and it must be
  # visible as such rather than as a bare `false`.
  it "distinguishes a dangling symlink from an absent path" do
    FileUtils.remove_entry(@real)
    report = described_class.for(expected: @link, got: nil, paths: { link: @link })

    expect(report).to include("symlink=true")
    expect(report).to include("exists=false")
    expect(report).to include("dangling")
  end

  # The other reading: the value the assertion actually saw. Both runs
  # that captured a message were runs that passed, which is why this is
  # named explicitly rather than left to RSpec's own diff.
  it "names what was expected and what was got" do
    report = described_class.for(expected: @link, got: @real, paths: {})

    # `.inspect`, not the bare path: it is what tells `nil` from the
    # string "nil" and shows trailing whitespace, and a report that
    # cannot do that is the one this entry has been waiting on.
    expect(report).to include(%(expected=) + @link.inspect)
    expect(report).to include(%(got=) + @real.inspect)
  end

  # The 0.2.18 addition to the entry is a GC example of the same shape,
  # and the load hypothesis is the one both share. A report that cannot
  # say how loaded the machine was cannot test it.
  it "records the load the run was under" do
    expect(described_class.for(expected: "a", got: "b", paths: {})).to match(/load=/)
  end
end
