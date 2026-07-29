# frozen_string_literal: true

RSpec.describe Ovallsp::Runtime::AncestryRegistry do
  subject(:registry) { described_class.new }

  it "is inactive until told there is a running application to ask" do
    expect(registry).not_to be_active
  end

  # The first question can only be asked while no answer exists yet, so
  # availability cannot be derived from having answered.
  it "is active once activated, before any answer has arrived" do
    registry.activate!

    expect(registry).to be_active
    expect(registry.entry("Widget")).to be_nil
  end

  it "answers nothing for a class it has never been told about" do
    expect(registry.entry("Widget")).to be_nil
  end

  describe "#install" do
    it "records the ancestors a class carries beyond the running Object's" do
      registry.install(
        object_ancestors: %w[Object Kernel BasicObject],
        classes: { "ActiveSupport::TestCase" => { ancestors: %w[ActiveSupport::TestCase ActiveSupport::Testing::Assertions Object Kernel BasicObject] } }
      )

      entry = registry.entry("ActiveSupport::TestCase")
      expect(entry.status).to eq(:loaded)
      expect(entry.foreign_ancestors).to eq(["ActiveSupport::Testing::Assertions"])
    end

    it "excludes the class itself, which is never evidence of a foreign ancestor" do
      registry.install(object_ancestors: %w[Object Kernel BasicObject],
                       classes: { "Widget" => { ancestors: %w[Widget Object Kernel BasicObject] } })

      expect(registry.entry("Widget").foreign_ancestors).to be_empty
    end

    # An application that mixes into Object (Active Support mixes in four)
    # makes every class carry those modules. Subtracting the same
    # process's own Object.ancestors is what keeps that from reading as
    # evidence about the class -- and is why the baseline is measured
    # rather than hardcoded.
    it "subtracts whatever the running application itself mixed into Object" do
      registry.install(
        object_ancestors: ["Object", "ActiveSupport::Tryable", "JSON::GeneratorMethods", "Kernel", "BasicObject"],
        classes: { "Widget" => { ancestors: ["Widget", "Object", "ActiveSupport::Tryable", "JSON::GeneratorMethods", "Kernel", "BasicObject"] } }
      )

      expect(registry.entry("Widget").foreign_ancestors).to be_empty
    end

    it "records a name the running application does not define as answered-but-absent" do
      registry.install(object_ancestors: %w[Object], classes: { "Ghost" => nil })

      entry = registry.entry("Ghost")
      expect(entry).not_to be_nil
      expect(entry.status).to eq(:absent)
    end

    # The case the real application actually needed: `ActiveSupport::TestCase`
    # is never loaded in the environment the Agent boots, so there is no
    # ancestry to compare -- but the autoload registration pointing at a
    # gem's own require path settles it without loading anything.
    it "records a class registered for autoload from outside the workspace as external" do
      registry.install(object_ancestors: %w[Object],
                       classes: { "ActiveSupport::TestCase" => { definedOutsideWorkspace: true } })

      expect(registry.entry("ActiveSupport::TestCase").status).to eq(:external)
    end

    it "reads the Agent's answer whether its keys arrive as symbols or strings" do
      registry.install(object_ancestors: %w[Object],
                       classes: { "Widget" => { "ancestors" => %w[Widget Foreign Object] } })

      expect(registry.entry("Widget").foreign_ancestors).to eq(["Foreign"])
    end

    it "becomes active on its own once it has installed an answer, which proves an application answered" do
      registry.install(object_ancestors: %w[Object], classes: { "Widget" => { ancestors: %w[Widget Object] } })

      expect(registry).to be_active
    end

    it "keeps answers from earlier installs rather than replacing the table" do
      registry.install(object_ancestors: %w[Object], classes: { "First" => { ancestors: %w[First Object] } })
      registry.install(object_ancestors: %w[Object], classes: { "Second" => { ancestors: %w[Second Object] } })

      expect(registry.entry("First")).not_to be_nil
      expect(registry.entry("Second")).not_to be_nil
    end
  end

  describe "the pending-question queue" do
    it "has nothing pending until something asks" do
      expect(registry.pending?).to be(false)
      expect(registry.drain_pending).to be_empty
    end

    it "collects each distinct name asked about exactly once" do
      registry.request("Widget")
      registry.request("Widget")
      registry.request("Gadget")

      expect(registry.pending?).to be(true)
      expect(registry.drain_pending).to contain_exactly("Widget", "Gadget")
    end

    it "empties on drain, so the same question is not asked twice" do
      registry.request("Widget")
      registry.drain_pending

      expect(registry.pending?).to be(false)
      expect(registry.drain_pending).to be_empty
    end

    # Without this a name the Agent could not answer is re-asked on every
    # keystroke, forever: the entry never arrives, so the engine keeps
    # requesting it.
    it "does not re-queue a name that has already been answered" do
      registry.install(object_ancestors: %w[Object], classes: { "Widget" => nil })
      registry.request("Widget")

      expect(registry.pending?).to be(false)
    end

    # The other half of the same guarantee, and the one #request cannot
    # give: a name asked *before* the answer arrives is still sitting in
    # the queue when it does, and nothing else ever removes it.
    it "clears a name from the queue when its answer arrives" do
      registry.request("Widget")

      registry.install(object_ancestors: %w[Object], classes: { "Widget" => { ancestors: %w[Widget Object] } })

      expect(registry.pending?).to be(false)
      expect(registry.drain_pending).to be_empty
    end

    it "leaves other queued names alone when one name's answer arrives" do
      registry.request("Widget")
      registry.request("Gadget")

      registry.install(object_ancestors: %w[Object], classes: { "Widget" => nil })

      expect(registry.drain_pending).to contain_exactly("Gadget")
    end
  end

  describe "#deactivate!, for an Agent that will not answer again" do
    it "stops the check deferring, while keeping answers already given" do
      registry.install(object_ancestors: %w[Object], classes: { "Known" => nil })

      registry.deactivate!

      expect(registry).not_to be_active
      expect(registry.entry("Known")).not_to be_nil
    end

    # Diagnostics activate on every publish, so a give-up that any
    # keystroke undoes is not a give-up at all.
    it "is not undone by a later activate!" do
      registry.deactivate!

      registry.activate!

      expect(registry).not_to be_active
    end

    # The race the epoch bump exists for: a fetch already in flight when
    # the Agent died lands afterwards, and #install marks the registry
    # active again -- silently restoring the deferral this was meant to end.
    it "is not undone by an answer that was already in flight" do
      in_flight = registry.epoch
      registry.deactivate!

      registry.install(object_ancestors: %w[Object], classes: { "Late" => nil }, epoch: in_flight)

      expect(registry).not_to be_active
      expect(registry.entry("Late")).to be_nil
    end

    it "is cleared by a restart, which is a different application" do
      registry.deactivate!

      registry.reset
      registry.activate!

      expect(registry).to be_active
    end
  end

  describe "#note_failure, the budget for an Agent that stops answering" do
    it "gives up only once the limit is reached" do
      results = (1..described_class::FAILURE_LIMIT).map { registry.note_failure(epoch: registry.epoch) }

      expect(results[0..-2]).to all(be(false))
      expect(results.last).to be(true)
      expect(registry).not_to be_active
    end

    # A restart is a different application, and it must start with a clean
    # budget. Kept outside the registry this count survived #reset, so the
    # first timeout against a fresh, healthy Agent re-tripped the limit --
    # and three ordinary `Gemfile.lock` saves disabled the check for good.
    it "starts over after a reset, so a new Agent does not inherit the old one's failures" do
      (described_class::FAILURE_LIMIT - 1).times { registry.note_failure(epoch: registry.epoch) }

      registry.reset

      expect(registry.note_failure(epoch: registry.epoch)).to be(false)
      registry.activate!
      expect(registry).to be_active
    end

    # A retired manager refuses every request, which is evidence that it
    # was replaced, not that the application is unresponsive.
    it "ignores a failure belonging to an Agent that has already been replaced" do
      stale = registry.epoch
      registry.reset

      results = (1..described_class::FAILURE_LIMIT).map { registry.note_failure(epoch: stale) }

      expect(results).to all(be(false))
      registry.activate!
      expect(registry).to be_active
    end

    it "starts over once the Agent answers again" do
      (described_class::FAILURE_LIMIT - 1).times { registry.note_failure(epoch: registry.epoch) }

      registry.install(object_ancestors: %w[Object], classes: { "Widget" => nil }, epoch: registry.epoch)

      expect(registry.note_failure(epoch: registry.epoch)).to be(false)
      expect(registry).to be_active
    end
  end

  describe "the epoch, which tells a stale answer from a current one" do
    it "refuses an install from an epoch the registry has moved past" do
      stale = registry.epoch
      registry.reset

      registry.install(object_ancestors: %w[Object], classes: { "Widget" => { ancestors: %w[Widget Object] } },
                       epoch: stale)

      expect(registry.entry("Widget")).to be_nil
      expect(registry).not_to be_active
    end

    # The epoch has to be tested *inside* the lock that writes, not before
    # it. Tested outside, a #reset landing between the test and the write
    # lets an answer about the dead process through, and answered names
    # are never re-asked, so it would stay for the session.
    #
    # Driven deterministically: `object_ancestors` is normalised before the
    # lock is taken, so an entry whose #to_s blocks holds the caller in
    # exactly the window between "epoch tested outside" and "lock taken".
    # A reset completes in that window. Inside-the-lock, the test has not
    # happened yet and sees the new epoch; outside-the-lock, it already
    # passed and the write lands anyway.
    it "refuses an answer when a reset lands between reading the epoch and writing" do
      reached = Queue.new
      proceed = Queue.new
      slow_name = Object.new
      slow_name.define_singleton_method(:to_s) do
        reached << :in_window
        proceed.pop
        "Object"
      end
      stale = registry.epoch

      writer = Thread.new do
        registry.install(object_ancestors: [slow_name], classes: { "Widget" => { ancestors: %w[Widget Object] } },
                         epoch: stale)
      end
      reached.pop
      registry.reset
      proceed << :go
      writer.join(5)

      expect(registry.entry("Widget")).to be_nil
    end

    it "accepts an install from the current epoch" do
      current = registry.epoch

      registry.install(object_ancestors: %w[Object], classes: { "Widget" => { ancestors: %w[Widget Object] } },
                       epoch: current)

      expect(registry.entry("Widget")).not_to be_nil
    end
  end

  describe "#reset" do
    # Ancestors cannot change without a restart -- so a restart must drop
    # them. A reloaded application may genuinely have different ones.
    it "forgets every answer and goes inactive, so a restarted Agent is re-asked" do
      registry.install(object_ancestors: %w[Object], classes: { "Widget" => { ancestors: %w[Widget Object] } })

      registry.reset

      expect(registry.entry("Widget")).to be_nil
      expect(registry).not_to be_active
    end
  end

end
