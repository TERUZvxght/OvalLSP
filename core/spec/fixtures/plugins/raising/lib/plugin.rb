# frozen_string_literal: true

Ovallsp::Plugins.register_static("ovallsp-raising") do |_context|
  raise "boom -- this plugin always fails"
end
