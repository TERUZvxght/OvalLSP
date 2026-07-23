require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module RailsReal
  class Application < Rails::Application
    config.load_defaults 8.1
    config.eager_load = false
    config.cache_classes = false
    config.enable_reloading = true
    config.autoload_lib(ignore: %w[assets tasks])
    config.logger = Logger.new(IO::NULL)
    config.active_record.maintain_test_schema = false
  end
end
