# frozen_string_literal: true

# **A test that starts a real process, under mocha's two-second default,
# is a wall-clock bound on an assertion about behaviour.**
#
# `coreProcess.test.ts`'s "establishes the Core session before loading the
# server entrypoint" spawns `ruby`, loads two files and checks that the
# session id equals the pid. It has nothing to say about speed. It went
# red on a loaded CI runner during a pull request whose whole diff was
# documentation and one Ruby comment, and it blocked the merge.
#
# Sweeping for the shape rather than fixing the instance found **three**
# examples in that file spawning a real process with no timeout of their
# own; the one that failed was simply the one that lost the race. The
# same file already sets `this.timeout(30000)` on four other examples,
# with a reason at each, so the practice existed and these three were
# outside it.
#
# This is the `no_wall_clock_thresholds_spec.rb` argument arriving from
# the other side. That file forbids *asserting* that something is fast,
# because such an assertion measures the machine. A default timeout is
# the same measurement without anybody choosing it, which is worse: no
# one wrote the number down, so no one can weigh it.
#
# What is checked is only that a number was chosen. Its size is a
# judgement, and 30 s is what the neighbouring examples use.
RSpec.describe "a TypeScript test that starts a real process" do
  # Methods, not constants: a constant written inside a `describe` is
  # defined on Object, and `spec_constants_spec.rb` caught this file
  # colliding on `root` with two others the moment it was written.
  def root = File.expand_path("../../..", __dir__)

  # `spawn`, `execFile` and the sync pair. Not `fork`: nothing here uses
  # it, and a needle nothing matches is one nobody notices going stale.
  def starts_a_process = /\b(?:spawn|spawnSync|execFile|execFileSync|execSync)\s*\(/

  # An `it(...)` and the body up to the line that closes it at the
  # describe's indentation. Deliberately textual: the alternative is
  # parsing TypeScript from Ruby, and what this needs to know is which
  # lines sit between two markers.
  def examples(source)
    found = []
    title = nil
    body = +""
    line_number = 0
    source.each_line.with_index(1) do |line, i|
      if (m = line.match(/^\s*it\(\s*['"](.+?)['"]/))
        found << [title, line_number, body] if title
        title = m[1]
        line_number = i
        body = +""
      elsif title && line.match?(/^ {2}\}\);\s*$/)
        found << [title, line_number, body]
        title = nil
        body = +""
      elsif title
        body << line
      end
    end
    found << [title, line_number, body] if title
    found
  end

  def unbounded(source)
    examples(source).select { |_title, _line, body| body.match?(starts_a_process) && !body.include?("this.timeout(") }
  end

  def test_files
    Dir.glob(File.join(root, "vscode", "src", "test", "**", "*.ts")).sort
  end

  it "chooses its own timeout rather than inheriting the default" do
    offenders = test_files.flat_map do |path|
      unbounded(File.read(path, encoding: "UTF-8")).map do |title, line, _body|
        "#{path.sub("#{root}/", '')}:#{line} — #{title}"
      end
    end

    expect(offenders).to be_empty,
                         "these start a real process under mocha's 2s default:\n  #{offenders.join("\n  ")}\n" \
                         "Add `this.timeout(...)` with a line saying why, as the four examples around them do."
  end

  # The control. Without it this file passes just as well if the scanner
  # matches nothing at all -- which is the state `check_pinned_mutations`
  # reported on its first run, indistinguishable from a clean tree.
  it "is looking at real examples, and at ones that do start a process" do
    sources = test_files.map { |p| File.read(p, encoding: "UTF-8") }

    expect(test_files.length).to be >= 3
    expect(sources.sum { |s| examples(s).length }).to be >= 50
    expect(sources.count { |s| s.match?(starts_a_process) }).to be >= 1
  end

  # And the other control: the check must be able to say yes. A scanner
  # that cannot report an offender would pass on a tree full of them.
  it "would report an example that starts a process with no timeout" do
    planted = <<~TS
      describe('planted', () => {
        it('starts something and bounds nothing', async function () {
          const child = spawn('ruby', ['-e', 'exit 0']);
          await once(child, 'close');
        });
      });
    TS

    expect(unbounded(planted).map(&:first)).to eq(["starts something and bounds nothing"])
  end

  # And must not report one that does, or the fix would be to delete the
  # example rather than to bound it.
  it "says nothing about the same example once it chooses a bound" do
    planted = <<~TS
      describe('planted', () => {
        it('starts something and bounds it', async function () {
          this.timeout(30000);
          const child = spawn('ruby', ['-e', 'exit 0']);
          await once(child, 'close');
        });
      });
    TS

    expect(unbounded(planted)).to be_empty
  end
end
