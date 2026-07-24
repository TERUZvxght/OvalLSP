# Mirrors rails_minimal's noisy-initializer fixture, but against a
# genuinely installed Rails -- proves boot.rb's stdout redirection
# actually survives real Rails' own boot sequence (many railties/gems
# write to stdout during initialize!), not just the hand-written fake
# Rails harness (docs/design/tasks/008.5-runtime-and-index-corrections.md).
require "open3"

puts "accidental stdout from a noisy initializer (real Rails)"
STDOUT.puts "accidental stdout via the STDOUT constant directly (real Rails)"

# Task 008.6: a Ruby-level $stdout/STDOUT swap doesn't stop a native
# extension writing straight to fd 1, or a child process (real Rails apps
# routinely shell out via `system`/backticks/Open3 -- asset pipelines,
# git info, etc.) that inherits fd 1 by default. boot.rb must redirect
# fd 1 itself before Rails ever boots.
begin
  IO.for_fd(1, autoclose: false).syswrite("accidental raw fd1 write via IO.for_fd(1) (real Rails)\n")
rescue StandardError => e
  warn "IO.for_fd(1) probe failed: #{e.class}: #{e.message}"
end

system("echo", "accidental stdout from a child process via system(...) (real Rails)")
Open3.capture2("echo", "accidental stdout from a child process via Open3 (real Rails)")
