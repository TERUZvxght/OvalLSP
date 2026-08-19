# frozen_string_literal: true

require "stringio"

# Every malformed frame took the whole process with it, with a raw Ruby
# backtrace on stderr and the client's next request unanswered. Ten
# inputs, all after a valid `initialize`: `Content-Length: 0`, `-5`,
# `abc`, `5.5`, a missing header, a truncated frame, a malformed body.
# `Server#run` rescues only `FramedReader::EOF`, so `JSON::ParserError`,
# `ArgumentError`, `NoMethodError` and `ProtocolError` all escaped.
#
# Only a client can send these, so a hostile workspace cannot reach it —
# but a reconnect, a proxy, or one stray byte on stdin ends the session,
# and what the user sees is a backtrace rather than a diagnosable message.
#
# `Integer()` also accepted `0x10` as 16 and `1_0` as 10, which the LSP
# framing grammar does not.
RSpec.describe Ovallsp::IO::FramedReader do
  def read(raw)
    described_class.new(StringIO.new(raw)).read_message
  end

  def frame(length, body)
    "Content-Length: #{length}\r\n\r\n#{body}"
  end

  it "refuses a length that is not a plain decimal number" do
    ["abc", "5.5", "0x10", "1_0", "-5", " "].each do |length|
      expect { read(frame(length, "{}")) }.to raise_error(described_class::ProtocolError, /Content-Length/)
    end
  end

  it "refuses a frame with no Content-Length at all" do
    expect { read("\r\n{}") }.to raise_error(described_class::ProtocolError, /Content-Length/)
  end

  it "refuses a body that is not JSON, naming the frame rather than the parser" do
    expect { read(frame(3, "not")) }.to raise_error(described_class::ProtocolError, /JSON/)
  end

  it "refuses an empty body" do
    expect { read(frame(0, "")) }.to raise_error(described_class::ProtocolError, /JSON/)
  end

  # A truncated frame is the one shape that is not malformed: more bytes
  # may still arrive on a live pipe, and the stream simply ended.
  it "reports a truncated frame as end of input" do
    expect { read(frame(20, "{}")) }.to raise_error(described_class::EOF)
  end

  it "still reads a well-formed frame" do
    expect(read(frame(2, "{}"))).to eq({})
  end

  # And the server keeps serving. A malformed frame carries no id, so
  # there is nobody to answer -- what matters is that the session
  # survives it and the request after it is answered.
  describe "the server reading one" do
    it "logs it and goes on answering" do
      logger = instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil)
      output = StringIO.new
      good = ->(hash) { (json = JSON.generate(hash)) && "Content-Length: #{json.bytesize}\r\n\r\n#{json}" }
      input = good.call(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
              "Content-Length: -5\r\n\r\n" +
              good.call(jsonrpc: "2.0", id: 2, method: "shutdown", params: nil) +
              good.call(jsonrpc: "2.0", method: "exit", params: nil)

      status = Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger).run

      expect(output.string).to include(%("id":2))
      expect(status).to eq(0)
      expect(logger).to have_received(:error).with(/Content-Length/)
    end
  end
end

