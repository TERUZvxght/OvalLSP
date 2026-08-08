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

  # Parsed, not scanned. This guard has now been wrong twice in its own
  # right, and both times for the same reason: a regex over lines cannot
  # tell which constants land on `Object`.
  #
  # The first version matched indent 0--2, on the reasoning that anything
  # deeper is inside a `class` or `module` and genuinely scoped. False --
  # a constant inside a nested `describe` is still `Object::NAME`,
  # because assignment resolves lexically and a block is not a lexical
  # scope. The second counted `class`/`module` openings against `end`s,
  # which a `class Widget; end` inside a fixture string raises for ever
  # (round 36 demonstrated both: a heredoc containing that line hid every
  # constant below it, and `ANCHOR_PREFIX` inside `module DeferredFindings`
  # was reported as a top-level one).
  #
  # Prism already answers the question exactly, and this suite depends on
  # it anyway. A `ClassNode` or `ModuleNode` body is a lexical scope and
  # nothing else is, so the walk simply does not descend into those.
  def self.object_constants(source)
    parsed = Prism.parse(source)
    return [] unless parsed.success?

    names = []
    collect_object_constants(parsed.value, names)
    names
  end

  def self.collect_object_constants(node, names)
    node.compact_child_nodes.each do |child|
      case child
      when Prism::ClassNode, Prism::ModuleNode
        # Its *name* is still written at this scope -- `class Foo` inside
        # a spec file does define `Object::Foo` -- but its body is not.
        names << child.constant_path.slice if child.constant_path.is_a?(Prism::ConstantReadNode)
      when Prism::ConstantWriteNode
        names << child.name.to_s
        collect_object_constants(child, names)
      else
        collect_object_constants(child, names)
      end
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
