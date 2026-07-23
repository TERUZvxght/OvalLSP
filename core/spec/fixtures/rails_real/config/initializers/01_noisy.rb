# Mirrors rails_minimal's noisy-initializer fixture, but against a
# genuinely installed Rails -- proves boot.rb's stdout redirection
# actually survives real Rails' own boot sequence (many railties/gems
# write to stdout during initialize!), not just the hand-written fake
# Rails harness (docs/design/tasks/008.5-runtime-and-index-corrections.md).
puts "accidental stdout from a noisy initializer (real Rails)"
STDOUT.puts "accidental stdout via the STDOUT constant directly (real Rails)"
