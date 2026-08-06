# frozen_string_literal: true

require "stringio"

# What the `@ivar` environment answers, for every shape a class is
# written in — asserted as a *presence*, from a table.
#
# This exists because the two examples added with the last fix both
# asserted `not_to include`, and an empty answer satisfies both. The fix
# then broke every namespaced class — `module Admin / class Importer`,
# which is what `rails g controller Admin::Articles` emits — and the
# suite stayed green, because nothing anywhere asserted the environment
# is still *populated* for the class the cursor is in.
#
# Two rounds running found a defect in that environment, so per
# `CLAUDE.md`'s same-place rule this is the countermeasure rather than a
# third regression test: the shapes are a table, adding one extends the
# check, and every row asserts the answer arrives.
#
# Four readers share this environment — hover, `@` completion, member
# completion after `@x.`, and `explainType` — so a hole in it is never
# one feature's.
RSpec.describe "Ovallsp::Server instance-variable environment" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def sent_messages
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  # `§` marks the cursor and is removed before the document is opened, so
  # a fixture says where it means rather than being counted by hand.
  def ask(method, source, uri: "file:///probe.rb")
    line = source.lines.index { |l| l.include?("§") }
    character = source.lines[line].index("§")
    input =
      frame(
        jsonrpc: "2.0", method: "textDocument/didOpen",
        params: { textDocument: { uri: uri, text: source.sub("§", ""), version: 1, languageId: "ruby" } }
      ) +
      frame(
        jsonrpc: "2.0", id: 1, method: method,
        params: { textDocument: { uri: uri }, position: { line: line, character: character } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger).run
    sent_messages.first[:result]
  end

  # Each writes `@data = "text"` in one method and reads it in another,
  # and each is a shape real Rails code is written in.
  {
    "a flat class" => <<~RUBY,
      class Importer
        def setup
          @data = "text"
        end

        def run
          @d§
        end
      end
    RUBY
    "a class inside a module" => <<~RUBY,
      module Admin
        class Importer
          def setup
            @data = "text"
          end

          def run
            @d§
          end
        end
      end
    RUBY
    "a compact namespaced class" => <<~RUBY,
      class Admin::Importer
        def setup
          @data = "text"
        end

        def run
          @d§
        end
      end
    RUBY
    "a class nested inside another class" => <<~RUBY,
      class Importer
        class Row
          def setup
            @data = "text"
          end

          def show
            @d§
          end
        end
      end
    RUBY
    "a class reopened further down the file" => <<~RUBY
      class Importer
        def setup
          @data = "text"
        end
      end

      class Importer
        def run
          @d§
        end
      end
    RUBY
  }.each do |shape, source|
    it "offers an instance variable another method assigned, in #{shape}" do
      labels = ask("textDocument/completion", source)[:items].map { |item| item[:label] }

      expect(labels).to include("@data")
    end

    it "types it, in #{shape}" do
      item = ask("textDocument/completion", source)[:items].find { |i| i[:label] == "@data" }

      expect(item[:detail]).to eq("String")
    end
  end

  # The boundary the presence rows exist beside: an ivar of a *different*
  # class in the same file is not in scope, whichever direction it lies.
  {
    "a nested class" => <<~RUBY,
      class Importer
        def run
          @d§
        end

        class Row
          def setup
            @detail = "nested"
          end
        end
      end
    RUBY
    "an enclosing class" => <<~RUBY,
      class Importer
        def setup
          @detail = "outer"
        end

        class Row
          def show
            @d§
          end
        end
      end
    RUBY
    "a sibling class" => <<~RUBY
      class Alpha
        def run
          @d§
        end
      end

      class Beta
        def setup
          @detail = "other"
        end
      end
    RUBY
  }.each do |shape, source|
    it "does not offer an instance variable that only #{shape} assigns" do
      labels = ask("textDocument/completion", source)[:items].map { |item| item[:label] }

      expect(labels).not_to include("@detail")
    end
  end

  # The other three readers of the same environment, so a hole in it
  # cannot be mistaken for one feature's problem.
  it "answers hover from it" do
    source = <<~RUBY
      module Admin
        class Importer
          def setup
            @data = "text"
          end

          def run
            @dat§a
          end
        end
      end
    RUBY

    expect(ask("textDocument/hover", source)[:contents][:value]).to eq("String")
  end

  it "answers member completion from it" do
    source = <<~RUBY
      module Admin
        class Importer
          def setup
            @data = "text"
          end

          def run
            @data.upc§
          end
        end
      end
    RUBY

    expect(ask("textDocument/completion", source)[:items].map { |i| i[:label] }).to include("upcase")
  end
end
