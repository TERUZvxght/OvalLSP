# frozen_string_literal: true

# Completion offers methods that raise if you pick them. Measured by a
# 0.2.8 review round by asking a *running* application `respond_to?` for
# every label returned: 91 of 816 on a Rails model class, 69 of 121 on a
# class of your own in a plain project, `initialize` among them.
#
# Three separate holes, all in the same rule:
#
# - `024.105` -- a `def` recorded as a singleton method is given
#   `visibility: nil` outright, so `private` inside `class << self` and
#   `private_class_method` have nothing downstream to filter on;
# - `024.108` -- protected methods are offered on an explicit external
#   receiver, though private ones are correctly excluded at the same
#   position;
# - `024.107` -- an alias never appears in completion at all, though
#   hover, definition and the undefined-method check all know it.
#
# The last is the shape `024.100` records: `#resolve` follows an alias and
# `#complete` does not, so one question has two answers depending which
# feature asks. `037`'s C2, step 4.
RSpec.describe "what completion offers, and whether it can be called" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:hierarchy_index) { Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index) }
  let(:resolver) do
    Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index, hierarchy_index: hierarchy_index)
  end

  def index(source)
    document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    hierarchy_index.replace_file(summary)
  end

  def offered(receiver_name, singleton: false)
    resolver.complete(receiver_type: Ovallsp::Types::Nominal.new(name: receiver_name), prefix: "",
                      context: { singleton: singleton, implicit_self: false })
            .map { |result| result[:name] }
  end

  describe "a method made private on the class side" do
    it "is not offered, and `private_class_method` is respected too" do
      index(<<~RUBY_SRC)
        class Gadget
          class << self
            def shown; end
            private
            def hidden; end
          end

          def self.also_hidden; end
          private_class_method :also_hidden
        end
      RUBY_SRC

      expect(offered("Gadget", singleton: true)).to include("shown")
      expect(offered("Gadget", singleton: true)).not_to include("hidden", "also_hidden")
    end

    # The control 0.2.8's round found already working, which is what makes
    # the above a hole rather than "visibility is not modelled": `private`
    # before `def self.x` does *not* apply, matching Ruby.
    it "does not apply a class-body `private` to a `def self.x` after it" do
      index("class Gadget\n  private\n  def self.still_public; end\nend\n")

      expect(offered("Gadget", singleton: true)).to include("still_public")
    end
  end

  describe "a protected method" do
    it "is not offered on an explicit receiver from outside" do
      index("class Prot\n  def open_one; end\n  protected\n  def guarded; end\nend\n")

      expect(offered("Prot")).to include("open_one")
      expect(offered("Prot")).not_to include("guarded")
    end

    # Protected is callable from inside the class, and this is where an
    # over-broad filter would be felt: it is the one visibility that
    # depends on where the call is written rather than only on the
    # declaration.
    it "is offered to an implicit self inside the class" do
      index("class Prot\n  protected\n  def guarded; end\nend\n")

      names = resolver.complete(receiver_type: Ovallsp::Types::Nominal.new(name: "Prot"), prefix: "",
                                context: { implicit_self: true }).map { |r| r[:name] }

      expect(names).to include("guarded")
    end
  end

  describe "an alias" do
    it "is offered, like the method it names" do
      index("class Aliased\n  def original; end\n  alias aka original\n  alias_method :aka2, :original\nend\n")

      expect(offered("Aliased")).to include("original", "aka", "aka2")
    end
  end

  # A method that overrides another showed its signature twice: `#resolve`
  # correctly answers the override *and* the one it overrides -- that
  # ordering is what makes go-to-definition land on the nearest -- and
  # `#signatures_of` turned both into labels. Ruby calls exactly one of
  # them, so the popup was offering a choice that does not exist.
  #
  # Measured by a 0.2.8 review round: `c.area(` returned
  # `["area()", "area()"]`.
  describe "signature help for a method that overrides another" do
    let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
    let(:query_service) do
      inferencer = Ovallsp::LocalInferencer.new(model_registry: model_registry, method_resolver: resolver)
      Ovallsp::Semantic::QueryService.new(local_inferencer: inferencer, method_resolver: resolver,
                                          model_registry: model_registry, workspace_index: workspace_index,
                                          signatures: Ovallsp::Signatures::Environment.new)
    end

    # The override's parameter is deliberately named differently from the
    # one it overrides. With the same name in both, the two labels are
    # identical and a dedup-on-label passes this example without ever
    # choosing the callable one -- which is what shipped, and what an
    # override that renames its parameter (the ordinary case) exposed.
    it "offers the one Ruby would call, once, even when the labels differ" do
      index("class Shape\n  def area(x); end\nend\nclass Circle < Shape\n  def area(radius); end\nend\n")

      labels = query_service.signatures_of(Ovallsp::Types::Nominal.new(name: "Circle"), "area").map { |s| s[:label] }

      expect(labels).to eq(["area(radius)"])
    end

    # A class receiver reaches here as `ClassOf[Widget]`, which is not a
    # Nominal and names no class -- only `MethodResolver` knows to read it
    # as Widget's singleton chain. Splitting the receiver into members
    # here must therefore hand each member to the resolver whole, not
    # unwrap it first.
    it "still answers for a class receiver, whose type names no class" do
      index("class Widget\n  def self.build(spec); end\nend\n")

      class_object = Ovallsp::Types::Generic.new(name: "ClassOf",
                                                 type_arg: Ovallsp::Types::Nominal.new(name: "Widget"))
      labels = query_service.signatures_of(class_object, "build").map { |s| s[:label] }

      expect(labels).to eq(["build(spec)"])
    end

    # The control: genuinely different signatures for one name -- which a
    # Union receiver produces, and which the popup is *for* -- still come
    # through as separate entries.
    it "still offers both when the two really differ" do
      index("class A\n  def go(x); end\nend\nclass B\n  def go(x, y); end\nend\n")

      union = Ovallsp::Types.normalize_union([Ovallsp::Types::Nominal.new(name: "A"),
                                              Ovallsp::Types::Nominal.new(name: "B")])
      labels = query_service.signatures_of(union, "go").map { |s| s[:label] }

      expect(labels).to contain_exactly("go(x)", "go(x, y)")
    end
  end
end

