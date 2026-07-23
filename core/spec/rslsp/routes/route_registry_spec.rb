# frozen_string_literal: true

RSpec.describe Rslsp::Routes::RouteRegistry do
  def fact(name:, verb:, action:, controller: "posts", required: [], optional: ["format"], location: nil)
    {
      name: name, verb: verb, pathTemplate: "/#{controller}", requiredParts: required, optionalParts: optional,
      defaults: { controller: controller, action: action }, sourceLocation: location, routeSet: "main_app"
    }
  end

  it "groups multiple verbs sharing a name into one helper, GET-first" do
    facts = [
      fact(name: "post", verb: "DELETE", action: "destroy", required: ["id"]),
      fact(name: "post", verb: "GET", action: "show", required: ["id"]),
      fact(name: "post", verb: "PATCH", action: "update", required: ["id"])
    ]

    registry = described_class.from_route_facts(facts)
    helper = registry.helper("post")

    expect(helper.path_helper).to eq("post_path")
    expect(helper.url_helper).to eq("post_url")
    expect(helper.required_parts).to eq(["id"])
    # GET always leads; ties otherwise keep each verb's original relative order.
    expect(helper.action_targets.map(&:verb)).to eq(%w[GET DELETE PATCH])
    expect(helper.action_targets.first).to eq(Rslsp::Routes::ActionTarget.new(controller: "posts", action: "show", verb: "GET"))
  end

  it "produces no helper for a route fact with no name (unnamed route)" do
    facts = [fact(name: nil, verb: "GET", action: "ping", controller: "health")]

    registry = described_class.from_route_facts(facts)

    expect(registry.helper(nil)).to be_nil
    expect(registry.completion_names("")).to be_empty
  end

  it "falls back gracefully when a route has no source location" do
    facts = [fact(name: "unlocatable", verb: "GET", action: "show", controller: "mystery", location: nil)]

    helper = described_class.from_route_facts(facts).helper("unlocatable")

    expect(helper.source_location).to be_nil
  end

  describe "malformed sourceLocation from the Agent boundary (Task 008.5)" do
    it "discards a sourceLocation that isn't a Hash instead of crashing" do
      facts = [fact(name: "post", verb: "GET", action: "show", location: "config/routes.rb:10")]

      expect { described_class.from_route_facts(facts) }.not_to raise_error
      expect(described_class.from_route_facts(facts).helper("post").source_location).to be_nil
    end

    it "discards a sourceLocation Hash missing required keys" do
      facts = [fact(name: "post", verb: "GET", action: "show", location: { path: "config/routes.rb" })]

      expect(described_class.from_route_facts(facts).helper("post").source_location).to be_nil
    end

    it "defaults column to 0 when the Agent omits it" do
      facts = [fact(name: "post", verb: "GET", action: "show", location: { path: "/app/config/routes.rb", line: 3 })]

      expect(described_class.from_route_facts(facts).helper("post").source_location).to eq(
        path: "/app/config/routes.rb", line: 3, column: 0
      )
    end
  end

  describe "#completion_names" do
    it "returns both _path and _url forms filtered by prefix" do
      facts = [fact(name: "post", verb: "GET", action: "show", required: ["id"])]
      registry = described_class.from_route_facts(facts)

      expect(registry.completion_names("post_p")).to contain_exactly("post_path")
      expect(registry.completion_names("post_")).to contain_exactly("post_path", "post_url")
    end
  end

  describe "#find_by_method_name" do
    it "resolves both the _path and _url forms back to the same helper" do
      facts = [fact(name: "post", verb: "GET", action: "show", required: ["id"])]
      registry = described_class.from_route_facts(facts)

      expect(registry.find_by_method_name("post_path")).to eq(registry.helper("post"))
      expect(registry.find_by_method_name("post_url")).to eq(registry.helper("post"))
      expect(registry.find_by_method_name("not_a_route")).to be_nil
    end
  end

  describe "#replace" do
    it "drops a helper that a later snapshot no longer includes (reload)" do
      registry = described_class.from_route_facts([fact(name: "post", verb: "GET", action: "show", required: ["id"])])
      expect(registry.helper("post")).not_to be_nil

      registry.replace([fact(name: "comment", verb: "GET", action: "show", controller: "comments", required: ["id"])])

      expect(registry.helper("post")).to be_nil
      expect(registry.helper("comment")).not_to be_nil
    end
  end
end
