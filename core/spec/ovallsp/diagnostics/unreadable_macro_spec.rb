# frozen_string_literal: true

# `024.110`. An unrecognised class-body macro correctly opens the owner's
# surface, so nothing it *might* define is reported. The call that opened
# it was reported anyway — the engine saying "I cannot enumerate this
# class's members because something unreadable ran here" and then
# asserting that the unreadable thing does not exist.
#
# One fact, two contradictory answers. A false report on ordinary code
# whenever a macro comes from a gem, a `Concern`, or an `extend` this
# parser cannot follow.
RSpec.describe "Ovallsp::Diagnostics::Engine and a macro it cannot read" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  # One stack, assembled where the server assembles its own (042's D8).
  let(:stack) { build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry, signatures: signatures) }
  let(:hierarchy_index) { stack.hierarchy_index }
  let(:method_resolver) { stack.method_resolver }
  let(:local_inferencer) { stack.local_inferencer }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: nil) } }

  def index(text, uri: "file:///a.rb")
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
    document
  end

  def unknown_methods(document)
    context = Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: method_resolver,
      local_inferencer: local_inferencer, model_registry: model_registry,
      route_registry: Ovallsp::Routes::RouteRegistry.new, signatures: signatures, generation: 1
    )
    Ovallsp::Diagnostics::Engine.new.analyze(document: document, semantic_context: context, mode: :standard)
                                .select { |f| f.code == "unknown-method" }
                                .map { |f| f.message[/named `(.+)`/, 1] }
  end

  # `024.116`. `declares_method_missing?` asked the index for
  # `kind: :instance_method` only, so a class answering class-level calls
  # through `def self.method_missing` was judged closed and every call it
  # handles was reported. Ruby:
  #
  #   $ ruby -e '
  #   class CWithMM
  #     def self.method_missing(n, *a) = :mm
  #     def self.respond_to_missing?(n, p = false) = true
  #   end
  #   p CWithMM.anything
  #   class CDynamic
  #     %w[dyn_a dyn_b].each { |n| define_singleton_method(n) { n } }
  #   end
  #   p CDynamic.dyn_a
  #   '
  #   # => :mm  and  "dyn_a"
  #   # ruby 3.4.10
  describe "a class that answers class-level calls it does not declare" do
    it "says nothing when the class defines def self.method_missing" do
      index("class CWithMM\n  def self.method_missing(name, *args); end\nend\n", uri: "file:///mm.rb")
      document = index("CWithMM.anything\n", uri: "file:///use_mm.rb")

      expect(unknown_methods(document)).to be_empty
    end

    it "says nothing when its class methods are made by define_singleton_method" do
      index("class CDynamic\n  %w[dyn_a dyn_b].each { |n| define_singleton_method(n) { n } }\nend\n",
            uri: "file:///dyn.rb")
      document = index("CDynamic.dyn_a\n", uri: "file:///use_dyn.rb")

      expect(unknown_methods(document)).to be_empty
    end

    # The control: a class doing neither still answers. Without this,
    # "stop reporting class-level calls" would pass both examples above.
    it "still reports a class-level typo on a class that does neither" do
      index("class COrdinary\n  def self.known; end\nend\n", uri: "file:///ord.rb")
      document = index("COrdinary.nope_x\n", uri: "file:///use_ord.rb")

      expect(unknown_methods(document)).to eq(["nope_x"])
    end
  end

  # **`024.110`, and 0.2.12 is the release that could finally hold it.**
  # The engine used to give two answers about one fact: it declined to
  # report anything an unreadable macro *might* define, and reported the
  # macro itself. 0.2.11 fixed that and rolled the fix back the same
  # release, because the reader then took `Module`'s open surface as
  # evidence about every class that inherits from it -- constant-receiver
  # findings 117 -> 0 over 16 gems, with a real latent `NoMethodError`
  # among the losses.
  #
  # `#open_surface?` ignores a synthesised link now, so the claim is
  # per-owner: *this* class's body was unreadable, and nobody else's.
  it "says nothing about the macro it could not read" do
    document = index("class HostC\n  attr_atomic :thing\nend\n")

    expect(unknown_methods(document)).to be_empty
  end

  # **A link's side, asked of the link rather than recomputed.** `extend M`
  # and the `Class`/`Module`/`Object`/`Kernel`/`BasicObject` tail both put
  # *instance* methods on a class-level chain, and both readers of that
  # rule had it written out by hand -- three review rounds in a row found
  # one of them wrong. Ruby:
  #
  #   $ ruby -e '
  #   class Object; def method_missing(n, *a) = :mm; end
  #   class Widget; end
  #   p Widget.nope
  #   '
  #   # => :mm
  #   # ruby 3.4.10
  it "says nothing about a class-level call when a workspace Object declares method_missing" do
    index("class Object\n  def method_missing(name, *args); end\nend\n", uri: "file:///oe.rb")
    index("class Widget\nend\n", uri: "file:///widget.rb")
    document = index("Widget.nope\n", uri: "file:///caller.rb")

    expect(unknown_methods(document)).to be_empty
  end

  it "still reports a class-level typo on a class whose body it could read" do
    index("class Plain\n  def self.known; end\nend\n", uri: "file:///plain.rb")
    document = index("Plain.known\nPlain.nope_x\n", uri: "file:///use.rb")

    expect(unknown_methods(document)).to eq(["nope_x"])
  end

  # **This example could not distinguish anything until 0.2.11's third
  # round.** Its fixture had no typo in it and `known` was declared, so
  # `be_empty` held under every candidate behaviour, while its own
  # comment claimed it would fail if the owner were silenced entirely.
  # Verified mechanically by the round: re-applying the change and
  # running the file failed the two examples above and passed this one.
  # `024.109`'s category, in the spec written to close `024.110`.
  # **The other half of the same reproduction**, and what `042`'s D2 is
  # for. `HostC`'s own body ran a macro this parser cannot read, so
  # nothing it might define is asserted about. `Widget`'s body is
  # readable, and the only unreadable thing in its *chain* is a reopened
  # `Module` -- a link the workspace did not write, and one every class
  # in every workspace has.
  it "declines about the owner whose own body was unreadable, and only that owner" do
    index("class Module\n  def blank_slate?; false; end\n  alias_method :blank?, :blank_slate?\nend\n",
          uri: "file:///core_ext.rb")
    index("class HostC\n  attr_atomic :thing\nend\n", uri: "file:///host.rb")
    index("class Widget\n  def go; 1; end\nend\n", uri: "file:///widget.rb")
    document = index("HostC.whatever\nWidget.tpyo_class\n", uri: "file:///caller.rb")

    expect(unknown_methods(document)).to eq(["tpyo_class"])
  end

  # **The distinguishing pair.** One class ran a macro this parser cannot
  # read; the other did not. An implementation that declined about the
  # workspace rather than about the owner would silence both, and one
  # that declined about neither would report both.
  it "declines about the class that ran the macro and not about its neighbour" do
    index("class Mixed\n  attr_atomic :thing\n  def self.known; end\nend\n", uri: "file:///mixed.rb")
    index("class Plain\n  def self.known; end\nend\n", uri: "file:///plain.rb")
    document = index("Mixed.tpyo_one\nPlain.tpyo_two\n", uri: "file:///ok.rb")

    expect(unknown_methods(document)).to eq(["tpyo_two"])
  end
end
