# frozen_string_literal: true

# `024.43`'s (C). A class-object receiver reached the RBS signature
# lookup un-normalised, so RBS was asked about a class literally named
# `ClassOf` and every `String.new(`, `File.read(`, `Integer.sqrt(`
# answered nothing.
#
# `#type_at("String")` is `Generic(name: "ClassOf", type_arg: Nominal("String"))`
# and `#each_nominal` yields `Nominal("ClassOf")`. Two moves are needed:
# unwrap to the type argument, and look the method up as a *singleton*
# method. `#add_signature_members` already makes both for completion, and
# its own comment names the two other places in the tree that make them.
#
# Three readers, not one: signature help and hover both go through
# `#signatures_of`, and go to definition goes through
# `#definitions_of` -> `#signature_definition_locations`, which carried a
# byte-identical copy of the same un-normalised lookup.
RSpec.describe "a class-object receiver reaching RBS" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:stack) { build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry, signatures: signatures) }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: nil) } }

  subject(:service) do
    Ovallsp::Semantic::QueryService.new(
      local_inferencer: stack.local_inferencer, method_resolver: stack.method_resolver,
      model_registry: model_registry, signatures: signatures, workspace_index: workspace_index
    )
  end

  before do
    document = Ovallsp::TextDocument.new(
      uri: "file:///w.rb", version: 1, language_id: "ruby",
      text: "class Widget\n  def self.build(name, count); end\n  def emit(a); end\nend\n"
    )
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    stack.hierarchy_index.replace_file(summary)
  end

  def class_object(name)
    Ovallsp::Types::Generic.new(name: "ClassOf", type_arg: Ovallsp::Types::Nominal.new(name: name))
  end

  def instance(name) = Ovallsp::Types::Nominal.new(name: name)

  describe "signature help and hover, through #signatures_of" do
    it "answers for a class method RBS declares" do
      expect(service.signatures_of(class_object("String"), "new").map { |s| s[:label] })
        .to include(a_string_starting_with("new("))
    end

    it "answers for one RBS declares only on an ancestor of the class object" do
      expect(service.signatures_of(class_object("File"), "read").map { |s| s[:label] })
        .to include(a_string_starting_with("read("))
    end

    # The four controls. Each already worked, and together they say the
    # fix did not simply start answering for everything: a workspace
    # class object, a workspace instance, an RBS instance, and a name
    # nothing declares.
    it "still answers for a workspace class method" do
      expect(service.signatures_of(class_object("Widget"), "build").map { |s| s[:label] })
        .to eq(["build(name, count)"])
    end

    it "still answers for a workspace instance method" do
      expect(service.signatures_of(instance("Widget"), "emit").map { |s| s[:label] })
        .to eq(["emit(a)"])
    end

    it "still answers for an RBS instance method" do
      expect(service.signatures_of(instance("String"), "upcase").map { |s| s[:label] })
        .to include(a_string_starting_with("upcase("))
    end

    it "says nothing for a name the class object does not have" do
      expect(service.signatures_of(class_object("String"), "definitely_not_a_method")).to be_empty
    end

    # The distinguishing pair: `new` exists as an *instance* method on
    # some classes and as a *singleton* method here. Asking the wrong
    # surface is how the un-normalised lookup could have been "fixed"
    # into answering the wrong thing.
    it "does not answer a class-object query from the instance surface" do
      expect(service.signatures_of(class_object("String"), "upcase")).to be_empty
    end
  end

  describe "go to definition, through #definitions_of" do
    it "jumps for a class method RBS declares" do
      expect(service.definitions_of(class_object("String"), "new")).not_to be_empty
    end

    it "still jumps for an RBS instance method" do
      expect(service.definitions_of(instance("String"), "upcase")).not_to be_empty
    end

    it "still says nothing for a name nothing declares" do
      expect(service.definitions_of(class_object("String"), "definitely_not_a_method")).to be_empty
    end
  end
end
