# frozen_string_literal: true

# `::User.find(1)` is ordinary Ruby, and `ModelRegistry` never saw it
# (0.1.12).
#
# The registry is keyed by Rails' own `model.name` — always bare (`User`)
# — while a constant receiver reaches the inferencer as whatever the
# source wrote: `Prism::ConstantPathNode#full_name` answers `::User` for
# `::User.find(1)`. The lookup missed, so the finder's type was lost and
# the Agent-backed model check went quiet for that receiver — the same
# "switched off without saying so" shape as this release's other fixes.
RSpec.describe "Ovallsp root-scoped model receivers (0.1.12)" do
  let(:model_registry) do
    Ovallsp::Models::ModelRegistry.new.tap do |registry|
      registry.register_from_agent_response(
        "User",
        { tableName: "users", partial: false,
          columns: [{ name: "email", type: "string", nullable: false }],
          associations: [{ name: "company", macro: "belongs_to", className: "Company" }] }
      )
    end
  end

  describe "the registry itself" do
    it "answers for the bare name it was registered under" do
      expect(model_registry.model("User")).not_to be_nil
    end

    it "answers for a root-scoped spelling of the same class" do
      expect(model_registry.model("::User")).not_to be_nil
    end

    it "answers for a column and an association through either spelling" do
      expect(model_registry.column("::User", "email")).not_to be_nil
      expect(model_registry.association("::User", "company")).not_to be_nil
      expect(model_registry.known_model?("::User")).to be(true)
    end

    # Normalising a prefix is not matching by simple name.
    it "does not answer for a nested class with the same simple name" do
      expect(model_registry.model("Admin::User")).to be_nil
    end

    # The write paths normalise too. Nothing feeds them a `::`-prefixed
    # name today, so this pins the symmetry rather than a live bug: a
    # registry that normalises reads only is one whose keys depend on
    # which door you came in (0.1.12).
    # All four doors, not the two a unit test reaches most easily: the
    # first attempt at this normalised only `register_from_agent_response`
    # and `remove`, which have no caller in `lib/`, while every production
    # write goes through `commit_replace` or `commit_updates`.
    RESPONSE = { tableName: "widgets", partial: false, columns: [], associations: [] }.freeze

    it "registers under a normalised key through register_from_agent_response" do
      registry = Ovallsp::Models::ModelRegistry.new
      registry.register_from_agent_response("::Widget", RESPONSE)

      expect(registry.model("Widget")).not_to be_nil
      expect(registry.remove("Widget")).not_to be_nil
      expect(registry.model("::Widget")).to be_nil
    end

    it "registers under a normalised key through commit_replace" do
      registry = Ovallsp::Models::ModelRegistry.new
      registry.commit_replace(registry.prepare_replace("::Widget" => RESPONSE))

      expect(registry.known_model?("Widget")).to be(true)
      expect(registry.known_model?("::Widget")).to be(true)
    end

    it "registers and removes under a normalised key through commit_updates" do
      registry = Ovallsp::Models::ModelRegistry.new
      registry.commit_updates(registry.prepare_replace("::Widget" => RESPONSE))
      expect(registry.known_model?("Widget")).to be(true)

      registry.commit_updates({}, removals: ["::Widget"])

      expect(registry.known_model?("Widget")).to be(false)
    end
  end

  describe "inference through a root-scoped receiver" do
    # One stack, assembled where the server assembles its own (042's D8).
    let(:stack) { build_analysis_stack(model_registry: model_registry) }
    let(:workspace_index) { stack.workspace_index }
    let(:inferencer) { stack.local_inferencer }

    def type_of(source)
      document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
      inferencer.infer_at(document, { line: 0, character: source.index(".") + 2 }).to_s
    end

    it "types `User.find(1)`" do
      expect(type_of("User.find(1)\n")).to eq("User")
    end

    it "types `::User.find(1)` the same way" do
      expect(type_of("::User.find(1)\n")).to eq("User")
    end

    # A constant receiver that is *not* a model still carries the source's
    # spelling into the type, so `::Widget` and `Widget` become two
    # different Nominals -- and a union of the two is not a single
    # Nominal, which is what the unknown-method check requires. The check
    # then goes silent, which is the same failure this release is about.
    it "types a plain `::Constant.new` without the leading colons" do
      expect(type_of("::Widget.new\n")).to eq("Widget")
    end

    # A constant used as a *value* rather than a receiver reaches the type
    # model through `constant_path_type`, which had its own copy of the
    # normalisation. Hover is the observable difference: the same class
    # named two ways must not read as two different types (0.1.12, round
    # 7 -- the one normalisation site in this file that a test could see
    # and none did).
    it "types `k = ::Widget` as ClassOf[Widget], the same as `k = Widget`" do
      %w[::Widget Widget].each do |spelling|
        source = "class Holder\n  def run\n    k = #{spelling}\n    k\n  end\nend\n"
        document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")

        expect(inferencer.infer_at(document, { line: 3, character: 4 }).to_s).to eq("ClassOf[Widget]")
      end
    end

    # `Prism::ConstantPathNode#full_name` raises on a path whose segments
    # are not all constants -- `klass::Error` is legal Ruby and idiomatic
    # in factory and delegator code. `resolve_call` asked for it
    # unguarded, and the raise escaped all the way to
    # `infer_ivars_for_method_node`'s blanket rescue, which answers with
    # the *initial* environment: one such expression anywhere in a
    # controller action silently voided every instance variable in it, so
    # the view got no types at all. Both sibling sites already guarded
    # this -- `constant_path_type` here, and
    # `MethodAnalyzer#eval_constant_receiver_call` -- which is what makes
    # it an oversight rather than a decision (0.1.12).
    it "keeps a method's other ivars when it contains a dynamic constant path" do
      source = <<~RUBY
        class PostsController
          def show
            @title = "hello"
            x = klass::Error.new
            @count = 1
          end
        end
      RUBY
      document = Ovallsp::TextDocument.new(uri: "file:///c.rb", text: source, version: 1, language_id: "ruby")
      nodes = inferencer.method_nodes(document, owner_name: "::PostsController")

      env = inferencer.infer_ivars_for_method_node(
        nodes["show"], initial_env: {}, self_type_name: "::PostsController"
      )

      expect(env.transform_values(&:to_s)).to eq({ "@title": "String", "@count": "Integer" })
    end

    it "types the dynamic constant path itself as Unknown rather than raising" do
      source = "x = klass::Error.new
x
"
      document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")

      expect(inferencer.infer_at(document, { line: 1, character: 0 }).to_s).to eq("Unknown")
    end

    # A receiver that is not a constant must not be read as one. This pins
    # the *outcome*, not the kind check that produces it: measured,
    # neither `CallNode` nor `LocalVariableReadNode` answers `#full_name`,
    # so removing the check reaches the rescue and returns nil anyway, and
    # this fixture cannot tell the two apart. An earlier version of this
    # comment claimed it could, on an untested assumption about which
    # Prism nodes carry `#full_name` (0.1.12).
    it "does not treat a method-call receiver as a constant" do
      source = "def run\n  h = helper\n  y = h.new\n  y\nend\n"
      document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")

      expect(inferencer.infer_at(document, { line: 3, character: 2 }).to_s).to eq("Unknown")
    end

    # The same raise, through the *other* path that reads a constant
    # receiver's name -- `is_a?`'s argument, which narrows a local. This
    # release edited that line without giving it the guard its sibling
    # got, so `result.is_a?(gateway.class::Failure)` -- idiomatic Ruby --
    # still cost the whole action its instance variables (0.1.12).
    it "keeps a method's ivars when `is_a?` narrows against a dynamic constant path" do
      source = <<~RUBY
        class OrdersController
          def create
            @order = Order.new
            result = charge
            @error = 1 if result.is_a?(gateway.class::Failure)
            @total = "42"
          end
        end
      RUBY
      document = Ovallsp::TextDocument.new(uri: "file:///o.rb", text: source, version: 1, language_id: "ruby")
      nodes = inferencer.method_nodes(document, owner_name: "::OrdersController")

      env = inferencer.infer_ivars_for_method_node(
        nodes["create"], initial_env: {}, self_type_name: "::OrdersController"
      )

      expect(env.keys).to eq(%i[@order @error @total])
    end

    it "narrows `is_a?(::Widget)` to the same type as `is_a?(Widget)`" do
      source = "def run(x)\n  return unless x.is_a?(::Widget)\n\n  x\nend\n"
      document = Ovallsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")

      expect(inferencer.infer_at(document, { line: 3, character: 3 }).to_s).to eq("Widget")
    end
  end

  # `MethodAnalyzer` looked the owner up by *simple name*, which is a
  # different rule from "strip a leading `::`" -- so a namespaced class
  # that is not a model at all borrowed a top-level model's associations.
  describe "a namespaced class that shares a model's simple name" do
    it "does not resolve a delegate against the unrelated top-level model" do
      registry = Ovallsp::Models::ModelRegistry.new.tap do |r|
        r.register_from_agent_response(
          "User", { tableName: "users", partial: false, columns: [],
                    associations: [{ name: "company", macro: "belongs_to", className: "Company" }] }
        )
      end

      expect(registry.association("Admin::User", "company")).to be_nil
      expect(registry.association("::User", "company")).not_to be_nil
    end
  end
end
