# frozen_string_literal: true

module Ovallsp
  module Index
    # Identifies semantic identity, not source location: two declarations
    # produced by reopening the same class share one SymbolId even though
    # they come from different Declaration instances (see docs/03-semantic-engine.md).
    #
    # - kind: :class, :module, :instance_method, :singleton_method, :constant
    # - owner: fully-qualified name of the enclosing class/module (e.g. "::Foo::Bar"),
    #   or nil at the top level
    # - name: the symbol's own name — fully-qualified for :class/:module
    #   (e.g. "::Foo::Bar"), plain for everything else (e.g. "company")
    # - discriminator: reserved for future overload disambiguation; nil for now
    SymbolId = Data.define(:kind, :owner, :name, :discriminator) do
      # The rule itself, reachable without building a SymbolId -- the
      # index also compares a bare owner string against stored ones, and
      # the diagnostics engine asks the signature environment with the
      # same shape of name.
      # Memoised, and by identity rather than by value, which is what
      # `symbol_id_memo_spec.rb` pins: `#eql?` was already true, so an
      # example asserting equality would pass with this reverted.
      #
      # 024.45 counted it rather than inferring it -- one `analyze` of
      # `net/http.rb` makes 1,961,027 calls here for **385** distinct
      # inputs, and every one allocated a new String. The profile that
      # entry records attributes roughly half of an analysis to building
      # and hashing `SymbolId`s, and two of these sit on the path of every
      # one of them.
      #
      # `Hash#[]=` dups and freezes a String key, so the cache's key is
      # never the caller's object and a caller mutating its own argument
      # afterwards cannot reach in. The value is frozen for the mirror
      # reason: one String is now handed to every caller.
      #
      # A class-level ivar and not a constant: the block `Data.define`
      # takes is `class_eval`'d, so an assignment here defines the
      # constant in the *enclosing* `Ovallsp::Index` rather than on this
      # class -- which is how the first version leaked one and then
      # failed its own `private_constant`.
      #
      # Unsynchronised deliberately, which is safe here and is not a
      # general licence (see 024.39): two threads racing this compute
      # the same String from the same input, so the loser wastes an
      # allocation and no reader can observe a wrong value. A mutex
      # would sit on the hottest line in an analysis to prevent that.
      #
      # Unbounded by construction, and bounded in fact by the number of
      # distinct constant names a workspace contains -- every one of which
      # the indexes already retain.
      def self.qualify_owner(owner)
        return nil if owner.nil?

        (@qualified ||= {})[owner] ||= "::#{owner.to_s.delete_prefix('::')}".freeze
      end

      # The same rule read the other way: the name without its leading
      # `::`. This is the form the type model, `Models::ModelRegistry`
      # (keyed by Rails' own bare `model.name`) and RBS's own `Nominal`
      # names use, so the two directions are one decision and belong in
      # one place. `Semantic::ReceiverResolution.canonical_receiver_name`
      # is the semantic layer's name for this and now delegates here
      # (0.1.12, round 7).
      def self.bare_name(name)
        name.to_s.delete_prefix("::")
      end

      # Lexical qualification, which is a *different* operation from the
      # two above: it prepends the enclosing owner rather than only
      # normalising a prefix. An already-root-scoped path is already
      # absolute and is left alone.
      #
      # Four byte-identical copies of this lived in `ParserService`,
      # `LocalInferencer` (twice) and `Signatures::RbiParser`. Nothing was
      # wrong with any of them, which is the point: 0.1.11 was spent on
      # what happens to a rule written once per call site, and four is
      # how many copies of the *previous* rule had to be found the hard
      # way (0.1.12, round 7).
      # The four copies each wrote this as a ternary on `owner`. It does
      # not need one: a nil owner interpolates to "", so the single form
      # produces "::Widget" at the top level and "::Admin::Widget" inside
      # one. The ternary's two arms are the same string, which is why a
      # mutation collapsing them changed nothing (0.1.12, round 7).
      def self.qualify_within(owner, local_path)
        return local_path if local_path.start_with?("::")

        "#{owner}::#{local_path}"
      end

      # An owner is stored qualified, whichever form the caller had
      # (0.1.11).
      #
      # `SymbolId` equality is exact, and `owner` arrives both ways:
      # `ParserService` indexes a declaration's owner qualified
      # (`::Object`), while `HierarchyIndex::DEFAULT_OBJECT_CHAIN` names
      # its entries bare (`Object`). Every lookup built by walking an
      # ancestor chain therefore missed for those three names -- a
      # workspace reopening `class Object` got a false `unknown-method`
      # on every closed receiver, and its methods were resolvable neither
      # by go-to-definition nor for visibility.
      #
      # Stated here because stating it at the call sites is what went
      # wrong: the rule was written four times in the diagnostics engine
      # alone and three of those had it inverted. This is the one place
      # that knows what an owner is.
      #
      # Only a leading `::` is normalized: `Admin::Object` remains a
      # different class from `::Object`. A nil owner stays nil -- a
      # class-level symbol has none, and `"::"` is not a class.
      # A class/module's own `name` is qualified too, and until 0.1.12 that
      # was documented (see this class's header) without being enforced.
      # `ParserService` always produced it that way, so nothing noticed --
      # but `Server#plugin_declaration` copies a plugin-supplied `SymbolId`
      # into the index verbatim, and `partition_plugin_facts` validates
      # only that it *is* a `SymbolId`. A plugin registering
      # `kind: :class, name: "Widget"` put a bare name into the index,
      # where `resolve_type_symbol_locked` then matched it against a
      # qualified needle and resolved the wrong class. Enforced here
      # rather than re-guarded at the one read site round 8 removed a
      # guard from: the invariant is this type's, not the reader's
      # (0.1.12, round 9).
      # `kind:` and `name:` stay required. Round 9 declared them with nil
      # defaults purely to read them here, and in doing so turned a missing
      # keyword from an `ArgumentError` at the offending call site into a
      # SymbolId with a nil name -- which indexes under "" , matches
      # nothing, and finally raises `NoMethodError` inside
      # `DocumentSymbolBuilder` as an internal error on an unrelated
      # request (0.1.12, round 10).
      def initialize(kind:, name:, owner: nil, **rest)
        qualified_name = %i[class module].include?(kind) ? SymbolId.qualify_owner(name) : name
        super(kind: kind, name: qualified_name, owner: SymbolId.qualify_owner(owner), **rest)
      end
    end
  end
end
