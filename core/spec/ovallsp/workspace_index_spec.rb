# frozen_string_literal: true

RSpec.describe Ovallsp::WorkspaceIndex do
  subject(:index) { described_class.new }

  def summary(uri:, declarations:, content_hash: "hash-#{uri}", version: 1, source: :buffer, read_sequence: 0)
    Ovallsp::Index::FileSummary.new(
      uri: uri, content_hash: content_hash, document_version: version, declarations: declarations, diagnostics: [],
      source: source, read_sequence: read_sequence
    )
  end

  def declaration(kind:, owner:, name:, line: 0, character: 0)
    Ovallsp::Index::Declaration.new(
      symbol_id: Ovallsp::Index::SymbolId.new(kind: kind, owner: owner, name: name, discriminator: nil),
      location: { start: { line: line, character: character }, end: { line: line, character: character + 1 } },
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

  describe "internal index hygiene (Task 008.5)" do
    it "does not plant an empty entry for a SymbolId that was never indexed, via a mere existence check" do
      unknown = Ovallsp::Index::SymbolId.new(kind: :class, owner: nil, name: "::Ghost", discriminator: nil)

      index.declarations(unknown)
      index.declarations_with_uri(unknown)
      index.declarations(unknown)

      by_symbol = index.instance_variable_get(:@by_symbol)
      expect(by_symbol).not_to have_key(unknown)
    end

    it "does not plant an empty entry in the simple-name index for a name that was never indexed" do
      index.find_by_simple_name("Ghost")
      index.find_by_simple_name("Ghost")

      by_simple_name = index.instance_variable_get(:@by_simple_name)
      expect(by_simple_name).not_to have_key("ghost")
    end

    it "removes the simple-name index entry once the last declaration with that name is removed" do
      decl = declaration(kind: :class, owner: nil, name: "::User")
      index.replace_file(summary(uri: "file:///a.rb", declarations: [decl]))

      index.remove_file("file:///a.rb")

      expect(index.find_by_simple_name("User")).to eq([])
      by_simple_name = index.instance_variable_get(:@by_simple_name)
      expect(by_simple_name).not_to have_key("user")
    end
  end

  # Every answer this index gives has to be a property of the workspace,
  # not of the order files reached it. `replace_file` removes a uri's
  # entries and appends the new ones, so re-indexing a file moved its
  # symbols to the back of every list they are in — and the readers take
  # `.first` of such a list, or truncate it. Typing one character in an
  # unrelated file changed where go-to-definition landed, which class an
  # ambiguous name resolved to, and which symbols survived
  # `workspace/symbol`'s limit.
  #
  # 0.1.12 tried to fix this four times by sorting one more *reader* each
  # round, produced two regressions, and was rolled back to 024.15. The
  # order lives in the storage now.
  #
  # **Every example that could regress on re-index re-indexes.** That is
  # the state the bug lives in, and the state every one of those four
  # attempts was pinned without. The rest fix an order that a single index
  # already decides -- ties within a file, byte-vs-case, the exact-match
  # bucket -- and adding a re-index to those would test nothing extra.
  # Re-indexing is not sufficient either: the `search` tail shipped
  # unpinned behind a re-indexing fixture whose eight files shared one
  # SymbolId, so the entry list `replace_file` already sorts was the only
  # thing it exercised (024.15, 0.1.13).
  describe "determinism across re-indexing" do
    def widget_in(letter, hash:, line: 1)
      summary(uri: "file:///#{letter}.rb", content_hash: hash,
              declarations: [declaration(kind: :class, owner: nil, name: "::Widget", line: line)])
    end

    def index_z_then_a
      index.replace_file(widget_in("z", hash: "z1"))
      index.replace_file(widget_in("a", hash: "a1"))
    end

    it "orders a symbol's declarations by uri, not by when each file was indexed" do
      index_z_then_a

      expect(index.declarations_with_uri(
        Ovallsp::Index::SymbolId.new(kind: :class, owner: nil, name: "::Widget", discriminator: nil)
      ).map(&:first)).to eq(["file:///a.rb", "file:///z.rb"])
    end

    it "keeps that order after one of the files is re-indexed" do
      index_z_then_a
      index.replace_file(widget_in("a", hash: "a2"))

      expect(index.class_declaration_uris("Widget")).to eq(["file:///a.rb", "file:///z.rb"])
    end

    # Ties are what a plain `sort_by` cannot answer -- it is not a stable
    # sort, and a class reopened twice in one file gives two entries with
    # the same uri. Eight is where CRuby starts scrambling equal keys.
    it "orders declarations within one file by source position" do
      decls = (0...8).map { |i| declaration(kind: :class, owner: nil, name: "::Widget", line: i * 10) }
      index.replace_file(summary(uri: "file:///w.rb", declarations: decls.reverse))

      expect(index.class_declarations("Widget").map { |d| d[:range][:start][:line] })
        .to eq((0...8).map { |i| i * 10 })
    end

    # One class has as many SymbolIds as there are ways to spell it, so
    # ordering within a SymbolId is not enough -- the outer walk over
    # `@by_simple_name` has to be ordered too.
    it "orders across the several SymbolIds one class can have, and keeps it across a re-index" do
      index.replace_file(summary(uri: "file:///z.rb", content_hash: "z1",
                                 declarations: [declaration(kind: :class, owner: "::Api", name: "::Api::Widget")]))
      index.replace_file(summary(uri: "file:///a.rb", content_hash: "a1",
                                 declarations: [declaration(kind: :class, owner: nil, name: "::Api::Widget")]))
      before = index.class_declaration_uris("Api::Widget")
      index.replace_file(summary(uri: "file:///z.rb", content_hash: "z2",
                                 declarations: [declaration(kind: :class, owner: "::Api", name: "::Api::Widget")]))

      expect(index.class_declaration_uris("Api::Widget")).to eq(before)
      expect(before).to eq(["file:///a.rb", "file:///z.rb"])
    end

    # Two *distinct* SymbolIds, deliberately. One name in two files is a
    # single SymbolId, so a fixture built that way exercises only the
    # entry list `replace_file` already sorts and leaves the outer walk
    # -- the thing under test -- unpinned.
    it "orders #find_by_simple_name and keeps it across a re-index" do
      index.replace_file(summary(uri: "file:///admin.rb", content_hash: "ad1",
                                 declarations: [declaration(kind: :class, owner: "::Admin", name: "::Admin::Thing")]))
      index.replace_file(summary(uri: "file:///api.rb", content_hash: "ap1",
                                 declarations: [declaration(kind: :class, owner: "::Api", name: "::Api::Thing")]))
      before = index.find_by_simple_name("Thing").map { |r| r[:uri] }
      index.replace_file(summary(uri: "file:///admin.rb", content_hash: "ad2",
                                 declarations: [declaration(kind: :class, owner: "::Admin", name: "::Admin::Thing")]))

      expect(index.find_by_simple_name("Thing").map { |r| r[:uri] }).to eq(before)
      expect(before).to eq(["file:///admin.rb", "file:///api.rb"])
    end

    # Which class an ambiguous bare name resolves to drives the ancestry
    # chain, the unknown-method check, find-references and rename.
    #
    # `Api` first and `api.rb` re-indexed -- the *first*-inserted file. A
    # re-index deletes its symbol from the Set and re-adds it at the back,
    # so re-indexing the second-inserted file leaves the order it already
    # had and `eq(before)` cannot fail; only the absolute assertion could.
    # Re-indexing the first-inserted one makes both able to fail, which is
    # what "the state the bug lives in" has to mean for an example that
    # asserts a before and an after. (Which one is stronger depends on the
    # assertion shape: with an absolute assertion alone, re-indexing the
    # first-inserted file lands on the ordered answer by accident. That is
    # why this example carries both.)
    #
    # Both are written `class Api::User`, so both carry owner nil and kind
    # :class -- which leaves the qualified name as the only element of the
    # key that can separate them.
    it "resolves an ambiguous simple name to the same class across a re-index" do
      %w[Api Admin].each do |ns|
        index.replace_file(
          summary(uri: "file:///#{ns.downcase}.rb", content_hash: ns,
                  declarations: [declaration(kind: :class, owner: nil, name: "::#{ns}::User")])
        )
      end
      before = index.resolve_type_name("User")
      index.replace_file(summary(uri: "file:///api.rb", content_hash: "Api2",
                                 declarations: [declaration(kind: :class, owner: nil, name: "::Api::User")]))

      expect(index.resolve_type_name("User")).to eq(before)
      expect(before).to eq("::Admin::User")
    end

    # `workspace/symbol` truncates, so an unstable order changes the
    # *membership* of the answer: the class in the file you were just
    # looking at could drop out of the list.
    it "keeps a truncated workspace/symbol result stable across a re-index" do
      8.times do |i|
        index.replace_file(
          summary(uri: "file:///f#{i}.rb", content_hash: "f#{i}",
                  declarations: [declaration(kind: :class, owner: nil, name: "::Widget", line: i)])
        )
      end
      before = index.search("widget", limit: 3).map { |m| m[:uri] }
      index.replace_file(summary(uri: "file:///f0.rb", content_hash: "f0v2",
                                 declarations: [declaration(kind: :class, owner: nil, name: "::Widget", line: 0)]))

      expect(index.search("widget", limit: 3).map { |m| m[:uri] }).to eq(before)
      expect(before).to eq(["file:///f0.rb", "file:///f1.rb", "file:///f2.rb"])
    end

    # The exact-match bucket has to come *first* in the key, not merely be
    # present: sorting by name alone puts `Widget` after `WidgetFactory`
    # only by luck of the alphabet, and reverses for a name where it does
    # not hold.
    # The tie the tail exists for is across *distinct* SymbolIds, not
    # within one: `search` walks `@by_symbol` in Hash key order, and a key
    # is deleted and re-inserted when the last file declaring it is
    # re-indexed. Six classes sharing the substring but not the exact
    # match all land in the same bucket, so without the tail the bucket's
    # order is index order and the truncation drops a different one each
    # time. A fixture of one class in eight files cannot see this — the
    # entry list `replace_file` already sorts is the only thing it
    # exercises, which is how this shipped unpinned once.
    it "keeps a truncated result stable when the tie is across several SymbolIds" do
      %w[A B C D E F].each do |suffix|
        index.replace_file(
          summary(uri: "file:///widget#{suffix.downcase}.rb", content_hash: suffix,
                  declarations: [declaration(kind: :class, owner: nil, name: "::Widget#{suffix}")])
        )
      end
      before = index.search("widget", limit: 3).map { |m| m[:symbol_id].name }
      index.replace_file(
        summary(uri: "file:///widgeta.rb", content_hash: "A2",
                declarations: [declaration(kind: :class, owner: nil, name: "::WidgetA")])
      )

      expect(index.search("widget", limit: 3).map { |m| m[:symbol_id].name }).to eq(before)
      expect(before).to eq(%w[::WidgetA ::WidgetB ::WidgetC])
    end

    # Uri before source position, deliberately. The two disagree only when
    # a class is reopened in files whose alphabetical order is the reverse
    # of their line numbers -- a controller split across concerns is
    # exactly that -- and which one wins decides whose instance variables
    # a view gets.
    it "orders by uri before source position, when the two disagree" do
      index.replace_file(summary(uri: "file:///a_billing.rb", content_hash: "a",
                                 declarations: [declaration(kind: :class, owner: nil, name: "::Acc", line: 25)]))
      index.replace_file(summary(uri: "file:///z_audit.rb", content_hash: "z",
                                 declarations: [declaration(kind: :class, owner: nil, name: "::Acc", line: 3)]))

      expect(index.class_declaration_uris("Acc")).to eq(["file:///a_billing.rb", "file:///z_audit.rb"])
    end

    # `replace_file` sorts *every* symbol the file touched, not just the
    # last one it saw. A file declaring two classes that are each also
    # declared elsewhere is the shape that tells those apart.
    it "orders every symbol a file touches, not only the last" do
      index.replace_file(
        summary(uri: "file:///a_pair.rb", content_hash: "p1",
                declarations: [declaration(kind: :class, owner: nil, name: "::Alpha"),
                               declaration(kind: :class, owner: nil, name: "::Beta")])
      )
      %w[Alpha Beta].each do |name|
        index.replace_file(
          summary(uri: "file:///z_#{name.downcase}.rb", content_hash: name,
                  declarations: [declaration(kind: :class, owner: nil, name: "::#{name}")])
        )
      end
      index.replace_file(
        summary(uri: "file:///a_pair.rb", content_hash: "p2",
                declarations: [declaration(kind: :class, owner: nil, name: "::Alpha"),
                               declaration(kind: :class, owner: nil, name: "::Beta")])
      )

      expect(index.class_declaration_uris("Alpha")).to eq(["file:///a_pair.rb", "file:///z_alpha.rb"])
      expect(index.class_declaration_uris("Beta")).to eq(["file:///a_pair.rb", "file:///z_beta.rb"])
    end

    # `search`'s key has to be *total*, not merely longer than it was.
    # These two shapes tie on name, uri and line, and both occur: one
    # class declared several times on one line, and a plugin's generated
    # methods, which all share a `plugin://` uri and a frozen line-0
    # location.
    it "returns the same order search and class_declarations agree on, within one line" do
      decls = (0...8).map do |i|
        Ovallsp::Index::Declaration.new(
          symbol_id: Ovallsp::Index::SymbolId.new(kind: :class, owner: nil, name: "::Widget", discriminator: nil),
          location: { start: { line: 0, character: i * 5 }, end: { line: 0, character: i * 5 + 1 } },
          visibility: nil, parameters: [], origin: :source
        )
      end
      index.replace_file(summary(uri: "file:///w.rb", declarations: decls))

      expect(index.search("widget", limit: 8).map { |m| m[:location][:start][:character] })
        .to eq(index.class_declarations("Widget").map { |d| d[:range][:start][:character] })
    end

    # The uri and line elements of the key have to be separated to be
    # tested: a fixture whose file names sort the same way as its line
    # numbers is satisfied by either one alone.
    it "orders search results by uri even when the line numbers disagree" do
      index.replace_file(summary(uri: "file:///a.rb", content_hash: "a",
                                 declarations: [declaration(kind: :class, owner: nil, name: "::Widget", line: 9)]))
      index.replace_file(summary(uri: "file:///z.rb", content_hash: "z",
                                 declarations: [declaration(kind: :class, owner: nil, name: "::Widget", line: 1)]))

      expect(index.search("widget", limit: 2).map { |m| m[:uri] }).to eq(["file:///a.rb", "file:///z.rb"])
    end

    it "orders search results by line within one file" do
      decls = (0...8).map { |i| declaration(kind: :class, owner: nil, name: "::Widget", line: i) }
      index.replace_file(summary(uri: "file:///w.rb", declarations: decls.reverse))

      expect(index.search("widget", limit: 8).map { |m| m[:location][:start][:line] }).to eq((0...8).to_a)
    end

    # Line before column, and the two have to disagree to show it: every
    # other fixture here holds one of them at 0 while varying the other,
    # which any order of the pair satisfies. A class reopened at the top
    # of a file and again, indented, inside a module further down is the
    # real shape -- and which one wins is where go-to-definition lands.
    it "orders declarations in one file by line before column, when the two disagree" do
      index.replace_file(
        summary(uri: "file:///w.rb",
                declarations: [declaration(kind: :class, owner: nil, name: "::Widget", line: 9, character: 0),
                               declaration(kind: :class, owner: nil, name: "::Widget", line: 5, character: 4)])
      )

      positions = index.class_declarations("Widget").map { |d| [d[:range][:start][:line], d[:range][:start][:character]] }
      expect(positions).to eq([[5, 4], [9, 0]])
      expect(index.search("widget", limit: 2).map { |m| [m[:location][:start][:line], m[:location][:start][:character]] })
        .to eq(positions)
    end

    # `name` *first*, not merely present. A key of `[kind, name, owner]`
    # ties on nothing and passes every other fixture here, but it makes
    # the answer to an ambiguous bare name depend on how the two
    # candidates happen to be declared -- and the documented rule, three
    # methods above `resolve_type_name`, is the alphabetically first
    # qualified name. `::Admin::Thing` is a module and `::Api::Thing` a
    # class, so the alphabet and the kinds order opposite.
    it "resolves an ambiguous simple name by qualified name before kind" do
      index.replace_file(summary(uri: "file:///admin.rb", content_hash: "ad",
                                 declarations: [declaration(kind: :module, owner: nil, name: "::Admin::Thing")]))
      index.replace_file(summary(uri: "file:///api.rb", content_hash: "ap",
                                 declarations: [declaration(kind: :class, owner: nil, name: "::Api::Thing")]))

      expect(index.resolve_type_name("Thing")).to eq("::Admin::Thing")
      expect(index.find_by_simple_name("Thing").map { |r| r[:uri] }).to eq(["file:///admin.rb", "file:///api.rb"])
    end

    # The kind element of the ordering key. `class Thing` and `module
    # Thing` in two files agree on the qualified name and on the owner
    # (both nil), so they tie on everything else -- and `type_kind` is
    # what `Semantic::HierarchyIndex` asks to decide whether a receiver
    # implicitly inherits `Object`'s methods. The *class*'s own file is
    # the one re-indexed: a re-index moves its symbol to the back of the
    # collection, so re-saving the module's file would leave the accepted
    # answer in front and the fixture could not fail.
    it "resolves a name declared as both a class and a module to the same kind across a re-index" do
      index.replace_file(summary(uri: "file:///c.rb", content_hash: "c1",
                                 declarations: [declaration(kind: :class, owner: nil, name: "::Thing")]))
      index.replace_file(summary(uri: "file:///m.rb", content_hash: "m1",
                                 declarations: [declaration(kind: :module, owner: nil, name: "::Thing")]))
      before = index.type_kind("Thing")
      index.replace_file(summary(uri: "file:///c.rb", content_hash: "c2",
                                 declarations: [declaration(kind: :class, owner: nil, name: "::Thing")]))

      expect(index.type_kind("Thing")).to eq(before)
      expect(before).to eq(:class)
    end

    # `kind` before `owner`, which only one shape can show: one class
    # written `module Api; class Thing` in one file and `module
    # Api::Thing` in another has a single qualified name and two owners,
    # so the key's first element ties and the last two decide. `:class`
    # sorts before `:module`, and the owners order the other way.
    it "orders the spellings of one qualified name by kind before owner" do
      index.replace_file(summary(uri: "file:///nested.rb", content_hash: "n",
                                 declarations: [declaration(kind: :class, owner: "::Api", name: "::Api::Thing")]))
      index.replace_file(summary(uri: "file:///flat.rb", content_hash: "f",
                                 declarations: [declaration(kind: :module, owner: nil, name: "::Api::Thing")]))

      expect(index.type_kind("Api::Thing")).to eq(:class)
      expect(index.class_declaration_uris("Api::Thing")).to eq(["file:///nested.rb", "file:///flat.rb"])
    end

    # The name element of the ranking key, on its own: the fixtures above
    # name each file after the class it declares, so uri order and name
    # order coincide and either element alone satisfies them.
    it "orders search results by qualified name before uri, when the two disagree" do
      index.replace_file(summary(uri: "file:///z.rb", content_hash: "z",
                                 declarations: [declaration(kind: :class, owner: nil, name: "::AWidget", line: 1)]))
      index.replace_file(summary(uri: "file:///a.rb", content_hash: "a",
                                 declarations: [declaration(kind: :class, owner: nil, name: "::ZWidget", line: 9)]))

      # Two files whose names order opposite to the classes they declare.
      # Both in one file would tie the uri element, which is the same
      # correlation this example was written to break, moved into a
      # constant -- and `limit: 1` is the point: an unstable order does
      # not reorder the answer, it changes which symbol is in it.
      expect(index.search("widget", limit: 1).map { |m| m[:symbol_id].name }).to eq(["::AWidget"])
      expect(index.search("widget", limit: 2).map { |m| m[:symbol_id].name }).to eq(%w[::AWidget ::ZWidget])
    end

    # The kind element of the tail. Its tie is the one a plugin makes:
    # `Server#apply_plugin_context` gives every declaration it registers
    # the same `plugin://` uri and a frozen line-0/char-0 location, so an
    # instance method and a singleton method of the same name on the same
    # owner agree on every earlier element of the key.
    it "orders search results by kind before owner, when everything earlier ties" do
      declarations = %w[::A ::B ::C ::D].flat_map do |owner|
        [declaration(kind: :singleton_method, owner: owner, name: "save"),
         declaration(kind: :instance_method, owner: owner, name: "save")]
      end
      index.replace_file(summary(uri: "plugin://rails", content_hash: "p", declarations: declarations))

      expect(index.search("save", limit: 8).map { |m| [m[:symbol_id].kind, m[:symbol_id].owner] })
        .to eq(%w[::A ::B ::C ::D].map { |o| [:instance_method, o] } +
               %w[::A ::B ::C ::D].map { |o| [:singleton_method, o] })
    end

    it "keeps a truncated result stable when every match shares a uri and a location" do
      owners = %w[Article Booking Comment Delivery Entry Feed Guest Handoff Invoice Job]
      generated = lambda do |list|
        list.map do |owner|
          Ovallsp::Index::Declaration.new(
            symbol_id: Ovallsp::Index::SymbolId.new(kind: :instance_method, owner: "::#{owner}",
                                                    name: "pending?", discriminator: nil),
            location: { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } },
            visibility: :public, parameters: [], origin: :generated
          )
        end
      end
      index.replace_file(summary(uri: "plugin://sm", declarations: generated.call(owners)))
      reversed = described_class.new
      reversed.replace_file(summary(uri: "plugin://sm", declarations: generated.call(owners.reverse)))

      expect(index.search("pending", limit: 3).map { |m| m[:symbol_id].owner })
        .to eq(reversed.search("pending", limit: 3).map { |m| m[:symbol_id].owner })
    end

    it "still ranks an exact name match first, ahead of the uri and name order" do
      index.replace_file(summary(uri: "file:///a.rb", content_hash: "a",
                                 declarations: [declaration(kind: :class, owner: nil, name: "::AbstractWidget")]))
      index.replace_file(summary(uri: "file:///z.rb", content_hash: "z",
                                 declarations: [declaration(kind: :class, owner: nil, name: "::Widget")]))

      expect(index.search("widget", limit: 2).map { |m| m[:uri] }).to eq(["file:///z.rb", "file:///a.rb"])
    end

    # Byte order, not case-insensitive order. Which of two files wins is
    # arbitrary either way; that the choice is written down is not,
    # because it decides where go-to-definition lands.
    it "orders uris by byte, so case decides between two files" do
      %w[Zebra apple].each do |name|
        index.replace_file(
          summary(uri: "file:///#{name}.rb", content_hash: name,
                  declarations: [declaration(kind: :class, owner: nil, name: "::Widget")])
        )
      end

      expect(index.class_declaration_uris("Widget")).to eq(["file:///Zebra.rb", "file:///apple.rb"])
    end

    # The column half of the source-position tiebreak: eight declarations
    # of one class on a single physical line.
    it "orders declarations sharing a line by column" do
      decls = (0...8).map do |i|
        Ovallsp::Index::Declaration.new(
          symbol_id: Ovallsp::Index::SymbolId.new(kind: :class, owner: nil, name: "::Widget", discriminator: nil),
          location: { start: { line: 0, character: i * 10 }, end: { line: 0, character: i * 10 + 1 } },
          visibility: nil, parameters: [], origin: :source
        )
      end
      index.replace_file(summary(uri: "file:///one_line.rb", declarations: decls.reverse))

      expect(index.class_declarations("Widget").map { |d| d[:range][:start][:character] })
        .to eq((0...8).map { |i| i * 10 })
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

  describe "type name resolution (Task 009)" do
    it "resolves an absolute (::-prefixed) name to itself when declared" do
      index.replace_file(summary(uri: "file:///a.rb", declarations: [declaration(kind: :class, owner: nil, name: "::User")]))

      expect(index.resolve_type_name("::User")).to eq("::User")
    end

    it "resolves an unqualified simple name to its declared absolute name" do
      index.replace_file(
        summary(uri: "file:///a.rb", declarations: [declaration(kind: :class, owner: "::Blog", name: "::Blog::Post")])
      )

      expect(index.resolve_type_name("Post")).to eq("::Blog::Post")
    end

    it "returns nil for a name that isn't declared anywhere" do
      expect(index.resolve_type_name("TotallyUnknown")).to be_nil
    end

    it "does not resolve a method/constant name -- only class/module kinds" do
      index.replace_file(
        summary(uri: "file:///a.rb", declarations: [declaration(kind: :constant, owner: nil, name: "MAX")])
      )

      expect(index.resolve_type_name("MAX")).to be_nil
    end

    it "reports the declared kind (:class or :module) for a resolvable type name" do
      index.replace_file(
        summary(uri: "file:///a.rb", declarations: [
                  declaration(kind: :class, owner: nil, name: "::User"),
                  declaration(kind: :module, owner: nil, name: "::Greetable")
                ])
      )

      expect(index.type_kind("User")).to eq(:class)
      expect(index.type_kind("Greetable")).to eq(:module)
      expect(index.type_kind("Nope")).to be_nil
    end
  end

  describe "#method_symbol_ids (Task 009)" do
    it "returns every SymbolId of the given kind declared directly under an owner, across reopened files" do
      index.replace_file(
        summary(uri: "file:///a.rb", declarations: [declaration(kind: :instance_method, owner: "::Widget", name: "a")])
      )
      index.replace_file(
        summary(uri: "file:///b.rb", declarations: [declaration(kind: :instance_method, owner: "::Widget", name: "b")])
      )
      index.replace_file(
        summary(uri: "file:///c.rb", declarations: [declaration(kind: :singleton_method, owner: "::Widget", name: "c")])
      )

      names = index.method_symbol_ids("::Widget", kind: :instance_method).map(&:name)

      expect(names).to contain_exactly("a", "b")
    end
  end

  describe "open-buffer-always-wins over disk (Task 008.6)" do
    it "never lets a disk-sourced summary overwrite a buffer-sourced one, no matter the read_sequence" do
      buffer_decl = declaration(kind: :class, owner: nil, name: "::Buffered")
      disk_decl = declaration(kind: :class, owner: nil, name: "::Stale")

      index.replace_file(summary(uri: "file:///a.rb", declarations: [buffer_decl], content_hash: "buf", source: :buffer))
      # A huge read_sequence would win against another disk summary, but
      # must still lose to the buffer -- source precedence is checked
      # before read_sequence, not instead of a version/sequence comparison
      # that happens to favor disk.
      accepted = index.replace_file(
        summary(uri: "file:///a.rb", declarations: [disk_decl], content_hash: "disk", source: :disk, read_sequence: 999_999)
      )

      expect(accepted).to be(false)
      expect(index.declarations(buffer_decl.symbol_id)).to eq([buffer_decl])
      expect(index.declarations(disk_decl.symbol_id)).to eq([])
    end

    it "lets a buffer-sourced summary overwrite an existing disk-sourced one unconditionally" do
      disk_decl = declaration(kind: :class, owner: nil, name: "::FromDisk")
      buffer_decl = declaration(kind: :class, owner: nil, name: "::FromBuffer")

      index.replace_file(summary(uri: "file:///a.rb", declarations: [disk_decl], content_hash: "disk", source: :disk, read_sequence: 5))
      accepted = index.replace_file(
        summary(uri: "file:///a.rb", declarations: [buffer_decl], content_hash: "buf", source: :buffer, version: 1)
      )

      expect(accepted).to be(true)
      expect(index.declarations(buffer_decl.symbol_id)).to eq([buffer_decl])
      expect(index.declarations(disk_decl.symbol_id)).to eq([])
    end

    it "orders two disk-sourced summaries by read_sequence (when each started reading), not by call order" do
      stale_decl = declaration(kind: :class, owner: nil, name: "::Stale")
      fresh_decl = declaration(kind: :class, owner: nil, name: "::Fresh")

      # Simulates a slow background walk (e.g. Cold Index) starting to
      # read stale content *before* a fast targeted reindex starts
      # reading fresh content -- but the fast one finishes (calls
      # #replace_file) first.
      stale_sequence = index.next_read_sequence
      fresh_sequence = index.next_read_sequence

      index.replace_file(
        summary(uri: "file:///a.rb", declarations: [fresh_decl], content_hash: "fresh", source: :disk, read_sequence: fresh_sequence)
      )
      accepted = index.replace_file(
        summary(uri: "file:///a.rb", declarations: [stale_decl], content_hash: "stale", source: :disk, read_sequence: stale_sequence)
      )

      expect(accepted).to be(false) # the stale read must lose even though it arrived second
      expect(index.declarations(fresh_decl.symbol_id)).to eq([fresh_decl])
      expect(index.declarations(stale_decl.symbol_id)).to eq([])
    end

    it "holds the buffer-wins guarantee under real concurrent replace_file calls from many threads" do
      buffer_decl = declaration(kind: :class, owner: nil, name: "::Buffered")
      index.replace_file(summary(uri: "file:///race.rb", declarations: [buffer_decl], content_hash: "buf", source: :buffer))

      disk_decl = declaration(kind: :class, owner: nil, name: "::Stale")
      threads = Array.new(30) do |i|
        Thread.new do
          sequence = index.next_read_sequence
          index.replace_file(
            summary(uri: "file:///race.rb", declarations: [disk_decl], content_hash: "disk#{i}", source: :disk,
                    read_sequence: sequence)
          )
        end
      end
      threads.each(&:join)

      expect(index.declarations(buffer_decl.symbol_id)).to eq([buffer_decl])
      expect(index.declarations(disk_decl.symbol_id)).to eq([])
    end

    it "promotes a disk-sourced entry to :buffer when an opened file's content happens to match disk exactly, even though that's a content-hash no-op" do
      decl = declaration(kind: :class, owner: nil, name: "::Unchanged")
      # Disk-sourced first (e.g. Cold Index reaches it before anyone
      # opens it), then a didOpen for the exact same, unmodified content
      # -- the ordinary case: most files are opened without having been
      # edited first.
      index.replace_file(summary(uri: "file:///a.rb", declarations: [decl], content_hash: "same", source: :disk, read_sequence: 1))
      accepted = index.replace_file(summary(uri: "file:///a.rb", declarations: [decl], content_hash: "same", source: :buffer, version: 1))

      expect(accepted).to be(true)

      # The entry must now behave as buffer-sourced: a later disk read
      # with *different* content (the file changed on disk while still
      # open, or a stale background read racing in) must be rejected
      # unconditionally, exactly like the "never lets a disk-sourced
      # summary overwrite a buffer-sourced one" case above -- if the
      # promotion above didn't actually happen, this disk write would be
      # compared via read_sequence (both :disk) and incorrectly accepted.
      stale_disk_decl = declaration(kind: :class, owner: nil, name: "::StaleFromDisk")
      rejected = index.replace_file(
        summary(uri: "file:///a.rb", declarations: [stale_disk_decl], content_hash: "different", source: :disk,
                read_sequence: 999_999)
      )

      expect(rejected).to be(false)
      expect(index.declarations(decl.symbol_id)).to eq([decl])
      expect(index.declarations(stale_disk_decl.symbol_id)).to eq([])
    end
  end

  describe "#declarations_for_uri (Task 013 review fix)" do
    it "returns every Declaration currently indexed for a uri, regardless of which source populated it" do
      decl = declaration(kind: :instance_method, owner: "::Widget", name: "build")
      index.replace_file(summary(uri: "file:///a.rb", declarations: [decl], source: :disk))

      expect(index.declarations_for_uri("file:///a.rb")).to eq([decl])
    end

    it "returns [] for a uri nothing has ever indexed" do
      expect(index.declarations_for_uri("file:///never.rb")).to eq([])
    end

    it "returns [] after the uri's contribution has been removed" do
      decl = declaration(kind: :instance_method, owner: "::Widget", name: "build")
      index.replace_file(summary(uri: "file:///a.rb", declarations: [decl]))
      index.remove_file("file:///a.rb")

      expect(index.declarations_for_uri("file:///a.rb")).to eq([])
    end

    it "reflects the previous version's declarations when called before a #replace_file that supersedes them" do
      old_decl = declaration(kind: :instance_method, owner: "::Widget", name: "old_name")
      index.replace_file(summary(uri: "file:///a.rb", declarations: [old_decl], content_hash: "v1"))

      before_replace = index.declarations_for_uri("file:///a.rb")
      new_decl = declaration(kind: :instance_method, owner: "::Widget", name: "new_name")
      index.replace_file(summary(uri: "file:///a.rb", declarations: [new_decl], content_hash: "v2"))

      expect(before_replace).to eq([old_decl]) # captured before the replace, not mutated by it
      expect(index.declarations_for_uri("file:///a.rb")).to eq([new_decl])
    end
  end

  # Indexed class names are always `::`-qualified, so a bare argument
  # matches nothing. The normalisation used to sit in `Server`, in one
  # caller, written by hand -- the shape 0.1.11 was spent removing. It
  # belongs to the lookup: every caller needs it, and here it is a
  # difference a test can see (0.1.12, round 5).
  describe "#class_declarations" do
    before do
      index.replace_file(
        summary(uri: "file:///admin/company.rb",
                declarations: [declaration(kind: :class, owner: "::Admin", name: "::Admin::Company", line: 1)])
      )
    end

    it "finds a class asked for by its qualified name" do
      expect(index.class_declarations("::Admin::Company").map { |d| d[:uri] }).to eq(["file:///admin/company.rb"])
    end

    it "finds the same class asked for without the leading `::`" do
      expect(index.class_declarations("Admin::Company").map { |d| d[:uri] }).to eq(["file:///admin/company.rb"])
    end

    it "carries each declaration's own range, not just its uri" do
      expect(index.class_declarations("Admin::Company").first[:range]).to eq(
        { start: { line: 1, character: 0 }, end: { line: 1, character: 1 } }
      )
    end

    # Normalising a prefix is not matching by simple name.
    it "does not answer for a same-named class in another namespace" do
      expect(index.class_declarations("Sales::Company")).to eq([])
      expect(index.class_declarations("Company")).to eq([])
    end

    it "answers #class_declaration_uris on the same terms" do
      expect(index.class_declaration_uris("Admin::Company")).to eq(["file:///admin/company.rb"])
    end

    # The method's own name says class, its filter and its doc comment say
    # class *or module*, and nothing exercised the second half of that
    # (0.1.12, round 7).
    it "finds a module, not only a class" do
      index.replace_file(
        summary(uri: "file:///shared.rb",
                declarations: [declaration(kind: :module, owner: nil, name: "::Shared")])
      )

      expect(index.class_declarations("Shared").map { |d| d[:uri] }).to eq(["file:///shared.rb"])
    end

    # A method is not one of the two kinds this answers for, even when it
    # is the only thing carrying the name.
    it "does not answer for a declaration that is neither a class nor a module" do
      index.replace_file(
        summary(uri: "file:///m.rb",
                declarations: [declaration(kind: :instance_method, owner: "::Holder", name: "::Solo")])
      )

      expect(index.class_declarations("Solo")).to eq([])
    end
  end
end
