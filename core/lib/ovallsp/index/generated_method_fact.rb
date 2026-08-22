# frozen_string_literal: true

module Ovallsp
  module Index
    # A method a Rails DSL macro (`enum`, `scope`, `delegate`, ...)
    # generates at load time, normalized to one common shape rather than
    # handling each DSL as its own special case in Server
    # (docs/design/tasks/017-rails-dsl-expansion.md "各DSLを直接Serverへ
    # 分岐追加しない。少なくとも次の共通factへ正規化する").
    #
    # - owner: the fully-qualified class the macro was called in.
    # - name / kind: same vocabulary as SymbolId -- a GeneratedMethodFact
    #   is expected to be paired with an actual Declaration (origin:
    #   :generated) carrying the matching SymbolId, so completion/hover-
    #   existence/definition already work through WorkspaceIndex/
    #   MethodResolver without this fact needing to duplicate that.
    # - parameters: array of Index::Parameter (usually [] -- none of the
    #   DSLs this task covers generate a method that takes arguments).
    # - return_type: a Types value. `Types::UNKNOWN` is a legitimate,
    #   honest value here (e.g. `delegate` when its target can't be
    #   statically resolved), not a placeholder that must be filled in
    #   later.
    # - source_location: the DSL call site's own LSP range -- what
    #   "生成元DSLへ移動できる" (definition on a generated method) points
    #   at, since there's no literal `def` for these methods anywhere.
    # - origin: which DSL produced this (:enum, :scope, :delegate, ...).
    # - confidence: :high for every fact this task produces -- everything
    #   recognized here comes from a literal, statically-parseable macro
    #   call, never a dynamic/runtime-only shape (those simply aren't
    #   recognized at all, rather than guessed at).
    # - metadata: origin-specific extra detail (e.g. delegate's `to:`
    #   target and delegated method name, enum's value name) --
    #   deliberately a plain Hash rather than per-origin subtypes, so a
    #   consumer that only cares about return_type/location never needs
    #   to know every DSL's own shape.
    GeneratedMethodFact = Data.define(:owner, :name, :kind, :parameters, :return_type, :source_location, :origin,
                                       :confidence, :metadata) do
      def initialize(parameters: [], metadata: {}, **rest)
        super(parameters: parameters, metadata: metadata, **rest)
      end
    end
  end
end
