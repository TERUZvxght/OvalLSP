# frozen_string_literal: true

# No two spec files may define the same top-level constant.
#
# A constant assigned inside `RSpec.describe "..." do ... end` is not
# scoped to that block -- the block's `self` is an anonymous example
# group, but constant assignment in Ruby resolves lexically, and the
# enclosing lexical scope of a `.rb` file is `Object`. So two spec files
# each writing `SOURCE = ...` are writing the same global, the second
# load wins, and RSpec loads files in sorted order.
#
# The failure is silent in the direction that matters. Ruby prints
# `warning: already initialized constant SOURCE` and carries on, and the
# file that loses gets the *other* file's fixture. Its examples still
# pass -- they are simply no longer testing what they say. Editing one
# file's fixture then changes another file's meaning, with nothing
# connecting them.
#
# Twice in 0.2.2. `server_declaration_position_spec.rb` collided with
# `server_receiverless_spec.rb` over `SOURCE` and was caught only because
# it happened to break an example outright; `server_diagnostics_debounce_spec.rb`
# collided with the same file over the same name and was not caught at
# all -- it ran for two review rounds against a fixture from another file.
# Hence a check rather than a third rename.
RSpec.describe "spec file constants" do
  ROOT = File.expand_path("../..", __dir__)

  # Assignments at the file's own indentation *or* one level in, which is
  # where an `RSpec.describe` block puts them. Deeper nesting is inside a
  # `class`/`module` and is genuinely scoped.
  ASSIGNMENT = /^ {0,2}([A-Z][A-Za-z0-9_]*)\s*=[^=~]/

  it "defines each one in only one file" do
    owners = Hash.new { |hash, key| hash[key] = [] }

    Dir.glob(File.join(ROOT, "spec", "**", "*_spec.rb")).sort.each do |path|
      relative = path.delete_prefix("#{ROOT}/")
      File.read(path, encoding: "UTF-8").scan(ASSIGNMENT) do |(name)|
        owners[name] << relative
      end
    end

    shared = owners.select { |_, files| files.uniq.length > 1 }

    expect(shared).to be_empty,
                      "constants defined in more than one spec file: " +
                      shared.map { |name, files| "#{name} (#{files.uniq.join(", ")})" }.join("; ") +
                      ". A constant in a spec file is on Object; the file that loads last wins and the " \
                      "other one silently gets its fixture. Prefix it with the file's own subject."
  end
end
