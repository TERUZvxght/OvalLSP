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

  # Every source answers from the first character. This used to skip the
  # two workspace-wide ones below two characters, on the reasoning that
  # one character matches essentially everything -- which cost the
  # published site's own example, "Typing `A` offers candidates", the one
  # length at which it did not work.
  #
  # What keeps that honest is the ranking, not a floor: the sources near
  # the cursor come first and the workspace ones after, so a class is in
  # the list without displacing a local.
  it "offers a workspace class for a one-character prefix, after the sources nearer the cursor" do
    result = complete(<<~RUBY, extra_opens: did_open("file:///article.rb", "class Article\nend\n"))
      class ArticlesController
        def show
          alpha = 1
          aHERE
        end
      end
    RUBY

    expect(labels(result)).to include("Article")
    expect(labels(result).index("alpha")).to be < labels(result).index("Article")
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
  # The premise this used to carry -- that a one-character answer is
  # incomplete because the next keystroke *adds a source* -- is gone with
  # the floor that made it true. Every source answers from the first
  # character now, so a short answer that fits under the cap is complete
  # and the editor may filter it locally.
  it "reports a short answer as complete, now that no source appears later" do
    result = complete(<<~RUBY)
      alpha = Article.new
      aHERE
    RUBY

    expect(result[:isIncomplete]).to be(false)
  end

  it "does not add bare-prefix candidates after a receiver dot" do
    result = complete(<<~RUBY)
      article = "text"
      article.upcHERE
    RUBY

    expect(labels(result)).to include("upcase")
    expect(labels(result)).not_to include("article")
  end

  # The index answers `workspace/symbol` by *substring* and completion by
  # *prefix*, and the two differ by more than wording: filtering the
  # substring answer after it was truncated filters what survived the
  # truncation. Two hundred classes whose names merely contain `art`
  # crowd out every class that starts with it, and the group comes back
  # empty on exactly the workspace size it exists for.
  it "offers a class that starts with the prefix even when many others merely contain it" do
    crowd = (1..250).map { |i| "class Aaa#{format('%03d', i)}Artish; end" }.join("\n")
    result = complete(<<~RUBY, extra_opens: did_open("file:///crowd.rb", crowd))
      class Artzzz; end

      artHERE
    RUBY

    expect(result[:items].map { |i| i[:label] }).to include("Artzzz")
  end

  # The exact-match rule inside the index decides *survival of the
  # truncation*, not the order the user sees -- `items` is re-sorted by
  # label before it goes out. So the fixture has to overflow the cap, and
  # the exact match has to be one the qualified-name order would cut:
  # `Zzz::Art` sorts after every `Artxxx`, and typing the whole of a short
  # name is exactly when the user has already said which one they mean.
  it "keeps an exact match when more candidates start with the prefix than fit" do
    crowd = (1..250).map { |i| "class Art#{format('%03d', i)}; end" }.join("\n")
    both = "module Zzz\n  class Art; end\nend\n"
    result = complete(<<~RUBY, extra_opens: did_open("file:///crowd.rb", crowd) + did_open("file:///art.rb", both))
      ArtHERE
    RUBY

    expect(result[:items].map { |i| i[:label] }).to include("Art")
  end

  # The secondary key of the index's own ordering decides *which*
  # candidates survive its cap, and `PrefixCompletion` re-sorts by label
  # afterwards -- so no ordering assertion can see it. Two hundred and
  # fifty classes declared in reverse name order overflow the cap: with
  # the key, the first two hundred by name survive and `Art001` is among
  # them; without it, the survivors are whichever two hundred the index
  # happened to store first.
  it "keeps the alphabetically first candidates when more match than the cap allows" do
    crowd = (1..1000).map { |i| "class Art#{format('%04d', i)}; end" }.reverse.join("\n")
    result = complete(<<~RUBY, extra_opens: did_open("file:///crowd.rb", crowd))
      ArtHERE
    RUBY

    # The index keeps the two hundred alphabetically first, and the fifty
    # shown are the front of those -- so the last label is `Art0050`
    # exactly. Without the key the survivors are scattered through the
    # thousand and the fiftieth is far higher.
    expect(result[:items].map { |i| i[:label] }.max).to eq("Art0050")
  end

  # `search` returns every declared symbol, methods included, and this
  # group is documented as workspace constants and labels each item
  # `CompletionItemKind.Class`. A method arriving here wore a class icon.
  it "does not offer a workspace method among the constants" do
    result = complete(<<~RUBY, extra_opens: did_open("file:///z.rb", "class Zzz\n  def artisanal_thing; end\nend\n"))
      class Artzzz; end

      artHERE
    RUBY

    labels = result[:items].select { |i| i[:kind] == 7 }.map { |i| i[:label] }
    expect(labels).to include("Artzzz")
    expect(labels).not_to include("artisanal_thing")
  end

  # Route helpers are merged in beside the bare-prefix candidates, which
  # carry a `sortText` that bands them. An item with none falls back to
  # its label, and every band prefix (`0-`..`3-`) sorts before a letter --
  # so route helpers dropped below everything. They are methods callable
  # on self, and belong in that band.
  it "bands route helpers with the other methods callable on self" do
    registry = Ovallsp::Routes::RouteRegistry.new
    registry.replace([{ name: "users", verb: "GET", path: "/users", controller: "users", action: "index" }])
    server = Ovallsp::Server.new(input: StringIO.new(""), output: output, logger: logger, route_registry: registry)
    server.send(:handle_did_open, textDocument: { uri: "file:///a.rb", text: "us\n", version: 1,
                                                  languageId: "ruby" })

    result = server.send(:completion_result, textDocument: { uri: "file:///a.rb" },
                                             position: { line: 0, character: 2 })
    helper = result[:items].find { |i| i[:label] == "users_path" }

    expect(helper).not_to be_nil, "the fixture registered no route helper"
    expect(helper[:sortText]).to start_with("1-")
  end

  # `word_prefix_at_position` stops at word characters, and the only
  # context test was "is there a dot behind it". So every sigil fell
  # through to the bare-prefix path: `@user` in a controller or a view is
  # about the most common thing anyone types in Rails, and it was
  # answered with every constant and Kernel method starting with `use` --
  # accepting one of which writes `@UserProfile`.
  {
    "an instance variable" => "@use",
    "a global" => "$use",
    "a symbol" => ":use",
    "a method being defined" => "def use",
    "a method being removed" => "undef use"
  }.each do |description, line|
    it "offers nothing from the workspace after #{description}" do
      result = complete(<<~RUBY, extra_opens: did_open("file:///p.rb", "class UserProfile; end\n"))
        #{line}HERE
      RUBY

      expect(result[:items].map { |i| i[:label] }).not_to include("UserProfile")
    end
  end

  # Silence after `@` was only ever half the answer. Offering the
  # workspace there is wrong -- `@UserProfile` is not a thing anyone
  # writes -- but the instance variables of the class you are in are
  # exactly what belongs, and this offered nothing at all, so the editor
  # fell back to matching words in the buffer and proposed `article`
  # without its sigil. Reported from a real editing session.
  describe "after an `@`" do
    IVAR_SOURCE = <<~RUBY
      class ArticlesController
        def show
          @article = Article.new
          @articles = Article.all
          local_one = 1
          @aHERE
        end
      end
    RUBY

    it "offers the instance variables assigned in this method, with their sigils" do
      labels = complete(IVAR_SOURCE)[:items].map { |item| item[:label] }

      expect(labels).to include("@article", "@articles")
    end

    # Both reviewers of round 25 found this independently, and it is the
    # two places an `@ivar` is most typed: a view, and an action other
    # than the one that assigned it. `ivar_items` read only the bindings
    # the walk to the cursor had built, so a `before_action` callback's
    # `@article` was invisible from `edit`, and a controller's ivars were
    # invisible from the template it rendered. Hover has read both since
    # 0.2.0.
    it "offers an instance variable assigned in another method of the same class" do
      result = complete(<<~RUBY)
        class ArticlesController
          def set_article
            @article = Article.new
          end

          def edit
            @aHERE
          end
        end
      RUBY

      expect(result[:items].map { |item| item[:label] }).to include("@article")
    end

    it "offers nothing that cannot be written after an `@`" do
      labels = complete(IVAR_SOURCE, extra_opens: did_open("file:///p.rb", "class ArticleProfile; end\n"))[:items]
               .map { |item| item[:label] }

      expect(labels).to all(start_with("@"))
      expect(labels).not_to include("ArticleProfile", "local_one")
    end

    it "offers every instance variable when only the sigil has been typed" do
      source = IVAR_SOURCE.sub("@aHERE", "@HERE")

      expect(complete(source)[:items].map { |i| i[:label] }).to include("@article", "@articles")
    end

    it "carries the inferred type as the detail, the way a local does" do
      item = complete(IVAR_SOURCE)[:items].find { |i| i[:label] == "@article" }

      expect(item[:detail]).to eq("Article")
    end

    # `ivar_prefix_at_position` is a raw text scan, and the same file's
    # call scan was given a code mask this release for exactly this
    # reason. A YARD `@param` tag or an `@` inside a string is not
    # somebody typing an instance variable.
    it "offers nothing for an `@` inside a comment" do
      source = IVAR_SOURCE.sub("    @aHERE", "    # @aHERE")

      expect(complete(source)[:items]).to be_empty
    end

    it "offers nothing for an `@` inside a string" do
      source = IVAR_SOURCE.sub("    @aHERE", '    note = "@aHERE"')

      expect(complete(source)[:items]).to be_empty
    end

    # The comment above `ivar_prefix_at_position` claimed `@@` took the
    # same path because "the environment keys it the same way". It does
    # not: `LocalInferencer` has no `ClassVariableWriteNode` case at all,
    # so the environment has no `@@` keys and this answered nothing while
    # saying it answered. The claim is gone; the behaviour it described is
    # what is pinned here.
    it "offers nothing for a class variable, which nothing tracks" do
      source = IVAR_SOURCE.sub("    @article = Article.new", "    @@shared = Article.new").sub("@aHERE", "@@sHERE")

      expect(complete(source)[:items]).to be_empty
    end

    it "leaves the other sigils silent" do
      expect(complete(IVAR_SOURCE.sub("@aHERE", "$aHERE"))[:items]).to be_empty
    end

    it "is a trigger character, so the popup opens on the `@` itself" do
      input =
        frame(jsonrpc: "2.0", id: 1, method: "initialize", params: { rootUri: nil, capabilities: {} }) +
        frame(jsonrpc: "2.0", method: "exit", params: nil)

      build_server(input).run

      triggers = sent_messages.first[:result][:capabilities][:completionProvider][:triggerCharacters]
      expect(triggers).to include("@")
    end
  end

  # `def` the keyword, not the three letters: `predef` is an ordinary
  # method call, and suppressing the workspace source for every
  # identifier ending in "def" would be a silent hole.
  it "still offers from the workspace after a call whose name ends in def" do
    result = complete(<<~RUBY, extra_opens: did_open("file:///p.rb", "class UserProfile; end\n"))
      predef useHERE
    RUBY

    expect(result[:items].map { |i| i[:label] }).to include("UserProfile")
  end

  # `constant` in the kinds this group asks for. Deleting the word removes
  # workspace constants from the answer with nothing failing, and C12's
  # own fixture only exercises a class and a local.
  it "offers a workspace constant, not only classes and modules" do
    result = complete(<<~RUBY, extra_opens: did_open("file:///c.rb", "MAX_RETRIES = 3\n"))
      MAX_HERE
    RUBY

    expect(result[:items].map { |i| i[:label] }).to include("MAX_RETRIES")
  end

  # Locals are matched case-insensitively, like every other source here.
  it "offers a local whose name differs from the prefix only in case" do
    result = complete(<<~RUBY)
      def go
        article = 1
        ArtHERE
      end
    RUBY

    expect(result[:items].map { |i| i[:label] }).to include("article")
  end

  # The label half of the ranking key. `sort_by` is not stable and this
  # feeds `.first(MAX_ITEMS)`, so the label is what decides *which* fifty
  # of a larger group reach the editor -- `sortText` re-orders what
  # survives and cannot restore what was dropped.
  it "keeps the alphabetically first locals when one group overflows the cap" do
    body = (1..80).map { |i| "  local#{format('%03d', i)} = 1" }.reverse.join("\n")
    result = complete(<<~RUBY)
      def go
      #{body}
        locHERE
      end
    RUBY

    labels = result[:items].map { |i| i[:label] }
    expect(labels).to include("local001")
    expect(labels).not_to include("local080")
  end

  # Two namespaces sharing a simple name give one item, and `detail`
  # carries a qualified name -- whichever the index ordered first, so the
  # answer does not change when an unrelated file is saved.
  it "shows the first qualified name for two constants sharing a simple name" do
    both = "module Zzz\n  class Widget; end\nend\n\nmodule Aaa\n  class Widget; end\nend\n"
    result = complete(<<~RUBY, extra_opens: did_open("file:///both.rb", both))
      WidHERE
    RUBY

    item = result[:items].find { |i| i[:label] == "Widget" }
    expect(item[:detail]).to eq("::Aaa::Widget")
  end

  # The last two bands. `puzzle` is a local and `puts`/`public_method` are
  # Kernel's, so this is the whole rule read end to end -- and inverting
  # either band drops the name the user just wrote below five methods
  # they did not.
  it "ranks a local above the Kernel methods sharing its prefix" do
    result = complete(<<~RUBY)
      puzzle = 1
      puHERE
    RUBY

    labels = result[:items].map { |i| i[:label] }
    expect(labels.first).to eq("puzzle")
    expect(labels).to include("puts")
  end

  # The band number itself, not the resulting order: a constant is
  # capitalised and a Kernel method is not, so within one band ASCII puts
  # the constant first anyway and no ordering assertion can tell band 2
  # from band 3. What the number decides is what an editor does when it
  # merges this list with another provider's.
  it "puts a workspace constant in the band above Kernel" do
    result = complete(<<~RUBY, extra_opens: did_open("file:///p.rb", "class Putter; end\n"))
      puHERE
    RUBY

    expect(result[:items].find { |i| i[:label] == "Putter" }[:sortText]).to start_with("2-")
    expect(result[:items].find { |i| i[:label] == "puts" }[:sortText]).to start_with("3-")
  end
end
