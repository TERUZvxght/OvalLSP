# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# RBS models `(?)` -- an untyped function -- as `RBS::Types::UntypedFunction`,
# which carries a return type and no parameter lists at all (0.1.12).
#
# `convert_method_type` asked it for `required_positionals` regardless, the
# `NoMethodError` was swallowed by the blanket rescue around signature
# building, and the method came back as "no signature" — which the
# unknown-method check reads as "RBS does not declare this". The result is
# a false report on `send`, `__send__`, `public_send` and `instance_exec`,
# which are ordinary Ruby, on every closed receiver in the workspace.
RSpec.describe "Ovallsp::Signatures untyped RBS functions (0.1.12)" do
  subject(:signatures) { Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: nil) } }

  # What a `(?)` declaration still *states* -- the two things the
  # conversion has to carry rather than flatten, and which stdlib's own
  # `(?)` methods all return `untyped` from, so they cannot show it.
  describe "what a `(?)` declaration still states" do
    around do |example|
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, "sig"))
        File.write(File.join(root, "sig", "untyped.rbs"), <<~RBS)
          class Untyped
            def plain: (?) -> String
            def generic: [U] (?) -> U
            def opts: (**untyped) -> void
            def required_kw: (name: String) -> void
            def opt_kw: (?limit: Integer) -> void
            def splat: (*Integer) -> void
          end
        RBS
        @root = root
        example.run
      end
    end

    let(:project) { Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: @root) } }

    def label_for(name)
      Ovallsp::Semantic::QueryService.new(
        local_inferencer: Ovallsp::LocalInferencer.new, signatures: project
      ).signatures_of(Ovallsp::Types::Nominal.new(name: "Untyped"), name).first[:label]
    end

    def overload_for(name)
      project.method_signatures(
        Ovallsp::Index::SymbolId.new(kind: :instance_method, owner: "::Untyped", name: name, discriminator: nil)
      ).overloads.first
    end

    # A project `sig/` reaches `untyped_overload` unnormalised, which is
    # what makes these two fixtures able to see the fields at all --
    # stdlib's own `(?)` methods all return `untyped` with no type
    # parameters, so nothing there could distinguish them.
    it "answers with the declared return type" do
      expect(overload_for("plain").return_type.to_s).to eq("String")
    end

    it "answers with the declared type parameters" do
      expect(overload_for("generic").type_parameters).to eq(["U"])
    end

    # The rest slots are where "takes anything" lives; `OverloadResolver`
    # reads them for truthiness, so emptying them would make such a method
    # match only a zero-argument call.
    it "accepts a call with arguments and keywords" do
      overload = overload_for("plain")

      expect(overload.rest_positional).not_to be_nil
      expect(overload.rest_keyword).not_to be_nil
    end

    # `**untyped` is the other half of "accepts more than it names". A
    # label built only from the named slots drops it silently, and stdlib
    # has no method with a rest-keyword and no rest-positional to show it
    # with -- so the fixture states it directly.
    it "marks a signature that accepts arbitrary keywords" do
      expect(label_for("opts")).to include("...")
    end

    # A required keyword is the one a caller *must* type, so leaving it out
    # of the label is the worst of the four omissions -- and no stdlib
    # method reachable here has one, which is why it is stated directly.
    # `?` is the only thing in the label separating a keyword the caller
    # must supply from one they may omit, so asserting the bare name
    # leaves the marker itself untested.
    it "names a required keyword in the label, without an optional marker" do
      expect(label_for("required_kw")).to include("(name:")
    end

    it "marks an optional keyword as optional" do
      expect(label_for("opt_kw")).to include("?limit:")
    end

    # `*rest` and `**rest` each independently mean "accepts more than it
    # names"; a marker driven by only one of them is silent for the other.
    it "marks a signature that accepts arbitrary positionals" do
      expect(label_for("splat")).to include("...")
    end

    # RBS refuses to parse a block on an untyped method type, so these two
    # fields describe a case that cannot arise -- they are literals rather
    # than expressions reading a `block` that is always nil.
    it "carries no block, which such a declaration cannot have" do
      expect(overload_for("plain").block_required).to be(false)
      expect(overload_for("plain").block_type).to be_nil
    end
  end

  def signature_for(owner, name)
    signatures.method_signatures(
      Ovallsp::Index::SymbolId.new(kind: :instance_method, owner: owner, name: name, discriminator: nil)
    )
  end

  # `Proc#call` and `Method#call` are declared `(?)` themselves, and reach
  # `Environment#convert_method_type`. The `send` family is declared with
  # an ordinary signature whose *block* is `(?)` -- `?{ (?) -> untyped }` --
  # so those reach `TypeConverter.convert_function` instead. Both paths
  # raised before 0.1.12; both are covered here, and the two groups are
  # kept apart because a fix to one does not fix the other.
  {
    "::Proc" => %w[call],
    "::Method" => %w[call]
  }.each do |owner, names|
    names.each do |name|
      it "builds a signature for #{owner}##{name}, whose own function is `(?)`" do
        expect(signature_for(owner, name)).not_to be_nil
      end
    end
  end

  {
    "::Kernel" => %w[send public_send],
    "::BasicObject" => %w[__send__ instance_exec]
  }.each do |owner, names|
    names.each do |name|
      it "builds a signature for #{owner}##{name}, whose block is `(?)`" do
        expect(signature_for(owner, name)).not_to be_nil
      end
    end
  end

  # Signature building is lazy, so the environment has no diagnostics at
  # all until something asks for one of these. Asking first is what makes
  # this able to fail.
  it "reports no diagnostics for the untyped functions it now understands" do
    signature_for("::Proc", "call")
    signature_for("::Method", "call")

    messages = signatures.diagnostics.map { |d| d[:message].to_s }

    expect(messages.grep(/NoMethodError|UntypedFunction|required_positionals/)).to be_empty
  end

  # `(?)` is where "takes anything" lives, and it lives in `rest_positional`.
  # A label built from the positional lists alone reads as zero arity --
  # which is a worse answer than the "no signature at all" these had before
  # they could be built.
  # The same failure one field over: a signature with no positionals and
  # only keywords also rendered as `name()`. 30 method types in the RBS
  # core this loads have that shape -- `Array#shuffle` among them -- so
  # the label asserted zero arity for each while the user typed keywords
  # into it.
  it "does not label a keyword-only method as taking no arguments" do
    query_service = Ovallsp::Semantic::QueryService.new(
      local_inferencer: Ovallsp::LocalInferencer.new, signatures: signatures
    )

    label = query_service.signatures_of(Ovallsp::Types::Nominal.new(name: "Array"), "shuffle").first[:label]

    # The keyword's own name, not merely "something other than `()`" --
    # a `...` from the rest slot would satisfy that while still telling
    # the user nothing about what to type.
    expect(label).to include("random:")
  end

  it "does not label a `(?)` method as taking no arguments" do
    query_service = Ovallsp::Semantic::QueryService.new(
      local_inferencer: Ovallsp::LocalInferencer.new, signatures: signatures
    )

    label = query_service.signatures_of(Ovallsp::Types::Nominal.new(name: "Proc"), "call").first[:label]

    expect(label).to include("...")
  end

  # `include("...")` alone cannot see a slot that should be empty: an
  # invented positional would render `call(Unknown, ...)` and still pass.
  # `(?)` says "takes anything" and nothing else, so every named slot of
  # the overload it builds must be empty and both rest slots open
  # (0.1.12, round 8 -- `untyped_overload` was added wholesale and this
  # was the one field of the seven nothing pinned).
  it "labels a `(?)` method as `...` and nothing else" do
    query_service = Ovallsp::Semantic::QueryService.new(
      local_inferencer: Ovallsp::LocalInferencer.new, signatures: signatures
    )

    label = query_service.signatures_of(Ovallsp::Types::Nominal.new(name: "Proc"), "call").first[:label]

    expect(label).to eq("call(...) -> Unknown")
  end

  # The engine's whole reason for asking: a method RBS declares must not be
  # reported as one nobody declares.
  it "does not report `__send__` as an unknown method on a workspace class" do
    workspace_index = Ovallsp::WorkspaceIndex.new
    hierarchy_index = Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index)
    method_resolver = Ovallsp::Semantic::MethodResolver.new(workspace_index: workspace_index,
                                                            hierarchy_index: hierarchy_index)
    [["file:///p.rb", "class Plain\nend\n"], ["file:///u.rb", "Plain.new.__send__(:x)\n"]].each do |uri, text|
      document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
      summary = Ovallsp::ParserService.new.summarize(document)
      workspace_index.replace_file(summary)
      hierarchy_index.replace_file(summary)
    end
    document = Ovallsp::TextDocument.new(uri: "file:///u.rb", text: "Plain.new.__send__(:x)\n",
                                         version: 1, language_id: "ruby")
    context = Ovallsp::Diagnostics::SemanticContext.new(
      workspace_index: workspace_index, hierarchy_index: hierarchy_index, method_resolver: method_resolver,
      local_inferencer: Ovallsp::LocalInferencer.new(method_resolver: method_resolver),
      model_registry: Ovallsp::Models::ModelRegistry.new, route_registry: Ovallsp::Routes::RouteRegistry.new,
      signatures: signatures, generation: 1
    )

    findings = Ovallsp::Diagnostics::Engine.new.analyze(document: document, semantic_context: context,
                                                       mode: :standard)

    expect(findings.select { |f| f.code == "unknown-method" }).to be_empty
  end
end
