# frozen_string_literal: true

Rslsp::Plugins.register_static("rslsp-raising") do |_context|
  raise "boom -- this plugin always fails"
end
