# frozen_string_literal: true

# A workspace test command that passes, riding along with a *broken*
# harness: Collector#results raises when Harness' at_exit hook calls it.
#
# Stands in for any bug inside Collector#stop/#results reachable only at
# exit time -- a TracePoint disabled from the wrong context, a type
# normalizer choking on one observed value, a mutex still held by a
# thread the suite left behind. Whatever the cause, the workspace's own
# suite passed, and its exit status must still say so: an exception
# escaping an at_exit handler prints a backtrace and forces the process'
# exit status to 1, which would turn this green run red (and a CI build
# with it) purely because Core asked to observe it.
Ovallsp::Observation::Collector.prepend(Module.new do
  def results(**) = raise("simulated broken harness")
end)

puts "workspace suite passed"
