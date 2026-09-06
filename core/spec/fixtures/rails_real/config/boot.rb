%w[RAILS_ENV RACK_ENV].each { |key| ENV[key] = "development" }
# This fixture recreates tables. Caller database URLs must never redirect
# its schema outside the disposable application's own database.
%w[DATABASE_URL PRIMARY_DATABASE_URL].each do |key|
  ENV[key] = "sqlite3:#{File.expand_path('../db/rails_real.sqlite3', __dir__)}"
end

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup"
