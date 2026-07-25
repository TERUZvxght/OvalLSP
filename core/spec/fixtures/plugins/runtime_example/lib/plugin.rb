# frozen_string_literal: true

Ovallsp::Plugins.register_runtime("ovallsp-runtime-example") do |context|
  context.register_snapshot_section("example") { { ok: true } }
  context.register_reload_hook { }
end
