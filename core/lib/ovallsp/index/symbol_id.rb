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
      def self.qualify_owner(owner)
        owner.nil? ? nil : "::#{owner.to_s.delete_prefix('::')}"
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
        return local_path if local_path.to_s.start_with?("::")

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
      def initialize(owner: nil, **rest)
        super(owner: SymbolId.qualify_owner(owner), **rest)
      end
    end
  end
end
