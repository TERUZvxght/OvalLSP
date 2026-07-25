# frozen_string_literal: true

Ovallsp::Plugins.register_static("ovallsp-slow") do |_context|
  sleep 60
end
