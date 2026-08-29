# frozen_string_literal: true

require "stringio"

# `ParserService::Visitor#visit_def_node` saves three things and restores
# them in a method-level `ensure`, and its first line is a `return` that
# sits *above* two of the saves. The restore runs anyway.
#
# One of the three was already known and fixed by hoisting the save above
# the guard (the cref). The other two were not, and both are live:
#
# - `@scope_stack` is popped by the `ensure` for a push the `return`
#   skipped, so the frame the *enclosing* construct opened is thrown away
#   and every local written after it is attributed to one scope further
#   out. Two unrelated locals of the same name then share one
#   `owner#scope_id`, which is the key `Rename::Planner` selects edits by.
# - `@included_hook_parameter` is restored from a local the `return`
#   never assigned, so it is cleared to nil — and `base.extend(...)` in
#   the rest of an old-style concern's `self.included` stops being
#   recognised as the concern hook.
#
# The guard fires for a `def` written inside a block whose owner nothing
# can name — `Class.new do ... end`, `other.instance_eval { ... }`.
#
# Ruby, for the scope half. A method body does not see the local scope it
# is written in:
#
#   $ ruby -e '
#   class A
#     v = 7
#     def m1
#       v
#     end
#   end
#   begin
#     A.new.m1
#   rescue NameError => e
#     p e.class
#   end
#   '
#   # => NameError
#   # ruby 3.4.10
#
# and that is just as true inside an anonymous class:
#
#   $ ruby -e '
#   Anon = Class.new do
#     n = 5
#     def a
#       defined?(n)
#     end
#   end
#   p Anon.new.a
#   '
#   # => nil
#   # ruby 3.4.10
#
# Ruby, for the concern half — the hook runs and the class methods arrive,
# whatever else the hook body happens to contain:
#
#   $ ruby -e '
#   module OldStyle
#     def self.included(base)
#       Class.new { def h; end }
#       base.extend(ClassMethods)
#     end
#     module ClassMethods
#       def old_cm; :cm; end
#     end
#   end
#   class Article
#     include OldStyle
#   end
#   p Article.respond_to?(:old_cm)
#   '
#   # => true
#   # ruby 3.4.10
RSpec.describe "Ovallsp::ParserService: a `def` in a nameless block and the frames around it" do
  def summarize(text, uri: "file:///a.rb")
    Ovallsp::ParserService.new.summarize(
      Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    )
  end

  # The key `Semantic::ReferenceResolver` builds a local's SymbolId from,
  # and therefore what decides whether two spellings of a name are one
  # variable.
  def local_keys(summary)
    summary.reference_candidates
           .select { |c| c.kind == :local_variable }
           .map { |c| [c.name, c.location[:start][:line], "#{c.owner}##{c.scope_id}"] }
  end

  # --- the scope frame -------------------------------------------------

  let(:anonymous_class) do
    <<~RUBY
      Anon = Class.new do
        n = 0
        def a
          n = 1
          n
        end
      end
    RUBY
  end

  it "gives the def's body a scope of its own rather than the block's" do
    keys = local_keys(summarize(anonymous_class))

    block_body = keys.find { |(_, line, _)| line == 1 }
    method_body = keys.select { |(_, line, _)| [3, 4].include?(line) }

    expect(method_body.map(&:last).uniq.size).to eq(1) # the method's own `n` is one variable
    expect(method_body.map(&:last)).not_to include(block_body.last)
  end

  # The frame the `return` never pushed is popped anyway, so the loss is
  # not confined to the block: everything after it in the *enclosing*
  # method body is attributed one scope further out, and lands on the
  # class body's own.
  let(:leaking_out) do
    <<~RUBY
      class A
        v = 0
        def m1
          k = Class.new do
            def h; end
          end
          v = 1
          v
        end
      end
    RUBY
  end

  it "leaves the enclosing method body its own scope after a nameless def" do
    keys = local_keys(summarize(leaking_out))

    class_body = keys.find { |(name, line, _)| name == "v" && line == 1 }
    method_body = keys.select { |(name, line, _)| name == "v" && [6, 7].include?(line) }

    expect(method_body.map(&:last).uniq.size).to eq(1)
    expect(method_body.map(&:last)).not_to include(class_body.last)
  end

  # The control for the two above, in the sense a wholesale decline would
  # break: the declaration is still withheld for a def nobody can name,
  # and its body is still walked.
  it "still withholds the declaration while walking the body" do
    summary = summarize(leaking_out)

    expect(summary.declarations.map { |d| d.symbol_id.name }).not_to include("h")
    expect(local_keys(summary).map(&:first)).to include("k")
  end

  # --- what the user sees ----------------------------------------------

  describe "textDocument/rename over a local beside a nameless def" do
    let(:output) { StringIO.new }
    let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

    def frame(hash)
      json = JSON.generate(hash)
      "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
    end

    def rename(text, line:, character:)
      input =
        frame(jsonrpc: "2.0", method: "textDocument/didOpen",
              params: { textDocument: { uri: "file:///a.rb", text: text, version: 1, languageId: "ruby" } }) +
        frame(jsonrpc: "2.0", id: 1, method: "textDocument/rename",
              params: { textDocument: { uri: "file:///a.rb" },
                        position: { line: line, character: character }, newName: "renamed" }) +
        frame(jsonrpc: "2.0", method: "exit", params: nil)
      Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger).run

      output.rewind
      reader = Ovallsp::IO::FramedReader.new(output)
      messages = []
      begin
        loop { messages << reader.read_message }
      rescue Ovallsp::IO::FramedReader::EOF
        nil
      end
      result = messages.find { |m| m[:id] == 1 }[:result]
      (result&.dig(:changes, :"file:///a.rb") || []).map { |e| e[:range][:start][:line] }
    end

    it "renames only the block body's local, not the method's" do
      expect(rename(anonymous_class, line: 1, character: 2)).to eq([1])
    end

    # The control. Renaming the *method's* local must still reach both of
    # its occurrences — a fix that narrowed every local to one edit would
    # pass the example above and be worse than the defect.
    it "still renames both occurrences of the method's own local" do
      expect(rename(anonymous_class, line: 3, character: 4)).to eq([3, 4])
    end
  end

  # --- the included hook parameter -------------------------------------

  # The pre-Concern spelling: `HierarchyIndex` reads this fact as the
  # marker that makes `include OldStyle` reach `OldStyle::ClassMethods`.
  def concern_targets(summary)
    summary.ancestor_facts.select { |f| f.relation == :concern_class_methods }.map(&:target)
  end

  it "keeps the included-hook parameter bound across a nameless def" do
    summary = summarize(<<~RUBY)
      module OldStyle
        def self.included(base)
          Class.new { def h; end }
          base.extend(ClassMethods)
        end

        module ClassMethods
          def old_cm; end
        end
      end
    RUBY

    expect(concern_targets(summary)).to eq(["ClassMethods"])
  end

  # The control: the same hook with nothing in front of it, which has
  # always worked and must keep working.
  it "recognises the hook with no nameless def in the way" do
    summary = summarize(<<~RUBY)
      module OldStyle
        def self.included(base)
          base.extend(ClassMethods)
        end

        module ClassMethods
          def old_cm; end
        end
      end
    RUBY

    expect(concern_targets(summary)).to eq(["ClassMethods"])
  end

  # --- the concern's class_methods body, which is a namespace body -----

  # `class_methods do ... end` is sugar for a `module ClassMethods` body,
  # so it opens a *namespace* and not a block frame: what is written
  # inside is at block depth zero, and the surface question reads that
  # depth. The visitor used to arrange this with a one-shot flag set
  # before dispatching the block and read-and-cleared inside the block
  # visitor; the flag is gone and the children are walked directly.
  #
  # Both spellings produce the same walk, so nothing in the suite could
  # tell them apart — this behaviour was unpinned before this example.
  # Restoring the dispatch gives the body a block frame, and an
  # unreadable macro written there stops opening the surface it should:
  # `Diagnostics::Engine` then reports calls to members the macro may
  # have defined.
  it "opens the ClassMethods surface for an unreadable macro in the block" do
    summary = summarize(<<~RUBY)
      module Taggable
        extend ActiveSupport::Concern

        class_methods do
          some_unreadable_macro :whatever
        end
      end
    RUBY

    expect(summary.open_surface_owners).to include(["Taggable::ClassMethods", :instance])
  end

  # The control, and the reason the assertion above is not "opens
  # something": inside a body that really *is* a block, the same call
  # says nothing about the enclosing owner's members, and must go on
  # saying nothing.
  it "opens nothing for the same macro written inside a lambda" do
    summary = summarize(<<~RUBY)
      module Taggable
        DEFAULT = -> { some_unreadable_macro :whatever }
      end
    RUBY

    expect(summary.open_surface_owners).to be_empty
  end
end
