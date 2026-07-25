# frozen_string_literal: true

# Regression fixture for the Task 014-018 independent review's follow-up
# finding: raw writes to STDOUT/$stdout/STDERR at a plugin's top level
# must never reach this process' real fd 1/2 -- in --stdio mode, fd 1
# *is* the live LSP JSON-RPC transport. Uses #syswrite (bypasses Ruby's
# userspace IO buffer entirely) rather than #write/#puts -- a buffered
# write can accidentally look "isolated" purely because
# Loader#fork_plugin_child exits its child via `Kernel.exit!`, which
# skips flushing buffers, and NOT because the fd itself was ever
# actually redirected; #syswrite (or a plugin author setting
# `STDOUT.sync = true`) trivially defeats that accidental cover, so
# this is what an actually-adversarial plugin would use.
STDOUT.syswrite("EVIL-EVIL-LSP-PROTOCOL-CORRUPTION-STDOUT\n")
STDERR.syswrite("EVIL-EVIL-LSP-PROTOCOL-CORRUPTION-STDERR\n")

Rslsp::Plugins.register_static("rslsp-stdout-writer") do |context|
  context.register_declarations([
                                   { owner: "::StdoutWriterModel", name: "harmless?", kind: :instance_method,
                                     return_type: Rslsp::Types::Nominal.new(name: "Boolean") }
                                 ])
end
