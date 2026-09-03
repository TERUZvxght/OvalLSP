# frozen_string_literal: true

require "rbconfig"

# A `PATH` that carries `ruby`, `git` and `bundle` and **no `gitleaks`**.
#
# `gitleaks` is installed on the machine this was written on and on none
# of the CI runners. Two examples in `release_flow_spec` asserted a
# listing `gate` prints and then let `gate` run on into the secret scan,
# so here they passed and on a runner they died with `Errno::ENOENT` --
# a spec whose result was decided by what the environment happened to
# supply. Every local signal said green for the same reason: preflight,
# the drives and the mutation manifest all ran where the tool exists.
#
# So an example that reaches a step needing an external tool says which
# tools it is entitled to, rather than inheriting the machine's. That is
# the same repair as `024.148`'s -- a check that cannot see what it
# checks reports what a working one reports -- arriving from the other
# side: an example that *could* not run reported what a passing one
# reports.
#
# Emptying `PATH` instead would take `git` and `ruby` with it, and the
# example would then pass on a `gate` that refused for want of `git`.
# Shims rather than symlinks: a symlinked interpreter resolves its own
# prefix from the link on some builds and from the target on others, and
# none of this is about that.
module WithoutGitleaks
  SHIMMED = %w[ruby bundle git].freeze

  def path_without_gitleaks
    dir = example_tmpdir("without-gitleaks")
    SHIMMED.each do |tool|
      real = tool == "ruby" ? RbConfig.ruby : executable_on_path(tool)
      next if real.nil?

      File.write(File.join(dir, tool), "#!/bin/sh\nexec #{real} \"$@\"\n")
      File.chmod(0o755, File.join(dir, tool))
    end
    dir
  end

  # `nil` for a tool this machine does not have: `bundle` is not needed
  # by every caller, and refusing to build the directory over it would
  # make this helper the thing that decides whether an example runs.
  # `git` and `ruby` are asked for by name where they are required.
  def executable_on_path(tool)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
       .map { |dir| File.join(dir, tool) }
       .find { |candidate| File.executable?(candidate) }
  end

  # For a caller that cannot proceed without one.
  def executable_on_path!(tool)
    executable_on_path(tool) or raise "#{tool} is not on PATH, and this example needs it to be"
  end
end

RSpec.configure { |config| config.include(WithoutGitleaks) }
