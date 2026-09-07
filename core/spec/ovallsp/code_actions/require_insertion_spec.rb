# frozen_string_literal: true

require_relative "../../unit_spec_helper"
require_relative "../../../lib/ovallsp/code_actions/require_insertion"

RSpec.describe Ovallsp::CodeActions::RequireInsertion do
  def build(source, path)
    described_class.build(source, path)
  end

  def insertion_at(line, text, character: 0)
    {
      range: { start: { line: line, character: character }, end: { line: line, character: character } },
      new_text: text
    }
  end

  it "inserts at the top of a file with no shebang, magic comment or require" do
    source = "module Foo\nend\n"
    expect(build(source, "json")).to eq(insertion_at(0, %(require "json"\n)))
  end

  it "inserts on the line after a shebang" do
    source = "#!/usr/bin/env ruby\nputs :hi\n"
    expect(build(source, "json")).to eq(insertion_at(1, %(require "json"\n)))
  end

  it "inserts after the magic comments when there is no shebang" do
    source = "# frozen_string_literal: true\n\nmodule Foo\nend\n"
    expect(build(source, "json")).to eq(insertion_at(1, %(require "json"\n)))
  end

  it "inserts after a shebang followed by magic comments" do
    source = "#!/usr/bin/env ruby\n# frozen_string_literal: true\n# encoding: utf-8\nputs :hi\n"
    expect(build(source, "json")).to eq(insertion_at(3, %(require "json"\n)))
  end

  it "does not treat an ordinary leading comment as a magic comment" do
    source = "# Copyright notice\nmodule Foo\nend\n"
    expect(build(source, "json")).to eq(insertion_at(0, %(require "json"\n)))
  end

  it "inserts alphabetically inside an existing require group" do
    source = <<~RUBY
      # frozen_string_literal: true

      require "date"
      require "set"

      module Foo
      end
    RUBY
    expect(build(source, "json")).to eq(insertion_at(3, %(require "json"\n)))
  end

  it "inserts after the last require when the path sorts last in the group" do
    source = <<~RUBY
      require "date"
      require "json"

      module Foo
      end
    RUBY
    expect(build(source, "set")).to eq(insertion_at(2, %(require "set"\n)))
  end

  it "extends only the first require group, leaving later groups alone" do
    source = <<~RUBY
      require "date"

      require "zlib"
    RUBY
    expect(build(source, "set")).to eq(insertion_at(1, %(require "set"\n)))
  end

  it "matches CRLF line endings in the inserted text" do
    source = "# frozen_string_literal: true\r\n\r\nmodule Foo\r\nend\r\n"
    expect(build(source, "json")).to eq(insertion_at(1, %(require "json"\r\n)))
  end

  it "returns nil when the require already exists with double quotes" do
    expect(build(%(require "json"\n), "json")).to be_nil
  end

  it "returns nil when the require already exists with single quotes" do
    expect(build("require 'json'\n", "json")).to be_nil
  end

  it "does not count a require of a different path or a require_relative as a duplicate" do
    source = %(require "json/pure"\nrequire_relative "json"\n)
    expect(build(source, "json")).to eq(insertion_at(0, %(require "json"\n)))
  end

  it "appends after a final line that has no trailing newline" do
    source = "# frozen_string_literal: true"
    expect(build(source, "json")).to eq(
      insertion_at(0, %(\nrequire "json"), character: source.length)
    )
  end

  it "handles an empty source" do
    expect(build("", "json")).to eq(insertion_at(0, %(require "json"\n)))
  end

  it "appends after a non-BMP final header using UTF-16 columns" do
    source = "#!/usr/bin/env ruby 😀"
    edit = build(source, "json")
    # ASCII prefix has 20 units; the emoji occupies two (CLIENT_BEHAVIOUR).
    expect(edit).to eq(insertion_at(0, %(\nrequire "json"), character: 22))
    prefix = source.encode("UTF-16LE").byteslice(0, edit[:range][:start][:character] * 2).force_encoding("UTF-16LE")
    expect(prefix.encode("UTF-8") + edit[:new_text]).to eq(source + %(\nrequire "json"))
  end

  it "returns nil for a blank require path" do
    expect(build("module Foo\nend\n", "")).to be_nil
    expect(build("module Foo\nend\n", nil)).to be_nil
  end
end
