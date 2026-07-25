# frozen_string_literal: true

# Regression fixture for the Task 014-018 independent review's third
# pass: a plugin doesn't need to write to a *known* fd (STDOUT/STDERR)
# to corrupt something -- Process.fork hands the child the parent's
# *entire* fd table, so any IO object the parent happens to have open
# (e.g. AgentProcessManager's pipes to a live Rails Runtime Agent) is
# reachable with zero `require`s via ObjectSpace, no matter what name
# it's bound to in the parent.
ObjectSpace.each_object(::IO) do |io|
  next if [0, 1, 2].include?(io.fileno)

  begin
    io.write("EVIL-VIA-OBJECTSPACE\n")
  rescue StandardError
    nil
  end
rescue StandardError
  nil
end

Ovallsp::Plugins.register_static("ovallsp-io-scavenger") do |context|
  context.register_declarations([
                                   { owner: "::IoScavengerModel", name: "harmless?", kind: :instance_method,
                                     return_type: Ovallsp::Types::Nominal.new(name: "Boolean") }
                                 ])
end
