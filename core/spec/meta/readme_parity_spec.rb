# frozen_string_literal: true

# `024.25`. The two parity specs deleted in 0.2.0 parsed Markdown prose
# with regexes, and every review round found another input shape they
# mishandled. The entry names the direction that was taken instead --
# *give the data a schema instead of parsing prose* -- and one thing left
# unguarded for the same reason it deleted the old specs: the EN/JA
# README divergence found in its round 2.
#
# This is that guard, in the shape `scripts/check_site_links.rb` already
# uses for the site's Japanese pages. It does **not** compare prose: the
# two READMEs were written independently and say the same things
# differently, and demanding identical wording would buy a stricter check
# by making the prose worse.
#
# What both copies really share is the *shape* of their tables -- how
# many rows, and which verdict marks each row carries, in order. That is
# the half a translation cannot legitimately change, and it is exactly
# what went wrong: a row saying ✅ in one language and ⚠️ in the other is
# a promise made in one language and withheld in the other.
RSpec.describe "the two READMEs" do
  MARK = /\A(✅|⚠️|❌|\d+\.\d+(\.\d+)?)\z/

  def shape_of(content)
    content.split("\n").filter_map do |line|
      next unless line.start_with?("| ")

      marks = line.delete_prefix("|").split("|").map(&:strip).grep(MARK)
      marks.empty? ? nil : marks
    end
  end

  def read(name) = File.read(File.expand_path("../../../#{name}", __dir__), encoding: "UTF-8")

  def table_shape(name) = shape_of(read(name))

  # **The example that shows this one can fail.** Reading a guard cannot
  # tell whether it would notice; the only way to know is to break the
  # thing it guards. Done in memory rather than on disk, because a spec
  # that edits the repository is a spec that can leave it edited.
  it "notices a promise made in one language and withheld in the other" do
    english = read("README.md")
    japanese = read("README.ja.md").sub("| ✅ |", "| ⚠️ |")

    expect(shape_of(japanese)).not_to eq(shape_of(english))
  end

  it "make the same promises, row for row" do
    english = table_shape("README.md")
    japanese = table_shape("README.ja.md")

    expect(japanese.length).to eq(english.length),
                              "README.md has #{english.length} rows carrying a verdict and " \
                              "README.ja.md has #{japanese.length}. A row present in one language " \
                              "and not the other is a capability documented for half the users."
    english.each_with_index do |marks, i|
      expect(japanese[i]).to eq(marks),
                             "row #{i + 1} of the matrix says #{marks.join(" ")} in README.md and " \
                             "#{japanese[i].join(" ")} in README.ja.md. The prose may differ; the " \
                             "promise may not."
    end
  end
end
