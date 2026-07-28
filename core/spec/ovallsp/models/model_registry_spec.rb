# frozen_string_literal: true

RSpec.describe Ovallsp::Models::ModelRegistry do
  subject(:registry) { described_class.new }

  def agent_response(columns: [], associations: [], table_name: "users", partial: false)
    {
      tableName: table_name,
      columns: columns,
      associations: associations,
      partial: partial
    }
  end

  it "maps DB column types to Ruby types" do
    registry.register_from_agent_response(
      "User",
      agent_response(columns: [
                        { name: "id", type: "integer", null: false },
                        { name: "total", type: "decimal", null: false },
                        { name: "active", type: "boolean", null: false },
                        { name: "notes", type: "some_custom_type", null: true }
                      ])
    )

    columns = registry.model("User").columns
    expect(columns.find { |c| c.name == "id" }.ruby_type).to eq("Integer")
    expect(columns.find { |c| c.name == "total" }.ruby_type).to eq("BigDecimal")
    expect(columns.find { |c| c.name == "active" }.ruby_type).to eq("Boolean")
    expect(columns.find { |c| c.name == "notes" }.ruby_type).to eq("Untyped") # unmapped type widens, doesn't guess
  end

  it "exposes associations with their optionality" do
    registry.register_from_agent_response(
      "User",
      agent_response(associations: [
                        { name: "company", macro: "belongs_to", className: "Company", optional: true }
                      ])
    )

    assoc = registry.association("User", "company")
    expect(assoc.macro).to eq(:belongs_to)
    expect(assoc.class_name).to eq("Company")
    expect(assoc.optional).to be(true)
  end

  it "looks up a column by name" do
    registry.register_from_agent_response("Order", agent_response(columns: [{ name: "total", type: "decimal", null: false }]))

    expect(registry.column("Order", "total").ruby_type).to eq("BigDecimal")
    expect(registry.column("Order", "missing")).to be_nil
  end

  it "is unaware of a model it was never given" do
    expect(registry.known_model?("Ghost")).to be(false)
    expect(registry.model("Ghost")).to be_nil
  end

  describe "nullable columns (Task 008.5)" do
    it "retains the Agent's null flag instead of discarding it" do
      registry.register_from_agent_response(
        "User",
        agent_response(columns: [
                          { name: "bio", type: "string", null: true },
                          { name: "email", type: "string", null: false }
                        ])
      )

      expect(registry.column("User", "bio").nullable).to be(true)
      expect(registry.column("User", "email").nullable).to be(false)
    end
  end

  describe "#replace (Task 008.5)" do
    it "fully swaps the model table so a model absent from the new generation disappears" do
      registry.register_from_agent_response("User", agent_response)
      expect(registry.known_model?("User")).to be(true)

      registry.replace({ "Company" => agent_response(table_name: "companies") })

      expect(registry.known_model?("User")).to be(false)
      expect(registry.known_model?("Company")).to be(true)
    end

    # Rewritten: the previous version asserted only that a malformed
    # payload leaves the registry untouched, which `replace`'s `to_h`
    # already guaranteed before this change -- so it passed with or
    # without it, and would have kept passing if the whole
    # prepare/commit split were deleted. What is actually new, and what
    # callers depend on to keep models and routes in step, is that
    # preparing a snapshot *publishes nothing*.
    it "prepares a replacement without publishing it, so a caller can validate a whole snapshot first" do
      registry.register_from_agent_response("User", agent_response(table_name: "old_users"))

      prepared = registry.prepare_replace("User" => agent_response(table_name: "new_users"))

      expect(registry.model("User").table_name).to eq("old_users")

      registry.commit_replace(prepared)

      expect(registry.model("User").table_name).to eq("new_users")
    end

    it "raises while preparing a malformed payload, before anything is published" do
      registry.register_from_agent_response("User", agent_response(table_name: "old_users"))

      expect do
        registry.prepare_replace(
          "User" => agent_response(table_name: "new_users"),
          "Team" => agent_response(associations: [{ name: "owner", macro: nil, className: "User" }])
        )
        # Matched on the message, not just the class: a build without
        # #prepare_replace raises NoMethodError too, and would otherwise
        # satisfy this expectation vacuously.
      end.to raise_error(NoMethodError, /to_sym/)

      expect(registry.model("User").table_name).to eq("old_users")
      expect(registry.known_model?("Team")).to be(false)
    end
  end

  describe "#remove (Task 008.5)" do
    it "drops a single model, e.g. after the Agent reports it no longer exists" do
      registry.register_from_agent_response("User", agent_response)

      registry.remove("User")

      expect(registry.known_model?("User")).to be(false)
    end
  end
end
