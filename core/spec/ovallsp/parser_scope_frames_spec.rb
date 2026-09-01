# frozen_string_literal: true

require "stringio"

# A local variable's identity is `owner` plus `scope_id`
# (`Semantic::ReferenceResolver#resolve_local`), so the scope id is what
# decides which occurrences of one name Find References and Rename treat
# as one variable. It was derived from the node's *kind*: every
# class/module body, `def`, `class << self` and block pushed a counter
# onto a stack, and a reference took whatever was on top.
#
# That answers a different question from the one Ruby asks. A block body
# is *both* a new binding scope for its own parameters and a closure over
# the enclosing one, and one id per lexical node cannot express both:
#
#   $ ruby -e '
#   def m
#     w = 1
#     [1].each { w = 2 }
#     w
#   end
#   p m
#   v = 1
#   f = ->(v) { v * 10 }
#   p f.call(7)
#   p v
#   '
#   # => 2
#   # => 70
#   # => 1
#   # ruby 3.4.10
#
# The first answer says the `w` inside the block is the *same* variable
# as the one outside it. The last two say the `v` inside the lambda is a
# *different* one. The innermost-open-frame rule gets both backwards.
#
# Prism has already computed the fact: every scope node carries the names
# that scope binds.
#
#   $ ruby -e '
#   require "prism"
#   src = "def m\n  w = 1\n  [1].each { |i| w = w + i }\n  w\nend\n"
#   Prism.parse(src).value.breadth_first_search { |n|
#     next false unless n.respond_to?(:locals) && !n.is_a?(Prism::BlockParametersNode)
#     p [n.class.name.split("::").last, n.locals]
#     false
#   }
#   '
#   # => ["ProgramNode", []]
#   # => ["DefNode", [:w]]
#   # => ["BlockNode", [:i]]
#   # ruby 3.4.10
#
# So a frame carries its node's `#locals`, and a reference is tagged with
# the id of the frame that *binds* the name rather than the innermost one
# that happens to be open.
RSpec.describe "Ovallsp::ParserService and the scope frame a local variable binds in" do
  let(:service) { Ovallsp::ParserService.new }

  def document(text, uri: "file:///a.rb")
    Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
  end

  def local_candidates(source)
    service.summarize(document(source)).reference_candidates.select { |c| c.kind == :local_variable }
  end

  # Every local-variable candidate as `[name, line, character] => scope_id`.
  def locals(source)
    local_candidates(source)
      .to_h { |c| [[c.name, c.location[:start][:line], c.location[:start][:character]], c.scope_id] }
  end

  # The identity Find References and Rename actually group on.
  def identity(source)
    local_candidates(source)
      .to_h do |c|
        [[c.name, c.location[:start][:line], c.location[:start][:character]], "#{c.owner}##{c.scope_id}"]
      end
  end

  # Where each candidate starts, so an example can say which occurrences
  # were recorded at all rather than only how they were grouped.
  def positions(source)
    local_candidates(source)
      .map { |c| [c.name, c.location[:start][:line], c.location[:start][:character]] }
      .sort
  end

  describe "a block closes over the enclosing scope" do
    it "gives a write outside a block and a write to the same name inside it one identity" do
      source = "def m\n  w = 1\n  [1].each { w = 2 }\n  w\nend\n"

      answers = locals(source).values_at(["w", 1, 2], ["w", 2, 13], ["w", 3, 2])

      expect(answers.uniq.length).to eq(1)
    end

    it "still separates a block parameter that shadows a same-named local" do
      # The control for the example above: if the fix were "stop opening
      # a frame for a block", this would collapse too. `s` inside the
      # block is the parameter, not the method's `s`.
      source = "def m\n  s = 1\n  [1].each { |s| s }\n  s\nend\n"

      answers = locals(source)

      expect(answers[["s", 2, 17]]).not_to eq(answers[["s", 1, 2]])
      expect(answers[["s", 3, 2]]).to eq(answers[["s", 1, 2]])
    end

    it "reaches an enclosing local from two block levels in" do
      source = "def m\n  t = 1\n  [1].each { [2].each { t = 2 } }\n  t\nend\n"

      answers = locals(source)

      expect(answers[["t", 2, 24]]).to eq(answers[["t", 1, 2]])
    end

    it "separates a name that only the block binds from a same-named local written after it" do
      # Ruby's rule in the other direction, and the one an
      # innermost-frame rule gets right by accident:
      #
      #   $ ruby -e '
      #   def m
      #     [1].each { z = 1 }
      #     defined?(z) ? "leaked" : "fresh"
      #   end
      #   p m
      #   '
      #   # => "fresh"
      #   # ruby 3.4.10
      source = "def m\n  [1].each { z = 1 }\n  z = 2\n  z\nend\n"

      answers = locals(source)

      expect(answers[["z", 1, 13]]).not_to eq(answers[["z", 2, 2]])
      expect(answers[["z", 3, 2]]).to eq(answers[["z", 2, 2]])
    end
  end

  describe "a lambda is a scope, in both of its spellings" do
    it "separates an arrow lambda's parameter from an enclosing local of the same name" do
      source = "def m\n  v = 1\n  f = ->(v) { v }\n  v\nend\n"

      answers = locals(source)

      expect(answers[["v", 2, 14]]).not_to eq(answers[["v", 1, 2]])
      expect(answers[["v", 3, 2]]).to eq(answers[["v", 1, 2]])
    end

    it "separates a name only an arrow lambda's body binds from an enclosing local" do
      # Ruby:
      #
      #   $ ruby -e '
      #   def m
      #     f = -> { n = 2; n }
      #     n = 1
      #     [f.call, n]
      #   end
      #   p m
      #   '
      #   # => [2, 1]
      #   # ruby 3.4.10
      #
      # If they were one variable `f.call` would set it to 2 and the
      # answer would be `[2, 2]`.
      source = "def m\n  f = -> { n = 2 }\n  n = 1\n  n\nend\n"

      answers = locals(source)

      expect(answers[["n", 1, 11]]).not_to eq(answers[["n", 2, 2]])
      expect(answers[["n", 3, 2]]).to eq(answers[["n", 2, 2]])
    end

    it "gives `-> { n }` and `lambda { n }` the same answer about a captured local" do
      arrow = locals("def m\n  n = 1\n  g = -> { n = 2 }\n  n\nend\n")
      block = locals("def m\n  n = 1\n  g = lambda { n = 2 }\n  n\nend\n")

      expect(arrow[["n", 2, 11]]).to eq(arrow[["n", 1, 2]])
      expect(block[["n", 2, 15]]).to eq(block[["n", 1, 2]])
    end
  end

  # The root frame comes from `ProgramNode` like every other frame comes
  # from its node, rather than being made by hand in the constructor. A
  # `def` whose declaration is withheld -- inside `Class.new do … end`,
  # which this parser cannot name -- still walks its body, so it is still
  # a scope and still opens one.
  describe "the frames at the two ends of the stack" do
    it "keeps every top-level local in the file's own frame across a nameless def" do
      source = "x = 1\nClass.new do\n  def a\n    q = 1\n  end\nend\nx = 2\nx\n"

      answers = locals(source)

      expect(answers[["x", 6, 0]]).to eq(answers[["x", 0, 0]])
      expect(answers[["x", 7, 0]]).to eq(answers[["x", 0, 0]])
      expect(answers[["x", 0, 0]]).not_to be_nil
    end

    it "gives two defs in one nameless block their own frames" do
      source = "Class.new do\n  def a\n    z = 1\n  end\n  def b\n    z = 2\n  end\nend\n"

      answers = locals(source)

      expect(answers[["z", 2, 4]]).not_to eq(answers[["z", 5, 4]])
    end

    it "binds a `rescue => e` written at the top level to the file's own frame" do
      # `ProgramNode#locals` is where Prism records it, so a hand-made
      # root frame carrying no names would decline this one outright.
      source = "begin\nrescue => e\n  e\nend\n"

      answers = locals(source)

      expect(answers[["e", 1, 10]]).not_to be_nil
      expect(answers[["e", 2, 2]]).to eq(answers[["e", 1, 10]])
    end
  end

  describe "the identities Find References groups on" do
    it "keeps two same-named locals in different methods apart" do
      source = "def a\n  x = 1\n  x\nend\ndef b\n  x = 2\n  x\nend\n"

      answers = identity(source)

      expect(answers[["x", 1, 2]]).not_to eq(answers[["x", 5, 2]])
      expect(answers[["x", 1, 2]]).to eq(answers[["x", 2, 2]])
    end

    it "keeps a class body's local apart from a same-named top-level one" do
      source = "y = 1\nclass Foo\n  y = 2\n  y\nend\ny\n"

      answers = identity(source)

      expect(answers[["y", 2, 2]]).not_to eq(answers[["y", 0, 0]])
      expect(answers[["y", 5, 0]]).to eq(answers[["y", 0, 0]])
    end

    # `class_methods do … end` is a module body written as a block, so
    # the frame has to carry the *block's* locals: the call that opens it
    # is not a scope node and has no `#locals` at all.
    it "binds a local written in a `class_methods do` body to that body" do
      source = <<~RUBY
        q = 1
        module Trackable
          extend ActiveSupport::Concern
          class_methods do
            q = 2
            q
          end
        end
        q
      RUBY

      answers = identity(source)

      expect(answers[["q", 4, 4]]).not_to eq(answers[["q", 0, 0]])
      expect(answers[["q", 5, 4]]).to eq(answers[["q", 4, 4]])
      expect(answers[["q", 8, 0]]).to eq(answers[["q", 0, 0]])
    end

    # A superclass expression is walked inside the class's own frame, and
    # Ruby evaluates it in the scope around it:
    #
    #   $ ruby -e '
    #   base = Class.new
    #   class Foo < base
    #   end
    #   p Foo.superclass.equal?(base)
    #   '
    #   # => true
    #   # ruby 3.4.10
    #
    # Searching for the frame that binds passes through the class frame
    # to the one that does, so the *scope id* is the enclosing one.
    #
    # **The owner half was wrong for two releases, and this example said
    # so.** `Semantic::ReferenceResolver#resolve_local` keys on
    # `"#{owner}##{scope_id}"`, and the occurrence in front of the class
    # took its owner from the cref there — `::Foo` — while the local it
    # names had none. The example asserted the two identities *differed*,
    # and its comment said only moving the walk outside the frame could
    # fix it: "a wider change than this one, with its own corpus to
    # drive".
    #
    # It was the wrong diagnosis. Nothing about the walk had to move: the
    # owner belongs to the frame that binds the name, and reading it from
    # there fixes this occurrence, the six `*_eval` block spellings, and
    # `024.271`'s `def` receiver with one rule. `024.277`. Driven, the
    # rename is now three edits and the file still runs.
    it "gives a superclass expression the enclosing scope's whole identity" do
      source = "base = Class.new\nclass Foo < base\nend\nbase\n"

      scopes = locals(source)
      identities = identity(source)

      expect(scopes[["base", 1, 12]]).to eq(scopes[["base", 0, 0]])
      expect(identities[["base", 1, 12]]).to eq(identities[["base", 0, 0]])
      expect(identities[["base", 3, 0]]).to eq(identities[["base", 0, 0]])
    end

    it "keeps a `class << self` body's local apart from the class body's" do
      source = "class Foo\n  k = 1\n  class << self\n    k = 2\n    k\n  end\n  k\nend\n"

      answers = identity(source)

      expect(answers[["k", 3, 4]]).not_to eq(answers[["k", 1, 2]])
      expect(answers[["k", 6, 2]]).to eq(answers[["k", 1, 2]])
    end
  end

  # Prism spells one variable's bindings with six node kinds and only two
  # were recorded, so Rename rewrote some occurrences and left the rest --
  # source that no longer runs. Ruby says every one of these names the
  # same variable:
  #
  #   $ ruby -e '
  #   def m
  #     total = 0
  #     total += 1
  #     total ||= 2
  #     total &&= 3
  #     other, total = 1, 4
  #     for total in [5]; end
  #     begin
  #       raise "x"
  #     rescue StandardError => total
  #     end
  #     total
  #   end
  #   p m.class
  #   '
  #   # => RuntimeError
  #   # ruby 3.4.10
  describe "every spelling of a binding is recorded" do
    it "records the target of `+=`" do
      expect(positions("def m\n  n = 0\n  n += 1\n  n\nend\n")).to eq([["n", 1, 2], ["n", 2, 2], ["n", 3, 2]])
    end

    it "records the target of `||=` and `&&=`" do
      expect(positions("def m\n  n = 0\n  n ||= 1\n  n &&= 2\nend\n"))
        .to eq([["n", 1, 2], ["n", 2, 2], ["n", 3, 2]])
    end

    it "records a multiple-assignment target" do
      expect(positions("def m\n  a, b = 1, 2\n  a\nend\n")).to eq([["a", 1, 2], ["a", 2, 2], ["b", 1, 5]])
    end

    it "records a rescue binding and a `for` variable" do
      expect(positions("def m\n  for i in [1]\n  end\n  begin\n  rescue => e\n  end\nend\n"))
        .to eq([["e", 4, 12], ["i", 1, 6]])
    end

    it "groups a compound write with the plain write of the same variable" do
      answers = identity("def m\n  n = 0\n  n += 1\n  [1].each { n ||= 2 }\n  n\nend\n")

      # The count as well as the grouping: with the compound spellings
      # unrecorded the two that remain agree trivially, so "they are one
      # identity" alone is an assertion this fixture cannot fail.
      expect(answers.keys.length).to eq(4)
      expect(answers.values.uniq.length).to eq(1)
    end

    # The decline, and the reason the recorder asks whether the location
    # really is the name. Prism hands back the *whole regular expression
    # literal* as a named capture's location once the literal contains an
    # escape, and a rename edit is applied to whatever range it is given:
    #
    #   $ ruby -e '
    #   require "prism"
    #   ["/(?<n>x)/o =~ s", "/(?<n>\\d)/ =~ s"].each { |src|
    #     Prism.parse(src).value.breadth_first_search { |node|
    #       p node.location.slice if node.is_a?(Prism::LocalVariableTargetNode)
    #       false
    #     }
    #   }
    #   '
    #   # => "n"
    #   # => "/(?<n>\\d)/"
    #   # ruby 3.4.10
    #
    # Recording the second *as Prism hands it over* would let Rename
    # replace the pattern with the new name, and section 0 ranks that
    # below saying nothing — which is why it was declined until 0.2.18.
    #
    # **Declining left something worse than silence, though**, and that
    # is `024.280`: the binding was not recorded and the *uses* were, so
    # a rename rewrote the uses and left the capture, and the renamed
    # name became a defined-but-nil local rather than an error. The name
    # is written literally inside the pattern, so its own range is
    # computable, and `#visit_match_write_node` records *that* — both
    # spellings now land on the name and nothing rewrites a pattern.
    it "records a named capture whose location really is the name" do
      expect(positions("def m(s)\n  /(?<n>x)/o =~ s\n  n\nend\n")).to eq([["n", 1, 6], ["n", 2, 2], ["s", 0, 6], ["s", 1, 16]])
    end

    it "records a named capture whose location is the whole literal, at the name's own range" do
      expect(positions("def m(s)\n  /(?<n>\\d)/ =~ s\n  n\nend\n"))
        .to eq([["n", 1, 6], ["n", 2, 2], ["s", 0, 6], ["s", 1, 16]])
    end

    # And exactly once. Prism gives the `/o` spelling a target whose
    # range already is the name, so both visitors would record it —
    # two identical edits in one WorkspaceEdit, and one occurrence
    # counted twice by Find References.
    it "records each named capture exactly once, whichever way Prism gives it" do
      %w[/(?<n>x)/o /(?<n>\d)/].each do |pattern|
        found = positions("def m(s)\n  #{pattern} =~ s\n  n\nend\n").select { |name, _, _| name == "n" }

        expect(found.count { |_, line, _| line == 1 }).to eq(1), "recorded the capture in #{pattern} twice"
      end
    end

    # The other decline, and the one only broken source reaches. This
    # file is what an editor holds mid-edit, and Prism recovers from
    # `Can't assign to nil` by emitting a target node for a name it does
    # *not* put in any scope's locals:
    #
    #   $ ruby -e '
    #   require "prism"
    #   res = Prism.parse("x, nil = 1, 2\n")
    #   p res.errors.map(&:message)
    #   p res.value.locals
    #   res.value.breadth_first_search { |node|
    #     p [node.class.name.split("::").last, node.name] if node.is_a?(Prism::LocalVariableTargetNode)
    #     false
    #   }
    #   '
    #   # => ["Can't assign to nil"]
    #   # => [:x]
    #   # => ["LocalVariableTargetNode", :x]
    #   # => ["LocalVariableTargetNode", :nil]
    #   # ruby 3.4.10
    #
    # Recording it would make every `nil` written this way in one method
    # a single "variable" that Rename would rewrite.
    it "declines a target Prism recovered for a name no scope binds" do
      expect(positions("def m\n  a, nil = 1, 2\n  a\nend\n")).to eq([["a", 1, 2], ["a", 2, 2]])
    end

    # The third shape the same guard reaches, and the one that was
    # already being recorded — with a range one character too wide.
    # Keyword-argument shorthand is a read whose location carries the
    # colon:
    #
    #   $ ruby -e '
    #   require "prism"
    #   Prism.parse("limit = 1\nhelper(limit:)\n").value.breadth_first_search { |node|
    #     p [node.name, node.location.slice] if node.is_a?(Prism::LocalVariableReadNode)
    #     false
    #   }
    #   '
    #   # => [:limit, "limit:"]
    #   # ruby 3.4.10
    #
    # **Recorded, and the edit expands rather than replaces.** This
    # example asserted a decline until the two halves of 0.2.17 met: one
    # cluster declined the shorthand because "the correct edit inserts
    # where Rename replaces", and the other had already made the
    # `Rename::Planner` expand it — the whole `limit:` is the site and
    # `limit: renamed` is the new text. Two `#visit_implicit_node`
    # definitions arrived in one release and the later silently replaced
    # the earlier, so the expansion was dead code until the suite said
    # so.
    #
    # A *read* is what expands. A pattern's *target* is the example below
    # and is a different question.
    it "records keyword-argument shorthand, whose edit expands it" do
      expect(positions("def m\n  limit = 1\n  helper(limit:)\n  limit\nend\n"))
        .to eq([["limit", 1, 2], ["limit", 2, 9], ["limit", 3, 2]])
    end

    # **And the shape that shows a slice comparison is not the question
    # being asked.** A *pattern's* value-omitted shorthand is reported
    # without the colon, so its slice is the bare name and the comparison
    # above passes it -- while the range handed over is both the local's
    # binding and the hash pattern's key. Prism marks all three spellings
    # the same way one node up: a value nobody wrote is an
    # `ImplicitNode`.
    #
    #   $ ruby -e '
    #   require "prism"
    #   { "in {a:}" => "case h\nin {a:}\nend\n",
    #     "h = {a:}" => "a = 1\nh = {a:}\n",
    #     "helper(limit:)" => "limit = 1\nhelper(limit:)\n" }.each { |label, src|
    #     Prism.parse(src).value.breadth_first_search { |node|
    #       next false unless node.is_a?(Prism::ImplicitNode)
    #       p [label, node.value.class.name.split("::").last, node.value.location.slice]
    #       false
    #     }
    #   }
    #   '
    #   # => ["in {a:}", "LocalVariableTargetNode", "a"]
    #   # => ["h = {a:}", "LocalVariableReadNode", "a:"]
    #   # => ["helper(limit:)", "LocalVariableReadNode", "limit:"]
    #   # ruby 3.4.10
    #
    # Two of those slices carry the colon and one does not, which is the
    # whole argument: the comparison declines two of the three by
    # accident and says nothing about the third, while the node above
    # says the same thing about all three on purpose. The pattern is the
    # worst of them to rewrite, because with an `else` branch nothing
    # raises -- the `case` quietly matches something else.
    it "declines a hash pattern's shorthand binding, whose range is the pattern's key too" do
      expect(positions("def m(h)\n  case h\n  in {a:}\n    a\n  end\nend\n"))
        .to eq([["a", 3, 4], ["h", 0, 6], ["h", 1, 7]])
    end

    # The hash-literal spelling of the same read, recorded for the same
    # reason and expanded the same way: `{a:}` is `{a: a}`, so the site
    # is `a:` and the new text is `a: renamed`.
    it "records the same shorthand written as a hash literal's value" do
      expect(positions("def m\n  a = 1\n  h = {a:}\n  a\nend\n"))
        .to eq([["a", 1, 2], ["a", 2, 7], ["a", 3, 2], ["h", 2, 2]])
    end

    # The control the two declines need, and it is the distinguishing
    # one: written out, the pattern binds through a range of its own and
    # is recorded. So the decline is about the *shorthand*, not about
    # patterns.
    it "records a pattern binding the source writes out in full" do
      expect(positions("def m(h)\n  case h\n  in {a: v}\n    v\n  end\nend\n"))
        .to eq([["h", 0, 6], ["h", 1, 7], ["v", 2, 9], ["v", 3, 4]])
    end

    # **Two edits that are each right, and a file that does not parse.**
    # A pattern may bind one name twice only when the name begins with an
    # underscore:
    #
    #   $ ruby -e '
    #   ["case [1, 2]; in [_a, _a] then :ok; end",
    #    "case [1, 2]; in [zz, zz] then :ok; end"].each { |src|
    #     begin
    #       p eval(src)
    #     rescue SyntaxError => e
    #       p e.message.include?("duplicated variable name")
    #     end
    #   }
    #   '
    #   # => :ok
    #   # => true
    #   # ruby 3.4.10
    #
    # Each range there really is the name and nothing else, so no
    # question asked *at a range* can see the problem: it is the pair
    # that is illegal, and `Rename::Planner` builds one `newText` per
    # range with no way to know two of them share a pattern. An
    # underscore-prefixed target is therefore declined, which is what
    # this tree did with all six target spellings until this release --
    # so nobody loses an answer they had. What that leaves is a partial
    # rename, published as a limitation.
    it "declines an underscore-prefixed target, which a pattern may repeat" do
      expect(positions("def m(pair)\n  case pair\n  in [_a, _a]\n    :ok\n  end\nend\n"))
        .to eq([["pair", 0, 6], ["pair", 1, 7]])
    end

    # The reach of that rule, pinned rather than left to be inferred from
    # the sentence above: it is written about targets, so it also
    # declines the underscore-prefixed ones no pattern produced, and
    # records the plain write beside them.
    it "declines an underscore-prefixed multiple-assignment target" do
      expect(positions("def m\n  _a, b = 1, 2\n  _a = 3\nend\n")).to eq([["_a", 2, 2], ["b", 1, 6]])
    end

    it "still records a target a pattern may not repeat" do
      expect(positions("def m(pair)\n  case pair\n  in [x, 1]\n    x\n  end\nend\n"))
        .to eq([["pair", 0, 6], ["pair", 1, 7], ["x", 2, 6], ["x", 3, 4]])
    end

    # **A parameter binds, and its own range is now recorded.** It was
    # not, and this example pinned the gap so it would read as a
    # decision rather than an oversight: over 1,179 gem files, 7,816 of
    # the 7,901 locals whose rename produced a file that no longer meant
    # what it meant were names a parameter declares. `024.273` named the
    # direction; 0.3.0 took it, because the same missing occurrence made
    # `documentHighlight` answer with the body alone and F1 does not
    # work for the commonest local in Ruby without it.
    it "records a parameter's own range, so a rename rewrites the `def` line too" do
      expect(positions("def m(value)\n  value * 2\nend\n")).to eq([["value", 0, 6], ["value", 1, 2]])
    end

    # **The two keyword nodes stay out, and that is the entry's own
    # exception rather than a shortfall.** `def m(by:)` spells the
    # method's interface: rewriting that `by` renames the keyword every
    # caller passes, which is a different edit from renaming a local and
    # one no caller in the workspace would be given. `024.272`.
    it "declines a keyword parameter, whose name is the method's interface" do
      expect(positions("def m(by:)\n  by * 2\nend\n")).to eq([["by", 1, 2]])
    end

    # `*rest`, `**opts` and `&blk` do bind ordinary locals, and their
    # names are the caller's business in no way at all.
    it "records the rest, keyword-rest and block parameters" do
      expect(positions("def m(*rest, **opts, &blk)\n  [rest, opts, blk]\nend\n"))
        .to eq([["blk", 0, 22], ["blk", 1, 15], ["opts", 0, 15], ["opts", 1, 9],
                ["rest", 0, 7], ["rest", 1, 3]])
    end

    # The control for that guard, and the reason it compares strings
    # rather than lengths: a local may be named in any script Ruby
    # accepts, and the comparison must not turn a legal name into a
    # decline. Ruby:
    #
    # (the magic comment is `ruby -e`'s, not this file's: with no locale
    # set, a `-e` script is read as US-ASCII and the name below is a
    # syntax error before it can be a local variable)
    #
    #   $ ruby -e '# encoding: utf-8
    #   def m
    #     名前 = 1
    #     名前
    #   end
    #   p m
    #   '
    #   # => 1
    #   # ruby 3.4.10
    it "still records a local whose name is not ASCII" do
      expect(positions("def m\n  名前 = 1\n  名前\nend\n")).to eq([["名前", 1, 2], ["名前", 2, 2]])
    end
  end

  describe "over the whole request, through the server" do
    def frame(hash)
      json = JSON.generate(hash)
      "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
    end

    def request(source, method, params)
      output = StringIO.new
      logger = instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil)
      input =
        frame(jsonrpc: "2.0", method: "textDocument/didOpen",
              params: { textDocument: { uri: "file:///a.rb", text: source, version: 1, languageId: "ruby" } }) +
        frame(jsonrpc: "2.0", id: 1, method: method, params: params) +
        frame(jsonrpc: "2.0", method: "exit", params: nil)
      Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger).run

      output.rewind
      reader = Ovallsp::IO::FramedReader.new(output)
      messages = []
      begin
        loop { messages << reader.read_message }
      rescue Ovallsp::IO::FramedReader::EOF
        nil
      end
      messages.find { |m| m[:id] == 1 }&.dig(:result)
    end

    def references(source, line, character)
      result = request(source, "textDocument/references",
                       textDocument: { uri: "file:///a.rb" },
                       position: { line: line, character: character }) || []
      result.map { |loc| [loc[:range][:start][:line], loc[:range][:start][:character]] }.sort
    end

    def renamed(source, line, character, new_name)
      result = request(source, "textDocument/rename",
                       textDocument: { uri: "file:///a.rb" },
                       position: { line: line, character: character }, newName: new_name)
      edits = result&.dig(:changes, :"file:///a.rb") || []
      lines = source.lines
      edits.sort_by { |e| [-e[:range][:start][:line], -e[:range][:start][:character]] }.each do |edit|
        row = edit[:range][:start][:line]
        lines[row] = lines[row].dup.tap do |text|
          text[edit[:range][:start][:character]...edit[:range][:end][:character]] = edit[:newText]
        end
      end
      lines.join
    end

    it "finds the write inside a block from the write outside it" do
      source = "thing = 1\n[1].each { thing = 2 }\nthing\n"

      expect(references(source, 0, 0)).to eq([[0, 0], [1, 11], [2, 0]])
    end

    it "does not offer the enclosing local's sites from inside a shadowing lambda" do
      # Renaming the method's `v` must not rewrite the lambda's own `v`,
      # which is a different variable.
      source = "def m\n  v = 1\n  f = ->(v) { v }\n  v\nend\n"

      expect(references(source, 1, 2)).to eq([[1, 2], [3, 2]])
    end

    it "rewrites the block's assignment too, so the renamed file still runs" do
      source = "def m\n  thing = 1\n  [1].each { thing = 2 }\n  thing\nend\n"

      expect(renamed(source, 1, 2, "renamed"))
        .to eq("def m\n  renamed = 1\n  [1].each { renamed = 2 }\n  renamed\nend\n")
    end

    it "leaves an arrow lambda's own parameter alone" do
      source = "def m\n  v = 1\n  f = ->(v) { v }\n  v\nend\n"

      expect(renamed(source, 1, 2, "renamed"))
        .to eq("def m\n  renamed = 1\n  f = ->(v) { v }\n  renamed\nend\n")
    end

    it "rewrites every compound spelling, so the renamed file still runs" do
      source = "def m\n  n = 0\n  n += 1\n  n ||= 2\n  other, n = 1, 3\n  n\nend\n"

      expect(renamed(source, 1, 2, "renamed"))
        .to eq("def m\n  renamed = 0\n  renamed += 1\n  renamed ||= 2\n  other, renamed = 1, 3\n  renamed\nend\n")
    end

    # **Three answers were available and 0.2.17 weighed two.** `in {a:}`
    # binds `a` from the key `a:`, so rewriting it changes which values
    # the `case` matches:
    #
    #   $ ruby -e '
    #   def before(h) = (case h; in {a:} then a + 1; else :fell_through; end)
    #   def after(h)  = (case h; in {renamed:} then renamed + 1; else :fell_through; end)
    #   p before({ a: 1 })
    #   p after({ a: 1 })
    #   '
    #   # => 2
    #   # => :fell_through
    #   # ruby 3.4.10
    #
    # `024.272` chose to leave the key and rewrite the use, on the
    # argument that a partial rename stops the file running and is
    # therefore louder than a `case` that silently takes the other
    # branch. Both of those are wrong answers; the third answer is to
    # **refuse**, which section 0 ranks above either, and which is what
    # every other unrenameable shape here already does.
    #
    # 0.3.0 takes it, not as a decision about patterns but as a
    # consequence of one about bindings: the planner refuses a local
    # whose binding site it does not record, and this binding is one of
    # the two it does not. `024.273`.
    it "refuses a hash pattern's shorthand rather than renaming half of it" do
      source = "def m(h)\n  case h\n  in {a:}\n    a\n  end\nend\n"

      expect(renamed(source, 3, 4, "renamed")).to eq(source)
    end

    it "rewrites a pattern binding the source writes out, so the renamed file still runs" do
      source = "def m(h)\n  case h\n  in {a: v}\n    v\n  end\nend\n"

      expect(renamed(source, 3, 4, "renamed"))
        .to eq("def m(h)\n  case h\n  in {a: renamed}\n    renamed\n  end\nend\n")
    end
  end

  # `024.271`. `def <local>.name` evaluates its receiver in the
  # *enclosing* scope, and the local is not visible inside the singleton
  # body at all:
  #
  #   $ ruby -e '
  #   class Runner
  #     def go
  #       ty = Object.new
  #       def ty.reads_outer
  #         defined?(ty)
  #       end
  #       [ty.reads_outer, binding.local_variable_defined?(:ty)]
  #     end
  #   end
  #   p Runner.new.go
  #   '
  #   # => [nil, true]
  #   # ruby 3.4.10
  #
  # The receiver is one of the `def` node's children, and the whole child
  # walk happened inside the method's own frame -- so the `ty` on the
  # `def` line got the method's scope id while the assignment and every
  # later read got the enclosing one. Two identities for one variable,
  # and Rename rewrote every mention *except* the one on the `def` line:
  # a WorkspaceEdit that leaves the file not running, which is `024.28`'s
  # failure exactly.
  describe "the receiver of `def <expr>.name` binds outside the method" do
    it "gives the receiver and the assignment that created it one identity" do
      source = "class Runner\n  def go\n    ty = Thing.new\n    def ty.outer\n      :x\n    end\n    ty\n  end\nend\n"

      answers = identity(source)

      expect(answers[["ty", 3, 8]]).to eq(answers[["ty", 2, 4]])
      expect(answers[["ty", 6, 4]]).to eq(answers[["ty", 2, 4]])
    end

    # The distinguishing half, and the reason the fix is not "give the
    # receiver the enclosing frame and stop there": the singleton body is
    # still its own scope, and a local written inside it is not the outer
    # one. Without this, walking the whole `def` in the enclosing frame
    # would pass the example above and be wrong.
    it "still separates a local written inside the singleton body" do
      source = "class Runner\n  def go\n    ty = Thing.new\n    def ty.outer\n      ty = 1\n      ty\n    end\n    ty\n  end\nend\n"

      answers = identity(source)

      expect(answers[["ty", 4, 6]]).not_to eq(answers[["ty", 2, 4]])
      expect(answers[["ty", 5, 6]]).to eq(answers[["ty", 4, 6]])
      expect(answers[["ty", 7, 4]]).to eq(answers[["ty", 2, 4]])
    end

    # And the receiver is still *recorded*, exactly once. Two things are
    # asserted here and they fail in opposite directions.
    #
    # **Recorded at all**: the cheapest wrong fix is to stop visiting the
    # receiver, which makes both examples above pass by having nothing to
    # compare.
    #
    # **Exactly once**: the receiver is visited before the frame, so the
    # child walk skips it. Since `024.277` gave the binding frame the
    # owner, a second visit no longer produces a *different* identity --
    # it produces a duplicate of the same one, which is two identical
    # edits in a WorkspaceEdit and one occurrence counted twice by Find
    # References. Measured: without the skip this position appears twice.
    it "records the receiver exactly once, rather than skipping or duplicating it" do
      source = "class Runner\n  def go\n    ty = Thing.new\n    def ty.outer\n      :x\n    end\n  end\nend\n"

      expect(positions(source).count(["ty", 3, 8])).to eq(1)
    end
  end

  # A local variable has no owner. Ruby's locals are lexical: the block
  # passed to `module_eval` closes over the method's `ks`, and changing
  # `self` does not change which variable that is.
  #
  #   $ ruby -e '
  #   module Mod; end
  #   def m
  #     ks = [1]
  #     Mod.module_eval do
  #       ks << 2
  #     end
  #     ks
  #   end
  #   p m
  #   '
  #   # => [1, 2]
  #   # ruby 3.4.10
  #
  # A reference candidate took its owner from `@cref` at the point of
  # *use*, and `#visit_block_node` gives an `instance_eval`, `class_eval`,
  # `module_eval` or `*_exec` block the receiver as its owner -- correctly,
  # for the macros those blocks contain. The local inside then came out
  # `::Mod#2` while the same variable outside was `nil#2`, and identity is
  # `owner#scope_id`. So Rename rewrote the outer occurrences and left the
  # inner one, which no longer names anything: the file the editor hands
  # back calls a method that does not exist.
  #
  # This is `024.271`'s cause in its general form. That entry fixed the
  # one instance -- a `def` receiver walked under the method's own cref --
  # by moving the walk. The rule is that the owner belongs to the frame
  # that *binds* the name, so it is captured when the frame is pushed and
  # read from there.
  describe "a local's identity does not follow the cref" do
    EVAL_BLOCK_SPELLINGS = %w[instance_eval instance_exec class_eval class_exec module_eval module_exec].freeze

    EVAL_BLOCK_SPELLINGS.each do |spelling|
      it "keeps one identity across a `#{spelling}` block, which changes self but not the binding" do
        source = "def m\n  ks = [1]\n  Mod.#{spelling} do\n    ks.size\n  end\n  ks\nend\n"

        answers = identity(source)

        expect(answers[["ks", 3, 4]]).to eq(answers[["ks", 1, 2]])
        expect(answers[["ks", 5, 2]]).to eq(answers[["ks", 1, 2]])
        expect(answers[["ks", 1, 2]]).not_to be_nil
      end
    end

    # The control. If the fix were "stop giving blocks an owner at all",
    # this would break: a macro written inside the same block still has to
    # be recorded against the receiver, which is why the block's cref is
    # what it is.
    it "still records a macro inside the block against the block's own owner" do
      source = "module Mod\nend\ndef m\n  ks = 1\n  Mod.module_eval do\n    attr_reader :tag\n  end\n  ks\nend\n"

      declarations = service.summarize(document(source)).declarations.map { |d| "#{d.symbol_id.owner}##{d.symbol_id.name}" }

      expect(declarations).to include("::Mod#tag")
    end

    # And the other control: two same-named locals in genuinely different
    # scopes must stay apart. An owner captured at the frame cannot be the
    # thing that separates them -- the scope id is -- so this fails if the
    # frame ever stops being distinguishing.
    it "still separates two same-named locals in different methods" do
      source = "class Host\n  def a\n    ks = 1\n    ks\n  end\n  def b\n    ks = 2\n    ks\n  end\nend\n"

      answers = identity(source)

      expect(answers[["ks", 6, 4]]).not_to eq(answers[["ks", 2, 4]])
    end
  end
end
