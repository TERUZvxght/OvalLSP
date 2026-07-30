# frozen_string_literal: true

require "stringio"

# Completion from a bare prefix -- no leading dot (0.2.0, closes 024.R8).
#
# Before this, `completion_result` matched a bare prefix against the route
# registry and nothing else, so typing `A` offered `article_path` and
# stopped. The locals in scope, the methods callable on self, and the
# workspace's own classes -- most of what anyone types -- appeared only
# after the whole name was written, at which point completion has nothing
# left to do.
RSpec.describe "Ovallsp::Server completion from a bare prefix (0.2.0)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def build_server(input_string)
    Ovallsp::Server.new(input: StringIO.new(input_string), output: output, logger: logger)
  end

  def sent_messages
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  def did_open(uri, text)
    frame(
      jsonrpc: "2.0", method: "textDocument/didOpen",
      params: { textDocument: { uri: uri, text: text, version: 1, languageId: "ruby" } }
    )
  end

  # The cursor is at the end of the line containing `HERE`, with the
  # marker itself removed -- so a fixture writes the prefix and where it
  # stops in one place.
  def complete(source, uri: "file:///a.rb", extra_opens: "")
    line = source.lines.index { |l| l.include?("HERE") }
    character = source.lines[line].index("HERE")
    input =
      extra_opens +
      did_open(uri, source.sub("HERE", "")) +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/completion",
        params: { textDocument: { uri: uri }, position: { line: line, character: character } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run
    sent_messages.first[:result]
  end

  def labels(result) = result[:items].map { |item| item[:label] }

  it "offers a local assigned above the cursor" do
    result = complete(<<~RUBY)
      article = Article.new
      artHERE
    RUBY

    expect(labels(result)).to include("article")
  end

  it "offers a method callable on self at that position" do
    result = complete(<<~RUBY)
      class ArticlesController
        def publish_all
        end

        def show
          pubHERE
        end
      end
    RUBY

    expect(labels(result)).to include("publish_all")
  end

  it "offers a class the workspace declares" do
    result = complete(<<~RUBY, extra_opens: did_open("file:///article.rb", "class Article\nend\n"))
      ArtHERE
    RUBY

    expect(labels(result)).to include("Article")
  end

  it "offers a Kernel method known from RBS" do
    result = complete(<<~RUBY)
      putHERE
    RUBY

    expect(labels(result)).to include("puts")
  end

  it "still offers route helpers, which were the only bare-prefix source before" do
    result = complete(<<~RUBY)
      artHERE
    RUBY

    expect(result[:items]).to be_an(Array)
  end

  # Ranking is the substance of this feature, not a refinement of it: a
  # bare prefix matches far more than a receiver does, and an editor shown
  # a thousand alphabetically-sorted candidates is worse than one shown
  # none, because the right answer is on page four and the user learns to
  # stop pressing the key. Closeness to the cursor is the order.
  it "ranks a local ahead of a same-named method on self" do
    result = complete(<<~RUBY)
      class ArticlesController
        def target
        end

        def show
          target = Article.new
          tarHERE
        end
      end
    RUBY

    first = result[:items].index { |item| item[:label] == "target" }
    expect(first).to eq(0)
  end

  it "ranks a method on self ahead of a workspace constant" do
    result = complete(<<~RUBY, extra_opens: did_open("file:///target.rb", "class Targetish\nend\n"))
      class ArticlesController
        def targetify
        end

        def show
          targetHERE
        end
      end
    RUBY

    method_at = labels(result).index("targetify")
    constant_at = labels(result).index("Targetish")
    expect(method_at).to be < constant_at
  end

  # The array order is not what the editor sorts by -- VS Code re-sorts a
  # completion list by `sortText`, falling back to the label. So the
  # ranking above is only real if it reaches the wire, and a fixture that
  # checks array positions alone passes with `sortText` deleted.
  it "renders the ranking into sortText, which is what the editor orders by" do
    result = complete(<<~RUBY)
      class ArticlesController
        def target
        end

        def show
          target = Article.new
          tarHERE
        end
      end
    RUBY

    local = result[:items].find { |item| item[:label] == "target" && item[:kind] == 6 }
    method = result[:items].find { |item| item[:label] == "target" && item[:kind] == 2 }
    expect(local[:sortText]).to be < method[:sortText]
  end

  # `sortText` carries the group *and* the label. Without the label an
  # editor sees one value for every item in a group and falls back to its
  # own tie-break, which is not the order this computed.
  it "orders items within a group by name, not only between groups" do
    result = complete(<<~RUBY)
      apricot = 1
      apple = 2
      apHERE
    RUBY

    sorted = result[:items].select { |i| %w[apple apricot].include?(i[:label]) }
    expect(sorted.size).to eq(2)
    expect(sorted.map { |i| i[:sortText] }.uniq.size).to eq(2)
    expect(sorted.sort_by { |i| i[:sortText] }.map { |i| i[:label] }).to eq(%w[apple apricot])
  end

  # `WorkspaceIndex#search` answers by substring, because that is what
  # `workspace/symbol` wants. A completion prefix is the *start* of the
  # name: offering `UnrelatedArticle` for `Art` is the noise this feature
  # has to avoid, not an extra courtesy.
  it "does not offer a constant that merely contains the prefix" do
    result = complete(<<~RUBY, extra_opens: did_open("file:///m.rb", "class Article\nend\nclass LegacyArticle\nend\n"))
      ArtHERE
    RUBY

    expect(labels(result)).to include("Article")
    expect(labels(result)).not_to include("LegacyArticle")
  end

  # A file's top level has no enclosing type, so there is no member set to
  # offer -- asking for one is a question with no answer, not a question
  # with an empty answer.
  it "offers no self methods at the top level of a file" do
    result = complete(<<~RUBY)
      article = Article.new
      artHERE
    RUBY

    expect(result[:items].map { |item| item[:kind] }).not_to include(2)
  end

  # Two files declaring the same class name are one candidate, not two:
  # the popup shows the label, so a duplicate is indistinguishable noise
  # that also consumes the cap.
  it "offers a class declared in two files once" do
    reopened =
      did_open("file:///one.rb", "class Article\n  def a; end\nend\n") +
      did_open("file:///two.rb", "class Article\n  def b; end\nend\n")
    result = complete(<<~RUBY, extra_opens: reopened)
      ArtHERE
    RUBY

    expect(labels(result).count("Article")).to eq(1)
  end

  # A one-character prefix matches essentially everything, so the honest
  # answer is the two sources that are actually near the cursor.
  it "offers only locals and methods on self for a one-character prefix" do
    result = complete(<<~RUBY, extra_opens: did_open("file:///article.rb", "class Article\nend\n"))
      class ArticlesController
        def show
          aHERE
        end
      end
    RUBY

    expect(labels(result)).not_to include("Article")
  end

  it "still offers a local for a one-character prefix" do
    result = complete(<<~RUBY)
      alpha = Article.new
      aHERE
    RUBY

    expect(labels(result)).to include("alpha")
  end

  # The cap is what keeps a large workspace usable; `isIncomplete` is what
  # makes the cap honest, since it tells the editor to ask again as the
  # prefix narrows rather than filtering a truncated list itself.
  it "caps the result and reports it as incomplete" do
    many = (1..80).map { |i| "class Prefixed#{i}\nend\n" }.join
    result = complete(<<~RUBY, extra_opens: did_open("file:///many.rb", many))
      PrefixedHERE
    RUBY

    expect(result[:items].size).to be <= 50
    expect(result[:isIncomplete]).to be(true)
  end

  it "reports a result that fits under the cap as complete" do
    result = complete(<<~RUBY)
      article = Article.new
      articHERE
    RUBY

    expect(result[:isIncomplete]).to be(false)
  end

  it "offers nothing for an empty prefix, rather than the whole workspace" do
    result = complete(<<~RUBY)
      article = Article.new
      HERE
    RUBY

    expect(result[:items]).to be_empty
  end

  # Completion after a dot is a different question with a different
  # answer, and it was already right -- a bare-prefix source must not
  # leak into it.
  # The receiver's type being Unknown is the ordinary case, so gating on
  # "the member path found nothing" instead of "there is a dot" offers
  # `thing.art` every local named `article`.
  it "does not add bare-prefix candidates after a dot whose receiver is unknown" do
    result = complete(<<~RUBY)
      def go(thing)
        article = 1
        thing.artHERE
      end
    RUBY

    expect(labels(result)).not_to include("article")
  end

  # Below the two-character threshold the answer *grows a source* at the
  # next keystroke, which no client-side filter can produce. An editor
  # told the answer is complete caches it and filters locally, so a user
  # typing straight through from the first letter never sees a workspace
  # constant at all.
  it "reports a one-character answer as incomplete, because the next keystroke adds sources" do
    result = complete(<<~RUBY)
      alpha = Article.new
      aHERE
    RUBY

    expect(result[:isIncomplete]).to be(true)
  end

  it "does not add bare-prefix candidates after a receiver dot" do
    result = complete(<<~RUBY)
      article = "text"
      article.upcHERE
    RUBY

    expect(labels(result)).to include("upcase")
    expect(labels(result)).not_to include("article")
  end
end
