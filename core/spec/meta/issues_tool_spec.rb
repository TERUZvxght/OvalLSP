# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "../../../scripts/issues"

# `scripts/issues.rb` browses and changes the issue register so that
# neither is hand-editing a 25,000-line document with a strict grammar.
#
# **These examples are about the write primitive, because that is where
# the damage lives.** `024.225` is a scripted edit that pasted the whole
# preceding file in at its anchor -- twice, taking the register from
# 11,555 lines to 25,878 -- and the line count was the only symptom.
# Every mutating subcommand goes through `Issues.rewrite`, which is told
# what the change should cost and refuses one that costs anything else.
#
# The first version of `#verify_shape!` only re-parsed the yaml blocks,
# and an attack walked past it. These four are the ones that now hold,
# and the fifth is the control: without it they would all pass on a
# primitive that simply refused everything.
RSpec.describe "scripts/issues.rb" do
  # `example_tmpdir`, not `Dir.mktmpdir`: the block-less form never
  # removes what it creates, and `tmpdir_hygiene_spec` refuses it.
  let(:root) { example_tmpdir("issues-tool") }
  let(:register) { File.join(root, "docs", "design", "tasks", "024-deferred-review-findings.md") }
  let(:repo) { File.expand_path("../../..", __dir__) }

  before do
    FileUtils.mkdir_p(File.dirname(register))
    FileUtils.cp(File.join(repo, "docs/design/tasks/024-deferred-review-findings.md"), register)
    FileUtils.cp(File.join(repo, "docs/design/tasks/024-deferred-review-findings-resolved.md"),
                 File.join(File.dirname(register), "024-deferred-review-findings-resolved.md"))
    stub_const("Issues::ROOT", root)
  end

  def lines_now = File.readlines(register, encoding: "UTF-8").length

  def attempt(expect_delta:, expect_entries: 0, &block)
    Issues.rewrite(register, expect_delta: expect_delta, why: "spec", expect_entries: expect_entries, &block)
  end

  def first_heading(lines) = lines.index { |l| l.start_with?("## 024.") }

  it "refuses the edit that pasted the file into itself" do
    before = lines_now

    expect { attempt(expect_delta: 2) { |lines| lines + lines } }
      .to raise_error(Issues::RefusedWrite, /changed by #{before}/)
    expect(lines_now).to eq(before)
  end

  it "refuses an unknown key inside a real entry's block, and puts the file back" do
    before = lines_now

    expect do
      attempt(expect_delta: 1) do |lines|
        h = first_heading(lines)
        lines.insert((h...lines.length).find { |i| lines[i].start_with?("status: ") }, "not_a_key: x\n")
      end
    end.to raise_error(Issues::RefusedWrite, /no longer parses/)
    expect(lines_now).to eq(before)
  end

  it "refuses an edit that loses an entry even when the line delta is declared honestly" do
    before = lines_now

    expect do
      attempt(expect_delta: 0) do |lines|
        first = first_heading(lines)
        second = (first + 1...lines.length).find { |i| lines[i].start_with?("## 024.") }
        lines[first...second] = ["\n"] * (second - first)
        lines
      end
    end.to raise_error(Issues::RefusedWrite, /entry count changed by -1/)
    expect(lines_now).to eq(before)
  end

  it "refuses a heading whose metadata no longer follows it" do
    expect do
      attempt(expect_delta: -1) { |lines| lines.delete_at(first_heading(lines)) && lines }
    end.to raise_error(Issues::RefusedWrite)
  end

  # **The control.** A primitive that refused everything would pass all
  # four examples above, so one honest edit has to go through.
  it "allows an edit whose cost is what the caller declared" do
    before = lines_now

    expect(attempt(expect_delta: 1) { |lines| lines + ["\n"] }).to eq(1)
    expect(lines_now).to eq(before + 1)
  end

  describe "browsing" do
    it "reads every entry through the same reader the specs use" do
      numbers = Issues.all.map(&:number)

      expect(numbers).to include("024.243")
      expect(numbers.length).to eq(DeferredFindings.headings(DeferredFindings.register(root)).length)
    end

    it "never hands out a number that is in use or retired" do
      allocated = Issues.next_number
      markdown = DeferredFindings.register(root)

      expect(DeferredFindings.headings(markdown)).not_to include(allocated)
      expect(DeferredFindings.retired_numbers(markdown)).not_to include(allocated)
    end
  end
end
