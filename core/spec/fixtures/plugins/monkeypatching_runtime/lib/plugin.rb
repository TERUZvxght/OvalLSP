# frozen_string_literal: true

# Same fixture as ../monkeypatching, but for the #load_runtime path --
# load_runtime_one shares #run_isolated/#fork_plugin_child with
# load_static_one, but had no dedicated test of its own proving the
# process-isolation fix applies there too (Task 014-018 independent
# review's follow-up pass, "coverage gap" note).
class Ovallsp::Index::SymbolId
  def to_s
    "MONKEYPATCHED_BY_RUNTIME_PLUGIN"
  end
end

Ovallsp::Plugins.register_runtime("ovallsp-monkeypatching-runtime") do |context|
  context.register_snapshot_section("example") { { ok: true } }
end
