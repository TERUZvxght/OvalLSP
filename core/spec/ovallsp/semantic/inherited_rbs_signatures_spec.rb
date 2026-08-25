# frozen_string_literal: true

# `024.43`'s remainder. The RBS signature lookup and
# `#signature_definition_locations` asked RBS about the receiver's *own*
# name and nothing else, so a method declared only on an RBS ancestor of
# a name RBS has never heard of was unreachable:
#
# - a receiverless `puts(` or `format(` inside a class body -- the call
#   goes to `Kernel`, which is not the receiver's name;
# - `MyErr < StandardError`, where `full_message` and `message` live on
#   `Exception`;
# - `MyStr < String`, where `sub` lives on `String`.
#
# Ruby's own answer for each, since the expectation is a claim about
# Ruby's semantics and not about this engine:
#
#     $ ruby -e '
#       class MyErr < StandardError; end
#       class MyStr < String; end
#       class Report; def run; end; end
#       p [MyErr.new.respond_to?(:full_message), MyErr.new.respond_to?(:message)]
#       p MyStr.new("ab").sub("a", "b")
#       p Report.private_instance_methods.include?(:puts)
#       p Report.private_instance_methods.include?(:format)'
#     [true, true]
#     "bb"
#     true
#     true
#     # ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [arm64-darwin25]
#
# `#add_signature_members` had already made the move for completion --
# `MethodResolver#lookup_owners` -- which is why bare-prefix completion
# offers `puts` in the very body where signature help says nothing.
#
# **The controls are the interesting half.** The ancestor chain must not
# be walked by the band that outranks the workspace's own declaration:
# `Kernel#format` and `String#sub` are both `direct` in RBS, so a fix
# that walked the chain in *that* band would answer `Formatter#format`
# and `MyStr#sub` with the stdlib's signature instead of the one the
# workspace wrote. That is a wrong answer where there used to be a right
# one, which section 0 ranks below the silence this entry is about.
RSpec.describe "a method RBS declares only on an ancestor" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:stack) { build_analysis_stack(workspace_index: workspace_index) }
  let(:signatures) { stack.signatures }

  subject(:service) do
    Ovallsp::Semantic::QueryService.new(
      local_inferencer: stack.local_inferencer, method_resolver: stack.method_resolver,
      model_registry: stack.model_registry, signatures: signatures, workspace_index: workspace_index
    )
  end

  before do
    document = Ovallsp::TextDocument.new(
      uri: "file:///w.rb", version: 1, language_id: "ruby",
      text: <<~RUBY
        class Report
          def initialize(a, b); end

          def run
            puts("x")
            helper(1)
          end

          def helper(a); end
        end

        class Formatter
          def format(template); end
        end

        class MyErr < StandardError
        end

        class MyStr < String
          def sub(pattern); end
        end

        class PlainStr < String
        end

        module Reader
          class ArgumentError < StandardError
          end
        end

        class String
          def tap(marker); end
        end

        class Builder
          def self.new(z); end

          def initialize(a, b); end
        end
      RUBY
    )
    stack.replace_file(Ovallsp::ParserService.new.summarize(document))
  end

  def instance(name) = Ovallsp::Types::Nominal.new(name: name)
  def class_object(name) = Ovallsp::Types::Generic.new(name: "ClassOf", type_arg: instance(name))
  def labels(type, name) = service.signatures_of(type, name).map { |signature| signature[:label] }

  describe "signature help and hover, through #signatures_of" do
    it "answers a receiverless Kernel call from inside a class body" do
      expect(labels(instance("Report"), "puts")).to include(a_string_starting_with("puts("))
    end

    it "answers the other Kernel call the entry names" do
      expect(labels(instance("Report"), "format")).to include(a_string_starting_with("format("))
    end

    it "answers for a workspace class inheriting a stdlib one" do
      expect(labels(instance("MyErr"), "full_message")).to include(a_string_starting_with("full_message("))
    end

    it "answers for the ancestor two links up" do
      expect(labels(instance("MyErr"), "message")).to include(a_string_starting_with("message("))
    end

    it "answers for a workspace subclass of String" do
      expect(labels(instance("PlainStr"), "sub")).to include(a_string_starting_with("sub("))
    end

    # The class-object half of the same walk: `Module`'s instance methods
    # are what a class object is, and RBS knows nothing about a class the
    # workspace declared.
    it "answers a Module method on a workspace class object" do
      expect(labels(class_object("Report"), "instance_methods")).to include(a_string_starting_with("instance_methods("))
    end
  end

  # `new` is the one name the chain must not answer from an ancestor.
  # Every other method keeps its parameter list as it is inherited;
  # `Class#new` forwards its arguments to the receiver's own
  # `initialize`, so an ancestor's `new` describes the *ancestor's*
  # constructor. Walking the singleton chain without this reported
  # `new() -> Object` -- RBS's rendering of `Object#initialize`, which
  # takes nothing -- for 31 of 253 newly answered call sites in the
  # Ruby 3.4.10 standard library, telling the user a constructor takes
  # no arguments when it takes two.
  #
  #     $ ruby -e '
  #       class Report; def initialize(a, b); end; end
  #       class Plain; end
  #       p Report.instance_method(:initialize).parameters
  #       p Plain.instance_method(:initialize).owner
  #       begin; Report.new(1); rescue ArgumentError => e; p e.message; end'
  #     [[:req, :a], [:req, :b]]
  #     BasicObject
  #     "wrong number of arguments (given 1, expected 2)"
  #     # ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [arm64-darwin25]
  #
  # So the answer for `X.new(` is `X#initialize` where the workspace
  # wrote one, and nothing where it did not -- RBS's own
  # `Object#initialize` is `() -> void`, and rendering that as `new()`
  # would repeat the same false claim from one layer down.
  describe "`.new(` is the receiver's own constructor" do
    it "answers with the workspace's initialize, not an ancestor's new" do
      expect(labels(class_object("Report"), "new")).to eq(["new(a, b)"])
    end

    it "says nothing rather than borrowing an ancestor's constructor" do
      expect(service.signatures_of(class_object("Formatter"), "new")).to be_empty
    end

    it "still answers a class RBS declares a constructor for itself" do
      expect(labels(class_object("String"), "new")).to include(a_string_starting_with("new("))
    end

    it "lands go to definition on the constructor the call reaches" do
      locations = service.definitions_of(class_object("Report"), "new")
      expect(locations.map { |l| l[:range][:start][:line] }).to eq([1])
    end

    it "does not send go to definition to an ancestor's new" do
      expect(service.definitions_of(class_object("Formatter"), "new")).to be_empty
    end

    # **The constructor rule sits below the source band, and this is the
    # fixture that can tell.** `Builder` writes both halves -- a
    # `def self.new(z)` and a `def initialize(a, b)` -- so the two
    # candidate orderings give different answers: the rule as written
    # answers `new(z)` because the workspace's own singleton method is
    # found first, and a rule hoisted above the source band would answer
    # `new(a, b)` from the constructor instead. Ruby calls the
    # `def self.new`:
    #
    #     $ ruby -e '
    #       class Builder
    #         def self.new(z) = [:self_new, z]
    #         def initialize(a, b); end
    #       end
    #       p Builder.new(1)'
    #     [:self_new, 1]
    #     # ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [arm64-darwin25]
    it "prefers the workspace's own `def self.new` to the constructor rule" do
      expect(labels(class_object("Builder"), "new")).to eq(["new(z)"])
    end

    it "jumps to the workspace's own `def self.new`, not to its initialize" do
      locations = service.definitions_of(class_object("Builder"), "new")

      expect(locations.map { |l| l[:range][:start][:line] }).to eq([35])
    end

    # `#constructor_candidate` looks `initialize` up on the *instance*
    # side whatever side the caller is asking about, because
    # `X.new(`'s constructor is an instance method however the call was
    # reached. A caller writing the call from inside `class << self`
    # passes `singleton: true`, and without the override that lookup
    # goes to `Report`'s singleton side, where no `initialize` is
    # declared.
    it "asks the instance side for the constructor even when the caller asks about the singleton one" do
      signatures = service.signatures_of(class_object("Report"), "new", context: { singleton: true })

      expect(signatures.map { |signature| signature[:label] }).to eq(["new(a, b)"])
    end
  end

  # `X.new(` is answered from the workspace's own `initialize`, which is
  # a fact about the workspace and not about RBS -- so the constructor
  # rule is reached before the band's `@signatures` guard, and an
  # engine with no RBS environment loaded still answers it. Every other
  # name in this file needs RBS and correctly answers nothing here.
  describe "with no RBS environment loaded" do
    subject(:service) do
      Ovallsp::Semantic::QueryService.new(
        local_inferencer: stack.local_inferencer, method_resolver: stack.method_resolver,
        model_registry: stack.model_registry, signatures: nil, workspace_index: workspace_index
      )
    end

    it "still answers `X.new(` from the workspace's own constructor" do
      expect(labels(class_object("Report"), "new")).to eq(["new(a, b)"])
    end

    it "answers nothing for a name only RBS could have" do
      expect(service.signatures_of(instance("Report"), "puts")).to be_empty
    end
  end

  # Each of these already answered, and each answers something *different*
  # from what the ancestor chain would say -- so an example that passes
  # here is asserting the workspace's answer won, not merely that some
  # answer arrived.
  describe "controls: the workspace's own declaration still wins" do
    it "answers a receiverless call to a method the workspace defines" do
      expect(labels(instance("Report"), "helper")).to eq(["helper(a)"])
    end

    it "answers the workspace's method rather than Kernel's of the same name" do
      expect(labels(instance("Formatter"), "format")).to eq(["format(template)"])
    end

    it "answers the subclass's override rather than String's" do
      expect(labels(instance("MyStr"), "sub")).to eq(["sub(pattern)"])
    end

    it "still answers an RBS instance method on its own type" do
      expect(labels(instance("String"), "upcase")).to include(a_string_starting_with("upcase("))
    end

    # The band that outranks the workspace is the one RBS declares
    # *directly*, and `::String#tap` is not one of those -- RBS carries
    # it on `::String` inherited from `Kernel`:
    #
    #     method_signatures(::String#tap).direct  # => false
    #     method_signatures(::String#upcase).direct # => true
    #
    # So a workspace reopening `String` to redefine `tap` is what the
    # call reaches, and RBS's inherited declaration is not. Dropping the
    # `direct:` restriction leaves every other example green, which is
    # why this one spells the parameter the workspace wrote.
    it "prefers a reopened core class's override to RBS's inherited declaration" do
      expect(labels(instance("String"), "tap")).to eq(["tap(marker)"])
    end

    it "still says nothing for a name no ancestor declares" do
      expect(service.signatures_of(instance("Report"), "definitely_not_a_method")).to be_empty
    end

    it "still says nothing for a name no ancestor of a stdlib subclass declares" do
      expect(service.signatures_of(instance("PlainStr"), "definitely_not_a_method")).to be_empty
    end

    # **The chain does not open where the receiver is.**
    # `HierarchyIndex` resolves a bare name against whatever the
    # workspace declares with that last segment, so this fixture's
    # `Reader::ArgumentError` is what `#lookup_owners` opens
    # `Nominal("ArgumentError")`'s chain at -- measured:
    #
    #     lookup_owners(Nominal("ArgumentError"), singleton: true)
    #     # => [["::Reader::ArgumentError", true], ["StandardError", true], ...]
    #
    # RBS says nothing about that name, so handing the chain to the RBS
    # readers unprefixed lost answers they had been giving. Driven over
    # the Ruby 3.4.10 standard library that cost two signatures and eight
    # definition jumps before the receiver's own name was put back at the
    # head. The same shape as the stdlib's own `EOFError`, `Encoding` and
    # `Marshal`, in a fixture.
    it "asks the receiver's own name even when the workspace shadows it" do
      expect(labels(class_object("ArgumentError"), "new")).to include(a_string_starting_with("new("))
    end

    # `Object` and `Kernel` are both in the chain and RBS answers `puts`
    # for both, so a walk that collected every owner instead of stopping
    # at the nearest would show the same line twice -- a choice the call
    # does not have. The count is the assertion; `include` cannot see it.
    it "offers one signature per overload, not one per owner that carries it" do
      expect(labels(instance("Report"), "puts")).to eq(["puts(...) -> nil"])
    end

    it "offers one definition jump, not one per owner that carries it" do
      expect(service.definitions_of(instance("Report"), "puts").size).to eq(1)
    end
  end

  describe "go to definition, through #definitions_of" do
    it "jumps for a method an RBS ancestor declares" do
      expect(service.definitions_of(instance("MyErr"), "full_message")).not_to be_empty
    end

    it "jumps for a receiverless Kernel call" do
      expect(service.definitions_of(instance("Report"), "puts")).not_to be_empty
    end

    it "still lands in the workspace for a method the workspace declares" do
      expect(service.definitions_of(instance("Formatter"), "format").map { |l| l[:uri] }).to eq(["file:///w.rb"])
    end

    it "still says nothing for a name no ancestor declares" do
      expect(service.definitions_of(instance("Report"), "definitely_not_a_method")).to be_empty
    end
  end

  # The reader that already walked the chain, and the reason the entry
  # could observe completion answering where signature help did not.
  # Unchanged by this, and here so a change to the shared walk cannot
  # quietly take it away.
  describe "control: completion, through #members_of" do
    it "still offers a Kernel method from a bare prefix inside a class" do
      expect(service.members_of(instance("Report"), prefix: "put").map(&:name)).to include("puts")
    end
  end

  # `#constructor_call?`'s `Types.class_object?` half, which a review round
  # found unpinned: mutating it to `method_name == "new"` alone left the
  # whole unit and e2e suite green while raising `NoMethodError: undefined
  # method 'type_arg'` on an ordinary instance receiver, because
  # `#constructor_candidate` reads `receiver_type.type_arg` and only this
  # test stops a `Nominal` reaching it.
  #
  # Written as a fixture whose two candidate behaviours give different
  # observable answers: an *instance* receiver asked for `new`. With the
  # guard it is an ordinary lookup; without it the constructor path runs
  # and raises.
  describe "asking an instance receiver for `new`" do
    it "does not take the constructor path, which would read a type argument that is not there" do
      instance = Ovallsp::Types::Nominal.new(name: "String")

      expect { service.signatures_of(instance, "new") }.not_to raise_error
      expect { service.definitions_of(instance, "new") }.not_to raise_error
    end

    it "still takes it for a class object, where `new` is the constructor" do
      class_object = Ovallsp::Types.class_object(Ovallsp::Types::Nominal.new(name: "String"))

      expect(service.signatures_of(class_object, "new")).not_to be_empty
    end
  end

end
