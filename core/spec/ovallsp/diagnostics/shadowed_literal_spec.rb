# frozen_string_literal: true

require "tmpdir"

# `024.47`'s literal half. A workspace class that shares a core class's
# name — `Billing::Range` beside `(1..5)` — and **three readers gave
# three answers**:
#
#     hover        "Range"                     right
#     completion   billing_only, no cover?     the workspace class's members
#     diagnostics  nothing                     declined
#
# Ruby settles it. A literal is the core class, always; a namespaced
# class of the same name has nothing to do with it:
#
#   $ ruby -e '
#   module Billing; class Range; end; end
#   module Billing
#     p [(1..5).class, (1..5).class.equal?(::Range)]
#   end
#   '
#   # => [Range, true]
#   # ruby 3.4.10
#
# So the literal's type is written **rooted**, and resolution already
# gives a rooted name exactly one possible referent —
# `WorkspaceIndex#resolve_type_symbol_locked` says so in as many words,
# and it is the rule that stopped `::JSON` resolving to a gem's own
# `JSON`.
#
# `Boolean` stays bare on purpose: it is not a class, and `::Boolean`
# would name something that does not exist.
RSpec.describe "a literal whose class name a workspace class shares" do
  def completion_labels(files, subject, line:, character:)
    Dir.mktmpdir("shadowed-literal-") do |root|
      signatures = Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: root) }
      workspace_index = Ovallsp::WorkspaceIndex.new
      stack = build_analysis_stack(workspace_index: workspace_index, signatures: signatures)
      parser = Ovallsp::ParserService.new
      documents = {}
      files.each do |name, source|
        document = Ovallsp::TextDocument.new(uri: "file://#{root}/#{name}", text: source, version: 1,
                                             language_id: "ruby")
        documents[name] = document
        summary = parser.summarize(document)
        workspace_index.replace_file(summary)
        stack.hierarchy_index.replace_file(summary)
      end
      query = Ovallsp::Semantic::QueryService.new(
        workspace_index: workspace_index, method_resolver: stack.method_resolver,
        local_inferencer: stack.local_inferencer, signatures: signatures
      )
      receiver = stack.local_inferencer.infer_at(documents.fetch(subject),
                                                 { line: line, character: character })
      receiver ? query.members_of(receiver, prefix: "").map(&:name) : []
    end
  end

  WORKSPACE = "module Billing\n  class Range\n    def billing_only = 1\n  end\nend\n"
  USE = "module Billing\n  class Use\n    def go\n      r = (1..5)\n      r\n    end\n  end\nend\n"

  # **Pending, and the fix is recorded rather than applied.** Writing the
  # literal's type rooted (`::Range`) makes this pass and breaks 11
  # examples across 7 files — `capabilities_spec`'s hover row, overload
  # narrowing three ways, the constant ladder, argument type in two
  # specs, root-scoped models, non-ASCII `explainType` — because every
  # one of them reads the literal's name bare. `CLAUDE.md` records the
  # same class from 0.2.5: one line in a type converter, one failure in
  # the suite, and a second consequence a corpus found immediately.
  #
  # The direction was recorded as `024.224`'s too: a type that came from
  # a literal has an identity, and encoding it in the *name* makes every
  # reader normalise the spelling back. `024.47`'s own entry withdraws
  # that pairing — `024.224`'s cause turned out to be a swallowed
  # `UNAVAILABLE`, repaired by one guard, not the identity change — so
  # the argument rests on this entry alone and is to be made or declined
  # on its own evidence rather than on a second case that has evaporated.
  it "completes the core class's members, not the workspace class's" do
    pending("rooting the name breaks 11 examples in 7 files; the identity belongs beside it — 024.47")

    labels = completion_labels({ "ws.rb" => WORKSPACE, "use.rb" => USE }, "use.rb", line: 3, character: 6)

    expect(labels).to include("cover?")
    expect(labels).not_to include("billing_only")
  end

  # **The control.** A workspace class the user actually wrote must still
  # complete its own members — without this, "literals resolve to core"
  # passes as "nothing resolves to the workspace".
  it "still completes a workspace class's own members" do
    use = "module Billing\n  class Use\n    def go\n      r = Range.new\n      r\n    end\n  end\nend\n"

    labels = completion_labels({ "ws.rb" => WORKSPACE, "use.rb" => use }, "use.rb", line: 3, character: 6)

    expect(labels).to include("billing_only")
  end
end
