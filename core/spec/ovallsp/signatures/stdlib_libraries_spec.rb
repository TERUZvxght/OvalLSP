# frozen_string_literal: true

# `024.321`. The signature environment loaded Ruby's **core** and no
# stdlib **library**, because `RBS::EnvironmentLoader.new` gives core
# alone and nothing called `add(library:)`.
#
# What that cost, driven before the fix: `declares?` answered `true` for
# `String`, `Integer`, `Array`, `Hash`, `Set`, `Time` and `File`, and
# `false` with zero ancestors for `JSON`, `Date`, `URI`, `Logger`, `CSV`
# and `Digest`. Hover, completion and go-to-definition had nothing to
# answer with across most of the standard library.
#
# It cost answers rather than correctness — a fixture requiring `json`
# and `date` produced no diagnostic of any kind, because the engine
# declines on a receiver it cannot describe. That is the direction
# section 0 prefers, and it is still a gap.
RSpec.describe "the stdlib libraries RBS ships" do
  # One environment for the whole file: loading is the expensive part and
  # every example asks the same loaded environment a different question.
  before(:context) do
    @environment = Ovallsp::Signatures::Environment.new
    @environment.load(workspace_root: nil)
  end

  # The names the entry was written from. Each is a library RBS ships and
  # an application reaches for without thinking.
  STDLIB_LIBRARY_NAMES = %w[JSON Date URI Logger CSV Digest Pathname StringIO Tempfile Forwardable].freeze

  # Core was always loaded. Without this the example below cannot tell
  # "the libraries arrived" from "the environment loaded at all".
  CORE_NAMES = %w[String Integer Array Hash Set Time File].freeze

  it "was already describing Ruby's core" do
    missing = CORE_NAMES.reject { |name| @environment.declares?(name) }

    expect(missing).to be_empty,
                       "core names the environment does not declare: #{missing.join(', ')}. " \
                       "Something is wrong with the load itself, not with the stdlib half."
  end

  it "describes the stdlib libraries too" do
    missing = STDLIB_LIBRARY_NAMES.reject { |name| @environment.declares?(name) }

    expect(missing).to be_empty,
                       "stdlib libraries the environment does not declare: #{missing.join(', ')}"
  end

  # `declares?` answering true is not the same as the chain being usable:
  # `024.223`'s `UNAVAILABLE` is a declared type whose ancestry could not
  # be built, and every reader that only adds names cannot tell the two
  # apart. A library that arrives unusable is not an improvement.
  it "can build an ancestor chain for each of them" do
    unusable = STDLIB_LIBRARY_NAMES.reject do |name|
      chain = @environment.ancestors("::#{name}")
      !Ovallsp::Signatures::Environment.unavailable?(chain) && !chain.empty?
    end

    expect(unusable).to be_empty,
                        "declared but with no usable ancestor chain: #{unusable.join(', ')}"
  end

  # The answer a user actually sees. `Date.today` is the shape the entry
  # was written about, and a method signature is what hover and
  # completion read.
  #
  # `kind: :singleton_method`, not a `discriminator:` — `#build_signature_method`
  # selects the singleton definition on `symbol_id.kind == :singleton_method`
  # and reads `discriminator` for nothing. Written the other way first,
  # this example failed against a correctly loaded `Date`, which is the
  # example testing the caller rather than the code.
  it "answers about a singleton method on one of them" do
    signature = @environment.method_signatures(
      Ovallsp::Index::SymbolId.new(kind: :singleton_method, name: "today", owner: "::Date", discriminator: nil)
    )

    expect(signature).not_to be_nil, "the environment knows ::Date but not Date.today"
    expect(signature.overloads).not_to be_empty
  end

  # The instance side, because the singleton one alone cannot tell a
  # loaded library from one whose singleton half happened to resolve.
  it "answers about an instance method on one of them" do
    signature = @environment.method_signatures(
      Ovallsp::Index::SymbolId.new(kind: :method, name: "strftime", owner: "::Date", discriminator: nil)
    )

    expect(signature).not_to be_nil, "the environment knows ::Date but not Date#strftime"
  end

  # **A library may add namespaces; it may not reopen a core class.**
  #
  # Loading all 61 brings the reopenings with them: `json` puts `to_json`
  # on `Object`, `pp` puts `pretty_inspect` there, `shellwords` puts
  # `shellescape` on `String`. Ruby does not, unless the program requires
  # those libraries — driven on the interpreter this suite runs on:
  #
  #     $ ruby -e 'class A; end; begin; A.new.to_json; rescue => e; p e.class; end'
  #     # => NoMethodError
  #     # ruby 3.4.10
  #
  #     $ ruby -e 'begin; "x".shellescape; rescue => e; p e.class; end'
  #     # => NoMethodError
  #     # ruby 3.4.10
  #
  # Offered in completion they are labels that raise when picked; hovered
  # they assert a signature the receiver has not got; and they made three
  # correct `unknown-method` reports disappear on a plain fixture, which
  # is a false negative in the guarantee the product exists for.
  #
  # So a member is kept only when the type it is declared on is one a
  # stdlib library introduced. On a type core declares, core's own
  # members are the answer.
  describe "a core class a library reopens" do
    LEAKED_ONTO_OBJECT = %w[to_json to_yaml pretty_inspect pretty_print DelegateClass Digest].freeze
    LEAKED_ONTO_STRING = %w[shellescape shellsplit parse_csv to_d].freeze

    it "does not gain the library's members on Object" do
      members = @environment.member_names("::Object", public_only: true)

      expect(members & LEAKED_ONTO_OBJECT).to be_empty
    end

    it "does not gain the library's members on String" do
      members = @environment.member_names("::String", public_only: true)

      expect(members & LEAKED_ONTO_STRING).to be_empty
    end

    # The control. Without it, a rule that dropped every member would
    # report the same clean result.
    it "still answers with core's own members" do
      members = @environment.member_names("::Object", public_only: true)

      expect(members).to include("inspect", "to_s", "frozen?", "instance_variable_get")
    end

    # And the point of the whole change: a type only a library declares
    # keeps everything, because there is no core answer to prefer.
    it "keeps every member of a class only a library declares" do
      expect(@environment.member_names("::Date", public_only: true)).to include("strftime", "leap?")
    end
  end
end
