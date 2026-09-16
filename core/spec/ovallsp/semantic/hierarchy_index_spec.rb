# frozen_string_literal: true

require "benchmark"

RSpec.describe Ovallsp::Semantic::HierarchyIndex do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  subject(:index) { described_class.new(workspace_index: workspace_index) }

  def index_source(text, uri: "file:///a.rb", version: 1)
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: version, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    index.replace_file(summary)
    summary
  end

  def names(entries) = entries.map(&:name)

  it "gives a plain class with no explicit superclass the implicit Object/Kernel/BasicObject root" do
    index_source("class Plain\nend\n")

    expect(names(index.ancestors("Plain"))).to eq(%w[::Plain Object Kernel BasicObject])
  end

  it "resolves simple inheritance: Admin < User includes User in Admin's ancestors" do
    index_source("class User\nend\n\nclass Admin < User\nend\n")

    expect(names(index.ancestors("Admin"))).to eq(%w[::Admin ::User Object Kernel BasicObject])
  end

  it "resolves multi-level inheritance" do
    index_source("class A\nend\n\nclass B < A\nend\n\nclass C < B\nend\n")

    expect(names(index.ancestors("C"))).to eq(%w[::C ::B ::A Object Kernel BasicObject])
  end

  it "places an included module right after the class itself" do
    index_source("module Greetable\nend\n\nclass User\n  include Greetable\nend\n")

    expect(names(index.ancestors("User"))).to eq(%w[::User ::Greetable Object Kernel BasicObject])
  end

  it "orders multiple includes with the most recently included module first (matching real Ruby)" do
    index_source(<<~RUBY)
      module M1
      end
      module M2
      end
      class Widget
        include M1
        include M2
      end
    RUBY

    expect(names(index.ancestors("Widget"))).to eq(%w[::Widget ::M2 ::M1 Object Kernel BasicObject])
  end

  it "gives a prepended module precedence over the class itself, most-recently-prepended first" do
    index_source(<<~RUBY)
      module P1
      end
      module P2
      end
      class Widget
        prepend P1
        prepend P2
      end
    RUBY

    expect(names(index.ancestors("Widget"))).to eq(%w[::P2 ::P1 ::Widget Object Kernel BasicObject])
  end

  it "does not descend into class/module reopens as separate entries -- a reopened class is one ancestor entry" do
    index_source(<<~RUBY)
      class Widget
        def a; end
      end

      class Widget
        def b; end
      end
    RUBY

    expect(index.ancestors("Widget").count { |e| e.name == "::Widget" }).to eq(1)
  end

  it "puts an extended module into the singleton ancestor chain, not the instance chain" do
    index_source("module Helpers\nend\n\nclass Widget\n  extend Helpers\nend\n")

    expect(names(index.ancestors("Widget"))).to eq(%w[::Widget Object Kernel BasicObject])
    # The tail after `::Helpers` is Ruby's, in Ruby's order: the
    # singleton classes of `Object` and `BasicObject` -- which is where a
    # workspace `class Object; def self.foo` lives (`024.26`) -- and then
    # what a class object *is*, a Class, which is a Module, where
    # `private`/`attr_reader` are found (`024.23`). `Object` appears
    # twice because those are two different links; the chain tells them
    # apart by which side each contributes, not by name.
    #
    #   $ ruby -e 'class Widget; end
    #              p Widget.singleton_class.ancestors'
    #   # => [#<Class:Widget>, #<Class:Object>, #<Class:BasicObject>,
    #   #     Class, Module, Object, Kernel, BasicObject]
    #   # ruby 3.4.10
    #
    # The extended module still comes first, which is this example's
    # point.
    expect(names(index.ancestors("Widget", singleton: true)))
      .to eq(%w[::Widget ::Helpers Object BasicObject Class Module Object Kernel BasicObject])
  end

  it "carries a singleton chain through the superclass' own singleton class" do
    index_source("class Base\n  extend Helpers\nend\n\nclass Sub < Base\nend\n\nmodule Helpers\nend\n")

    # One tail, at the end of the whole chain -- not one per class in it.
    expect(names(index.ancestors("Sub", singleton: true)))
      .to eq(%w[::Sub ::Base ::Helpers Object BasicObject Class Module Object Kernel BasicObject])
  end

  it "degrades to a partial ancestor chain instead of crashing on an unresolved superclass" do
    index_source("class Sub < TotallyUnknownExternalClass\nend\n")

    expect { index.ancestors("Sub") }.not_to raise_error
    expect(names(index.ancestors("Sub"))).to eq(["::Sub", "TotallyUnknownExternalClass"])
  end

  it "degrades to a partial chain instead of looping forever on a self-referential (cyclic) superclass" do
    # Not valid Ruby, but ParserService's fact extraction doesn't validate
    # semantics -- HierarchyIndex must still terminate.
    index_source("class Cyclic < Cyclic\nend\n")

    expect { index.ancestors("Cyclic") }.not_to raise_error
    expect(names(index.ancestors("Cyclic"))).to eq(["::Cyclic"])
  end

  it "removes a file's ancestor contribution when the file is removed" do
    index_source("class Admin < User\nend\n", uri: "file:///admin.rb")
    index_source("class User\nend\n", uri: "file:///user.rb")
    expect(names(index.ancestors("Admin"))).to include("::User")

    workspace_index.remove_file("file:///user.rb")
    index.remove_file("file:///user.rb")

    expect(names(index.ancestors("Admin"))).not_to include("::User")
  end

  it "bumps generation on every applied replace/remove" do
    expect(index.generation).to eq(0)

    index_source("class A\nend\n")
    expect(index.generation).to eq(1)

    index.remove_file("file:///a.rb")
    expect(index.generation).to eq(2)
  end

  it "reports every alias/alias_method fact declared directly in a type's own body" do
    index_source("class Widget\n  alias short_name name\n  alias_method :sn, :name\nend\n")

    expect(index.aliases("Widget").map(&:new_name)).to contain_exactly("short_name", "sn")
  end

  describe "at scale", :benchmark do
    it "resolves ancestors for any of 1,000 classes in a deep chain well under a second" do
      source = +""
      1000.times { |i| source << "class Gen#{i}#{i.zero? ? '' : " < Gen#{i - 1}"}\nend\n" }
      index_source(source)

      elapsed = Benchmark.realtime { index.ancestors("Gen999") }

      expect(names(index.ancestors("Gen999")).first(3)).to eq(%w[::Gen999 ::Gen998 ::Gen997])
      # perf-guard: a 1000-deep chain must not be walked quadratically
      expect(elapsed).to be < 1.0
    end
  end

  # **A memo that survives a mutation is a wrong answer, not a fast one.**
  # `#ancestors` is memoised for one generation, because `024.45`'s
  # profile puts the chain walk and everything it allocates near the top
  # of an analysis and a file asks about the same few receivers
  # repeatedly. The whole of its correctness is that every mutation --
  # and a gem-index swap, which changes chains without bumping the
  # generation -- clears it.
  describe "the ancestor memo" do
    def summarize(text, uri)
      Ovallsp::ParserService.new.summarize(
        Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
      )
    end

    it "reflects a file's ancestors being replaced" do
      workspace = Ovallsp::WorkspaceIndex.new
      index = described_class.new(workspace_index: workspace)
      %w[a.rb].each do |_|
        summary = summarize("module Mixin\nend\nclass Widget\n  include Mixin\nend\n", "file:///a.rb")
        workspace.replace_file(summary)
        index.replace_file(summary)
      end
      expect(index.ancestors("Widget").map(&:name_or_nil)).to include("::Mixin")

      summary = summarize("module Mixin\nend\nclass Widget\nend\n", "file:///a.rb")
      workspace.replace_file(summary)
      index.replace_file(summary)

      expect(index.ancestors("Widget").map(&:name_or_nil)).not_to include("::Mixin")
    end

    # **The third input, and the one that changes without either index
    # being written to.** `#canonical_name` asks `@signatures.declares?`
    # through `#free_for_a_gem_to_claim?`, and
    # `Signatures::Environment#load` mutates the environment in place --
    # so reloading a workspace's `sig/` changed what a name resolves to
    # while every memoised chain kept the old answer. Found by cold
    # review, which built the disagreement between a memoised index and a
    # fresh one given the same three inputs.
    it "reflects a signature environment that reloaded under it" do
      workspace = Ovallsp::WorkspaceIndex.new
      signatures = instance_double(Ovallsp::Signatures::Environment)
      allow(signatures).to receive(:declares?).and_return(false)
      gems = Ovallsp::Semantic::GemIndex.from_agent(
        { gems: { "ar-1.0.0": { classes: [
          { name: "ActiveRecord::Relation",
            ancestors: %w[ActiveRecord::Relation Object Kernel BasicObject],
            instanceMethods: %w[to_a], singletonMethods: [], definesMethodMissing: false }
        ] } } }
      )
      index = described_class.new(workspace_index: workspace, gem_index: gems, signatures: signatures)
      summary = summarize("class Widget < Relation\nend\n", "file:///a.rb")
      workspace.replace_file(summary)
      index.replace_file(summary)
      before = index.ancestors("Widget").map(&:name_or_nil)
      expect(before).to include("ActiveRecord::Relation")

      # `sig/` now declares a `Relation` of the workspace's own, so the
      # gem may no longer claim the bare name.
      allow(signatures).to receive(:declares?).and_return(true)
      index.signatures_reloaded

      expect(index.ancestors("Widget").map(&:name_or_nil)).not_to include("ActiveRecord::Relation")
    end

    # **The gem index is an input too, and swapping it bumps nothing.**
    # `HierarchyIndex#gem_index=` clears the memo for that reason -- the
    # Runtime Agent installs its index after construction, and a chain
    # computed before that reaches a name the gem index would have
    # answered for. The clear was written with the memo and pinned by
    # nothing: reverting it left every example in this file and in
    # `workspace_index_spec` green, because no spec swapped a gem index
    # after construction. Found by cold review.
    it "reflects a gem index installed after a chain was computed" do
      workspace = Ovallsp::WorkspaceIndex.new
      # A signature environment is required for the gem index to be
      # consulted at all: `#free_for_a_gem_to_claim?` returns false
      # without one, so a fixture that omits it never reaches the input
      # this example is about.
      signatures = instance_double(Ovallsp::Signatures::Environment)
      allow(signatures).to receive(:declares?).and_return(false)
      index = described_class.new(workspace_index: workspace, signatures: signatures)
      summary = summarize("class Widget < Relation\nend\n", "file:///a.rb")
      workspace.replace_file(summary)
      index.replace_file(summary)
      expect(index.ancestors("Widget").map(&:name_or_nil)).to eq(["::Widget", "Relation"])

      index.gem_index = Ovallsp::Semantic::GemIndex.from_agent(
        { gems: { "ar-1.0.0": { classes: [
          { name: "ActiveRecord::Relation",
            ancestors: %w[ActiveRecord::Relation Object Kernel BasicObject],
            instanceMethods: %w[to_a], singletonMethods: [], definesMethodMissing: false }
        ] } } }
      )

      expect(index.ancestors("Widget").map(&:name_or_nil)).to include("ActiveRecord::Relation")
    end

    it "reflects the file being removed entirely" do
      workspace = Ovallsp::WorkspaceIndex.new
      index = described_class.new(workspace_index: workspace)
      summary = summarize("class Base\nend\nclass Widget < Base\nend\n", "file:///a.rb")
      workspace.replace_file(summary)
      index.replace_file(summary)
      expect(index.ancestors("Widget").map(&:name_or_nil)).to include("::Base")

      workspace.remove_file("file:///a.rb")
      index.remove_file("file:///a.rb")

      expect(index.ancestors("Widget").map(&:name_or_nil)).not_to include("::Base")
    end

    # **`024.45`: a body-only edit is the edit, and it paid for the whole
    # memo.** Every keystroke inside a method body re-summarises the file
    # with the same ancestor facts, the same aliases and the same declared
    # types -- every input this file feeds a chain, value-identical,
    # locations included -- and the unconditional clear then rebuilt the
    # same few chains from scratch. When all three are provably equal the
    # replace keeps the memo; the generation still moves, because memo
    # freshness and publish ordering are separate contracts.
    it "keeps a memoised chain across a body-only edit" do
      workspace = Ovallsp::WorkspaceIndex.new
      index = described_class.new(workspace_index: workspace)
      summary = summarize("module Mixin\nend\nclass Widget\n  include Mixin\n  def go\n    1\n  end\nend\n", "file:///a.rb")
      workspace.replace_file(summary)
      index.replace_file(summary)
      expect(index.ancestors("Widget").map(&:name_or_nil)).to include("::Mixin")

      edited = summarize("module Mixin\nend\nclass Widget\n  include Mixin\n  def go\n    2\n  end\nend\n", "file:///a.rb")
      workspace.replace_file(edited)
      expect { index.replace_file(edited) }.to change(index, :generation).by(1)

      expect(workspace).not_to receive(:resolve_type_name)
      expect(index.ancestors("Widget").map(&:name_or_nil)).to include("::Mixin")
    end

    # **Why the retained replace skips the remove-and-re-add instead of
    # replaying it.** Re-adding appends the file's facts at the end of
    # each owner bucket, so a replayed swap moves this file's `include`
    # behind another file's in a class both reopen -- the chain order
    # then changes on a body edit, and a kept memo would disagree with
    # what the index itself computes once anything clears it. Both are
    # asserted: the chain a body edit answers is the chain from before
    # it, and it is still that chain after an unrelated clear forces a
    # fresh compute from the same state.
    it "keeps the chain order stable across a body-only edit of one of two files reopening a class" do
      workspace = Ovallsp::WorkspaceIndex.new
      index = described_class.new(workspace_index: workspace)
      first = summarize("module M1\nend\nclass Widget\n  include M1\n  def a\n    1\n  end\nend\n", "file:///one.rb")
      second = summarize("module M2\nend\nclass Widget\n  include M2\nend\n", "file:///two.rb")
      [first, second].each do |summary|
        workspace.replace_file(summary)
        index.replace_file(summary)
      end
      chain_before = index.ancestors("Widget").map(&:name_or_nil)
      expect(chain_before).to eq(%w[::Widget ::M2 ::M1 Object Kernel BasicObject])

      edited = summarize("module M1\nend\nclass Widget\n  include M1\n  def a\n    2\n  end\nend\n", "file:///one.rb")
      workspace.replace_file(edited)
      index.replace_file(edited)
      expect(index.ancestors("Widget").map(&:name_or_nil)).to eq(chain_before)

      index.signatures_reloaded
      expect(index.ancestors("Widget").map(&:name_or_nil)).to eq(chain_before)
    end

    # **Equal facts are not enough, and this is the example that says
    # why.** A chain's inputs include what the workspace *declares*:
    # `class Widget` gaining a sibling `module Helper` writes no ancestor
    # fact at all, yet it changes what the bare name resolves to and what
    # kind it has. Kept on facts alone, the memo keeps answering that
    # `Helper` is a name nothing declares (065 P4: no retention on
    # `ancestor_facts == old` alone).
    it "reflects a type declared by an edit that changes no ancestor fact" do
      workspace = Ovallsp::WorkspaceIndex.new
      index = described_class.new(workspace_index: workspace)
      summary = summarize("class Widget\nend\n", "file:///a.rb")
      workspace.replace_file(summary)
      index.replace_file(summary)
      expect(index.ancestors("Helper").map(&:name_or_nil)).to eq(["Helper"])

      added = summarize("class Widget\nend\nmodule Helper\nend\n", "file:///a.rb")
      workspace.replace_file(added)
      index.replace_file(added)

      expect(index.ancestors("Helper").map(&:name_or_nil)).to eq(["::Helper"])
    end

    # **An alias is part of the file's contribution too.** The retained
    # replace skips the remove-and-re-add, so it may only be taken when
    # the alias facts also match -- an alias whose own line moved must
    # come back with its new location, exactly as a fresh index would
    # answer it. Compared against one, so the example needs no line
    # numbers of its own (065 P4: no retention on a shape that omits
    # location).
    it "reflects an alias whose line moved under an edit above it" do
      workspace = Ovallsp::WorkspaceIndex.new
      index = described_class.new(workspace_index: workspace)
      summary = summarize("class Widget\n  def a\n  end\n  alias_method :b, :a\nend\n", "file:///a.rb")
      workspace.replace_file(summary)
      index.replace_file(summary)
      index.ancestors("Widget")

      moved = summarize("class Widget\n  def a\n  end\n\n  alias_method :b, :a\nend\n", "file:///a.rb")
      workspace.replace_file(moved)
      index.replace_file(moved)

      fresh_workspace = Ovallsp::WorkspaceIndex.new
      fresh = described_class.new(workspace_index: fresh_workspace)
      fresh_workspace.replace_file(moved)
      fresh.replace_file(moved)
      expect(index.aliases("Widget")).to eq(fresh.aliases("Widget"))
    end

    # The same rule for an ancestor fact's own location: an ambiguous
    # `include` is answered as a nameless entry carrying the fact's range,
    # so the range is part of the returned chain and a moved line is a
    # changed input, not a body edit.
    it "reflects an ambiguous include whose line moved under an edit above it" do
      source = ->(gap) do
        "module A\n  module Helper\n  end\nend\nmodule B\n  module Helper\n  end\nend\n" \
          "class Widget\n#{gap}  include Helper\nend\n"
      end
      workspace = Ovallsp::WorkspaceIndex.new
      index = described_class.new(workspace_index: workspace)
      summary = summarize(source.call(""), "file:///a.rb")
      workspace.replace_file(summary)
      index.replace_file(summary)
      expect(index.ancestors("Widget").reject(&:identified?)).not_to be_empty

      moved = summarize(source.call("\n"), "file:///a.rb")
      workspace.replace_file(moved)
      index.replace_file(moved)

      fresh_workspace = Ovallsp::WorkspaceIndex.new
      fresh = described_class.new(workspace_index: fresh_workspace)
      fresh_workspace.replace_file(moved)
      fresh.replace_file(moved)
      expect(index.ancestors("Widget")).to eq(fresh.ancestors("Widget"))
    end
  end
end
