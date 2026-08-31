# frozen_string_literal: true

require "tmpdir"
require "fileutils"

# 024.275: `server_workspace_identity_spec.rb`'s workspace-root examples
# failed in one full-suite run and have not failed since. The entry's
# instruction -- *the next run that reproduces it captures the failure
# message before anything else* -- has stood unexecuted for two releases,
# because it addresses whoever happens to be watching and nobody is.
#
# So the capture is built into the assertion instead. Every one of those
# examples fails with this attached, which makes a reproduction
# self-recording: the two readings the entry says have never been told
# apart -- `File.directory?` answering false for a symlink whose target
# still exists, and the root simply never being adopted -- are different
# lines of this report, and so is the load hypothesis the entry's own
# 0.2.18 addition shares with it.
#
# `server_identity_report_spec.rb` pins what it says, because a report
# that quietly stopped naming one of them would leave the next
# reproduction as uninformative as the last.
module WorkspaceIdentityReport
  module_function

  def for(expected:, got:, paths:)
    lines = ["expected=#{expected.inspect}", "got=#{got.inspect}", "load=#{load_average}"]
    paths.each { |label, path| lines << "  #{label}: #{describe(path)}" }
    "\n#{lines.join("\n")}"
  end

  def describe(path)
    return "#{path} (nil)" if path.nil?

    symlink = File.symlink?(path)
    exists = File.exist?(path)
    parts = ["#{path}", "exists=#{exists}", "directory=#{File.directory?(path)}", "symlink=#{symlink}"]
    if symlink
      target = File.readlink(path)
      parts << "-> #{target}"
      # The distinction the entry is waiting on: a symlink that is still
      # a symlink but whose target has gone answers false to
      # `File.directory?` while looking present to a casual reading.
      parts << "dangling" unless exists
    end
    parts.join(" ")
  end

  # One-minute load average, or a note that this platform does not carry
  # one. Reported rather than raised: a report that fails is a report
  # that hides the failure it was attached to.
  def load_average
    File.read("/proc/loadavg").split.first
  rescue SystemCallError
    # Contained: not Linux. `uptime` is the portable-enough fallback and
    # its absence is reported as an unknown load, never as a number.
    out = begin
      `uptime 2>/dev/null`
    rescue SystemCallError
      ""
    end
    out[/load averages?:\s*([\d.]+)/, 1] || "unknown"
  end
end
