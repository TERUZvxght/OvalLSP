# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# **String containment is not containment.**
#
# `Store.inside?` compared `File.expand_path(path)` against the root, and
# `expand_path` resolves `..` and `~` and nothing else -- a symlink in the
# middle of the path is left exactly as written. The sweep on the other
# side *enumerates through* such a link, because `Dir.children` reads what
# the link points at. So a link inside the cache produces removal targets
# that are inside it by string and outside it by filesystem, and
# `#remove_within` -- the one place this class deletes, written so that
# containment is a property of removal rather than of each caller's
# arithmetic -- passed them.
#
# `024.51`'s incident is the reason that one place exists, and this is the
# same class of defect one layer down: the guard was in the right place
# and asking a question that does not mean what it says. Found by the
# 2026-09-05 critical review, R01.
#
# **The final component is deliberately not resolved.** A symlink written
# *directly* in the cache is an ordinary cache entry: `remove_entry`
# unlinks the link and never touches what it points at, so refusing it
# would leave undeletable rubbish in the cache forever. Resolving the
# parent and keeping the basename is exactly that distinction.
#
# Every example is inside `Dir.mktmpdir`, and each asserts a file that
# must survive as well as one that must go -- a guard that refused
# everything would pass the removals and fail the survivals.
RSpec.describe Ovallsp::Cache::Store, "containment of what it deletes" do
  around do |example|
    Dir.mktmpdir("ovallsp-containment-") do |tmp|
      @tmp = File.realpath(tmp)
      @root = File.join(@tmp, "cache")
      @outside = File.join(@tmp, "outside")
      FileUtils.mkdir_p([@root, @outside])
      example.run
    end
  end

  def write(path, body = "x")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  it "removes an ordinary directory inside the cache" do
    victim = write(File.join(@root, "scope", "gen1", "a.cache"))

    described_class.remove_within(@root, File.join(@root, "scope", "gen1"))

    expect(File.exist?(victim)).to be(false)
  end

  it "refuses a path that leaves the cache through an intermediate symlink" do
    valuable = write(File.join(@outside, "victim", "valuable.txt"))
    File.symlink(@outside, File.join(@root, "scope"))

    described_class.remove_within(@root, File.join(@root, "scope", "victim"))

    expect(File.exist?(valuable)).to be(true)
  end

  it "still removes a symlink written directly in the cache, and not its target" do
    target = write(File.join(@outside, "kept.txt"))
    link = File.join(@root, "link")
    File.symlink(target, link)

    described_class.remove_within(@root, link)

    expect(File.symlink?(link)).to be(false)
    expect(File.exist?(target)).to be(true)
  end

  it "refuses the root itself and a sibling whose name starts with it" do
    sibling = write("#{@root}-other/a.txt")

    described_class.remove_within(@root, @root)
    described_class.remove_within(@root, "#{@root}-other")

    expect(Dir.exist?(@root)).to be(true)
    expect(File.exist?(sibling)).to be(true)
  end

  it "does not raise on a path that is already gone" do
    expect { described_class.remove_within(@root, File.join(@root, "never-existed")) }.not_to raise_error
  end

  # A cache root reached through a link of its own is ordinary -- macOS
  # puts `/tmp` behind one. Both sides are resolved, so this is inside.
  it "removes normally when the cache root is itself behind a symlink" do
    linked_root = File.join(@tmp, "linked-cache")
    File.symlink(@root, linked_root)
    victim = write(File.join(@root, "scope", "a.cache"))

    described_class.remove_within(linked_root, File.join(linked_root, "scope"))

    expect(File.exist?(victim)).to be(false)
  end

  # The sweep that produces those paths, driven through its own public
  # API at the default keep count rather than through the guard directly.
  it "prunes generations without following a link out of the cache" do
    valuable = write(File.join(@outside, "valuable.txt"))
    scope = File.join(@root, "scope")
    File.symlink(@outside, scope)
    (1..12).each { |n| write(File.join(@outside, "gen#{n}", "a.cache")) }

    described_class.prune_generations(cache_root: @root, current: File.join(scope, "gen12"))

    expect(File.exist?(valuable)).to be(true)
    expect(Dir.exist?(File.join(@outside, "gen1"))).to be(true)
  end

  # Its control: the same sweep over a real directory still prunes, so the
  # example above is the link being refused and not the sweep being dead.
  it "still prunes generations in an ordinary cache directory" do
    scope = File.join(@root, "scope")
    (1..12).each { |n| write(File.join(scope, "gen#{n}", "a.cache")) }

    described_class.prune_generations(cache_root: @root, current: File.join(scope, "gen12"))

    expect(Dir.children(scope).length).to be < 12
    expect(Dir.exist?(File.join(scope, "gen12"))).to be(true)
  end

  # `#tighten` chmods whatever it is handed, and a chmod through a symlink
  # changes the *target's* mode. The tree walk is bounded by the cache, so
  # a link inside it was a way to reach a file outside it -- the same
  # escape as the removal, in the operation beside it.
  it "does not change the mode of a file outside the cache through a link" do
    target = write(File.join(@outside, "theirs.txt"))
    File.chmod(0o644, target)
    File.symlink(target, File.join(@root, "scope-link"))

    described_class.tighten_tree(@root)

    expect(format("%o", File.stat(target).mode & 0o777)).to eq("644")
  end

  it "still tightens an ordinary file inside the cache" do
    ours = write(File.join(@root, "scope", "a.cache"))
    File.chmod(0o644, ours)

    described_class.tighten_tree(@root)

    expect(format("%o", File.stat(ours).mode & 0o777)).to eq("600")
  end
end
