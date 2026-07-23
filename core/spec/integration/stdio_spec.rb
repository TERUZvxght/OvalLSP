# frozen_string_literal: true

require "open3"
require "rbconfig"

RSpec.describe "rslsp --stdio (subprocess integration)" do
  let(:core_root) { File.expand_path("../..", __dir__) }
  let(:bin_path) { File.join(core_root, "bin", "rslsp") }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def parse_frames(raw)
    remaining = raw.b
    messages = []

    until remaining.empty?
      header, rest = remaining.split("\r\n\r\n", 2)
      length = header[/Content-Length: (\d+)/, 1].to_i
      body = rest.byteslice(0, length)
      messages << JSON.parse(body, symbolize_names: true)
      remaining = rest.byteslice(length..) || "".b
    end

    messages
  end

  it "writes only well-formed protocol frames to stdout and exits 0 after shutdown" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      frame(jsonrpc: "2.0", method: "initialized", params: {}) +
      frame(jsonrpc: "2.0", id: 2, method: "shutdown", params: nil) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    stdout_str, stderr_str, status = Open3.capture3(
      RbConfig.ruby, "-I", File.join(core_root, "lib"), bin_path, "--stdio",
      stdin_data: input
    )

    expect(status.exitstatus).to eq(0)
    expect(stderr_str).not_to include("Content-Length")

    messages = parse_frames(stdout_str)
    expect(messages.map { |m| m[:id] }.compact).to eq([1, 2])
  end

  it "leaves no zombie process behind after exit" do
    input =
      frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
      frame(jsonrpc: "2.0", id: 2, method: "shutdown", params: nil) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    _stdout_str, _stderr_str, status = Open3.capture3(
      RbConfig.ruby, "-I", File.join(core_root, "lib"), bin_path, "--stdio",
      stdin_data: input
    )

    expect(status).to be_exited
  end
end
