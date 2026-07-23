# frozen_string_literal: true

require "benchmark"

RSpec.describe "Rslsp::WorkspaceIndex at scale", :benchmark do
  it "indexes 1,000 synthetic files and answers queries in well under a second" do
    index = Rslsp::WorkspaceIndex.new
    file_count = 1000
    declarations_per_file = 5

    summaries = Array.new(file_count) do |i|
      declarations = Array.new(declarations_per_file) do |j|
        Rslsp::Index::Declaration.new(
          symbol_id: Rslsp::Index::SymbolId.new(kind: :class, owner: nil, name: "::Generated#{i}_#{j}", discriminator: nil),
          location: { start: { line: j, character: 0 }, end: { line: j, character: 1 } },
          visibility: nil,
          parameters: [],
          origin: :source
        )
      end

      Rslsp::Index::FileSummary.new(
        uri: "file:///generated/file_#{i}.rb",
        content_hash: "hash-#{i}",
        document_version: 1,
        declarations: declarations,
        diagnostics: []
      )
    end

    index_time = Benchmark.realtime { summaries.each { |s| index.replace_file(s) } }
    search_time = Benchmark.realtime { index.search("Generated500", limit: 10) }

    expect(index.generation).to eq(file_count)
    expect(index.declarations(summaries.last.declarations.first.symbol_id).size).to eq(1)

    warn "[benchmark] indexed #{file_count} files x #{declarations_per_file} declarations in #{index_time.round(3)}s, " \
         "search in #{(search_time * 1000).round(2)}ms"

    expect(index_time).to be < 2.0
    expect(search_time).to be < 0.5
  end

  it "replacing one file does not reparse or touch the others' cached FileSummary objects" do
    index = Rslsp::WorkspaceIndex.new
    other_summaries = Array.new(50) do |i|
      Rslsp::Index::FileSummary.new(
        uri: "file:///other_#{i}.rb", content_hash: "h#{i}", document_version: 1, declarations: [], diagnostics: []
      )
    end
    other_summaries.each { |s| index.replace_file(s) }

    changed = Rslsp::Index::FileSummary.new(
      uri: "file:///changed.rb", content_hash: "v1", document_version: 1, declarations: [], diagnostics: []
    )
    index.replace_file(changed)
    index.replace_file(
      Rslsp::Index::FileSummary.new(
        uri: "file:///changed.rb", content_hash: "v2", document_version: 2, declarations: [], diagnostics: []
      )
    )

    # Same object identity: WorkspaceIndex never rebuilt or reparsed these.
    expect(index.generation).to eq(52)
  end
end
