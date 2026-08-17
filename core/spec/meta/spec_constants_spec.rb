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
# Twice during the 0.2.x work. `server_declaration_position_spec.rb`
# collided with `server_receiverless_spec.rb` over `SOURCE` and was
# caught only because it happened to break an example outright; a spec
# on the 0.2.4-bound branch collided with the same file over the same
# name and was not caught at all -- it ran for two review rounds against
# a fixture from another file. Hence a check rather than a third rename.
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
  # (the 0.2.4-bound branch's round 36 demonstrated both: a heredoc
  # containing that line hid every constant below it, and
  # `ANCHOR_PREFIX` inside `module DeferredFindings` was reported as a
  # top-level one).
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
        # A path form counts only when it is rooted (`class ::Foo`) or
        # explicitly `Object::`-prefixed; `class Ns::In` writes onto
        # `Ns`, which is not this guard's business.
        path = child.constant_path
        if path.is_a?(Prism::ConstantReadNode)
          names << path.slice
        elsif path.is_a?(Prism::ConstantPathNode) && object_scoped_path?(path)
          names << path.name.to_s
        end
      when Prism::ConstantWriteNode
        names << child.name.to_s
        collect_object_constants(child, names)
      when Prism::ConstantPathWriteNode
        # `::FOO = ...` and `Object::FOO = ...` -- Prism parses both as a
        # path write, so the plain `ConstantWriteNode` branch above never
        # sees them, and the external review of the 0.2.3 release PR
        # showed two files could collide in that spelling unseen.
        target = child.target
        names << target.name.to_s if target.is_a?(Prism::ConstantPathNode) && object_scoped_path?(target)
        collect_object_constants(child, names)
      else
        collect_object_constants(child, names)
      end
    end
  end

  # `::FOO` (parent nil) and `Object::FOO` both land on `Object`;
  # `Ns::FOO` lands on `Ns`.
  def self.object_scoped_path?(path)
    parent = path.parent
    parent.nil? || (parent.is_a?(Prism::ConstantReadNode) && parent.slice == "Object")
  end

  # The walker itself, stated with the cases that must *fail*. Round 39
  # blinded `object_constants` to return `[]` for every file and this
  # file stayed green: a guard that sees nothing passes exactly as
  # happily as one that sees everything, and this is the third
  # implementation of a walk whose first two were both wrong in that
  # direction. Each example below is one of those two bugs.
  describe ".object_constants" do
    it "finds a constant inside a nested describe, which is still Object's" do
      source = <<~RUBY
        RSpec.describe "outer" do
          describe "inner" do
            DEEP = "x"
          end
        end
      RUBY

      expect(self.class.object_constants(source)).to eq(["DEEP"])
    end

    it "does not find one inside a class or module, which is not" do
      source = <<~RUBY
        module Wrapper
          SCOPED = "x"
        end

        class Holder
          ALSO_SCOPED = "x"
        end
      RUBY

      # `Wrapper` and `Holder` themselves *are* Object's constants -- a
      # top-level class or module name is exactly that, and the walker is
      # right to report them. What must not appear is what is assigned
      # *inside* them, which is the second implementation's bug.
      found = self.class.object_constants(source)

      expect(found).not_to include("SCOPED", "ALSO_SCOPED")
      expect(found).to eq(%w[Wrapper Holder])
    end

    # The external review of the 0.2.3 release PR found the third
    # implementation blind in a fourth direction: Prism parses
    # `::FOO = ...` and `Object::FOO = ...` as `ConstantPathWriteNode`,
    # not `ConstantWriteNode`, so two files defining the same constant
    # in that spelling never met the census. Same for `class ::Foo`,
    # whose `constant_path` is a `ConstantPathNode` the class branch's
    # `ConstantReadNode` guard skipped. All of these land on `Object`;
    # `Ns::BAR = ...` and `class Ns::In` land on `Ns` and must not be
    # collected -- the fixture distinguishes the two.
    it "finds a rooted or Object-prefixed assignment, which is also Object's" do
      source = <<~RUBY
        RSpec.describe "outer" do
          ::ROOTED = "x"
          Object::PREFIXED = "x"
          Namespace::SCOPED_PATH = "x"
        end
      RUBY

      found = self.class.object_constants(source)

      expect(found).to include("ROOTED", "PREFIXED")
      expect(found).not_to include("SCOPED_PATH")
    end

    it "finds a rooted class name, and still not a scoped path's" do
      source = <<~RUBY
        class ::RootedHolder
        end

        module Namespace
        end

        class Namespace::Inner
        end
      RUBY

      found = self.class.object_constants(source)

      expect(found).to include("RootedHolder", "Namespace")
      expect(found).not_to include("Inner")
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
