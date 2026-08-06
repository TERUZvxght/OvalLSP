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

  # Any indentation. The first version of this allowed 0--2 spaces on the
  # reasoning that deeper nesting means a `class` or `module` and is
  # genuinely scoped -- which is false, and was checked rather than
  # reasoned about the second time: a constant assigned inside a *nested*
  # `describe` is still `Object::NAME`, because constant assignment
  # resolves lexically and a block is not a lexical scope. The guard was
  # blind to `UNCLOSED` at indent 4 in the very file it was written for.
  #
  # A `class`/`module` body genuinely is scoped, so those are excluded by
  # tracking the nesting rather than by counting spaces.
  ASSIGNMENT = /^\s*([A-Z][A-Za-z0-9_]*)\s*=[^=~]/
  OPENS_SCOPE = /^\s*(?:class|module)\s+[A-Z]/
  CLOSES = /^(\s*)end\b/

  # Constant assignments in `source` that land on `Object`.
  def self.object_constants(source)
    depth = 0
    source.lines.filter_map do |line|
      if line.match?(OPENS_SCOPE)
        depth += 1
        next
      end
      depth -= 1 if depth.positive? && line.match?(CLOSES)
      next unless depth.zero?

      line[ASSIGNMENT, 1]
    end
  end

  it "defines each one in only one file" do
    owners = Hash.new { |hash, key| hash[key] = [] }

    Dir.glob(File.join(ROOT, "spec", "**", "*_spec.rb")).sort.each do |path|
      relative = path.delete_prefix("#{ROOT}/")
      self.class.object_constants(File.read(path, encoding: "UTF-8")).each do |name|
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
