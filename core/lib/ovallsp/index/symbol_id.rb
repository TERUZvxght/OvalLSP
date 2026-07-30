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
