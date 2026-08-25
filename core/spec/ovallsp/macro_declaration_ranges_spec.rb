# frozen_string_literal: true

require "stringio"

# `024.27`. A macro that takes a list of names -- `attr_accessor :a, :b`,
# `enum status: { active: 0, archived: 1 }`, `delegate :name, :age, to:` --
# declared every one of those methods at the *whole call's* range, and with
# no `name_location` at all. Two consequences, both user-visible:
#
#   * the outline showed N rows whose `range` and `selectionRange` were
#     byte-identical, so picking any of them selected the whole macro
#     line rather than the name it is labelled with -- what
#     `selectionRange` is for is a client fact, and it is stated once, in
#     `docs/CLIENT_BEHAVIOUR.md`;
#   * everything that asks "which declaration is the caret on?" by taking
#     the *smallest* enclosing range had N tied candidates and picked the
#     first, so Find References on `:b` answered `a`'s references.
#
# Narrowing has two consequences of its own, and both are pinned below
# because neither is obvious from the change that caused them: the rest
# of the macro call now belongs to no method's range, so a caret on the
# keyword falls through to the enclosing class the way every other
# position in a class body already did; and a name span can lie *outside*
# the node it belongs to, which would put `selectionRange` outside
# `range`.
#
# The values below are derived from the fixture rather than typed: each
# expected range is computed by locating the token in the source text, so
# an example cannot pass by agreeing with a number somebody copied out of
# a previous run.
RSpec.describe "the source range a macro-declared method reports (024.27)" do
  let(:parser) { Ovallsp::ParserService.new }

  # A `let`, not a constant. A bare `SOURCE =` inside a `describe` block
  # assigns at *top level* -- the block is instance-eval'd, so the
  # constant lands on Object and the last spec file loaded wins. Another
  # file in this directory already has one by that name, and while these
  # examples passed on their own they failed as a directory, reading the
  # other file's fixture.
  let(:source) do
    <<~RUBY
      class Widget
        attr_accessor :alpha, :beta
        enum status: { active: 0, archived: 1 }
        scope :recent, -> { where(x: 1) }
        delegate :title, :author, to: :company
        define_method(:calc) { |v| v }
        def plain = 1
        attr_reader "quoted"
      end
    RUBY
  end

  # `source.lines[line]` and a column index into it -- the fixture's own
  # text is the only place these numbers come from.
  def span(line, token, length: token.length)
    character = source.lines[line].index(token) or raise("#{token.inspect} is not on line #{line}")
    { start: { line: line, character: character }, end: { line: line, character: character + length } }
  end

  def outline(text = source)
    document = Ovallsp::TextDocument.new(uri: "file:///widget.rb", text: text, version: 1, language_id: "ruby")
    summary = parser.summarize(document)
    Ovallsp::Index::DocumentSymbolBuilder.build(summary.declarations)
  end

  def rows(text = source)
    outline(text).first[:children].to_h { |child| [child[:name], child] }
  end

  # Does `outer` contain `inner`? An LSP position orders by line first
  # and character second, which is what comparing the pair gives --
  # `Array#<=>` rather than `<=`, because `Array` has no `<=`.
  def contains?(outer, inner)
    corner = ->(position) { [position[:line], position[:character]] }
    (corner[outer[:start]] <=> corner[inner[:start]]) <= 0 &&
      (corner[inner[:end]] <=> corner[outer[:end]]) <= 0
  end

  describe "documentSymbol" do
    # The distinguishing value: `alpha` and `beta` come from one call, so
    # "the whole call" and "this name's own token" are two different
    # answers and only one of them tells the two rows apart.
    it "gives each name a `range` of its own token, not the whole macro call" do
      expect(rows.fetch("alpha")[:range]).to eq(span(1, ":alpha"))
      expect(rows.fetch("beta")[:range]).to eq(span(1, ":beta"))
    end

    it "selects the name itself, without the colon that makes it a symbol" do
      expect(rows.fetch("alpha")[:selectionRange]).to eq(span(1, "alpha"))
      expect(rows.fetch("beta")[:selectionRange]).to eq(span(1, "beta"))
    end

    # `attr_accessor :alpha` declares two methods from *one* token, and
    # they really do share it -- so this pair being identical is the right
    # answer, and asserting it keeps a future change from splitting a
    # token that is not divisible.
    it "gives a reader and its writer the same token, because they have one" do
      expect(rows.fetch("alpha=")[:range]).to eq(rows.fetch("alpha")[:range])
      expect(rows.fetch("alpha=")[:selectionRange]).to eq(span(1, "alpha"))
    end

    # `attr_reader "quoted"` is legal Ruby and appears in the wild:
    #
    #   $ ruby -e 'class W; attr_reader "quoted"; end
    #             p W.instance_methods(false)'
    #   [:quoted]
    #   # ruby 3.4.10
    #
    # A string literal's name span excludes its quotes, the same way a
    # symbol's excludes its colon. Selecting `"quoted"` would select two
    # characters the method's name does not have.
    it "excludes the quotes when the macro was written with a string" do
      expect(rows.fetch("quoted")[:range]).to eq(span(7, '"quoted"'))
      expect(rows.fetch("quoted")[:selectionRange]).to eq(span(7, "quoted"))
    end

    it "gives each enum predicate the hash key it comes from" do
      expect(rows.fetch("active?")[:selectionRange]).to eq(span(2, "active"))
      expect(rows.fetch("archived?")[:selectionRange]).to eq(span(2, "archived"))
      expect(rows.fetch("active?")[:range]).not_to eq(rows.fetch("archived?")[:range])
    end

    it "gives each delegated name its own token" do
      expect(rows.fetch("title")[:range]).to eq(span(4, ":title"))
      expect(rows.fetch("author")[:selectionRange]).to eq(span(4, "author"))
    end

    # `scope` and `define_method` declare exactly one method per call, and
    # the rest of the call is that method's body -- the lambda, the block.
    # There is nothing else in the call to tell apart, so `range` stays the
    # whole call and only `selectionRange` narrows.
    it "keeps the whole call as the range where the call declares one method" do
      expect(rows.fetch("recent")[:range]).to eq(span(3, "scope :recent, -> { where(x: 1) }"))
      expect(rows.fetch("recent")[:selectionRange]).to eq(span(3, "recent"))
      expect(rows.fetch("calc")[:range]).to eq(span(5, "define_method(:calc) { |v| v }"))
      expect(rows.fetch("calc")[:selectionRange]).to eq(span(5, "calc"))
    end

    # A macro call written over several lines is where narrowing changes
    # a *line* and not only a column, and the start line of
    # `Declaration#location` is what hover's "Defined: file:line",
    # `Observation::Fingerprint` and `WorkspaceIndex#entry_order` read.
    # Before `024.27` both names below reported the line the `delegate`
    # keyword is on; each now reports the line it is written on. The
    # expectations come from the fixture, and the two must differ --
    # equal line numbers is precisely the old answer.
    it "reports the line each name is written on, not the line the call starts on" do
      wrapped = "class Widget\n  delegate :alpha,\n           :beta,\n           to: :company\nend\n"
      children = rows(wrapped)

      expect(children.fetch("alpha")[:range][:start][:line])
        .to eq(wrapped.lines.index { |text| text.include?(":alpha") })
      expect(children.fetch("beta")[:range][:start][:line])
        .to eq(wrapped.lines.index { |text| text.include?(":beta") })
      expect(children.fetch("alpha")[:range][:start][:line])
        .not_to eq(children.fetch("beta")[:range][:start][:line])
    end

    # `docs/CLIENT_BEHAVIOUR.md` records, against the installed
    # `vscode-languageserver-types`, that `selectionRange` must be
    # *contained by* `range`. Narrowing `range` to a name token is what
    # made that breakable, because the span Prism keeps for a literal's
    # name is not always inside the node that literal occupies. A
    # heredoc is the shape where it is not -- the `<<~` marker is the
    # node, and the text is on later lines:
    #
    #   $ ruby -rprism -e '
    #   src = "attr_reader <<~NAME\n  quoted\nNAME\n"
    #   a = Prism.parse(src).value.statements.body.first.arguments.arguments.first
    #   p [a.location.start_offset, a.location.end_offset, a.location.slice]
    #   p [a.content_loc.start_offset, a.content_loc.end_offset]'
    #   [12, 19, "<<~NAME"]
    #   [20, 29]
    #   # prism 1.9.0, ruby 3.4.10
    #
    # So the name span is taken only when it lies inside the region the
    # declaration owns, and this shape falls back to that region.
    #
    # **Not to the answer the outline gave before `024.27`.** That region
    # narrowed for this shape too -- `node:` for `attr_*` is the argument
    # now, so driven through a real server the row's `range` went from the
    # whole `attr_reader <<~NAME` call to the `<<~NAME` marker alone. What
    # is unchanged is that the two fields are equal, which is legal; the
    # value is not.
    #
    # The fixture is pathological on purpose, and Ruby says so: the name
    # the heredoc produces carries the newline, and `attr_reader` will
    # not have it.
    #
    #   $ ruby -e 'class W
    #                attr_reader <<~NAME
    #                  quoted
    #                NAME
    #              end'
    #   NameError: invalid attribute name 'quoted
    #   '
    #   # ruby 3.4.10
    #
    # So nothing here is about supporting that spelling. What the
    # example pins is the containment invariant, and this was the first
    # shape probed for it.
    it "never selects outside the range it reports, even where the name span lies outside its node" do
      heredoc = "class Widget\n  attr_reader <<~NAME\n    quoted\n  NAME\nend\n"
      children = outline(heredoc).first[:children]

      expect(children).not_to be_empty
      children.each do |child|
        expect(contains?(child[:range], child[:selectionRange]))
          .to be(true), "#{child[:name].inspect} selects #{child[:selectionRange]} outside #{child[:range]}"
      end
    end

    # The control for the example above: the fallback must be reached
    # *only* by the shape that needs it. A guard that declined for every
    # literal would satisfy the containment assertion everywhere and
    # undo `024.27`, so the same containment is asserted over the main
    # fixture, together with a name that really does narrow.
    it "still narrows every ordinary literal, and contains every selection there too" do
      rows.each_value do |child|
        expect(contains?(child[:range], child[:selectionRange]))
          .to be(true), "#{child[:name].inspect} selects #{child[:selectionRange]} outside #{child[:range]}"
      end
      expect(rows.fetch("beta")[:selectionRange]).to eq(span(1, "beta"))
      expect(rows.fetch("quoted")[:selectionRange]).to eq(span(7, "quoted"))
    end

    # The control. Narrowing a macro's ranges must not narrow a `def`'s,
    # and must not make the outline stop listing anything: a builder that
    # declined wholesale would pass every "not equal to the whole call"
    # assertion above.
    it "still reports a plain `def` unchanged, and still lists every name" do
      expect(rows.fetch("plain")[:range]).to eq(span(6, "def plain = 1"))
      expect(rows.fetch("plain")[:selectionRange]).to eq(span(6, "plain"))
      expect(rows.keys).to contain_exactly("alpha", "alpha=", "beta", "beta=", "active?", "archived?",
                                           "recent", "title", "author", "calc", "plain", "quoted")
    end
  end

  # Driven through the real server rather than by reimplementing its
  # lookup here. `Server#declaration_symbol_id_at` picks the smallest
  # declaration whose `location` contains the caret; with every name at the
  # whole call's range the candidates tied and `min_by` returned the first,
  # so Find References on the *second* name answered about the first. A
  # copy of that algorithm in this file would pin the copy.
  describe "textDocument/references from a macro's own declaration" do
    let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

    # `use` calls each name once, on its own line, so the answer to "whose
    # references are these?" is a different line number per name -- the
    # distinguishing value the tied ranges destroyed.
    let(:calls_each_name) do
      <<~RUBY
        class Widget
          attr_accessor :alpha, :beta
          delegate :title, :author, to: :company

          def use
            alpha
            beta
            title
            author
            plain
          end

          def plain = 1

          scope :recent, -> { where(x: 1) }
        end
      RUBY
    end

    def frame(hash)
      json = JSON.generate(hash)
      "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
    end

    # A fresh `StringIO` per request. Sharing one across two calls in an
    # example makes the second read the *first* call's reply, which is a
    # green example asserting nothing about the second question.
    def answer_lines(method, line, character)
      output = StringIO.new
      position = { line: line, character: character }
      input =
        frame(jsonrpc: "2.0", method: "textDocument/didOpen",
              params: { textDocument: { uri: "file:///widget.rb", text: calls_each_name,
                                        version: 1, languageId: "ruby" } }) +
        frame(jsonrpc: "2.0", id: 1, method: method,
              params: { textDocument: { uri: "file:///widget.rb" }, position: position }) +
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
      result = messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }.first[:result]
      Array(result).map { |location| location[:range][:start][:line] }
    end

    def reference_lines(line, token)
      answer_lines("textDocument/references", line, calls_each_name.lines[line].index(token))
    end

    it "answers about the name under the caret, not the first name in the call" do
      expect(reference_lines(1, "beta")).to eq([6])
      expect(reference_lines(2, "author")).to eq([8])
    end

    # The control against the opposite failure: narrowing must not make
    # the lookup find nothing. The first name in each call still answers,
    # and so does a plain `def`.
    it "still answers about the first name, and about a `def`" do
      expect(reference_lines(1, "alpha")).to eq([5])
      expect(reference_lines(2, "title")).to eq([7])
      expect(reference_lines(12, "plain")).to eq([9])
    end

    # The other side of narrowing, and the one the entry understated:
    # each name now owns only its own token, so the rest of the macro
    # call -- the keyword, the commas, `to: :company` -- belongs to no
    # method's range at all. What answers there is the enclosing class,
    # which is what this engine has always answered for a position in a
    # class body that no narrower declaration covers. That is asserted
    # against the class's own `end` rather than a typed line, so the
    # example says "the same answer as every other such position"
    # rather than repeating a number.
    #
    # Before `024.27` the macro call's range covered its keyword, the
    # tied candidates were resolved by `min_by` returning the first, and
    # a caret on `attr_accessor` answered `alpha`'s call site -- an
    # answer about a name the caret is not on. Both halves are asserted:
    # what it does answer, and what it must no longer answer.
    it "treats the macro's own keyword as the class body, not as its first name" do
      class_end = calls_each_name.lines.rindex { |text| text.start_with?("end") }
      attr_line = calls_each_name.lines.index { |text| text.include?("attr_accessor") }
      delegate_line = calls_each_name.lines.index { |text| text.include?("delegate") }
      elsewhere_in_the_body = answer_lines("textDocument/references", class_end, 0)
      on_attr_keyword = answer_lines("textDocument/references", attr_line,
                                     calls_each_name.lines[attr_line].index("attr_accessor"))

      expect(on_attr_keyword).to eq(elsewhere_in_the_body)
      expect(answer_lines("textDocument/references", delegate_line,
                          calls_each_name.lines[delegate_line].index("delegate")))
        .to eq(elsewhere_in_the_body)
      expect(on_attr_keyword).not_to eq(reference_lines(attr_line, "alpha"))
    end

    # `#declaration_named_at` reads `name_location || location`, so the
    # narrow token is what go-to-definition matches against even where
    # `location` stays wide. `scope` is the fixture that can tell those
    # two apart: its `location` is the whole call, deliberately, because
    # the lambda is the scope's body -- so a caret on the `scope`
    # keyword is inside `location` and outside `name_location`, and only
    # a reader that prefers the second declines there. Before `024.27`
    # there was no second, and it answered "you are already at the
    # definition" from anywhere on the line.
    #
    # The control is the name one token to the right, which must still
    # resolve to this declaration -- an implementation that declined for
    # the whole line would pass the first assertion on its own.
    it "reads the name token, not the whole call, where a macro keeps both" do
      scope_line = calls_each_name.lines.rindex { |text| text.include?("scope :recent") }
      keyword = calls_each_name.lines[scope_line].index("scope")
      name = calls_each_name.lines[scope_line].index("recent")

      expect(answer_lines("textDocument/definition", scope_line, keyword)).to eq([])
      expect(answer_lines("textDocument/definition", scope_line, name)).to eq([scope_line])
    end
  end
end
