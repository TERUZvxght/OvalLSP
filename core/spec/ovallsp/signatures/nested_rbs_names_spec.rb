# frozen_string_literal: true

require "tmpdir"

# RBS type names arrive fully qualified (`::File::Stat`) and were reduced
# to their last component, so every nested core type answered under a
# bare name. Where a workspace defines a class of that name, the
# workspace one shadowed the core type: `File.stat(path)` answered as the
# workspace's `Stat`, offering its methods and denying the real ones.
#
# Measured before changing it: 240 of 334 types in the loaded RBS
# environment are nested, and 27 of their 238 distinct basenames are also
# defined as classes in the installed gem corpus -- `Error`, `Node`,
# `Generator`, `Buffer`, `Location`. Ordinary names in ordinary code.
RSpec.describe "Ovallsp::Signatures::TypeConverter keeps a nested type's namespace" do
  def converted(rbs_source_type)
    Ovallsp::Signatures::TypeConverter.convert(rbs_source_type)
  end

  def parse_type(text)
    RBS::Parser.parse_type(text)
  end

  it "keeps the path of a nested type rather than its last segment" do
    expect(converted(parse_type("::File::Stat")).to_s).to eq("File::Stat")
  end

  # The distinguishing pair. Under the old behaviour both answered
  # "Stat", so a fixture using only one of them could not tell the two
  # behaviours apart -- and a workspace `Stat` then captured the core
  # type's identity entirely.
  it "tells a nested core type apart from a workspace class of the same basename" do
    core = converted(parse_type("::File::Stat")).to_s
    workspace_shaped = converted(parse_type("::Stat")).to_s

    expect(core).not_to eq(workspace_shaped)
  end

  it "leaves a top-level type alone, prefix and all" do
    expect(converted(parse_type("::Array")).to_s).to start_with("Array")
    expect(converted(parse_type("::Array")).to_s).not_to start_with("::")
  end

  it "keeps the namespace inside a generic's element type" do
    expect(converted(parse_type("::Array[::Encoding::Converter]")).to_s).to include("Encoding::Converter")
  end
end
