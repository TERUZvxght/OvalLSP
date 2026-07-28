# frozen_string_literal: true

# Establish a durable ownership boundary before any OvalLSP code can
# launch the Rails Runtime Agent or an observation runner. The VS Code
# extension tracks this session and can terminate every surviving process
# in it even if the Core process exits first.
Process.setsid

core_script = ARGV.shift or abort("missing OvalLSP Core script")
load core_script
