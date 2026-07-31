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
  end

  describe "inference through a root-scoped receiver" do
    let(:inferencer) { Ovallsp::LocalInferencer.new(model_registry: model_registry) }

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
