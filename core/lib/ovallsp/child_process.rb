# frozen_string_literal: true

module Ovallsp
  # The primitives every subprocess boundary in Core needs when it has
  # decided a child must die: signal it *totally* (never raising, and
  # reporting whether the signal actually landed), reap it *boundedly*
  # (never blocking indefinitely, never leaving a permanent zombie), and
  # let go of the plumbing around it -- its pipe ends (#close_quietly,
  # round 15) and its pump threads (#join_quietly, round 16) -- without
  # either of those becoming the thing that aborts the teardown.
  #
  # One property unites all four: none of them may raise. Every call site
  # is a cleanup path, most of them literally inside an `ensure`, where an
  # escaping exception does not merely fail its own step -- it *replaces*
  # the exception already propagating and skips every step after it.
  #
  # Extracted after an independent review (round 12) of Task 022.2 found
  # the same defect a third time, in a third hand-rolled copy. Round 11
  # fixed Observation::Runner: its kill retried the bare pid only on
  # Errno::ESRCH -- the one failure meaning "already gone", i.e. the one
  # needing no retry -- so any *other* signal failure left the child
  # completely unsignalled, and an unbounded `Process.waitpid(pid)` then
  # blocked on it forever. Because #run is called synchronously on the LSP
  # transport thread, that turned an observation *timeout* into a
  # permanent editor hang. Plugins::Loader#kill_child had a byte-for-byte
  # equivalent pair of mistakes (rescuing only ESRCH/ECHILD around the
  # signal, then an unbounded `Process.waitpid`), on the `initialize`
  # request handler's own thread, and round 11's own note in that file
  # asserted the hang could not happen there. AgentProcessManager was
  # bounded already, but escalated through a non-total `Process.kill` and
  # abandoned an unreaped child on giving up.
  #
  # Three independent reimplementations of one three-line contract, two of
  # them wrong, is the architecture allowing the class of bug rather than
  # any one site being careless -- so the contract lives here once and
  # every site calls it (docs/CODE_DISCIPLINE.md: "fix the underlying design, not the
  # symptom"; "when a review finding implies the architecture allows this
  # class of bug, fix the architecture").
  module ChildProcess
    # How long #reap is willing to wait for a signalled child to actually
    # die before handing it to Process.detach. Measured on this project's
    # own machine, a SIGKILL'd child is reaped within ~2ms (worst of 20
    # consecutive runs), so this is ~1000x headroom -- and overshooting it
    # is harmless anyway, see #reap.
    DEFAULT_REAP_TIMEOUT_SECONDS = 2

    module_function

    # True only if the signal was genuinely delivered, so a caller can
    # tell "handled" from "nothing was signalled at all" -- and never
    # raises, so it is safe to call from an `ensure` where an escaping
    # exception would *replace* the one currently propagating (silently
    # converting "the user Ctrl-C'd the server" into an unrelated Errno).
    #
    # Every failure is reported the same way on purpose. Wiring a retry or
    # a rescue to Errno::ESRCH specifically is the exact mistake round 11
    # found: ESRCH means the target is already gone, so it is the one
    # failure that needs no follow-up, while EPERM (a group member that
    # changed uid) and anything else killpg(2)/kill(2) can report are
    # precisely the ones that leave a live child unsignalled.
    # `Process.kill(sig, 0)` signals **every process in the caller's own
    # process group**, which is never what a caller here wants: each one
    # holds a specific child's pid. Refused rather than trusted, because
    # trusting every call site to be right is the arrangement that let a
    # spec's fabricated `"/x"` delete `/Applications` -- the lesson
    # recorded in docs/CODE_DISCIPLINE.md is to contain the dangerous operation where it
    # happens. A spec fabricating `0` as a plausible pid is what found
    # this one, by killing the rspec process.
    #
    # Negative stays allowed: `#signal_group` passes `-pid` deliberately,
    # and that names a group rather than "whichever group I am in".
    def signal(target, name = "KILL")
      return false if target.to_i.zero?

      Process.kill(name, target)
      true
    rescue StandardError
      false
    end

    # Closes an IO (or nil, or an already-closed one) without ever raising
    # -- the pipe-side counterpart to #signal's totality, and for the same
    # reason: every caller here closes from inside an `ensure`, where an
    # IOError/Errno escaping would *replace* the exception currently
    # propagating (silently converting "the user Ctrl-C'd the server" into
    # an unrelated Errno, or masking the Errno::ENOENT that explains why
    # the spawn failed in the first place).
    #
    # Lives here rather than being re-derived per call site for exactly the
    # reason #signal/#reap do: an independent review (round 15) found
    # AgentProcessManager#spawn_process was the one subprocess-owning
    # method in Core still doing every bit of its cleanup on the
    # straight-line success path, leaking all six pipe ends whenever
    # `Process.spawn` failed -- while Plugins::Loader, one file over, had
    # had to grow a private `#close_quietly` of its own in round 14 to
    # close the same hole. One contract, one place.
    def close_quietly(io)
      io.close unless io.nil? || io.closed?
    rescue StandardError
      nil
    end

    # Waits at most `timeout` seconds for a pipe-pump thread belonging to a
    # child process (AgentProcessManager's stderr logger being the one such
    # thread in Core) and never lets that wait be the thing that breaks
    # teardown: `Thread#join` *re-raises whatever exception killed the
    # joined thread, in the joiner*, so a pump thread that died on anything
    # its own rescue list didn't enumerate hands its exception to the
    # teardown path that was merely trying to wind it down. That is the
    # third face of the same contract #signal and #close_quietly already
    # carry -- and it is not hypothetical here: #log_stderr rescues only
    # IOError/Errno::EBADF, while `IO#each_line` can raise Errno::EIO and
    # the logger it calls per line can raise Errno::EPIPE/ENOSPC when the
    # editor closes or fills Core's own stderr.
    #
    # BackgroundTasks#reclaim_batch had already learned exactly this
    # (`safely { t.join(...) }`, so one bad thread can't stop the rest
    # being reclaimed) without the lesson ever reaching this sibling
    # boundary -- the same one-more-hand-rolled-copy shape that produced
    # this module in round 12 (see the module docs).
    #
    # Returns true if the thread is finished by the time this returns --
    # including finished *abnormally*, which is what the rescue below
    # means: `join` raising is Ruby's way of reporting that the thread
    # terminated on an exception, so it answers the same question as a
    # normal return, not the opposite one. False means only "still running
    # when `timeout` ran out" (or no thread at all). Never raises.
    def join_quietly(thread, timeout)
      return false if thread.nil?

      !thread.join(timeout).nil?
    rescue StandardError
      true
    end

    # Signals the child's whole process group (negative pid -- the group a
    # `pgroup: true` spawn created, whose id is the child's own pid), so a
    # wrapper's forked work dies with it, falling back to the bare pid
    # whenever that group signal did not actually land.
    #
    # Two preconditions the caller owns, both about `pid` naming what the
    # caller thinks it names:
    #
    # 1. The pid must still be unreaped. A reaped pid is free for the
    #    kernel to reuse, and `-pid` would then name an unrelated process
    #    group -- see Observation::Runner#spawn_and_collect's `settled`,
    #    which exists for exactly this.
    # 2. The pid must be a real child pid, i.e. a `Process.spawn`/
    #    `Process.fork` return value in the *parent*. `kill(2)` reads 0
    #    and -1 as targets rather than pids ("the caller's own process
    #    group" and "every process this uid may signal"), so a 0 would
    #    make this SIGKILL Core itself. Nothing here defends against it,
    #    because nothing can produce it: in the parent, fork(2)/
    #    posix_spawn(3) either yield a pid >= 1 or fail, and Ruby raises
    #    SystemCallError on failure rather than returning a sentinel --
    #    0 is the *child's* return from fork, which never reaches here.
    def signal_group(pid, name = "KILL")
      signal(-pid, name) || signal(pid, name)
    end

    # Waits for `pid` for at most `timeout` seconds and then gives up --
    # never an unbounded `Process.waitpid(pid)`. Every caller here runs on
    # a thread that must stay responsive (the LSP transport thread, or a
    # timeout path whose entire purpose is to bound how long something
    # takes), so blocking indefinitely does not merely strand a zombie: it
    # converts the timeout mechanism itself into a hang. A child can
    # outlive SIGKILL for reasons no caller can rule out -- the signal
    # never landed at all (see #signal), or the process sits in an
    # uninterruptible kernel wait, e.g. a test suite blocked on a wedged
    # NFS/FUSE mount, which SIGKILL cannot preempt.
    #
    # Giving up hands the pid to Process.detach rather than abandoning it:
    # that reaps in a background thread whenever the child finally does
    # die, so declining to block here still cannot leave a permanent
    # zombie for the rest of the session.
    #
    # Overshooting `timeout` on a loaded machine is deliberately harmless
    # rather than merely unlikely. `Process.detach` on a pid that dies a
    # moment later reaps it normally; on a pid that was *already* reaped
    # it swallows the resulting Errno::ECHILD and its Process::Waiter
    # thread simply exits (verified against this machine's Ruby, not
    # assumed); and a detached pid racing another waiter leaves exactly
    # one winner, the loser seeing ECHILD, which every caller here already
    # rescues. The waiter thread waits on one specific pid, so it can
    # never reap anything else's child either.
    #
    # Returns true if the child was reaped here, false if it had to be
    # detached. Never raises.
    def reap(pid, timeout: DEFAULT_REAP_TIMEOUT_SECONDS, logger: nil)
      # `Process.waitpid(0, …)` waits on any child in the caller's own
      # process group. See #signal for why that is refused here rather
      # than guarded at each caller.
      return false if pid.to_i.zero?

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        return true if Process.waitpid(pid, Process::WNOHANG)
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 0.01
      end

      logger&.error("child process #{pid} outlived its kill signal -- detaching it rather than blocking on it")
      Process.detach(pid)
      false
    rescue StandardError
      # Errno::ECHILD -- somebody else already reaped it -- is the
      # expected shape here, and means the job is done.
      true
    end
  end
end
