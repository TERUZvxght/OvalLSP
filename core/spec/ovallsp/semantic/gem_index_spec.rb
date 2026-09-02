# frozen_string_literal: true

# 024.R7. What the gems define, held Core-side.
#
# The undefined-method check fires only on a *closed* receiver, and
# "closed" has meant "the workspace can see the whole ancestry". In a
# Rails application that is a minority of classes -- a controller
# inherits from `ApplicationController`, whose parent is in a gem -- so
# the check works where it is least needed and says nothing where most
# code is written.
#
# **Closedness and members have to arrive together.** Telling the engine
# a gem class is closed without also telling it that class's methods
# turns every correct call on a gem into a report. These examples hold
# both halves against each other.
RSpec.describe Ovallsp::Semantic::GemIndex do
  let(:payload) do
    { gems: {
      "activerecord-8.1.0": { classes: [
        { name: "ActiveRecord::Base", ancestors: %w[ActiveRecord::Base ActiveRecord::Persistence Object],
          instanceMethods: %w[becomes], singletonMethods: %w[find], definesMethodMissing: false },
        { name: "ActiveRecord::Persistence", ancestors: %w[ActiveRecord::Persistence Object],
          instanceMethods: %w[save save!], singletonMethods: [], definesMethodMissing: false }
      ] },
      "dynamic-1.0.0": { classes: [
        { name: "Dynamic::Thing", ancestors: %w[Dynamic::Thing Object],
          instanceMethods: [], singletonMethods: [], definesMethodMissing: true }
      ] }
    } }
  end

  subject(:index) { described_class.from_agent(payload) }

  it "knows a class a gem defines" do
    expect(index.knows?("ActiveRecord::Base")).to be true
    expect(index.knows?("::ActiveRecord::Base")).to be true
  end

  it "does not claim a class no gem defined" do
    expect(index.knows?("Widget")).to be false
  end

  # The half that stops a closed receiver becoming a report factory.
  it "answers the instance methods a class declares itself" do
    expect(index.instance_methods("ActiveRecord::Persistence")).to include("save", "save!")
    expect(index.instance_methods("ActiveRecord::Base")).to include("becomes")
    expect(index.instance_methods("ActiveRecord::Base")).not_to include("save")
  end

  it "answers the singleton methods separately" do
    # A Set, not an Array: membership is the only question anyone asks
    # of these and the lists run to thousands of names.
    expect(index.singleton_methods("ActiveRecord::Base")).to contain_exactly("find")
    expect(index.instance_methods("ActiveRecord::Base")).not_to include("find")
  end

  it "answers the ancestors a class was loaded with" do
    expect(index.ancestors("ActiveRecord::Base")).to include("ActiveRecord::Persistence")
  end

  # **A class that answers at call time is never closed**, whatever the
  # index holds about it: `method_missing` means it responds to names no
  # enumeration can list, and reporting against it is asserting from a
  # question that cannot be asked.
  it "refuses to call a method_missing class knowable" do
    expect(index.knows?("Dynamic::Thing")).to be false
    expect(index.defines_method_missing?("Dynamic::Thing")).to be true
  end

  # An empty index is the ordinary state -- no Agent, a static workspace,
  # a boot that failed. Every answer has to be "I do not know", never
  # "there is nothing there".
  it "is empty rather than authoritative when there is no agent" do
    empty = described_class.empty

    expect(empty.knows?("ActiveRecord::Base")).to be false
    expect(empty.instance_methods("ActiveRecord::Base")).to be_empty
    expect(empty.defines_method_missing?("ActiveRecord::Base")).to be false
  end

  it "survives a payload that is not the shape it expects" do
    expect(described_class.from_agent(nil).knows?("X")).to be false
    expect(described_class.from_agent({ gems: nil }).knows?("X")).to be false
  end
end
