# frozen_string_literal: true

# Minimal example plugin (docs/design/tasks/018-static-runtime-plugin-api-and-sdk.md
# "最小のfixture DSLを定義し、次を生成するpluginを同梱する... `pending?`等の
# method factを返す"): stands in for a fixture DSL like
#
#   state_machine do
#     state :pending
#   end
#
# by registering the `pending?` predicate method it would generate,
# directly, on a fixture class -- proving the full plugin contribution
# pipeline (manifest -> Loader -> StaticContext -> real Declaration/
# GeneratedMethodFact -> ordinary WorkspaceIndex/MethodResolver
# resolution) works end to end without any Core code change, per this
# task's acceptance criterion "Core変更なしでfixture DSLのmethodを
# 追加できる". Scanning arbitrary source files for a `state_machine do
# ... end` block and generating one predicate per declared state is
# real per-file DSL recognition -- out of scope for this pass (see
# StaticContext's own docs); this example demonstrates the *pipeline*,
# not that specific recognition.
Rslsp::Plugins.register_static("rslsp-example-state-machine") do |context|
  context.register_declarations([
                                   { owner: "::ExampleModel", name: "pending?", kind: :instance_method,
                                     return_type: Rslsp::Types::Nominal.new(name: "Boolean") }
                                 ])
end
