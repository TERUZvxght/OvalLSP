# OvalLSP Plugin SDK (Task 018)

A minimal, explicitly-opt-in way to teach OvalLSP Core about a Gem- or
project-specific DSL, without editing Core itself. See
`docs/design/tasks/018-static-runtime-plugin-api-and-sdk.md` for the
full design; this is the short "how do I write one" version.

## Manifest

Every plugin has a `plugin-manifest.json`, validated against
`docs/design/schemas/plugin-manifest.schema.json`:

```json
{
  "name": "ovallsp-my-plugin",
  "version": "0.1.0",
  "protocol_version": 1,
  "static_entrypoint": "lib/plugin.rb",
  "capabilities": ["staticFacts"]
}
```

- `name` must match `^[a-z0-9_-]+$`.
- `protocol_version` must equal `Ovallsp::Plugins::CURRENT_PROTOCOL_VERSION`
  (currently `1`) or the plugin is skipped, with a clear log message
  explaining the mismatch — never silently ignored.
- `static_entrypoint` / `runtime_entrypoint` are paths relative to the
  manifest's own directory.

## Static plugins

A static plugin contributes facts Core can use without running the
target Rails app: methods a DSL generates, generic-container rules, or
diagnostic checks. The entrypoint file registers a block:

```ruby
# lib/plugin.rb
Ovallsp::Plugins.register_static("ovallsp-my-plugin") do |context|
  context.register_declarations([
    { owner: "::MyModel", name: "some_generated_method", kind: :instance_method,
      return_type: Ovallsp::Types::Nominal.new(name: "Boolean") }
  ])
end
```

`context` is a `Ovallsp::Plugins::StaticContext` — a write-only
collection surface, never the real `WorkspaceIndex`. What you register
here becomes an ordinary `Index::Declaration` (so completion, hover
existence, definition, and the unknown-method diagnostic all see it for
free) plus, when you give a `return_type:`, an
`Index::GeneratedMethodFact` MethodAnalyzer resolves it from directly.

`return_type:` must be one of the `Ovallsp::Types` values — `Nominal`,
`Generic`, `Union`, `ProcType`, `TypeParameter`, `UNKNOWN`, `NIL`.
Anything else is dropped rather than carried across the process
boundary: since 0.2.6 the boundary is plain JSON that cannot name a
class, and Core rebuilds the typed value in the parent from fields it
has checked (`Plugins::Wire`, `024.73`). Before that it was
`Marshal.load`, which built whatever the stream named before any
validation ran. The registration API is unchanged, so a plugin written
against the documented contract needs no edit and
`protocol_version` stays at 1.

`context.register_generic_rules([...])` accepts
`Semantic::GenericRule` values, the same shape `map`/`select`/`find`
use for Array/Relation/CollectionProxy (see Task 011).

`context.register_diagnostics { |document, semantic_context| [...] }`
registers a diagnostic check returning an array of
`Diagnostics::Finding`.

## Runtime plugins

A runtime plugin would contribute to the Rails Runtime Agent's own
snapshot (routes/models/...) via `Ovallsp::Plugins::RuntimeContext`'s
`register_snapshot_section`/`register_reload_hook`. **Only loaded for a
trusted workspace** — a runtime plugin runs with the same code-execution
authority as the Rails app itself, so `Plugins::Loader#load_runtime`
returns `[]` unconditionally for an untrusted one, before reading a
single byte of the entrypoint. Forwarding a runtime plugin's
contribution into the actual Agent process is not implemented yet;
`RuntimeContext` collects it in isolation, but nothing in `Server`
calls `#load_runtime` today.

## Loading

OvalLSP never auto-discovers plugins from installed Gems. List manifest
paths explicitly in `initializationOptions.pluginManifests`:

```json
{
  "initializationOptions": {
    "pluginManifests": ["/absolute/path/to/ovallsp-my-plugin/plugin-manifest.json"]
  }
}
```

## Failure isolation

Every plugin entrypoint runs under `Ovallsp::Plugins::Loader`, which:

- times out a plugin that hangs (`DEFAULT_TIMEOUT_SECONDS`, 5s),
- rescues any exception the entrypoint or its registered block raises,
- disables a plugin after `MAX_CONSECUTIVE_FAILURES` (3) consecutive
  failures across separate loads,
- logs every failure with the plugin's own name, never lets one
  broken plugin affect Core, the Agent, or any other plugin.

## Example

`core/spec/fixtures/plugins/state_machine_example/` is a complete,
working minimal plugin — stand-in for a `state_machine do state
:pending end`-style DSL, registering the `pending?` method it would
generate. See `core/spec/ovallsp/server_plugins_spec.rb` for it loaded
through a real Server end to end.
