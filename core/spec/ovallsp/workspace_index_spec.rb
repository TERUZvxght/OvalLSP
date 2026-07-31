# frozen_string_literal: true

RSpec.describe Ovallsp::WorkspaceIndex do
  subject(:index) { described_class.new }

  def summary(uri:, declarations:, content_hash: "hash-#{uri}", version: 1, source: :buffer, read_sequence: 0)
    Ovallsp::Index::FileSummary.new(
      uri: uri, content_hash: content_hash, document_version: version, declarations: declarations, diagnostics: [],
      source: source, read_sequence: read_sequence
    )
  end

  def declaration(kind:, owner:, name:, line: 0)
    Ovallsp::Index::Declaration.new(
      symbol_id: Ovallsp::Index::SymbolId.new(kind: kind, owner: owner, name: name, discriminator: nil),
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
  end
end
