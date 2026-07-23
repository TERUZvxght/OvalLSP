# frozen_string_literal: true

RSpec.describe Rslsp::LocalInferencer do
  subject(:inferencer) { described_class.new }

  def infer(source, line:, character:)
    document = Rslsp::TextDocument.new(uri: "file:///a.rb", text: source, version: 1, language_id: "ruby")
    inferencer.infer_at(document, { line: line, character: character })
  end

  it "infers Class.new as a Nominal reference to that class" do
    type = infer("user = User.new\n", line: 0, character: 1)

    expect(type).to eq(Rslsp::Types::Nominal.new(name: "User"))
  end

  it "infers literals as their base class" do
    expect(infer("x = 1\n", line: 0, character: 1).to_s).to eq("Integer")
    expect(infer("x = 1.5\n", line: 0, character: 1).to_s).to eq("Float")
    expect(infer("x = \"s\"\n", line: 0, character: 1).to_s).to eq("String")
    expect(infer("x = :sym\n", line: 0, character: 1).to_s).to eq("Symbol")
    expect(infer("x = true\n", line: 0, character: 1).to_s).to eq("Boolean")
    expect(infer("x = nil\n", line: 0, character: 1).to_s).to eq("nil")
  end

  it "unions ternary branches" do
    type = infer("value = cond ? User.new : Company.new\n", line: 0, character: 1)

    expect(type).to eq(Rslsp::Types.normalize_union(
                          [Rslsp::Types::Nominal.new(name: "User"), Rslsp::Types::Nominal.new(name: "Company")]
                        ))
  end

  it "unions full if/else branches the same way as a ternary" do
    source = <<~RUBY
      if cond
        value = User.new
      else
        value = Company.new
      end
    RUBY

    type = infer(source, line: 1, character: 3)
    expect(type).to eq(Rslsp::Types::Nominal.new(name: "User"))
  end

  it "removes nil from a local's type after a `return unless` guard clause" do
    source = "user = cond ? User.new : nil\nreturn unless user\nuser.name\n"

    before_guard = infer(source, line: 0, character: 1)
    after_guard = infer(source, line: 2, character: 1)

    expect(before_guard).to eq(Rslsp::Types.normalize_union([Rslsp::Types::Nominal.new(name: "User"), Rslsp::Types::NIL]))
    expect(after_guard).to eq(Rslsp::Types::Nominal.new(name: "User"))
  end

  it "narrows via `if x.nil?` guarded by an unconditional return" do
    source = "user = cond ? User.new : nil\nreturn if user.nil?\nuser.name\n"

    expect(infer(source, line: 2, character: 1)).to eq(Rslsp::Types::Nominal.new(name: "User"))
  end

  it "adds nil to the result of a safe-navigation call" do
    type = infer("user = User.new\nuser&.name\n", line: 1, character: 8)

    expect(type).to be_a(Rslsp::Types::Union)
    expect(type.members).to include(Rslsp::Types::NIL)
  end

  it "falls back to Unknown for calls it can't resolve" do
    expect(infer("x = foo\n", line: 0, character: 1)).to eq(Rslsp::Types::UNKNOWN)
  end

  it "returns Unknown, not an exception, once the step budget is exceeded" do
    tiny_budget = described_class.new(max_steps: 5)
    source = (1..50).map { |i| "v#{i} = #{i}" }.join("\n") + "\n"
    document = Rslsp::TextDocument.new(uri: "file:///b.rb", text: source, version: 1, language_id: "ruby")

    expect { tiny_budget.infer_at(document, { line: 49, character: 1 }) }.not_to raise_error
    expect(tiny_budget.infer_at(document, { line: 49, character: 1 })).to eq(Rslsp::Types::UNKNOWN)
  end

  it "returns Unknown for unparsable source instead of raising" do
    document = Rslsp::TextDocument.new(uri: "file:///c.rb", text: "def broken(\n", version: 1, language_id: "ruby")

    expect { inferencer.infer_at(document, { line: 0, character: 5 }) }.not_to raise_error
  end

  describe "Active Record model resolution (Task 007)" do
    let(:model_registry) do
      registry = Rslsp::Models::ModelRegistry.new
      registry.register_from_agent_response(
        "User",
        { tableName: "users", partial: false, columns: [],
          associations: [{ name: "company", macro: "belongs_to", className: "Company", optional: true }] }
      )
      registry.register_from_agent_response(
        "Company",
        { tableName: "companies", partial: false, columns: [{ name: "name", type: "string", null: false }],
          associations: [{ name: "orders", macro: "has_many", className: "Order", optional: false }] }
      )
      registry.register_from_agent_response(
        "Order",
        { tableName: "orders", partial: false,
          columns: [{ name: "total", type: "decimal", null: false }], associations: [] }
      )
      registry
    end
    let(:inferencer) { described_class.new(model_registry: model_registry) }

    it "infers Model.find as the model itself" do
      expect(infer("user = User.find(1)\n", line: 0, character: 1)).to eq(Rslsp::Types::Nominal.new(name: "User"))
    end

    it "infers Model.find_by as an optional model" do
      type = infer("user = User.find_by(id: 1)\n", line: 0, character: 1)
      expect(type).to eq(Rslsp::Types.normalize_union([Rslsp::Types::Nominal.new(name: "User"), Rslsp::Types::NIL]))
    end

    it "infers Model.where/.all as Relation[Model]" do
      expect(infer("x = User.where(id: 1)\n", line: 0, character: 1).to_s).to eq("Relation[User]")
      expect(infer("x = User.all\n", line: 0, character: 1).to_s).to eq("Relation[User]")
    end

    it "infers a belongs_to association through a Union receiver (user.company.orders)" do
      source = "user = User.find(1)\nuser.company.orders\n"
      expect(infer(source, line: 1, character: 13).to_s).to eq("CollectionProxy[Order]")
    end

    it "infers CollectionProxy[T]#first as T | nil, matching the README MVP example" do
      source = "user = User.find(1)\nuser.company.orders.first\n"
      type = infer(source, line: 1, character: 20)
      expect(type).to eq(Rslsp::Types.normalize_union([Rslsp::Types::Nominal.new(name: "Order"), Rslsp::Types::NIL]))
    end

    it "infers CollectionProxy[T]#first! as T (no nil)" do
      source = "user = User.find(1)\nuser.company.orders.first!\n"
      expect(infer(source, line: 1, character: 20)).to eq(Rslsp::Types::Nominal.new(name: "Order"))
    end

    it "infers a DB column accessor by its mapped Ruby type" do
      source = "company = User.find(1).company\ncompany.name\n"
      expect(infer(source, line: 1, character: 9).to_s).to eq("String")
    end

    it "adds nil via safe navigation on top of an already-nilable association" do
      source = "user = User.find(1)\nuser.company&.orders\n"
      expect(infer(source, line: 1, character: 15).to_s).to eq("CollectionProxy[Order] | nil")
    end

    it "does not resolve members on an unknown model" do
      expect(infer("x = Ghost.find(1)\n", line: 0, character: 1)).to eq(Rslsp::Types::UNKNOWN)
    end
  end
end
