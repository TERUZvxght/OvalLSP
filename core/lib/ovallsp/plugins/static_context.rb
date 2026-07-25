# frozen_string_literal: true

require_relative "../index/declaration"
require_relative "../index/symbol_id"

module Ovallsp
  module Plugins
    # What a static plugin's entrypoint actually gets -- never the real
    # WorkspaceIndex object itself
    # (docs/design/tasks/018-static-runtime-plugin-api-and-sdk.md
    # "pluginへ内部WorkspaceIndex objectを直接渡さない"), only a narrow
    # write-only surface a plugin can contribute *to*. Everything a
    # plugin registers here is collected, never applied directly --
    # Plugins::Loader is what turns these into real Declarations/
    # GenericRules after the plugin's entrypoint returns, so a
    # misbehaving plugin can never reach into (or corrupt) live index
    # state mid-call.
    class StaticContext
      attr_reader :plugin_name, :declarations, :generic_rules, :diagnostic_checks

      def initialize(plugin_name)
        @plugin_name = plugin_name
        @declarations = []
        @generic_rules = []
        @diagnostic_checks = []
      end

      # `facts` is an array of Hashes: `{ owner:, name:, kind: (:instance_method/:singleton_method),
      # return_type: (optional Types value) }`. Turned into ordinary
      # Index::Declaration values (origin: :plugin) plus an
      # Index::GeneratedMethodFact when a return_type was given -- the
      # exact same normalized shape Task 017's enum/scope/delegate
      # support already produces, so completion/hover/definition/
      # unknown-method-diagnostic all work on a plugin's contributions
      # for free through the ordinary WorkspaceIndex/MethodResolver path.
      def register_declarations(facts)
        Array(facts).each do |fact|
          @declarations << {
            symbol_id: Index::SymbolId.new(kind: fact.fetch(:kind), owner: fact.fetch(:owner), name: fact.fetch(:name),
                                            discriminator: nil),
            return_type: fact[:return_type]
          }
        end
      end

      # `rules` is an array of Semantic::GenericRule values (Task 011's
      # own shape) -- a plugin can teach the generic-container evaluator
      # about its own DSL's container methods the same way Array/
      # Relation/CollectionProxy's built-in rules work.
      def register_generic_rules(rules)
        @generic_rules.concat(Array(rules))
      end

      # `block` is called as `block.call(document, semantic_context)` and
      # must return an Array of Diagnostics::Finding -- run under the
      # same per-plugin timeout/rescue isolation every other plugin
      # contribution point gets (Plugins::Loader), so a broken diagnostic
      # check degrades to "no findings from this plugin" rather than
      # ever affecting Core's own diagnostics.
      def register_diagnostics(&block)
        @diagnostic_checks << block if block
      end

      # Loader-internal: reconstructs a StaticContext in the *parent*
      # process from the plain-data `declarations` a plugin's entrypoint
      # produced in its isolated child process (Plugins::Loader,
      # #static_plugin_declarations) -- `generic_rules`/`diagnostic_checks`
      # deliberately stay empty here, since neither is consumed by
      # anything yet (confirmed by the Task 014-018 independent review)
      # and, being Proc-bearing, couldn't cross the process boundary
      # even if something did read them.
      def restore_declarations(declarations)
        @declarations = declarations
      end
    end
  end
end
