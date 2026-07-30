# frozen_string_literal: true

require "stringio"

RSpec.describe Ovallsp::IO::FramedWriter do
  it "sets Content-Length to the byte size of the JSON body, not its character count" do
    io = StringIO.new
    writer = described_class.new(io)

    writer.write_message(jsonrpc: "2.0", id: 1, result: { message: "こんにちは😀" })

    io.rewind
    raw = io.read.b
    header, rest = raw.split("\r\n\r\n", 2)
    declared_length = header[/Content-Length: (\d+)/, 1].to_i

    expect(declared_length).to eq(rest.bytesize)
    expect(declared_length).not_to eq(rest.force_encoding(Encoding::UTF_8).length) # char count < byte count here
    expect(JSON.parse(rest, symbolize_names: true)[:result][:message]).to eq("こんにちは😀")
  end

  it "writes back-to-back messages that a reader can split apart again" do
    io = StringIO.new
    writer = described_class.new(io)

    writer.write_message(jsonrpc: "2.0", id: 1, result: "first")
    writer.write_message(jsonrpc: "2.0", id: 2, result: "second")

    io.rewind
    reader = Ovallsp::IO::FramedReader.new(io)

    expect(reader.read_message[:result]).to eq("first")
    expect(reader.read_message[:result]).to eq("second")
  end
end

# Background threads publish diagnostics too (the Runtime Agent becoming
# ready, and from 0.2.0 the workspace-wide pass), so two writers can be
# inside this at once. A header and its body are two separate writes: let
# them interleave and the stream carries a length that belongs to someone
# else's message, which is not a recoverable protocol error -- the client
# resynchronises by guessing.
RSpec.describe "Ovallsp::IO::FramedWriter under concurrent writers" do
  # A StringIO will not reproduce this: the GVL rarely switches between
  # writes. This yields around every write, which is what a real pipe
  # does whenever one blocks.
  YieldingOutput = Class.new do
    def initialize = @buffer = +""
    def string = @buffer
    def flush = nil

    def write(chunk)
      Thread.pass
      @buffer << chunk
      Thread.pass
    end
  end

  # A frame that reaches the stream as two writes can be interrupted
  # between them -- by another thread, or by `Thread#kill` at shutdown,
  # which no mutex defends against. A `Content-Length` with no message
  # after it is the one framing error a client cannot recover from.
  it "puts a frame on the stream in a single write" do
    output = YieldingOutput.new
    writes = []
    allow(output).to receive(:write).and_wrap_original do |original, chunk|
      writes << chunk
      original.call(chunk)
    end

    Ovallsp::IO::FramedWriter.new(output).write_message(jsonrpc: "2.0", method: "note", params: {})

    expect(writes.size).to eq(1)
  end

  it "never interleaves one message's header with another's body" do
    output = YieldingOutput.new
    writer = Ovallsp::IO::FramedWriter.new(output)

    threads = 8.times.map do |i|
      Thread.new do
        20.times { |j| writer.write_message(jsonrpc: "2.0", method: "note", params: { thread: i, seq: j }) }
      end
    end
    threads.each(&:join)

    reader = Ovallsp::IO::FramedReader.new(StringIO.new(output.string))
    messages = []
    begin
      loop { messages << reader.read_message }
    rescue Ovallsp::IO::FramedReader::EOF
      nil
    end

    expect(messages.size).to eq(160)
    expect(messages.map { |m| m[:params][:thread] }.uniq.sort).to eq((0..7).to_a)
  end
end
