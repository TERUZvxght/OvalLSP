# frozen_string_literal: true

# A hanging test command that is a *wrapper*: it spawns the process doing
# the real work and then waits on it. That is the ordinary shape of every
# common real test command -- `bin/rails test`, `make test`, `npm test`,
# `docker compose run ...`, any shell wrapper -- so Runner's timeout kill
# has to reach the whole process group, not just the pid it spawned.
#
# ARGV[0] is where to record the grandchild's pid, so the spec can assert
# it actually died rather than being orphaned and left running.
grandchild = Process.spawn(RbConfig.ruby, "-e", "sleep 120")
File.write(ARGV.fetch(0), grandchild.to_s)

sleep 120
