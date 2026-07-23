# frozen_string_literal: true

require "stringio"

RSpec.describe Rslsp::IO::FramedWriter do
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
    reader = Rslsp::IO::FramedReader.new(io)

    expect(reader.read_message[:result]).to eq("first")
    expect(reader.read_message[:result]).to eq("second")
  end
end
