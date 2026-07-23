# frozen_string_literal: true

RSpec.describe Rslsp::WorkspaceIndex do
  subject(:index) { described_class.new }

  def summary(uri:, declarations:, content_hash: "hash-#{uri}", version: 1)
    Rslsp::Index::FileSummary.new(
      uri: uri, content_hash: content_hash, document_version: version, declarations: declarations, diagnostics: []
    )
  end

  def declaration(kind:, owner:, name:, line: 0)
    Rslsp::Index::Declaration.new(
      symbol_id: Rslsp::Index::SymbolId.new(kind: kind, owner: owner, name: name, discriminator: nil),
      location: { start: { line: line, character: 0 }, end: { line: line, character: 1 } },
      visibility: nil,
      parameters: [],
      origin: :source
    )
  end

  it "starts at generation 0 and bumps it on each applied mutation" do
    expect(index.generation).to eq(0)

    index.replace_file(summary(uri: "file:///a.rb", declarations: []))
    expect(index.generation).to eq(1)

    index.remove_file("file:///a.rb")
    expect(index.generation).to eq(2)
  end

  it "does not bump generation for a no-op remove" do
    index.remove_file("file:///missing.rb")

    expect(index.generation).to eq(0)
  end

  it "aggregates declarations for the same SymbolId across files (class reopened elsewhere)" do
    user_decl_a = declaration(kind: :class, owner: nil, name: "::User")
    user_decl_b = declaration(kind: :class, owner: nil, name: "::User", line: 5)

    index.replace_file(summary(uri: "file:///a.rb", declarations: [user_decl_a]))
    index.replace_file(summary(uri: "file:///b.rb", declarations: [user_decl_b]))

    results = index.declarations(user_decl_a.symbol_id)
    expect(results).to contain_exactly(user_decl_a, user_decl_b)
  end

  it "skips reindexing when the content hash is unchanged" do
    decl = declaration(kind: :class, owner: nil, name: "::User")
    first = summary(uri: "file:///a.rb", declarations: [decl], content_hash: "same", version: 1)
    second = summary(uri: "file:///a.rb", declarations: [decl], content_hash: "same", version: 2)

    expect(index.replace_file(first)).to be(true)
    expect(index.replace_file(second)).to be(false)
    expect(index.generation).to eq(1)
  end

  it "rejects a summary with an older document version than what's indexed" do
    decl = declaration(kind: :class, owner: nil, name: "::User")
    newer = summary(uri: "file:///a.rb", declarations: [decl], content_hash: "v2", version: 5)
    older = summary(uri: "file:///a.rb", declarations: [decl], content_hash: "v1", version: 2)

    expect(index.replace_file(newer)).to be(true)
    expect(index.replace_file(older)).to be(false)
    expect(index.generation).to eq(1)
  end

  it "always accepts a summary when either side has a nil (disk-sourced) version" do
    decl = declaration(kind: :class, owner: nil, name: "::User")
    buffer_version = summary(uri: "file:///a.rb", declarations: [decl], content_hash: "v1", version: 10)
    disk_version = summary(uri: "file:///a.rb", declarations: [decl], content_hash: "v2", version: nil)

    expect(index.replace_file(buffer_version)).to be(true)
    expect(index.replace_file(disk_version)).to be(true)
  end

  it "does not touch other files' contributions when replacing one file" do
    decl_a = declaration(kind: :class, owner: nil, name: "::A")
    decl_b = declaration(kind: :class, owner: nil, name: "::B")
    index.replace_file(summary(uri: "file:///a.rb", declarations: [decl_a]))
    index.replace_file(summary(uri: "file:///b.rb", declarations: [decl_b]))

    index.replace_file(summary(uri: "file:///a.rb", declarations: [decl_a], content_hash: "changed", version: 2))

    expect(index.declarations(decl_b.symbol_id)).to eq([decl_b])
  end

  it "fully removes a file's contribution, including shared SymbolIds" do
    decl = declaration(kind: :class, owner: nil, name: "::User")
    index.replace_file(summary(uri: "file:///a.rb", declarations: [decl]))
    index.replace_file(summary(uri: "file:///b.rb", declarations: [decl], content_hash: "other"))

    index.remove_file("file:///a.rb")

    expect(index.declarations_with_uri(decl.symbol_id)).to eq([["file:///b.rb", decl]])

    index.remove_file("file:///b.rb")
    expect(index.declarations(decl.symbol_id)).to eq([])
  end

  describe "#find_by_simple_name" do
    it "matches class/module/constant declarations by their unqualified name" do
      nested = declaration(kind: :class, owner: "::Blog", name: "::Blog::Post")
      index.replace_file(summary(uri: "file:///post.rb", declarations: [nested]))

      expect(index.find_by_simple_name("Post")).to eq([{ uri: "file:///post.rb", range: nested.location }])
      expect(index.find_by_simple_name("Nope")).to eq([])
    end
  end

  describe "#search" do
    it "ranks an exact name match above a substring match" do
      user = declaration(kind: :class, owner: nil, name: "::User")
      user_profile = declaration(kind: :class, owner: nil, name: "::UserProfile")
      index.replace_file(summary(uri: "file:///a.rb", declarations: [user, user_profile]))

      results = index.search("user", limit: 10)

      expect(results.first[:symbol_id]).to eq(user.symbol_id)
      expect(results.map { |r| r[:symbol_id] }).to include(user_profile.symbol_id)
    end

    it "respects the limit" do
      declarations = (1..5).map { |i| declaration(kind: :class, owner: nil, name: "::Widget#{i}") }
      index.replace_file(summary(uri: "file:///a.rb", declarations: declarations))

      expect(index.search("widget", limit: 2).size).to eq(2)
    end
  end
end
