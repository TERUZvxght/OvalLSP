# frozen_string_literal: true

require_relative "utf8"
require "rspec/core/formatters/json_formatter"
require_relative "../core/lib/ovallsp/redactor"

# Never persist a raw formatter/log: failures can interpolate user paths
# and credentials. Source locations remain relative to core/.
class TestReportFormatter < RSpec::Core::Formatters::JsonFormatter
  RSpec::Core::Formatters.register self, :close

  def close(notification)
    output_hash[:run_id] = ENV.fetch("OVALLSP_TEST_RUN_ID")
    output_hash[:pid] = Process.pid
    output_hash[:errors_outside_of_examples_count] = RSpec.world.non_example_failure ? 1 : 0
    clean = sanitize(output_hash)
    output.write(JSON.generate(clean))
  end

  def sanitize(value)
    case value
    when Hash then value.transform_values { |item| sanitize(item) }
    when Array then value.map { |item| sanitize(item) }
    when String
      text = value.gsub(Dir.pwd + "/", "./")
      Ovallsp::Redactor.redact(text).gsub(%r{(?:/Users/|/home/)[^/\s"']+}, "~")
    else value
    end
  end
end
