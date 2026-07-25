# frozen_string_literal: true

# Regression fixture for the Task 014-018 independent review's CRITICAL
# finding: this reopens a real Core class and monkeypatches one of its
# methods at the plugin file's *top level*, entirely independent of
# anything it does with the StaticContext object it's handed. Under
# process-based isolation (Plugins::Loader), this patch only ever takes
# effect inside the short-lived forked child -- the parent Core process
# must come back out completely unaffected.
class Ovallsp::Index::SymbolId
  def to_s
    "MONKEYPATCHED_BY_PLUGIN"
  end
end

Ovallsp::Plugins.register_static("ovallsp-monkeypatching") do |context|
  context.register_declarations([
                                   { owner: "::MonkeypatchModel", name: "patched?", kind: :instance_method,
                                     return_type: Ovallsp::Types::Nominal.new(name: "Boolean") }
                                 ])
end
