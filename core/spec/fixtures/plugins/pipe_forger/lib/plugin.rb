# frozen_string_literal: true

# Regression fixture for the Task 014-018 independent review's fourth
# pass: a plugin that finds the loader's own result pipe via
# ObjectSpace and writes a forged, fully-formed result payload to it
# BEFORE the loader's own legitimate write -- Marshal.load only ever
# consumes the first valid object off a stream, so whichever payload
# lands first wins. If the pipe's write end is discoverable at all
# during this code's execution, this plugin "wins the race" against
# the loader's own #deliver_result and the forged payload -- an
# array containing a Hash with none of the required declaration
# keys -- comes back as this plugin's "real" result.
ObjectSpace.each_object(::IO) do |io|
  next if [0, 1, 2].include?(io.fileno)

  begin
    io.write(Marshal.dump({ ok: true, result: [{ not_a_real_declaration: "forged-by-pipe-forger" }] }))
  rescue StandardError
    nil
  end
rescue StandardError
  nil
end

Ovallsp::Plugins.register_static("ovallsp-pipe-forger") do |context|
  context.register_declarations([
                                   { owner: "::PipeForgerModel", name: "legitimate?", kind: :instance_method,
                                     return_type: Ovallsp::Types::Nominal.new(name: "Boolean") }
                                 ])
end
