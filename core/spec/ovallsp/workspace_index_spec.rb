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

    # **The nesting rule, asked of the reader that wants a name.**
    # `#nested_type_name` and `#resolve_type_symbol` share one
    # implementation of it so they cannot come to disagree, and until
    # 0.2.17 nothing asked this method anything directly -- its three
    # callers exercise it through `024.103`'s fix, which is coverage of
    # the fix rather than of the rule.
    #
    # The two same-named classes are what tells the rule from the
    # workspace-wide pick `#resolve_type_name` makes: that pick answers
    # `::Api::Thing` for a bare `Thing` whatever nesting it was written
    # in, and the whole point here is that it must not. The nil rows are
    # the other half -- **nil means "the nesting decides nothing"**, and a
    # caller rewriting a name it will hand downstream depends on getting
    # nil rather than a guess.
    it "resolves a bare name through the nesting, and answers nil where the nesting decides nothing" do
      index.replace_file(summary(uri: "file:///api.rb", content_hash: "a",
                                 declarations: [declaration(kind: :class, owner: "::Api", name: "::Api::Thing")]))
      index.replace_file(summary(uri: "file:///web.rb", content_hash: "w",
                                 declarations: [declaration(kind: :class, owner: "::Web", name: "::Web::Thing")]))

      expect(index.nested_type_name("Thing", nesting: ["::Web"])).to eq("::Web::Thing")
      expect(index.nested_type_name("Thing", nesting: ["::Api"])).to eq("::Api::Thing")
      # No frame declares it, so the nesting decides nothing -- and this
      # must not fall through to the pick, which would answer.
      expect(index.nested_type_name("Thing", nesting: ["::Other"])).to be_nil
      expect(index.nested_type_name("Thing", nesting: [])).to be_nil
      # A rooted name means the top level, whatever it is written inside.
      expect(index.nested_type_name("::Thing", nesting: ["::Web"])).to be_nil
      # The control: the pick does answer, which is what makes the four
      # nils above a decision rather than an empty index.
      expect(index.resolve_type_name("Thing")).to eq("::Api::Thing")
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
    # `apple` indexed *first*, so the asserted answer is not also the
    # insertion order: with `Zebra` first this example passed with the
    # write-time sort deleted outright, which is pinning an accident.
    it "orders uris by byte, so case decides between two files" do
      %w[apple Zebra].each do |name|
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

    # The controls for `024.137`, which moved this method off a scan of
    # every symbol and onto the index keyed by downcased simple name. Each
    # fixture distinguishes the answer from a plausible way of getting the
    # new structure wrong, rather than only asserting that some answer
    # comes back.

    # A bucket key is the *simple* name, so nothing in the namespace is
    # matchable. An implementation that matched the stored qualified name
    # -- the obvious slip when the thing being scanned is a name index --
    # would return `::Billing::Invoice` here.
    it "matches the symbol's own name, not the namespace it sits in" do
      index.replace_file(
        summary(uri: "file:///a.rb",
                declarations: [declaration(kind: :class, owner: "::Billing", name: "::Billing::Invoice")])
      )

      expect(index.search("billing", limit: 10)).to be_empty
      expect(index.search("invoice", limit: 10).map { |m| m[:symbol_id].name }).to eq(["::Billing::Invoice"])
    end

    # Two classes with one simple name share a single bucket, and the
    # bucket holds a Set of SymbolIds. Reading the bucket and stopping at
    # its first element answers this with one result; both must come back,
    # in the order the ranking key gives.
    it "returns every symbol sharing a simple name across namespaces" do
      index.replace_file(
        summary(uri: "file:///s.rb",
                declarations: [declaration(kind: :class, owner: "::Sales", name: "::Sales::Invoice")])
      )
      index.replace_file(
        summary(uri: "file:///b.rb",
                declarations: [declaration(kind: :class, owner: "::Billing", name: "::Billing::Invoice")])
      )

      expect(index.search("invoice", limit: 10).map { |m| m[:symbol_id].name })
        .to eq(["::Billing::Invoice", "::Sales::Invoice"])
    end

    # The keys are stored downcased, so the *needle* has to be downcased
    # to meet them -- and so does the exact-match test that decides
    # ranking. The two halves need different fixtures, and the first
    # version of this example only had the first: `::User` sorts ahead of
    # `::UserProfile` on the name key whether or not anything ranks as
    # exact, so it answered the same under a `#rank` that compares the
    # bucket key against the *raw* query. Verified, not reasoned: with
    # `rank(matches, query.to_s, limit)` the whole file stayed green.
    #
    # The exact match has to sort *last* on the tail key for the exact
    # bucket to be the thing being observed, and that is a claim about
    # Ruby's String order, so it comes from Ruby:
    #
    #   ["::User", "::UserProfile"].sort
    #   # => ["::User", "::UserProfile"]        exact already first
    #   ["::AbstractWidget", "::Widget"].sort
    #   # => ["::AbstractWidget", "::Widget"]   exact last
    #
    # So a raw-query `#rank` -- which finds nothing exact and falls
    # through to the name -- inverts this pair and leaves the old one
    # alone. Registered in `spec/meta/pinned_mutations.yml` so the next
    # fixture that stops distinguishing this fails a check instead of
    # waiting for a reviewer.
    it "is case-insensitive in the query, for matching and for exact-match ranking" do
      index.replace_file(
        summary(uri: "file:///a.rb",
                declarations: [declaration(kind: :class, owner: nil, name: "::AbstractWidget")])
      )
      index.replace_file(
        summary(uri: "file:///z.rb", declarations: [declaration(kind: :class, owner: nil, name: "::Widget")])
      )

      expect(index.search("WIDGET", limit: 10).map { |m| m[:symbol_id].name })
        .to eq(["::Widget", "::AbstractWidget"])
    end

    # `workspace/symbol` sends an empty query when the picker opens, and
    # the result feeds VS Code's list directly. It is also the one query
    # for which every symbol in the workspace is a match.
    it "returns every symbol for the empty query the picker opens with" do
      index.replace_file(
        summary(uri: "file:///a.rb",
                declarations: [declaration(kind: :class, owner: nil, name: "::Alpha"),
                               declaration(kind: :instance_method, owner: "::Alpha", name: "run")])
      )

      expect(index.search("", limit: 10).map { |m| m[:symbol_id].name }).to eq(["::Alpha", "run"])
    end

    # `#rank` needs the bucket key to decide whether a match is exact, so
    # `#search` carries it alongside each match and drops it again on the
    # way out. Without that last step the ranking aid ships in the answer:
    # nothing downstream reads it, which is exactly why no other example
    # would notice.
    it "answers with the three keys a result is made of, not the ranking aid" do
      index.replace_file(
        summary(uri: "file:///a.rb", declarations: [declaration(kind: :class, owner: nil, name: "::Alpha")])
      )

      expect(index.search("alpha", limit: 10).map(&:keys)).to eq([%i[symbol_id uri location]])
    end

    # `#search` now reaches a symbol through its simple-name bucket, so a
    # removed symbol has to leave *both* structures or the picker keeps
    # answering with it. That is a joint invariant and this is a joint
    # control: what it distinguishes is the pair being pruned together.
    #
    # It is not the pin for either half on its own, and the first draft of
    # this comment claimed it was. Measured: stop `remove_file_locked`
    # pruning `@by_simple_name` and this example still passes -- the
    # pre-existing "removes the simple-name index entry once the last
    # declaration with that name is removed" is what fails. Nor does it
    # pin `#search`'s `fetch(symbol_id, [])`: subscripting instead leaves
    # the whole file green, because the two structures never disagree.
    # That form is this class's stated read convention rather than a
    # decision taken here -- `#initialize`'s comment gives the rule, and
    # all six readers of `@by_symbol` follow it.
    it "does not answer with a symbol whose last declaring file was removed" do
      index.replace_file(
        summary(uri: "file:///gone.rb", declarations: [declaration(kind: :class, owner: nil, name: "::Vanishing")])
      )
      index.remove_file("file:///gone.rb")

      expect(index.search("vanish", limit: 10)).to be_empty
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
  # `#method_symbol_ids` answers from a secondary index keyed on
  # [owner, kind] rather than by scanning every symbol. A secondary index
  # is only as good as its removal path, and this one is written in two
  # places (`replace_file`'s loop and `remove_file_locked`), so the cases
  # below are about it staying in step with `@by_symbol` -- a stale entry
  # here is a method offered in completion that no longer exists.
  describe "the [owner, kind] index" do
    def summary_for(text, uri)
      document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
      Ovallsp::ParserService.new.summarize(document)
    end

    it "answers with the owner's methods of that kind, and no others" do
      index.replace_file(summary_for("class W\n  def a; end\n  def self.b; end\nend\nclass X\n  def c; end\nend\n",
                                     "file:///a.rb"))

      expect(index.method_symbol_ids("::W", kind: :instance_method).map(&:name)).to eq(["a"])
      expect(index.method_symbol_ids("::W", kind: :singleton_method).map(&:name)).to eq(["b"])
      expect(index.method_symbol_ids("::X", kind: :instance_method).map(&:name)).to eq(["c"])
    end

    it "forgets a method when its file goes away" do
      index.replace_file(summary_for("class W\n  def a; end\nend\n", "file:///a.rb"))
      index.remove_file("file:///a.rb")

      expect(index.method_symbol_ids("::W", kind: :instance_method)).to be_empty
    end

    it "keeps a method two files declare until both are gone" do
      index.replace_file(summary_for("class W\n  def a; end\nend\n", "file:///a.rb"))
      index.replace_file(summary_for("class W\n  def a; end\nend\n", "file:///b.rb"))
      index.remove_file("file:///a.rb")

      expect(index.method_symbol_ids("::W", kind: :instance_method).map(&:name)).to eq(["a"])

      index.remove_file("file:///b.rb")

      expect(index.method_symbol_ids("::W", kind: :instance_method)).to be_empty
    end

    it "does not list a method twice when two files declare it" do
      index.replace_file(summary_for("class W\n  def a; end\nend\n", "file:///a.rb"))
      index.replace_file(summary_for("class W\n  def a; end\nend\n", "file:///b.rb"))

      expect(index.method_symbol_ids("::W", kind: :instance_method).map(&:name)).to eq(["a"])
    end

    it "drops a method a re-index removed from the file that declared it" do
      index.replace_file(summary_for("class W\n  def a; end\n  def b; end\nend\n", "file:///a.rb"))
      index.replace_file(summary_for("class W\n  def a; end\nend\n", "file:///a.rb"))

      expect(index.method_symbol_ids("::W", kind: :instance_method).map(&:name)).to eq(["a"])
    end

    # An unordered collection read by `.first` or truncated is what
    # 024.15 was spent on; this one is sorted where it is read.
    it "answers in a stable order regardless of which file was indexed last" do
      index.replace_file(summary_for("class W\n  def zeta; end\nend\n", "file:///z.rb"))
      index.replace_file(summary_for("class W\n  def alpha; end\nend\n", "file:///a.rb"))
      index.replace_file(summary_for("class W\n  def zeta; end\nend\n", "file:///z.rb"))

      expect(index.method_symbol_ids("::W", kind: :instance_method).map(&:name)).to eq(%w[alpha zeta])
    end
  end

  describe "#guessed_type_name?" do
    def index(text, uri: "file:///a.rb")
      document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
      index_instance.replace_file(Ovallsp::ParserService.new.summarize(document))
    end

    let(:index_instance) { described_class.new }

    # A name nothing matches was not substituted -- `resolve_type_name`
    # answers nil and every caller keeps the name as written. Calling
    # that a guess is what made this silence 2,517 `unknown-method`
    # reports over the standard library and five Rails gems: every class
    # whose superclass lives outside the corpus stopped being closed, so
    # the check went off for the whole class.
    it "is false for a name nothing in the workspace matches" do
      index("class Widget\nend\n")

      expect(index_instance.guessed_type_name?("Vendor::Gadgets::Nothing")).to be(false)
    end

    it "is true for a qualified name answered by a class from another namespace" do
      index("class Widget\nend\n")

      expect(index_instance.guessed_type_name?("Vendor::Gadgets::Widget")).to be(true)
    end

    it "is false for a name that resolved as written" do
      index("module Vendor\n  class Widget\n  end\nend\n")

      expect(index_instance.guessed_type_name?("Vendor::Widget")).to be(false)
    end

    it "is false for a bare name matching exactly one type, and true for two" do
      index("module A\n  class Collector\n  end\nend\n", uri: "file:///a.rb")
      expect(index_instance.guessed_type_name?("Collector")).to be(false)

      index("module B\n  class Collector\n  end\nend\n", uri: "file:///b.rb")
      expect(index_instance.guessed_type_name?("Collector")).to be(true)
    end
  end

  # `::JSON` is rooted: in Ruby it can only mean the top-level constant.
  # Resolution matched on the last segment alone, so a nested
  # `I18n::Backend::KeyValue::JSON` answered for it -- and the
  # undefined-method check then reported `JSON.parse` and
  # `JSON.load_file` as missing, over ordinary i18n source. Measured over
  # the 213-file gem corpus: 2 of the 18 remaining false reports.
  #
  # Answering nil is the point. Nothing in the workspace is `::JSON`, so
  # RBS answers instead, which is where the real `JSON` is.
  describe "a name written with a leading ::" do
    before do
      index.replace_file(
        summary(uri: "file:///kv.rb",
                declarations: [declaration(kind: :class, owner: "::Outer::Inner", name: "::Outer::Inner::JSON")])
      )
    end

    it "does not resolve to a same-named class in some other namespace" do
      expect(index.resolve_type_name("::JSON")).to be_nil
    end

    it "still resolves when the workspace really does declare it at top level" do
      index.replace_file(
        summary(uri: "file:///top.rb", declarations: [declaration(kind: :class, owner: nil, name: "::JSON")])
      )

      expect(index.resolve_type_name("::JSON")).to eq("::JSON")
    end

    # The distinguishing control: written *without* the ::, the same name
    # is a bare reference and the heuristic that finds the nested class is
    # the behaviour 024.15 deliberately made deterministic. This change is
    # about rootedness, not about narrowing that.
    it "leaves the bare form resolving as it did" do
      expect(index.resolve_type_name("JSON")).to eq("::Outer::Inner::JSON")
    end
  end

  # `File::Stat` resolved to a workspace `Stat` in some other namespace,
  # because resolution matched on the last segment alone and fell back to
  # the alphabetically first candidate. Completion after
  # `File.stat(path).` then offered that class's members -- byte for byte
  # what completing `Stat.new(x).` offers (`024.78`). Hover and
  # diagnostics had already been fixed; member lookup had not.
  #
  # A written namespace is a constraint, not decoration. It is still not
  # an *absolute* path -- `Inner::Klass` inside `module Outer` legitimately
  # means `Outer::Inner::Klass` -- so the test is a suffix on segment
  # boundaries rather than equality. `::Stat` does not end with
  # `File::Stat`; `::Outer::Inner::Klass` does end with `Inner::Klass`.
  #
  # Bare names are deliberately untouched. That is 024.47's territory, and
  # 0.2.1 rolled back an attempt to apply a shadowing rule to them here.
  describe "a name written with a namespace" do
    before do
      index.replace_file(
        summary(uri: "file:///stat.rb", declarations: [declaration(kind: :class, owner: nil, name: "::Stat")])
      )
      index.replace_file(
        summary(uri: "file:///nested.rb",
                declarations: [declaration(kind: :class, owner: "::Outer::Inner", name: "::Outer::Inner::Klass")])
      )
    end

    it "does not resolve to a class whose namespace is different" do
      expect(index.resolve_type_name("File::Stat")).to be_nil
    end

    it "still resolves a partially-qualified name to the class it names" do
      expect(index.resolve_type_name("Inner::Klass")).to eq("::Outer::Inner::Klass")
    end

    it "still resolves a fully-qualified name" do
      expect(index.resolve_type_name("Outer::Inner::Klass")).to eq("::Outer::Inner::Klass")
    end

    # The control: a bare name keeps the heuristic 024.15 made
    # deterministic, so this change is about written namespaces only.
    it "leaves a bare name resolving as it did" do
      expect(index.resolve_type_name("Klass")).to eq("::Outer::Inner::Klass")
      expect(index.resolve_type_name("Stat")).to eq("::Stat")
    end
  end

  # **A memo that survives a mutation is a wrong answer, not a fast one.**
  # `024.45`'s profile put `#resolve_type_symbol_locked`'s own path at the
  # top of an analysis because one file resolves the same handful of names
  # over and over, so it is memoised for one generation -- and the whole
  # of its correctness is that every mutation clears it.
  describe "the type-resolution memo" do
    def summarize(text, uri)
      Ovallsp::ParserService.new.summarize(
        Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
      )
    end

    it "stops resolving a class whose only declaration was removed" do
      index = described_class.new
      index.replace_file(summarize("class Gone\nend\n", "file:///gone.rb"))
      expect(index.resolve_type_name("Gone")).to eq("::Gone")

      index.remove_file("file:///gone.rb")

      expect(index.resolve_type_name("Gone")).to be_nil
    end

    it "resolves a class declared after the first question was asked" do
      index = described_class.new
      expect(index.resolve_type_name("Later")).to be_nil

      index.replace_file(summarize("class Later\nend\n", "file:///later.rb"))

      expect(index.resolve_type_name("Later")).to eq("::Later")
    end

    it "follows a class that moved namespace in the same file" do
      index = described_class.new
      index.replace_file(summarize("class Moved\nend\n", "file:///m.rb"))
      expect(index.resolve_type_name("Moved")).to eq("::Moved")

      index.replace_file(summarize("module Outer\n  class Moved\n  end\nend\n", "file:///m.rb"))

      expect(index.resolve_type_name("Moved")).to eq("::Outer::Moved")
    end
  end
end
