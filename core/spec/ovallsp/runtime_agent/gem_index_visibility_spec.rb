# frozen_string_literal: true

require "stringio"
require "logger"

# **The producer half of the private/protected fix, which nothing else
# pins.** 0.3.0's review found that `mod.instance_methods(false)` omits
# private and protected methods, so a subclass calling a gem's own
# inherited private helper was reported as calling a method that does not
# exist. The fix sends all three sets; `GemIndex` and `MethodResolver`
# have examples that consume them, and until this file nothing asserted
# the Agent ever *sends* them.
#
# The verify stage of that review is what found the gap: deleting both
# lines from `#module_answer` left 727 examples green. If the fields are
# ever dropped again, `process_action` on an ActionController subclass
# goes back to being reported undefined with a fully green suite.
#
# Ruby, so the expectation is not a belief about what the three sets
# contain:
#
#   $ ruby -e '
#   class VisProbe
#     def pub; end
#     private def helper; end
#     protected def compare; end
#   end
#   p VisProbe.instance_methods(false).sort
#   p VisProbe.private_instance_methods(false).sort
#   p VisProbe.protected_instance_methods(false).sort
#   '
#   # => [:compare, :pub]
#   # => [:helper]
#   # => [:compare]
#   # ruby 3.4.10
# **One name, six modules, and the index kept the empty one.**
#
# Rails' per-model relation classes override `.name` to answer their
# parent's, so after `eager_load!` six Module objects report
# `ActiveRecord::Relation`. `GemIndex` keys by name and the last
# writer wins, and the survivor on this repository's fixture had no
# methods of its own -- `knows? == true` with an empty surface, the
# one state `gem_index.rb`'s header says must not exist.
#
# Taken from Ruby, because the expectation is about what `.name` does
# and not about what this engine does:
#
#     $ ruby -e '
#     class ShadowProbeReal; end
#     class ShadowProbeCopy < ShadowProbeReal
#       def self.name = "ShadowProbeReal"
#     end
#     p [ShadowProbeCopy.name, Object.const_get("ShadowProbeReal").equal?(ShadowProbeCopy)]
#     '
#     # => ["ShadowProbeReal", false]
#     # ruby 3.4.10
#
# `024.305`.
RSpec.describe "the Agent's module walk and a name two modules answer to" do
  let(:agent) do
    Ovallsp::RuntimeAgent::Agent.new(input: StringIO.new(""), output: StringIO.new,
                                     logger: Logger.new(File::NULL))
  rescue ArgumentError
    Ovallsp::RuntimeAgent::Agent.allocate
  end

  it "keeps the module a name resolves to, not a copy that answers to it" do
    stub_const("ShadowProbeReal", Class.new { def self.name = "ShadowProbeReal" })
    copy = Class.new(ShadowProbeReal) { def self.name = "ShadowProbeReal" }

    expect(agent.send(:own_constant?, ShadowProbeReal, "ShadowProbeReal")).to be(true)
    expect(agent.send(:own_constant?, copy, "ShadowProbeReal")).to be(false)
  end

  # The control: a name nothing defines is not kept either, and the
  # test does not raise on it. `safely` is what makes that true, and
  # without it the walk would die on the first such module.
  it "declines a name the process cannot resolve, rather than raising" do
    anonymous = Class.new { def self.name = "DefinitelyNotAConstantZZ" }

    expect { agent.send(:own_constant?, anonymous, "DefinitelyNotAConstantZZ") }.not_to raise_error
    expect(agent.send(:own_constant?, anonymous, "DefinitelyNotAConstantZZ")).to be(false)
  end
end

RSpec.describe Ovallsp::RuntimeAgent::Agent do
  let(:output) { StringIO.new }
  let(:logger) { Logger.new(File::NULL) }

  describe "#module_answer's visibility split" do
    # A module whose source location the walk will attribute to a gem, so
    # `#gem_index_result` reports it at all.
    let(:probe) do
      Module.new do
        def self.name = "GemIndexVisibilityProbe"

        def pub; end
        private def helper; end
        protected def compare; end
      end
    end

    subject(:answer) do
      agent = described_class.new(input: StringIO.new(""), output: output, logger: logger, root: "/app")
      agent.send(:module_answer, probe, "GemIndexVisibilityProbe")
    end

    it "sends the public instance methods" do
      expect(answer[:instanceMethods]).to include("pub")
    end

    it "sends the private ones, which `instance_methods(false)` omits" do
      expect(answer[:privateInstanceMethods]).to include("helper")
    end

    it "sends the protected ones too" do
      expect(answer[:protectedInstanceMethods]).to include("compare")
    end

    # **The control, and it is what makes the three above mean
    # something.** If every set were simply `instance_methods`, those
    # would all pass while the distinction the explicit-receiver
    # completion filter depends on was gone.
    #
    # `instanceMethods` legitimately carries `compare`: Ruby's
    # `instance_methods(false)` returns public *and* protected, which is
    # what the session above shows. What must never appear there is the
    # private one.
    it "keeps private out of the public set, which is the split that matters" do
      expect(answer[:instanceMethods]).not_to include("helper")
      expect(answer[:privateInstanceMethods]).not_to include("pub", "compare")
      expect(answer[:protectedInstanceMethods]).not_to include("pub", "helper")
    end
  end
end
