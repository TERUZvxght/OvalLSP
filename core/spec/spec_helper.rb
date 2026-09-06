# frozen_string_literal: true

require_relative "test_hygiene"
require_relative "../lib/ovallsp"

Dir[File.join(__dir__, "support", "*.rb")].sort.each { |f| require f }
