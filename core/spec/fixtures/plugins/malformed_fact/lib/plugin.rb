# frozen_string_literal: true

# Missing required :owner/:kind keys -- StaticContext#register_declarations
# raises KeyError, exercising "malformed contribution validation" /
# Loader's own per-plugin isolation (the raise never escapes past
# Loader#run_isolated).
Rslsp::Plugins.register_static("rslsp-malformed-fact") do |context|
  context.register_declarations([{ name: "oops" }])
end
