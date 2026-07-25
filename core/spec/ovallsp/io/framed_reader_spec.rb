# frozen_string_literal: true

RSpec.describe Ovallsp::IO::FramedReader do
  # Simulates a real stdio pipe: each #read call may return fewer bytes
  # than requested, split at arbitrary byte boundaries (including inside
  # multi-byte UTF-8 sequences).
  class ChunkedIO
    def initialize(chunks)
      @chunks = chunks.dup
    end

    def readpartial(_maxlen = nil)
      chunk = @chunks.shift
      raise EOFError if chunk.nil?

      chunk
    end
  end

  def frame_bytes(payload)
    json = JSON.generate(payload)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}".b
  end

  def chunk_bytes(bytes, size)
    bytes.bytes.each_slice(size).map { |slice| slice.pack("C*") }
  end

  it "reassembles a message delivered across many small partial reads" do
    payload = { jsonrpc: "2.0", id: 1, method: "initialize", params: {} }
    chunks = chunk_bytes(frame_bytes(payload), 3)

    reader = described_class.new(ChunkedIO.new(chunks))

    expect(reader.read_message).to eq(payload)
  end

  it "handles reads split in the middle of a multi-byte UTF-8 character" do
    payload = { jsonrpc: "2.0", id: 2, method: "textDocument/hover", params: { text: "こんにちは😀" } }
    chunks = chunk_bytes(frame_bytes(payload), 1)

    reader = described_class.new(ChunkedIO.new(chunks))

    expect(reader.read_message).to eq(payload)
  end

  it "reads consecutive messages from a continuous stream" do
    first = { jsonrpc: "2.0", id: 1, method: "a", params: {} }
    second = { jsonrpc: "2.0", id: 2, method: "b", params: {} }
    chunks = chunk_bytes(frame_bytes(first) + frame_bytes(second), 5)

    reader = described_class.new(ChunkedIO.new(chunks))

    expect(reader.read_message).to eq(first)
    expect(reader.read_message).to eq(second)
  end

  it "raises EOF when the stream ends before a full message arrives" do
    payload = { jsonrpc: "2.0", id: 1, method: "initialize", params: {} }
    truncated = frame_bytes(payload).byteslice(0, 10)

    reader = described_class.new(ChunkedIO.new([truncated]))

    expect { reader.read_message }.to raise_error(described_class::EOF)
  end
end
