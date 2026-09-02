# frozen_string_literal: true

# 0.3.0 gave each local-variable occurrence a `write` flag, read by inlay
# hints (which label assignments) and by documentHighlight (which reports
# `Read`/`Write`). Only four of Prism's write-producing visitors set it.
#
# **Predicted blind.** A subagent given the release's feature list and no
# code guessed that "pattern-match and multiple-assignment bindings
# aren't marked `write`, because only the plain assignment producer sets
# the new flag" — and that the hash-shorthand producer, which reaches
# `record_reference` directly, would leave it `nil`. Both reproduced.
#
# What it costs: `a, b = 1, 2` highlights as a *read* of `a`, and gets no
# inlay hint, in a shape as common as plain assignment.
RSpec.describe "the write flag on a local-variable occurrence" do
  def occurrences(source)
    document = Ovallsp::TextDocument.new(uri: "file:///w.rb", text: source, version: 1, language_id: "ruby")
    Ovallsp::ParserService.new.summarize(document).reference_candidates
                          .select { |c| c.kind == :local_variable }
                          .group_by { |c| c.name.to_s }
  end

  # The control: the shape that already worked, so a change that broke
  # everything would not read as a fix.
  it "marks a plain assignment and its operator form" do
    by_name = occurrences("def go\n  n = 1\n  n += 2\n  n\nend\n")

    expect(by_name["n"].map(&:write)).to eq([true, true, false])
  end

  it "marks a multiple assignment" do
    by_name = occurrences("def go\n  a, b = 1, 2\n  [a, b]\nend\n")

    expect(by_name["a"].first.write).to be(true), "`a, b = 1, 2` records `a` as a read"
    expect(by_name["b"].first.write).to be(true)
  end

  it "marks a `for` loop's variable" do
    by_name = occurrences("def go\n  for idx in 1..3\n    idx\n  end\nend\n")

    expect(by_name["idx"].first.write).to be(true)
  end

  it "marks a pattern binding" do
    by_name = occurrences("def go(input)\n  case input\n  in [pat]\n    pat\n  end\nend\n")

    expect(by_name["pat"].first.write).to be(true)
  end

  it "marks a rightward assignment" do
    by_name = occurrences("def go(input)\n  input => bound\n  bound\nend\n")

    expect(by_name["bound"].first.write).to be(true)
  end

  it "marks a `rescue => e` binding" do
    by_name = occurrences("def go\n  begin\n    nil\n  rescue => err\n    err\n  end\nend\n")

    expect(by_name["err"].first.write).to be(true)
  end

  # **A block parameter's declaration is a write.** This example said
  # the opposite -- that the declaration was not recorded at all --
  # and it was true when it was written and measured. `024.273` named
  # recording the parameter's own range as the direction, and 0.3.0
  # took it, so the binding site is now an occurrence like any other
  # and the value arriving there makes it a write.
  it "marks a block parameter's declaration, and its use as a read" do
    by_name = occurrences("def go\n  [1].each { |item| item }\nend\n")

    expect(by_name["item"].map(&:write)).to eq([true, false])
  end

  # **`nil`, not `false`.** The hash-shorthand producer reaches
  # `record_reference` directly rather than through
  # `#record_local_variable`, so it took the keyword's `nil` default --
  # and `nil` means "not a local" to the reader, so the same local read
  # as `Text` here and `Read` one line up.
  it "records a hash shorthand as a read rather than as no answer" do
    by_name = occurrences("def go\n  name = 1\n  { name: }\nend\n")

    expect(by_name["name"].map(&:write)).to eq([true, false])
  end

  # **Instance variables too**, and this was predicted blind: "cursor
  # on `@foo` -- expect silent empty results on the one symbol kind
  # users most expect to work". They are recorded, so highlighting is
  # not empty; what was missing is the flag, so an assignment and a
  # read both answered `Text` where a local answers `Write`/`Read`.
  it "marks an instance variable's assignment, and its read as a read" do
    document = Ovallsp::TextDocument.new(uri: "file:///i.rb", version: 1, language_id: "ruby",
                                         text: "class C\n  def a\n    @x = 1\n  end\n" \
                                               "  def b\n    @x\n  end\nend\n")
    ivars = Ovallsp::ParserService.new.summarize(document).reference_candidates
                                 .select { |c| c.kind == :ivar }

    expect(ivars.map(&:write)).to eq([true, false])
  end

  # A regexp named capture binds a local, and 0.3.0 records its binding
  # site (`024.280`) -- but through the one call that forgot the flag,
  # so the binding read back as a `Read`. Worse, `Rename::Planner`'s new
  # "is the binding site known" guard asks exactly this question, so a
  # rename from a use was refused rather than performed.
  #
  # CONTROL: the plain local in the same fixture, whose binding must
  # still be a write and whose use must still be a read -- an example
  # that marked everything `true` fails on it.
  it "marks a regexp named capture's binding site as a write" do
    by_name = occurrences("def go(line)\n  plain = 1\n  /(?<caught>\\d+)/ =~ line\n  [plain, caught]\nend\n")

    expect(by_name["caught"].map(&:write)).to eq([true, false])
    expect(by_name["plain"].map(&:write)).to eq([true, false])
  end

  # An ivar's *operator* assignments were not recorded at all -- not as
  # a read, not as a write, simply absent -- because only the plain read
  # and write nodes had visitors. documentHighlight showed two of four
  # occurrences and rename rewrote two of four, leaving a file that
  # still parses and memoises into an ivar nothing reads.
  #
  # CONTROL: the plain write and the plain read in the same method, which
  # already worked and must keep their flags.
  def ivar_occurrences(source)
    document = Ovallsp::TextDocument.new(uri: "file:///i.rb", text: source, version: 1, language_id: "ruby")
    Ovallsp::ParserService.new.summarize(document).reference_candidates
                          .select { |c| c.kind == :ivar }
  end

  it "records an ivar's operator, or- and and-writes, and its multiple-assignment target" do
    ivars = ivar_occurrences(
      "class C\n  def go\n    @count = 0\n    @count ||= 1\n    @count &&= 2\n" \
      "    @count += 1\n    @count, @other = 3, 4\n    @count\n  end\nend\n"
    )

    by_name = ivars.group_by { |c| c.name.to_s }
    expect(by_name["@count"].map { |c| [c.location[:start][:line], c.write] })
      .to eq([[2, true], [3, true], [4, true], [5, true], [6, true], [7, false]])
    expect(by_name["@other"].map(&:write)).to eq([true])
  end

  # A class variable took `#record_reference`'s `nil` default, so
  # `@@x = 1` answered `Text` where `@x = 1` answers `Write`.
  it "marks a class variable's assignment and read the way an ivar's are" do
    cvars = Ovallsp::ParserService.new
                                  .summarize(Ovallsp::TextDocument.new(
                                               uri: "file:///c.rb", version: 1, language_id: "ruby",
                                               text: "class C\n  @@n = 1\n  def go\n    @@n\n  end\nend\n"
                                             ))
                                  .reference_candidates.select { |c| c.kind == :cvar }

    expect(cvars.map(&:write)).to eq([true, false])
  end
end
