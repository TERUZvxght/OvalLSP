# frozen_string_literal: true

require "tmpdir"

# `024.45`. `Signatures::Environment`'s header says definitions are
# "built lazily per symbol_id and memoized". They were built lazily. The
# memo was `@method_cache[symbol_id] ||= build_signature_method(symbol_id)`,
# and **`||=` does not remember a `nil`.**
#
# `#build_signature_method` answers `nil` for every name the type does
# not declare — which is exactly what the undefined-method check asks
# about, because that is the question it exists to answer. So every such
# ask was a permanent cache miss that rebuilt the owner's whole RBS
# definition.
#
# Counted over one `Diagnostics::Engine#analyze` of Ruby 3.4.10's
# `net/http.rb` (2,574 lines), before:
#
#   build_definition calls: 76,365   distinct (type, singleton): 42
#     62,644 x  ::HTTP (singleton)   all via #method_signatures
#      3,796 x  ::HTTP
#      3,324 x  ::OpenSSL::SSL::SSLContext
#
# The examples assert the *shape* — one build per distinct owner, and a
# second ask for an absent name building nothing — rather than a
# duration, because a timing assertion on a shared runner measures the
# runner.
RSpec.describe "Ovallsp::Signatures::Environment and the definitions it builds" do
  def env_in(root)
    Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: root) }
  end

  # Counts through the real builder rather than stubbing it, so the
  # answers stay the answers RBS gives.
  def builds_while(env)
    tally = Hash.new(0)
    inner = env.instance_variable_get(:@definition_builder)
    spy = Class.new do
      define_method(:initialize) { |real, counts| @real = real; @counts = counts }
      define_method(:build_instance) { |n| @counts[[n.to_s, false]] += 1; @real.build_instance(n) }
      define_method(:build_singleton) { |n| @counts[[n.to_s, true]] += 1; @real.build_singleton(n) }
      define_method(:ancestor_builder) { @real.ancestor_builder }
    end.new(inner, tally)
    env.instance_variable_set(:@definition_builder, spy)
    yield
    tally
  ensure
    env.instance_variable_set(:@definition_builder, inner)
  end

  def absent_name(index)
    Ovallsp::Index::SymbolId.new(kind: :instance_method, owner: "::String",
                                 name: "definitely_not_declared_#{index}", discriminator: nil)
  end

  # The defect, in the smallest form that shows it: one name, asked
  # twice. `||=` rebuilt on the second ask because the answer was `nil`.
  it "asks the builder once for a name the type does not declare, however often it is asked" do
    Dir.mktmpdir("definition-memo-") do |root|
      env = env_in(root)
      symbol = absent_name(0)
      env.method_signatures(symbol) # first ask: a build is expected

      counts = builds_while(env) { 25.times { env.method_signatures(symbol) } }

      expect(counts).to be_empty, "asked the builder #{counts.values.sum} more time(s) for an answer it already had"
    end
  end

  # And at the scale the check actually works at: many absent names on
  # one owner is the undefined-method check's whole job, and each of them
  # used to rebuild that owner.
  it "builds one owner's definition once across many absent names" do
    Dir.mktmpdir("definition-memo-") do |root|
      env = env_in(root)

      counts = builds_while(env) { 40.times { |i| env.method_signatures(absent_name(i)) } }

      expect(counts.values.sum).to be <= 1,
                                   "rebuilt ::String #{counts.values.sum} times for 40 names it does not declare"
    end
  end

  # **The control.** Remembering `nil` must not make a name that *is*
  # declared answer `nil` too — a memo that returned the wrong answer
  # would satisfy both counts above.
  it "still answers for a name the type does declare" do
    Dir.mktmpdir("definition-memo-") do |root|
      env = env_in(root)
      declared = Ovallsp::Index::SymbolId.new(kind: :instance_method, owner: "::String",
                                              name: "upcase", discriminator: nil)

      first = env.method_signatures(declared)
      second = env.method_signatures(declared)

      expect(first).not_to be_nil
      expect(second).to eq(first)
      expect(env.method_signatures(absent_name(99))).to be_nil
    end
  end
end
