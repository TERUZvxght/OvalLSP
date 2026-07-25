# frozen_string_literal: true

Rslsp::Plugins.register_static("rslsp-slow") do |_context|
  sleep 60
end
