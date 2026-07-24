# frozen_string_literal: true

require "benchmark"

RSpec.describe Rslsp::Semantic::HierarchyIndex do
  let(:workspace_index) { Rslsp::WorkspaceIndex.new }
  subject(:index) { described_class.new(workspace_index: workspace_index) }

  def index_source(text, uri: "file:///a.rb", version: 1)
    document = Rslsp::TextDocument.new(uri: uri, text: text, version: version, language_id: "ruby")
    summary = Rslsp::ParserService.new.summarize(document)
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
    expect(names(index.ancestors("Widget", singleton: true))).to eq(%w[::Widget ::Helpers])
  end

  it "carries a singleton chain through the superclass' own singleton class" do
    index_source("class Base\n  extend Helpers\nend\n\nclass Sub < Base\nend\n\nmodule Helpers\nend\n")

    expect(names(index.ancestors("Sub", singleton: true))).to eq(%w[::Sub ::Base ::Helpers])
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
      expect(elapsed).to be < 1.0
    end
  end
end
