# frozen_string_literal: true

require "tmpdir"
require "set"

# `024.91` shape D. The signature set's `::Object` does not declare every
# name the Ruby it runs on puts on every object, and each name in that gap
# was reported as missing on the user's own class:
#
#     class Runner
#       def go
#         trap("INT") { nil }   # reported: Runner has no method named `trap`
#       end
#     end
#
# Taken from Ruby, per the expected-value rule -- `ruby 3.4.10`, no gems:
#
#     $ ruby --disable-gems -e 'p Object.private_instance_methods.include?(:trap)'
#     true
#     $ ruby --disable-gems -e 'p Object.private_instance_methods.include?(:set_trace_func)'
#     true
#     $ ruby --disable-gems -e 'p Object.private_instance_methods.include?(:iterator?)'
#     true
#
# and from RBS 4.0.3, `::Object`'s instance definition: all three absent,
# while `require`, `puts` and `format` are present. So this is a gap in
# the signature set surfacing as an assertion about the user's code, which
# is the shape section 0 ranks worst.
#
# The fix is one-directional by construction and that is the whole reason
# it is safe to make. It declines only on names Ruby itself gives every
# object, so it can never silence a typo: a typo is not such a name.
# Contrast `024.13`, whose proposed fix declined on a *proxy* -- "the
# workspace reopens a foreign class" -- and took four real typo reports
# with it.
#
# And only *core* names. `URI(...)` on the user's own class is still
# reported, because `Kernel#URI` comes from a gem, and inferring it from
# what this engine's own process happens to have loaded would be another
# guess. Indexing what the gems define is `024.R7`.
#
# Measured over 177 files of rspec-core / i18n / psych / reline, both
# sides on the identical corpus with `unresolved-constant` as a control
# at 891: `unknown-method` 18 -> 16, the two removed being rspec-core's
# real `trap` calls, and nothing introduced.
RSpec.describe "a name the signature set's Object omits and Ruby has" do
  def findings(source)
    Dir.mktmpdir("object-gap-") do |root|
      signatures = Ovallsp::Signatures::Environment.new.tap { |env| env.load(workspace_root: root) }
      workspace_index = Ovallsp::WorkspaceIndex.new
      stack = build_analysis_stack(workspace_index: workspace_index, signatures: signatures)

      document = Ovallsp::TextDocument.new(uri: "file://#{root}/runner.rb", text: source, version: 1,
                                           language_id: "ruby")
      summary = Ovallsp::ParserService.new.summarize(document)
      workspace_index.replace_file(summary)
      stack.hierarchy_index.replace_file(summary)

      context = Ovallsp::Diagnostics::SemanticContext.new(
        workspace_index: workspace_index, hierarchy_index: stack.hierarchy_index,
        method_resolver: stack.method_resolver, local_inferencer: stack.local_inferencer,
        model_registry: Ovallsp::Models::ModelRegistry.new,
        route_registry: Ovallsp::Routes::RouteRegistry.new, signatures: signatures, generation: 1
      )
      Ovallsp::Diagnostics::Engine.new
                                  .analyze(document: document, semantic_context: context, mode: :standard)
                                  .select { |f| f.code == "unknown-method" }.map(&:message)
    end
  end

  OBJECT_GAP_NAMES = %w[trap set_trace_func iterator?].freeze

  OBJECT_GAP_NAMES.each do |name|
    it "says nothing about `#{name}`, which every object has" do
      expect(findings("class Runner\n  def go\n    #{name}\n  end\nend\n")).to be_empty
    end
  end

  # The control that keeps every example above from being an assertion
  # that cannot fail. If the fix declined on the *body* rather than on
  # the name, this would go silent too and nothing else here would say so.
  it "still reports a typo written in the same body" do
    source = "class Runner\n  def go\n    trap\n    definitely_not_a_member\n  end\nend\n"
    expect(findings(source)).to eq(["Runner has no method named `definitely_not_a_member`"])
  end

  # The written list is what keeps a gem out of the answer -- see the
  # constant's comment -- but a written list is exactly the thing that
  # goes stale on the next Ruby or the next RBS. So it is re-derived
  # here, both sides, in a subprocess: `--disable-gems` so no gem can
  # widen Ruby's half, and core-only RBS so no project sig can narrow
  # RBS's. If either moves, this fails and somebody reads it.
  it "re-derives the list from a bare interpreter and core RBS" do
    # `RUBYOPT` and `RUBYLIB` must go, or bundler's own `-rbundler/setup`
    # is inherited and puts rubygems back -- `--disable-gems` then reads
    # as honoured while `gem` and `gem_original_require` are on `Object`
    # anyway. Written the other way round first, and this example is what
    # caught it: three names became six.
    bare = IO.popen({ "RUBYOPT" => nil, "RUBYLIB" => nil },
                    [RbConfig.ruby, "--disable-gems", "--disable-did_you_mean", "-e",
                     "puts (Object.private_instance_methods + Object.instance_methods).map(&:to_s)"],
                    &:read)
    expect($?).to be_success
    ruby_names = bare.lines.map(&:chomp).to_set
    expect(ruby_names.size).to be > 100 # the subprocess ran and said something

    loader = RBS::EnvironmentLoader.new(core_root: RBS::EnvironmentLoader::DEFAULT_CORE_ROOT,
                                        repository: RBS::Repository.new)
    declared = RBS::DefinitionBuilder
               .new(env: RBS::Environment.from_loader(loader).resolve_type_names)
               .build_instance(RBS::TypeName.parse("::Object")).methods.keys.map(&:to_s).to_set

    expect((ruby_names - declared).to_a.sort)
      .to eq(Ovallsp::Signatures::Environment::UNIVERSAL_RUBY_NAMES.sort)
  end

  # **A row for every Ruby CI runs, or the table goes stale the way the
  # single list did.** The example above re-derives only for the Ruby it
  # runs under, so on 3.4 it says nothing at all about the 4.0 row -- and
  # 4.0's gap was found by a job failing rather than by anything here.
  # This is the half that can be checked from any Ruby: `ci.yml`'s matrix
  # names the versions, and each of them must have been measured.
  it "carries a row for every Ruby CI runs" do
    workflow = File.read(File.expand_path("../../../../.github/workflows/ci.yml", __dir__), encoding: "UTF-8")
    matrix = workflow[/ruby:\s*\[([^\]]*)\]/, 1].to_s.scan(/"([\d.]+)"/).flatten
    informational = workflow.scan(/ruby-version:\s*"([\d.]+)"/).flatten
    exercised = (matrix + informational).uniq
    measured = Ovallsp::Signatures::Environment::UNIVERSAL_RUBY_NAMES_BY_MINOR.keys

    expect(exercised).to include("3.3", "3.4", "4.0"), "ci.yml no longer names the versions this expects"
    expect(exercised - measured).to be_empty, "no measured row for: #{(exercised - measured).join(', ')}"
  end

  # **The fallback errs towards silence, and this is the example that can
  # fail.** An unlisted Ruby has no measured row, and the two ways of
  # being wrong are not equal: a name in the list this Ruby lacks costs
  # one true report, a name missing from it costs a false report on every
  # class in the workspace. Section 0 ranks the second worse, so the
  # fallback is the union.
  it "answers an unlisted Ruby with the union of every measured row" do
    table = Ovallsp::Signatures::Environment::UNIVERSAL_RUBY_NAMES_BY_MINOR
    union = table.values.flatten.uniq.sort

    expect(Ovallsp::Signatures::Environment.universal_ruby_names_for("99.9")).to eq(union)

    # The control: a listed Ruby gets its own row, and for at least one
    # row that is *not* the union -- otherwise the assertion above would
    # hold on a table with a single entry and say nothing.
    expect(table.values.uniq.length).to be >= 2
    expect(Ovallsp::Signatures::Environment.universal_ruby_names_for("3.4")).to eq(table.fetch("3.4"))
    expect(Ovallsp::Signatures::Environment.universal_ruby_names_for("3.4")).not_to eq(union)
  end

  # And no gem may reach the list. `to_json` is on this *process*'s
  # `Object` because the suite loads `json`, and a project that never
  # requires it must still be told about a genuine typo -- what a gem
  # defines is `024.R7`'s question, not this one's.
  it "excludes a name only a loaded gem puts on Object" do
    expect(Object.private_instance_methods.include?(:to_json) ||
           Object.instance_methods.include?(:to_json)).to be(true)
    expect(Ovallsp::Signatures::Environment.universal_ruby_name?("to_json")).to be(false)
  end

  # A name the signature set already declares is not in the gap, so the
  # list cannot grow to cover names RBS answers for.
  it "excludes a name the signature set declares" do
    expect(Ovallsp::Signatures::Environment.universal_ruby_name?("puts")).to be(false)
    expect(Ovallsp::Signatures::Environment.universal_ruby_name?("definitely_not_a_member")).to be(false)
  end
end
