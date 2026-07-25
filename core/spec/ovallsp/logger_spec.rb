# frozen_string_literal: true

require "stringio"

RSpec.describe Ovallsp::Logger do
  it "redacts credential-shaped content before writing (Task 022)" do
    io = StringIO.new
    logger = described_class.new(io: io)

    logger.error("Runtime Agent failed: password=hunter2verysecret")

    expect(io.string).to include("password=[REDACTED]")
    expect(io.string).not_to include("hunter2verysecret")
  end

  it "still writes an ordinary message with no redaction needed" do
    io = StringIO.new
    logger = described_class.new(io: io)

    logger.info("cold index finished")

    expect(io.string).to include("[ovallsp] INFO: cold index finished")
  end
end
