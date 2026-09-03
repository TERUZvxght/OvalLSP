# frozen_string_literal: true

require_relative "../../../scripts/measure_arity_recall"
require "tmpdir"

# `024.40` asked for the `argument-count` check to be measured on real
# code. The measurement it wanted -- precision -- has nothing to measure:
# the check produces zero reports on 2,095 files of stdlib and gems and
# on 90 files of `core/lib`, because committed Ruby that runs does not
# call its own methods with the wrong number of arguments. So the tool
# measures recall instead, by writing calls that are definitely wrong.
#
# What is pinned here is the part of that tool a wrong answer would hide
# in. A generator that emits the probe one line off its recorded line
# reports every probe as missed, and a recall of 0 reads exactly like a
# check that is switched off -- which is the shape `docs/MEASURING.md` warns
# about under "a checker that cannot see the thing it checks". The
# line-number round trip is the assertion.
RSpec.describe ArityRecall do
  def candidates_for(source)
    Dir.mktmpdir("arity-recall-spec-") do |dir|
      File.write(File.join(dir, "subject.rb"), source)
      described_class.candidates([dir])
    end
  end

  describe ".candidates" do
    it "records the container a singleton method was written in" do
      found = candidates_for(<<~RUBY)
        class Klass
          def self.two(a, b); end
        end
        module Mod
          def self.one(a); end
        end
      RUBY

      expect(found.map { |c| [c.owner, c.name, c.required, c.container] })
        .to contain_exactly(["Klass", :two, 2, :class], ["Mod", :one, 1, :module])
    end

    # Every one of these makes a wrong argument count arguable rather than
    # certain, so a probe built from one would measure the check's
    # judgement instead of its recall.
    it "skips a parameter list that is not entirely required positionals" do
      found = candidates_for(<<~RUBY)
        class Klass
          def self.optional(a, b = 1); end
          def self.splat(*a); end
          def self.keyword(a, k: 1); end
          def self.kwsplat(a, **k); end
          def self.blocky(a, &b); end
          def self.post(*a, b); end
        end
      RUBY

      expect(found).to be_empty
    end

    it "does not take an instance method, whose receiver would have to be typed first" do
      expect(candidates_for("class Klass\n  def instance_one(a); end\nend\n")).to be_empty
    end

    it "does not take a bare top-level singleton method, which has no owner to call through" do
      expect(candidates_for("def self.loose(a); end\n")).to be_empty
    end
  end

  describe ".probe" do
    let(:found) do
      candidates_for("class Klass\n  def self.two(a, b); end\n  def self.none; end\nend\n")
    end

    it "puts each generated call on the line it records for it" do
      source, expected = described_class.probe(found)
      lines = source.lines

      aggregate_failures do
        expected.each do |probe|
          expect(lines[probe[:line] - 1]).to include("#{probe[:owner]}.#{probe[:name]}")
        end
      end
    end

    it "writes one too-many call and one too-few call where there is a required parameter" do
      _, expected = described_class.probe(found)

      expect(expected.map { |p| [p[:name], p[:kind]] })
        .to eq([[:two, "too_many"], [:two, "too_few"], [:none, "too_many"]])
    end

    # The distinguishing values: two required means three arguments and
    # one argument, and zero required means one argument and no too-few
    # call at all -- there is no such thing as fewer than none.
    it "gets the argument counts wrong in the direction it says it does" do
      source, expected = described_class.probe(found)
      lines = source.lines

      calls = expected.map { |p| lines[p[:line] - 1].strip }

      expect(calls).to eq(["::Klass.two(0, 1, 2)", "::Klass.two(0)", "::Klass.none(0)"])
    end

    it "produces a probe Ruby can parse, so a failure to report is the check's" do
      source, = described_class.probe(found)

      expect(Prism.parse(source).success?).to be(true)
    end
  end
end
