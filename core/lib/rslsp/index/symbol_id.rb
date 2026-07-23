# frozen_string_literal: true

module Rslsp
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
    SymbolId = Data.define(:kind, :owner, :name, :discriminator)
  end
end
