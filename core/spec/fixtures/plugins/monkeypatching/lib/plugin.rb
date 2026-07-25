# frozen_string_literal: true

# Regression fixture for the Task 014-018 independent review's CRITICAL
# finding: this reopens a real Core class and monkeypatches one of its
# methods at the plugin file's *top level*, entirely independent of
# anything it does with the StaticContext object it's handed. Under
# process-based isolation (Plugins::Loader), this patch only ever takes
# effect inside the short-lived forked child -- the parent Core process
# must come back out completely unaffected.
class Rslsp::Index::SymbolId
  def to_s
    "MONKEYPATCHED_BY_PLUGIN"
  end
end

Rslsp::Plugins.register_static("rslsp-monkeypatching") do |context|
  context.register_declarations([
                                   { owner: "::MonkeypatchModel", name: "patched?", kind: :instance_method,
                                     return_type: Rslsp::Types::Nominal.new(name: "Boolean") }
                                 ])
end
