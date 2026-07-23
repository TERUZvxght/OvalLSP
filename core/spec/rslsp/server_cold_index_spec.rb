# frozen_string_literal: true

require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe "Rslsp::Server cold index (Task 008.5)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Rslsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def write(root, relative_path, content)
    full = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
    full
  end

  def wait_until(timeout: 3)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield

      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.02
    end
  end

  it "resolves a view opened before its controller has ever been opened (the Task 008 cold-index gap)" do
    Dir.mktmpdir do |root|
      write(root, "app/controllers/users_controller.rb", <<~RUBY)
        class UsersController
          def show
            @user = User.find(params[:id])
          end
        end
      RUBY
      view_path = write(root, "app/views/users/show.html.erb", "<p><%= @user %></p>\n")

      model_registry = Rslsp::Models::ModelRegistry.new
      model_registry.register_from_agent_response(
        "User", { tableName: "users", partial: false, columns: [], associations: [] }
      )

      view_uri = Rslsp::UriUtil.from_path(view_path)
      view_text = File.read(view_path)

      server = Rslsp::Server.new(
        input: StringIO.new(""), output: output, logger: logger,
        model_registry: model_registry, workspace_root: root
      )

      # Simulates what `initialize` triggers, without needing a full
      # protocol round trip for this test: cold-indexing runs on a
      # background thread, so poll rather than assume timing.
      server.send(:start_cold_index)
      controller_symbol = Rslsp::Index::SymbolId.new(kind: :class, owner: nil, name: "::UsersController",
                                                                     discriminator: nil)
      indexed = wait_until { !server.instance_variable_get(:@workspace_index).declarations(controller_symbol).empty? }
      expect(indexed).to be(true), "expected cold indexing to discover UsersController without it ever being opened"

      # The view itself is opened normally — only the *controller* relies
      # on cold indexing, matching the actual Task 008 gap.
      server.instance_variable_get(:@document_store).open(
        uri: view_uri, text: view_text, version: 1, language_id: "erb"
      )

      result = server.send(:explain_type_result,
                            { textDocument: { uri: view_uri }, position: { line: 0, character: 8 } })

      expect(result).to eq(type: "User")
    end
  end

  it "still answers initialize immediately even when the workspace is large enough that cold indexing takes a while" do
    Dir.mktmpdir do |root|
      120.times { |i| write(root, "app/models/generated_#{i}.rb", "class Generated#{i}\nend\n") }

      input =
        frame(jsonrpc: "2.0", id: 1, method: "initialize", params: {}) +
        frame(jsonrpc: "2.0", method: "exit", params: nil)

      server = Rslsp::Server.new(input: StringIO.new(input), output: output, logger: logger, workspace_root: root)

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      server.run
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      expect(elapsed).to be < 1.0
    end
  end
end
