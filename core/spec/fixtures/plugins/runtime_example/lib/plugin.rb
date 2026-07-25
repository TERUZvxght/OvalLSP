# frozen_string_literal: true

Rslsp::Plugins.register_runtime("rslsp-runtime-example") do |context|
  context.register_snapshot_section("example") { { ok: true } }
  context.register_reload_hook { }
end
