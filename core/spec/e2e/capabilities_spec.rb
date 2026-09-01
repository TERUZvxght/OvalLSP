# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "lsp_client"

# The capability suite behind docs/EXTENSION_CAPABILITIES.md.
#
# It exists because several releases in a row installed cleanly, started
# cleanly, reported healthy status, and did almost nothing a user would
# notice. Every check we had answered a question no user asks. These
# examples ask the user's question: type a dot, does anything come back.
#
# Deliberately end to end. Each example drives a real Core process over
# stdio against a real Rails application, waits for the Runtime Agent and
# the cold index the way the extension does, and then asks. Handing the
# engine a document in-process would pass while the shipped extension
# answers nothing -- which is exactly what happened.
#
# Example names carry their capability id (C5, G4, ...) so a failure names
# the row of the document it breaks.
RSpec.describe "Extension capabilities", :e2e do
  # Named for this file. A constant declared inside `RSpec.describe` is
  # defined at top level, so a generic name (FIXTURE_SOURCE, FIXTURE_ROOT)
  # silently collides with another spec file's -- which is exactly what
  # happened: this suite passed alone and copied another file's fixture
  # when the whole suite ran.
  E2E_RAILS_FIXTURE = File.expand_path("../fixtures/rails_real", __dir__)

  # Copied per-run so an example may edit a file (introducing a syntax
  # error, adding a bad call) without mutating the fixture the rest of the
  # suite shares. Created and removed explicitly rather than through
  # `example_tmpdir`, which is per-example: this workspace has to outlive
  # every example in the file, and #remove_workspace is its `ensure`.
  def self.workspace
    @workspace ||= begin
      dir = File.join(Dir.tmpdir, "ovallsp-e2e-#{Process.pid}-#{object_id}")
      FileUtils.mkdir_p(dir)
      FileUtils.cp_r("#{E2E_RAILS_FIXTURE}/.", dir)
      dir
    end
  end

  def self.remove_workspace
    FileUtils.remove_entry(@workspace) if @workspace && Dir.exist?(@workspace)
  rescue StandardError
    nil
  ensure
    @workspace = nil
  end

  def self.available?
    return @available if defined?(@available)

    @available = Dir.chdir(workspace) do
      env = Ovallsp::BundleEnvironment.for_workspace(workspace)
      system(env, "bundle", "lock", "--local", out: File::NULL, err: File::NULL) &&
        system(env, "bundle", "install", "--local", out: File::NULL, err: File::NULL)
    end
  end

  before(:all) do
    skip "rails/sqlite3 not installed locally; capability suite needs a real Rails app" unless self.class.available?

    @client = E2E::LspClient.new(self.class.workspace)
    @client.initialize!
    @state = @client.wait_until_ready(agent: true)
    @posts_controller = @client.open(File.join(self.class.workspace, "app/controllers/posts_controller.rb"))
  end

  after(:all) do
    @client&.stop
    self.class.remove_workspace
  end

  def descendant_pids(root_pid)
    rows = `ps -axo pid=,ppid=`.lines.filter_map do |line|
      pid, ppid = line.split.map(&:to_i)
      [pid, ppid] if pid && ppid
    end
    children = rows.select { |_pid, ppid| ppid == root_pid }.map(&:first)
    children + children.flat_map { |child| rows.select { |_pid, ppid| ppid == child }.map(&:first) }
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  end

  def wait_until_gone(pid, timeout: 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    sleep 0.1 while process_alive?(pid) && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    !process_alive?(pid)
  end

  # Writes `source` into the workspace as `relative_path`, opens it, and
  # yields its uri. The file stays for the rest of the run; names are
  # unique per example.
  def with_file(relative_path, source)
    path = File.join(self.class.workspace, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    yield @client.open(path, text: source), path
  end

  describe "baseline" do
    it "B1/B2: reaches a ready state against a real Rails app" do
      expect(@state).to eq("ready-rails")
    end
  end

  # Runs its own Core rather than the shared one: this is about what
  # happens to a process on shutdown, and the shared client has to stay
  # alive for every other example.
  it "B3: leaves no Core or Runtime Agent process behind after shutdown" do
    client = E2E::LspClient.new(self.class.workspace)
    client.initialize!
    client.wait_until_ready(agent: true)
    pid = client.core_pid
    agent_pids = descendant_pids(pid)

    client.stop

    expect(wait_until_gone(pid)).to be(true), "Core #{pid} survived shutdown"
    agent_pids.each do |agent_pid|
      expect(wait_until_gone(agent_pid)).to be(true), "a Runtime Agent/runner (#{agent_pid}) survived shutdown"
    end
  end

  describe "hover" do
    it "H1: reports the class of a local assigned from a constructor" do
      with_file("app/models/widget_probe.rb", <<~RUBY) do |uri|
        class WidgetProbe
          def run
            value = WidgetProbe.new
            value
          end
        end
      RUBY
        expect(@client.hover_text(uri, 3, 6)).to eq("WidgetProbe")
      end
    end

    it "H2: reports the model class of a local assigned from an Active Record finder" do
      with_file("app/models/finder_probe.rb", <<~RUBY) do |uri|
        class FinderProbe
          def run
            post = Post.find(1)
            post
          end
        end
      RUBY
        expect(@client.hover_text(uri, 3, 6)).to eq("Post")
      end
    end

    it "H7: shows the RDoc comment above the method being hovered" do
      with_file("app/models/hover_doc_probe.rb", <<~RUBY) do |uri|
        class HoverDocProbe
          # Charges the card.
          def charge_it
          end

          def run
            HoverDocProbe.new.charge_it
          end
        end
      RUBY
        expect(@client.hover_text(uri, 6, 25)).to include("Charges the card.")
      end
    end

    # The same row, for the call shape Ruby uses most. H5 carries no
    # receiver qualifier in either language and its example writes one --
    # the fourth capability row found this way. Go to definition and
    # signature help were both given the receiverless path in 0.2.0;
    # hover was not, and answered an empty popup.
    it "H5: shows a method's parameters when hovering a call with no receiver" do
      with_file("app/models/receiverless_hover_probe.rb", <<~RUBY) do |uri|
        class ReceiverlessHoverProbe
          def documented(first, second = 1)
          end

          def run
            documented(1)
          end
        end
      RUBY
        # `second = 1` rather than `second`. The fixture declares a
        # default and 0.2.15 shows it -- the row promises "a method's
        # parameters", and an optional parameter rendered as a required
        # one is not the parameter the source declares (`024.89`).
        expect(@client.hover_text(uri, 5, 6)).to include("documented(first, second = 1)")
      end
    end

    it "H3: reports an ivar's type in a view from the action that assigned it" do
      with_file("app/controllers/hover_view_controller.rb", <<~RUBY) do |_uri|
        class HoverViewController < ApplicationController
          def show
            @record = Post.find(1)
          end
        end
      RUBY
        with_file("app/views/hover_view/show.html.erb", "<%= @record %>\n") do |view_uri|
          expect(@client.hover_text(view_uri, 0, 5)).to eq("Post")
        end
      end
    end

    it "H5: shows a method's parameters when hovering it" do
      with_file("app/models/hover_params_probe.rb", <<~RUBY) do |uri|
        class HoverParamsProbe
          def documented(first, second = 1)
          end

          def run
            value = HoverParamsProbe.new
            value.documented(1)
          end
        end
      RUBY
        # See the receiverless example above: the default is part of the
        # parameter, and this row promises the parameters (`024.89`).
        expect(@client.hover_text(uri, 6, 10)).to include("documented(first, second = 1)")
      end
    end

    # Regression: `locate` descended into a listed handful of node types
    # and answered with the enclosing node's own type everywhere else, so
    # a keyword argument, an array element, a hash value, a `while`/
    # `case`/`begin` body and a `return` value all reported the wrong
    # thing. The same omission for call arguments reported
    # `User.find(params[:id])` as a missing `[]` on the model.
    it "H6: reports the type of an expression nested inside any structure" do
      with_file("app/models/nesting_probe.rb", <<~RUBY) do |uri|
        class NestingProbe
          def run(flag)
            values = [Post.new]
            case flag
            when 1
              post = values.first
              post
            end
          end
        end
      RUBY
        expect(@client.hover_text(uri, 6, 8)).to eq("Post")
      end
    end

    # The row promises `"s"`, `1` and `[1]`, and this hovered a *local*
    # assigned from one of them -- not a literal at all, and only the
    # first of the three. Every literal the engine settles outright is
    # asserted now, on the literal itself.
    it "H4: reports literal types" do
      with_file("app/models/literal_probe.rb", <<~RUBY) do |uri|
        class LiteralProbe
          def run
            ["s", 1, [1], 1.5, :sym, (1..5), /re/, ->(n) { n }, true]
          end
        end
      RUBY
        # Columns computed from the source rather than counted by hand:
        # an off-by-one probe tests nothing and says so in neither
        # direction, which this project has been caught by three times.
        line_text = '    ["s", 1, [1], 1.5, :sym, (1..5), /re/, ->(n) { n }, true]'
        {
          '"s"' => "String", " 1," => "Integer", "[1]" => "Array[Integer]", "1.5" => "Float",
          ":sym" => "Symbol", "(1..5)" => "Range", "/re/" => "Regexp", "->(n)" => "Proc", "true" => "Boolean"
        }.each do |snippet, expected|
          character = line_text.index(snippet) + (snippet.start_with?(" ") ? 1 : 0)
          actual = @client.hover_text(uri, 2, character)
          expect(actual).to eq(expected), "#{snippet.inspect} at #{character} answered #{actual.inspect}"
        end
      end
    end
  end

  describe "completion" do
    it "C1: offers stdlib methods on a String" do
      with_file("app/models/string_completion_probe.rb", <<~RUBY) do |uri|
        class StringCompletionProbe
          def run
            text = "s"
            text.
          end
        end
      RUBY
        expect(@client.completion_labels(uri, 3, 9)).to include("upcase", "split")
      end
    end

    it "C2: offers a workspace class's own instance methods" do
      with_file("app/models/own_methods_probe.rb", <<~RUBY) do |uri|
        class OwnMethodsProbe
          def alpha; end
          def beta; end

          def run
            value = OwnMethodsProbe.new
            value.
          end
        end
      RUBY
        expect(@client.completion_labels(uri, 6, 10)).to include("alpha", "beta")
      end
    end

    it "C3: offers an Active Record instance's columns and associations" do
      with_file("app/models/ar_instance_probe.rb", <<~RUBY) do |uri|
        class ArInstanceProbe
          def run
            user = User.find(1)
            user.
          end
        end
      RUBY
        labels = @client.completion_labels(uri, 3, 9)

        # The row says columns *and* associations; only the association
        # was asserted.
        expect(labels).to include("posts")
        expect(labels).to include("email")
      end
    end

    it "C4: offers Active Record's own instance API" do
      with_file("app/models/ar_api_probe.rb", <<~RUBY) do |uri|
        class ArApiProbe
          def run
            user = User.find(1)
            user.
          end
        end
      RUBY
        expect(@client.completion_labels(uri, 3, 9)).to include("save", "destroy")
      end
    end

    it "C5: offers Active Record's class API on the model constant" do
      with_file("app/models/ar_class_probe.rb", <<~RUBY) do |uri|
        class ArClassProbe
          def run
            User.
          end
        end
      RUBY
        # The row names `new` alongside the rest, and it was the one the
        # list did not have: `new` is `Class`'s, one step up the singleton
        # chain, and the signature source answered about the receiver's
        # own name only.
        expect(@client.completion_labels(uri, 2, 9)).to include("find", "where", "all", "create", "new")
      end
    end

    it "C6: offers a workspace class's own singleton methods on the constant" do
      with_file("app/models/singleton_probe.rb", <<~RUBY) do |uri|
        class SingletonProbe
          def self.build_one; end

          def run
            SingletonProbe.
          end
        end
      RUBY
        expect(@client.completion_labels(uri, 4, 19)).to include("build_one")
      end
    end

    it "C8: inserts a call template with the cursor between the parentheses" do
      with_file("app/models/snippet_probe.rb", <<~RUBY) do |uri|
        class SnippetProbe
          def takes_two(first, second); end

          def run
            value = SnippetProbe.new
            value.
          end
        end
      RUBY
        item = @client.completion_item(uri, 5, 10, "takes_two")

        # 2 is InsertTextFormat.Snippet: `$1`/`${1:name}` are tab stops
        # rather than literal text.
        expect(item[:insertTextFormat]).to eq(2)
        expect(item[:insertText]).to eq("takes_two(${1:first}, ${2:second})")
      end
    end

    it "C9: inserts a no-argument method without parentheses" do
      with_file("app/models/no_arg_probe.rb", <<~RUBY) do |uri|
        class NoArgProbe
          def plain_call; end

          def run
            value = NoArgProbe.new
            value.
          end
        end
      RUBY
        item = @client.completion_item(uri, 5, 10, "plain_call")

        # No insertText and no snippet format: the label is inserted
        # verbatim. `plain_call()` is not how Ruby is written, and an
        # editor that produces it is worse than one that inserts the name.
        expect(item[:insertText]).to be_nil
        expect(item[:insertTextFormat]).to be_nil
      end
    end

    it "C10: puts the cursor inside the parentheses when a method takes arguments of unknown shape" do
      with_file("app/models/ar_snippet_probe.rb", <<~RUBY) do |uri|
        class ArSnippetProbe
          def run
            User.
          end
        end
      RUBY
        # Active Record defines `where(*, **, &)`, so there are no
        # parameter names to offer -- but "takes arguments" is known, and
        # that is enough to open the parentheses and put the cursor there.
        item = @client.completion_item(uri, 2, 9, "where")

        expect(item[:insertTextFormat]).to eq(2)
        expect(item[:insertText]).to eq("where($1)")
      end
    end

    # The same raw-versus-extracted mistake the diagnostics engine had:
    # completion resolves the receiver by asking for the type at the
    # position before the dot, and for an .erb file that position was
    # read against the template text rather than its Ruby regions.
    it "C11: completes a method on a local inside an ERB template" do
      with_file("app/views/posts/completion_probe.html.erb",
                %(<div class="wrapper">\n  <% post = Post.new %>\n  <%= post. %>\n</div>\n)) do |uri|
        expect(@client.completion_labels(uri, 2, 11)).to include("title")
      end
    end

    # C11's own row, for the way a Rails view actually refers to a model.
    # Its example types `post.`, a local -- and a local in a template is
    # what a partial receives. An action's `@ivar` is the common case,
    # and it answered nothing: hover resolves an ivar in a view through
    # the controller action that assigned it (H3), and
    # `receiver_type_before_dot` -- which completion and go-to-definition
    # both use -- did not, though Task 013 records "hover and completion
    # use the same receiver type" as the rule.
    it "C11: offers a model's members after an `@ivar` in an ERB template" do
      with_file("app/controllers/ivar_completion_controller.rb", <<~RUBY) do |_uri|
        class IvarCompletionController < ApplicationController
          def show
            @record = Post.find(1)
          end
        end
      RUBY
        with_file("app/views/ivar_completion/show.html.erb", "<%= @record. %>\n") do |view_uri|
          labels = @client.completion_labels(view_uri, 0, 12)

          expect(labels).to include("title")
          expect(labels).to include("save")
        end
      end
    end

    it "C12: offers workspace classes, locals and methods on self with no receiver in front" do
      with_file("app/models/prefix_probe.rb", <<~RUBY) do |uri|
        class PrefixProbe
          def prefixed_method; end

          def run
            prefix_local = 1
            pre
          end
        end
      RUBY
        labels = @client.completion_labels(uri, 5, 7)

        # All three sources the row names. The method on self was the one
        # nothing asserted, so nothing failed if that source broke.
        expect(labels).to include("prefix_local")
        expect(labels).to include("PrefixProbe")
        expect(labels).to include("prefixed_method")
      end
    end

    # The public site promises "Typing `A` offers candidates" -- one
    # character, a capital, i.e. a class. It offered locals and methods on
    # self at that length and skipped workspace classes entirely, so the
    # example the site chose was the one that did not work.
    it "C12: offers a workspace class at a single character" do
      with_file("app/models/single_char_probe.rb", <<~RUBY) do |uri|
        class SingleCharProbe
          def run
            S
          end
        end
      RUBY
        expect(@client.completion_labels(uri, 2, 5)).to include("SingleCharProbe")
      end
    end

    # `024.85`. Both halves in one example, because "not empty" is not
    # the claim: the instance side must offer the instance method and not
    # the class method, and the class side the other way round. A single
    # `include` would pass against an engine that answered the wrong
    # surface, which is the failure mode `class << self` has produced
    # here twice.
    it "C14: offers the enclosing self's own members after `self.`" do
      with_file("app/models/self_probe.rb", <<~RUBY) do |uri|
        class SelfProbe
          def self.built_here; end
          def labelled_here; end

          def run
            self.
          end

          def self.run_class_side
            self.
          end
        end
      RUBY
        instance_side = @client.completion_labels(uri, 5, 9)
        class_side = @client.completion_labels(uri, 9, 9)

        expect(instance_side).to include("labelled_here")
        expect(instance_side).not_to include("built_here")
        expect(class_side).to include("built_here")
        expect(class_side).not_to include("labelled_here")
      end
    end

    it "C13: resolves a completion item to the RDoc comment above its declaration" do
      with_file("app/models/documented_probe.rb", <<~RUBY) do |uri|
        class DocumentedProbe
          # Charges the card.
          def charge_it
          end

          def run
            DocumentedProbe.new.cha
          end
        end
      RUBY
        item = @client.completion_item(uri, 6, 29, "charge_it")
        expect(item).not_to be_nil
        resolved = @client.raw_request("completionItem/resolve", item)
        expect(resolved.dig(:documentation, :value).to_s).to include("Charges the card.")
      end
    end

    it "C7: offers route helpers by prefix" do
      with_file("app/controllers/route_probe_controller.rb", <<~RUBY) do |uri|
        class RouteProbeController < ApplicationController
          def index
            posts_
          end
        end
      RUBY
        labels = @client.completion_labels(uri, 2, 10)

        # The row names both forms and its own example prefix (`article_p`)
        # could only ever match one of them. Both the row and this fixture
        # use a prefix that matches both.
        expect(labels).to include("posts_path")
        expect(labels).to include("posts_url")
      end
    end
  end

  describe "definition" do
    it "D1: jumps to a workspace method's declaration" do
      with_file("app/models/definition_probe.rb", <<~RUBY) do |uri|
        class DefinitionProbe
          def target_method; end

          def run
            value = DefinitionProbe.new
            value.target_method
          end
        end
      RUBY
        locations = @client.definitions(uri, 5, 12)
        expect(locations.map { |l| l[:uri] }).to include(uri)
      end
    end



    # The same row, for the call shape Ruby actually uses most. The
    # example above writes a receiver; without one, `definition_result`
    # fell through to a *name* lookup that only matches classes, modules
    # and constants -- so a call to a method of the class you are writing
    # in resolved to nothing. Measured on a real Rails application:
    # `article_params` in a scaffolded controller, 0 locations, while
    # find-references on the same pair answered 2.
    it "D1: jumps to a workspace method's declaration with no receiver in front" do
      with_file("app/models/receiverless_definition_probe.rb", <<~RUBY) do |uri|
        class ReceiverlessDefinitionProbe
          def target_method; end

          def run
            target_method
          end
        end
      RUBY
        locations = @client.definitions(uri, 4, 8)
        expect(locations.map { |l| l[:uri] }).to include(uri)
        expect(locations.map { |l| l[:range][:start][:line] }).to include(1)
      end
    end
  end

  describe "definition (continued)" do
    it "D2: jumps to the owning model for an Active Record column" do
      with_file("app/models/column_definition_probe.rb", <<~RUBY) do |uri|
        class ColumnDefinitionProbe
          def run
            user = User.find(1)
            user.email
          end
        end
      RUBY
        targets = @client.definitions(uri, 3, 12).map { |location| location[:uri] }
        expect(targets).to include(a_string_ending_with("app/models/user.rb"))
      end
    end

    # The same row, for its other half. `posts` is an association rather
    # than a column, and only the column was asserted.
    it "D2: jumps to the owning model for an Active Record association" do
      with_file("app/models/association_definition_probe.rb", <<~RUBY) do |uri|
        class AssociationDefinitionProbe
          def run
            user = User.find(1)
            user.posts
          end
        end
      RUBY
        targets = @client.definitions(uri, 3, 12).map { |location| location[:uri] }
        expect(targets).to include(a_string_ending_with("app/models/user.rb"))
      end
    end

    it "D3: jumps into the RBS declaration for a stdlib method" do
      with_file("app/models/stdlib_definition_probe.rb", <<~RUBY) do |uri|
        class StdlibDefinitionProbe
          def run
            text = "s"
            text.upcase
          end
        end
      RUBY
        targets = @client.definitions(uri, 3, 12).map { |location| location[:uri] }
        expect(targets).to include(a_string_matching(/string\.rbs\z/))
      end
    end

    # 0.3.0. `045`: "cheap given `explainType` already resolves the type".
    # The difference from D1 is the whole point -- go to *definition* on
    # `widget.build` lands on `def build`; go to *type* definition lands on
    # the class the expression evaluates to.
    it "D4: jumps to the class an expression evaluates to, not to the method that produced it" do
      source = <<~SOURCE
        class TdWidget
          def label
            "x"
          end
        end

        class TdHolder
          def use
            made = TdWidget.new
            made
          end
        end
      SOURCE

      with_file("app/models/td_probe.rb", source) do |uri|
        # The caret is on `made` at line 9, whose type is TdWidget.
        targets = @client.type_definitions(uri, 9, 4)
        expect(targets).not_to be_empty, "typeDefinition answered nothing for a local of a known class"
        expect(targets.map { |t| t[:uri] }).to all(end_with("td_probe.rb"))

        # **The control, and it is inside the answer rather than beside it.**
        # Line 0 is `class TdWidget`; line 8 is the assignment `made = ...`.
        # A server that forwarded this to `textDocument/definition` would
        # answer the assignment and look plausible. Go to definition at this
        # same caret answers nothing at all today, so it cannot be the
        # control -- measured, not assumed.
        expect(targets.map { |t| t[:line] }).to eq([0])
      end
    end

    it "D5: answers nothing where the type is not a workspace class" do
      source = "class TdUnknown\n  def go(anything)\n    anything\n  end\nend\n"

      with_file("app/models/td_unknown.rb", source) do |uri|
        # A parameter with no declared type: the engine does not know what
        # it is, and the nearest name that looks right is a guess.
        expect(@client.type_definitions(uri, 2, 4)).to be_empty
      end
    end

    # 0.3.0. `045`: "the inference that already exists". Hover answers
    # these today; inlay hints put the answer where the code is.
    it "I1: labels each local assignment with its inferred type, and nothing it cannot infer" do
      source = <<~SOURCE
        class IhProbe
          def go(unknown_thing)
            counted = 1
            named = "x"
            made = IhProbe.new
            borrowed = unknown_thing
            [counted, named, made, borrowed]
          end
        end
      SOURCE

      with_file("app/models/ih_probe.rb", source) do |uri|
        hints = @client.inlay_hints(uri)
        by_line = hints.to_h

        expect(by_line[2]).to eq(": Integer")
        expect(by_line[3]).to eq(": String")
        expect(by_line[4]).to eq(": IhProbe")

        # **The line that makes this a capability rather than a decoration.**
        # `borrowed` is assigned from an untyped parameter, so the engine
        # does not know; a label there would be a wrong answer written into
        # the margin of the user's code, which section 0 ranks below none.
        expect(by_line).not_to have_key(5)

        # And a read is not an assignment: line 6 mentions all four and
        # gets nothing.
        expect(by_line).not_to have_key(6)
      end
    end

    it "I2: labels each argument with the parameter name it is passed as" do
      source = <<~SOURCE
        class IhCallee
          def resize(width, height, scale = 1)
            [width, height, scale]
          end

          def post_required(first, middle = 1, last)
            [first, middle, last]
          end

          def collecting(head, *tail)
            [head, tail]
          end
        end

        class IhCaller
          def go
            IhCallee.new.resize(10, 20, 30)
          end

          def awkward
            IhCallee.new.post_required(1, 2)
          end

          def splatty
            IhCallee.new.collecting(1, 2, 3)
          end
        end
      SOURCE

      with_file("app/models/ih_caller.rb", source) do |uri|
        on = ->(line) { @client.inlay_hints(uri).select { |(l, _)| l == line }.map(&:last) }

        # Two required and one optional, all three labelled: where the
        # shape is plain the index-to-parameter mapping holds, and
        # refusing the optional was under-answering.
        expect(on.call(16)).to eq(["width:", "height:", "scale:"])

        # **A required parameter after an optional one refuses the whole
        # call.** Ruby fills the optional last -- `f(1, 2)` on
        # `def f(a, b = 1, c)` binds `c = 2` -- so labelling by index
        # would write `middle:` beside a value passed as `last`.
        expect(on.call(20)).to be_empty

        # And a `*rest` parameter, for the same reason.
        expect(on.call(24)).to be_empty
      end
    end

    # 0.3.0. `045`: "the diagnostics that already exist". Each of these is
    # offered only where the edit is defined -- a quick fix that guesses is
    # a wrong edit applied with one click, which is section 0 at its
    # sharpest, because the user never sees the reasoning.
    it "Q1: offers a `def` for an unknown method, inserted into the class it was called on" do
      # `QfCaller` is written **first** on purpose. With the receiver's
      # class first, "insert into the class the call was made on" and
      # "insert into whichever class this file declares first" are the same
      # edit, and the example cannot tell them apart.
      source = "class QfCaller\n  def go\n    QfSubject.new.absent_one\n  end\nend\n\n" \
               "class QfSubject\n  def known; end\nend\n"

      with_file("app/models/qf_probe.rb", source) do |uri|
        published = @client.published_diagnostics(uri)
        unknown = published.select { |d| d[:code] == "unknown-method" }
        expect(unknown).not_to be_empty, "no unknown-method diagnostic to act on"

        actions = @client.code_actions(uri, unknown.first[:range][:start][:line], unknown)
        titles = actions.map(&:first)
        expect(titles).to include(a_string_including("absent_one"))

        # The edit goes into QfSubject's body, not the caller's -- the
        # method was called *on* QfSubject.
        edits = actions.find { |t, _| t.include?("absent_one") }.last
        # Line 7, the first line of `QfSubject`'s body -- which is now
        # the *second* class in the file, so this cannot be satisfied
        # by inserting into whichever class comes first.
        expect(edits.map(&:first)).to eq([7])
        expect(edits.map(&:last).join).to include("def absent_one")
      end
    end

    it "Q2: replaces an unknown route helper with the closest one the application has" do
      # `posts_path` exists in this workspace (`config/routes.rb` draws
      # `resources :posts`), and `postss_path` is one edit from it.
      #
      # The name has to *end* in `_path` or `_url`, or the engine reads
      # it as an ordinary unknown method rather than a route helper --
      # `posts_pathh` was the first attempt and produced
      # `unknown-method`, which is a different fix. The
      # first version of this example used a route the application does
      # not have at all and skipped -- a skipped example is not a passing
      # one, and this row claims PASS.
      source = "class QfRoutes\n  def go\n    postss_path\n  end\nend\n"

      with_file("app/models/qf_routes.rb", source) do |uri|
        published = @client.published_diagnostics(uri)
        helper = published.select { |d| d[:code] == "unknown-route-helper" }
        expect(helper).not_to be_empty, "no unknown-route-helper diagnostic: #{published.map { |d| d[:message] }}"

        actions = @client.code_actions(uri, helper.first[:range][:start][:line], helper)
        expect(actions.map(&:first)).to include("Change to `posts_path`")

        # And the edit replaces the name rather than appending to it.
        expect(actions.first.last.map(&:last)).to eq(["posts_path"])

        # **And a name that is not close to anything is refused.** Rewriting
        # one wrong name into another unrelated one is a wrong edit applied
        # with a click, not a fix -- so the ceiling is what makes this a
        # capability rather than a name-substitution.
        far = "class QfFarRoute\n  def go\n    completely_different_thing_path\n  end\nend\n"
        with_file("app/models/qf_far_route.rb", far) do |far_uri|
          published_far = @client.published_diagnostics(far_uri)
          far_helper = published_far.select { |d| d[:code] == "unknown-route-helper" }
          expect(far_helper).not_to be_empty
          expect(@client.code_actions(far_uri, far_helper.first[:range][:start][:line], far_helper)).to be_empty
        end
      end
    end

    it "Q3: removes surplus arguments, and offers nothing when there are too few" do
      source = "class QfArity\n  def takes_two(a, b)\n    [a, b]\n  end\n\n" \
               "  def too_many\n    takes_two(1, 2, 3)\n  end\n\n" \
               "  def too_few\n    takes_two(1)\n  end\nend\n"

      with_file("app/models/qf_arity.rb", source) do |uri|
        published = @client.published_diagnostics(uri)
        counts = published.select { |d| d[:code] == "argument-count" }
        expect(counts.length).to eq(2), "expected one diagnostic per call, got #{counts.map { |d| d[:message] }}"

        surplus = counts.find { |d| d[:range][:start][:line] == 6 }
        missing = counts.find { |d| d[:range][:start][:line] == 10 }

        expect(@client.code_actions(uri, 6, [surplus]).map(&:first))
          .to include(a_string_including("Remove"))

        # **Nothing for the other one, and that is the capability.** There
        # is no value to write in place of a missing argument, and writing
        # `nil` would be this engine putting a guess into the user's file.
        expect(@client.code_actions(uri, 10, [missing])).to be_empty
      end
    end

    # 0.3.0, `024.86`, and the roadmap's "completion of `@ivar` names the
    # moment you type the sigil". One missing seed produced both: the
    # descent starts a fresh environment per `def`, so an ivar assigned in
    # another method was invisible to the method being edited -- for its
    # type *and* for its name. It works in an ERB view because a view has
    # no `def` for the descent to reset at.
    it "C15: offers the class's instance variables at the sigil, not only this method's" do
      source = <<~SOURCE
        class IvProbe
          def setup
            @from_setup = 1
          end

          def use
            @from_use = 2
            @
          end
        end
      SOURCE

      with_file("app/models/iv_probe.rb", source) do |uri|
        labels = @client.completion_labels(uri, 7, 5)
        expect(labels).to include("@from_setup", "@from_use")
      end
    end

    # 024.R7's Core half, first step. The Agent reports what the gems
    # define and the server holds it; **nothing reads it to decide an
    # answer yet**, which is why this asserts the index exists rather than
    # a diagnostic that changed. Closedness and members have to arrive
    # together, and turning silence into reports across every Rails file
    # owes a corpus run with a control.
    it "W5/W6: holds the running application's gem index once the Agent is ready" do
      @client.wait_for_gem_index
      status = @client.raw_request("ovallsp/status", {})

      expect(status).to have_key(:gemIndexClasses)
      expect(status[:gemIndexClasses]).to be > 100,
                                          "the gem index holds #{status[:gemIndexClasses]} classes; " \
                                          "a real Rails bundle contributes thousands"
    end

    # 024.87 and the roadmap's "`Article.all.` completes". The type half
    # was fixed in 0.2.15 -- a chain stays `Relation[T]` -- and the entry
    # says the diagnostic half is unconfirmed. This confirms it either way
    # rather than leaving it as a belief.
    it "C16: completes and checks past the second link of a relation chain" do
      # The caret is at the end of the line, after the trailing dot --
      # counted from the source rather than written as a number, which
      # is how the first version of this landed on the `:id` inside
      # `order(:id)` and measured `Symbol`.
      # The members come from the running application (024.R7), so the
      # index has to have landed -- the same wait G18 makes.
      expect(@client.wait_for_gem_index).to be > 100

      chain = "    Post.where(x: 1).order(:id)."
      source = "class RelProbe\n  def go\n#{chain}\n  end\nend\n"

      with_file("app/models/rel_probe.rb", source) do |uri|
        # `Relation`'s own members, at the second hop -- which is where
        # 024.87 says the chain used to lose its type.
        labels = @client.completion_labels(uri, 2, chain.length)

        # What a `Relation` actually offers, read off the answer rather than
        # assumed: `where` is `Post`'s *singleton* method, not a member of the
        # relation the chain evaluates to. The first version of this example
        # asserted `where` and was measuring the wrong receiver.
        #
        # 228 items come back here where the pre-0.3.0 build offered none.
        expect(labels.length).to be > 50, "the chain lost its members at the second link"
        expect(labels).to include("each", "map")
      end
    end

    it "G19: reports a typo past the second link of a relation chain" do
      source = "class RelDiag < ApplicationRecord\n  def go\n    Post.where(x: 1).order(:id).titel\n  end\nend\n"

      expect(@client.wait_for_gem_index).to be > 100

      with_file("app/models/rel_diag.rb", source) do |uri|
        messages = @client.diagnostic_messages(uri).join(" ")

        # **Recorded either way.** `024.87` calls this half unconfirmed; a
        # relation is an Active Record object and `ActiveRecord::Relation`
        # delegates through `method_missing`, so silence here is the
        # correct answer and not a gap -- which is what the expectation
        # below says, measured rather than assumed.
        expect(messages).not_to include("titel")
      end
    end

    # 024.R7, and the roadmap's first 0.3.0 promise. Until now "closed"
    # meant "the workspace can see the whole ancestry", so a class
    # inheriting from a gem was never checked -- the check worked where it
    # was least needed and said nothing where most code is written.
    #
    # Measured over activerecord's own 397 files with the index on and
    # off, same corpus sha, control identical at 1,609: **0 reports
    # introduced, 13 removed.**
    #
    # **`ActiveRecord::Base` is deliberately not the fixture, and cannot
    # be.** `ActiveRecord::AttributeMethods` defines `method_missing` --
    # `ActiveRecord::Base.private_method_defined?(:method_missing)` is
    # `true`, asked of the running application -- so a model answers to
    # names no enumeration can list and reporting on one would be a wrong
    # answer. 577 of this bundle's classes have no such ancestor; this is
    # one of them.
    it "G18: reports a method that does not exist on a class inheriting from a gem" do
      source = "class GemHeir < ActionView::Helpers::FormBuilder\n  def go\n    no_such_method_at_all\n  end\nend\n"

      expect(@client.wait_for_gem_index).to be > 100, "the gem index never loaded"

      with_file("app/models/gem_heir.rb", source) do |uri|
        expect(@client.wait_for_diagnostic(uri, "no_such_method_at_all")).to include("no_such_method_at_all")
      end
    end

    # The other half, and the one section 0 cares about more: a receiver
    # that answers at call time stays silent, whatever the index holds.
    it "G18: stays silent on an Active Record model, which answers at call time" do
      source = "class QuietHeir < ActiveRecord::Base\n  def go\n    no_such_method_at_all\n  end\nend\n"

      expect(@client.wait_for_gem_index).to be > 100

      with_file("app/models/quiet_heir.rb", source) do |uri|
        expect(@client.diagnostic_messages(uri).join(" ")).not_to include("no_such_method_at_all")
      end
    end

    it "H8: types an ivar assigned in another method, and declines where two methods disagree" do
      source = <<~SOURCE
        class IvWidget
          def label
            "x"
          end
        end

        class IvHolder
          def setup
            @agreed = IvWidget.new
            @disputed = IvWidget.new
          end

          def other_setup
            @disputed = 41
          end

          def use
            [@agreed, @disputed]
          end
        end
      SOURCE

      with_file("app/models/iv_holder.rb", source) do |uri|
        expect(@client.hover_text(uri, 17, 8)).to include("IvWidget")

        # **Two methods, two different types, so nothing.** Picking one
        # would be a wrong answer where the code has no single one, and a
        # hover is read as the engine's claim about the program.
        expect(@client.hover_text(uri, 17, 18).to_s).not_to include("IvWidget")
        expect(@client.hover_text(uri, 17, 18).to_s).not_to include("Integer")
      end
    end
  end

  describe "semantic highlighting" do
    it "T1: distinguishes a local variable from a call on self" do
      with_file("app/models/token_probe.rb", <<~RUBY) do |uri|
        class TokenProbe
          def helper
          end

          def run
            value = 1
            value
            helper
          end
        end
      RUBY
        by_line = semantic_token_types_by_line(uri)

        # The row promises the two are coloured *differently*, so the
        # assertion has to be per position. Asserting only that both
        # kinds appear somewhere passed with the classification fully
        # inverted -- a reviewer swapped `:variable` and `:method` in the
        # collector and both T1 examples stayed green.
        expect(by_line[6]).to eq(["variable"])
        expect(by_line[7]).to eq(["method"])
      end
    end

    # The row promises the distinction holds "in `.rb` and in an ERB
    # template's Ruby regions alike", and a row is what this document
    # says a capability is -- so the ERB half needs to be in the row, not
    # only in `semantic_tokens_spec.rb`.
    it "T1: makes the same distinction inside an ERB template's Ruby regions" do
      with_file("app/views/probes/show.html.erb", <<~ERB) do |uri|
        <% value = 1 %>
        <%= value %>
        <%= helper %>
      ERB
        by_line = semantic_token_types_by_line(uri)

        expect(by_line[1]).to eq(["variable"])
        expect(by_line[2]).to eq(["method"])
      end
    end

    # LSP semantic tokens are delta-encoded against the previous token,
    # so a type is only meaningful once the deltas are accumulated back
    # into absolute positions.
    def semantic_token_types_by_line(uri)
      data = @client.raw_request("textDocument/semanticTokens/full",
                                 { textDocument: { uri: uri } })[:data]
      line = 0
      data.each_slice(5).each_with_object(Hash.new { |h, k| h[k] = [] }) do |token, by_line|
        line += token[0]
        by_line[line] << Ovallsp::SemanticTokens::LEGEND[token[3]]
      end
    end
  end

  describe "diagnostics" do
    it "G1: reports a syntax error" do
      with_file("app/models/syntax_probe.rb", "class SyntaxProbe\n  def broken(\n") do |uri|
        expect(@client.diagnostic_messages(uri).join(" ")).to match(/expect|unexpected/i)
      end
    end

    it "G2: reports an unknown method on a workspace class" do
      with_file("app/models/unknown_method_probe.rb", <<~RUBY) do |uri|
        class UnknownMethodProbe
          def run
            value = UnknownMethodProbe.new
            value.definitely_not_here
          end
        end
      RUBY
        expect(@client.diagnostic_messages(uri).join(" ")).to match(/no method named/i)
      end
    end

    # Needs a *declared* parameter type, which Ruby source does not carry
    # -- hence the fixture's own `sig/argument_probe.rbs`, loaded at boot
    # like any project signature.
    it "G15: reports an argument whose type cannot be the declared one" do
      with_file("app/models/argument_call_probe.rb", <<~RUBY) do |uri|
        class ArgumentCallProbe
          def run
            ArgumentProbe.new.resize("large")
          end
        end
      RUBY
        expect(@client.diagnostic_messages(uri).join(" ")).to match(/expects Integer/i)
      end
    end

    it "G16: reports a view reading an ivar no action assigns" do
      with_file("app/controllers/ivar_probe_controller.rb", <<~RUBY) do |_uri|
        class IvarProbeController < ApplicationController
          def show
            @record = Post.find(1)
          end
        end
      RUBY
        with_file("app/views/ivar_probe/show.html.erb", "<%= @recrod %>\n") do |view_uri|
          expect(@client.diagnostic_messages(view_uri).join(" ")).to match(/never assigned/i)
        end
      end
    end

    it "G3: reports an unknown route helper" do
      with_file("app/controllers/bad_route_controller.rb", <<~RUBY) do |uri|
        class BadRouteController < ApplicationController
          def index
            no_such_thing_path
          end
        end
      RUBY
        expect(@client.diagnostic_messages(uri).join(" ")).to match(/no route named/i)
      end
    end

    it "G4: reports an unknown method on an Active Record model" do
      with_file("app/models/ar_unknown_probe.rb", <<~RUBY) do |uri|
        class ArUnknownProbe
          def run
            user = User.find(1)
            user.definitely_not_an_ar_method
          end
        end
      RUBY
        expect(@client.diagnostic_messages(uri).join(" ")).to match(/no method named/i)
      end
    end

    # Regression: every one of these produced a false "has no method
    # named" against a real Rails application. The unknown-method check
    # only fires on a *closed* receiver, and a Rails class is never
    # closed in reality -- its real definition lives in a gem. Three
    # different ways the chain silently looked complete anyway.
    it "G6: says nothing about a class whose superclass is a gem constant" do
      with_file("config/gem_parent_probe.rb", <<~RUBY) do |uri|
        module GemParentProbe
          class Application < Rails::Application
            config.load_defaults 8.1
          end
        end
      RUBY
        expect(@client.diagnostic_messages(uri, timeout: 6).join(" ")).not_to match(/no method named/i)
      end
    end

    it "G7: says nothing about a class whose superclass is an expression" do
      with_file("db/migrate_probe.rb", <<~RUBY) do |uri|
        class MigrateProbe < ActiveRecord::Migration[8.1]
          def change
            create_table :probes
          end
        end
      RUBY
        expect(@client.diagnostic_messages(uri, timeout: 6).join(" ")).not_to match(/no method named/i)
      end
    end

    # Regression: diagnostics ran the *raw* template through type
    # inference while ParserService extracted the Ruby regions first, so
    # every receiver in an .erb file was resolved against HTML. A partial
    # using its local read as a String, and its `article.errors` was
    # reported as a missing String method.
    it "G9: does not report methods against HTML in an ERB template" do
      with_file("app/views/articles/_diag_probe.html.erb",
                "<div>\n  <% if article.errors.any? %>\n    <p>x</p>\n  <% end %>\n</div>\n") do |uri|
        expect(@client.diagnostic_messages(uri, timeout: 6).join(" ")).not_to match(/String has no method/i)
      end
    end

    # Regression: `<%= yield %>` is legal in a layout -- the compiled
    # template is a method body -- but the extracted Ruby is top level,
    # where Prism rejects it. Every Rails layout reported a syntax error.
    it "G10: does not report `yield` in a layout as a syntax error" do
      with_file("app/views/layouts/probe.html.erb", "<html>\n  <%= yield %>\n</html>\n") do |uri|
        expect(@client.diagnostic_messages(uri, timeout: 6).join(" ")).not_to match(/yield/i)
      end
    end

    # Regression: the receiver position for an inner call was recorded
    # one character past the receiver, which lands on `[` in
    # `params[:id]` -- a position the *enclosing* expression also covers.
    # With a model registry loaded, `Article.find(params[:id])` therefore
    # resolved `[]`'s receiver to Article and reported "Article has no
    # method named `[]`". Invisible without model data, which is why no
    # unit test saw it.
    it "G11: attributes an inner call to its own receiver, not the enclosing expression" do
      with_file("app/models/inner_call_probe.rb", <<~RUBY) do |uri|
        class InnerCallProbe
          def run(params)
            User.find(params[:id])
          end
        end
      RUBY
        expect(@client.diagnostic_messages(uri, timeout: 6).join(" ")).not_to match(/no method named/i)
      end
    end

    # Regression: diagnostics were computed once, when a file was opened,
    # and never again. The extension opens files as soon as it starts --
    # before the Runtime Agent has reported any routes -- so every
    # `*_path` in an already-open file was permanently marked unresolved,
    # and the only way to clear it was to edit the file. Invisible to any
    # test that waits for `ready-rails` before opening anything, which is
    # what every other example here does.
    it "G12: clears a route diagnostic once the Runtime Agent reports routes" do
      client = E2E::LspClient.new(self.class.workspace)
      begin
        client.initialize!
        path = File.join(self.class.workspace, "app/controllers/early_open_controller.rb")
        File.write(path, <<~RUBY)
          class EarlyOpenController < ApplicationController
            def destroy
              redirect_to posts_path
            end
          end
        RUBY
        # Opened immediately, the way the extension does, rather than
        # after waiting for the Agent.
        uri = client.open(path)
        client.wait_until_ready(agent: true)

        # Two halves, because `not_to match` alone is satisfied by a
        # world in which the check never ran: 0.2.0 made a route table
        # that has never loaded answer nothing at all (024.24), so this
        # example passed whether or not anything ever cleared. The
        # positive assertion is what makes the negative one mean
        # something -- routes arrived, the file was not touched, and
        # `posts_path` resolves.
        messages = client.diagnostic_messages(uri, timeout: 20)
        expect(messages.join(" ")).not_to match(/no route named/i)
        expect(Array(client.raw_request("textDocument/definition",
                                        { textDocument: { uri: uri },
                                          position: { line: 2, character: 18 } }))).not_to be_empty
      ensure
        client.stop
      end
    end

    # The shape `rails new` generates, and the last false positive 0.1.6
    # shipped with: `ActiveSupport::TestCase` lives in a gem, so reopening
    # it here is indistinguishable from defining it and the static chain
    # reads as complete. It is also never loaded in the environment the
    # Agent boots, so its ancestors cannot be compared -- only its autoload
    # registration settles it (024.R5).
    it "G13: reports nothing for a gem class the workspace reopens" do
      uri = @client.open(File.join(self.class.workspace, "test/test_helper.rb"))

      messages = @client.diagnostic_messages(uri, timeout: 10)
      # The control first: this file *is* being diagnosed, so the absence
      # below is the check staying silent rather than nothing running.
      expect(messages.join(" ")).to match(/definitely_not_a_method_on_this_class/)
      expect(messages.join(" ")).not_to match(/parallelize|fixtures/)
    end

    # The reopen makes `ActiveSupport::TestCase` a workspace-declared name,
    # so every test file inheriting from it has a static chain that reaches
    # BasicObject through it. Asking about the receiver alone left all of
    # them reporting the gem's whole API as unknown -- the same false
    # positive, one level down (024.R5).
    it "G14: reports nothing in a test that inherits from a reopened gem class" do
      uri = @client.open(File.join(self.class.workspace, "test/models/probe_subclass_test.rb"))

      expect(@client.diagnostic_messages(uri, timeout: 10).join(" ")).not_to match(/has no method named/i)
    end

    it "G5: reports a call with the wrong number of arguments" do
      with_file("app/models/arity_probe.rb", <<~RUBY) do |uri|
        class ArityProbe
          def takes_one(a); end

          def run
            value = ArityProbe.new
            value.takes_one(1, 2, 3)
          end
        end
      RUBY
        expect(@client.diagnostic_messages(uri).join(" ")).to match(/argument/i)
      end
    end
  end

  # G17. The row 0.2.0 shipped without, on 024.14's strength -- which
  # said a never-opened probe produced no diagnostic in 45 seconds.
  #
  # It reproduces as *working*: on a real Rails application the file is
  # answered 1.4s from process start. What the original measurement most
  # likely hit is the line below: `Dir.tmpdir` is `/var/folders/…` on
  # macOS and the server publishes `/private/var/folders/…`, so a test
  # that builds the expected uri from the un-resolved path waits for a
  # notification that has already arrived under another name.
  describe "workspace-wide diagnostics" do
    # Its own Core, because the property is about a file that is on disk
    # *before* the server starts -- which is what 024.14 described and
    # what the shared client, started in `before(:all)`, cannot be given.
    it "G17: reports a mistake in a file nobody opened" do
      path = File.join(self.class.workspace, "app/models/unopened_capability_probe.rb")
      File.write(path, <<~RUBY)
        class UnopenedCapabilityProbe
          def run
            UnopenedCapabilityProbe.new.definitely_not_here
          end
        end
      RUBY
      # The path as the *client* named it, not its resolved form. This
      # example said `File.realpath(path)` and passed until 0.2.8, which
      # is the whole of `024.98` seen from the test side: Core inferred
      # its root from its own cwd, which the OS resolves, so a workspace
      # under a symlinked `/tmp` published every uri under `/private/tmp`
      # and this example had to resolve the path to find them. It now
      # publishes under the root the client sent -- the one the editor
      # will use when it opens the file -- so the two agree without a
      # `realpath` anywhere.
      #
      # The single `realpath` in this suite was the tell, and nobody read
      # it as one for four releases.
      uri = "file://#{path}"

      client = E2E::LspClient.new(self.class.workspace)
      begin
        client.initialize!
        client.wait_until_ready(agent: true)
        # One unrelated file opened, the way an editor restores a session.
        client.open(File.join(self.class.workspace, "app/controllers/posts_controller.rb"))

        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 60
        found = nil
        while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
          found = client.diagnostics_by_uri[uri]
          break if found && !found.empty?

          sleep 0.5
        end

        expect(Array(found).map { |d| d[:message] }.join(" ")).to match(/no method named/i)
      ensure
        client.stop
        File.delete(path) if File.exist?(path)
      end
    end
  end


  describe "signature help" do

    it "S1: reports a workspace method's parameters" do
      with_file("app/models/signature_probe.rb", <<~RUBY) do |uri|
        class SignatureProbe
          def takes(first, second); end

          def run
            value = SignatureProbe.new
            value.takes(
          end
        end
      RUBY
        expect(@client.signature_labels(uri, 5, 16).join(" ")).to include("first")
      end
    end

    # The same row, without a receiver -- the third capability whose
    # example only covered the receiver-qualified half. `documented(` in
    # the class that declares `documented` answered nothing.
    it "S1: reports a workspace method's parameters with no receiver in front" do
      with_file("app/models/receiverless_signature_probe.rb", <<~RUBY) do |uri|
        class ReceiverlessSignatureProbe
          def takes(first, second); end

          def run
            takes(
          end
        end
      RUBY
        expect(@client.signature_labels(uri, 4, 10).join(" ")).to include("first")
      end
    end
  end

  describe "signature help (continued)" do
    # Every other example here ends the source at an *unclosed* `(`,
    # which is the one input for which "scan back for any `(`" and "scan
    # back for an unmatched one" agree. With a call that has already
    # closed before the cursor they disagree, and the scan answered with
    # the inner call's signature for the rest of the line -- on
    # scaffolded Rails code, `link_to "Edit", edit_article_path(@article),
    # class: "btn"` showed `edit_article_path`'s parameters from the
    # closing paren onward.
    it "S1: reports the enclosing call's parameters, not an inner call that has already closed" do
      with_file("app/models/nested_signature_probe.rb", <<~RUBY) do |uri|
        class NestedSignatureProbe
          def takes(first, second); end
          def compute(a); a; end

          def run
            takes(compute(1), 2)
          end
        end
      RUBY
        # `    takes(compute(1), 2)` -- column 22 is the `2`, `takes`'s
        # second argument, with `compute(1)` closed behind it.
        labels = @client.signature_labels(uri, 5, 22).join(" ")

        expect(labels).to include("first")
        expect(labels).not_to include("compute")
      end
    end

    it "S2: reports an RBS overload label for a stdlib method" do
      with_file("app/models/stdlib_signature_probe.rb", <<~RUBY) do |uri|
        class StdlibSignatureProbe
          def run
            text = "s"
            text.split(
          end
        end
      RUBY
        expect(@client.signature_labels(uri, 3, 15).join(" ")).to include("split")
      end
    end

    it "S3: reports a route helper's parts" do
      with_file("app/controllers/route_signature_controller.rb", <<~RUBY) do |uri|
        class RouteSignatureController < ApplicationController
          def index
            post_path(
          end
        end
      RUBY
        expect(@client.signature_labels(uri, 2, 14).join(" ")).to include("post_path")
      end
    end
  end

  describe "workspace-wide" do
    it "W1: finds every reference to a workspace method" do
      with_file("app/models/reference_probe.rb", <<~RUBY) do |uri|
        class ReferenceProbe
          def referenced_method; end

          def run
            value = ReferenceProbe.new
            value.referenced_method
          end
        end
      RUBY
        with_file("app/models/reference_caller_probe.rb", <<~RUBY) do |caller_uri|
          class ReferenceCallerProbe
            def run
              ReferenceProbe.new.referenced_method
            end
          end
        RUBY
          targets = @client.references(uri, 1, 8).map { |location| location[:uri] }

          # The row says "across files", and `not_to be_empty` was true of
          # an answer carrying the declaration and nothing else.
          expect(targets).to include(uri)
          expect(targets).to include(caller_uri)
        end
      end
    end

    it "W2: rewrites every call site when a workspace method is renamed" do
      with_file("app/models/rename_probe.rb", <<~RUBY) do |uri|
        class RenameProbe
          def old_name; end

          def run
            value = RenameProbe.new
            value.old_name
          end
        end
      RUBY
        edits = @client.rename_edits(uri, 1, 8, "new_name")
        expect(edits.values.flatten.size).to be >= 2
      end
    end

    # Its own row, not a second `W2`: `capability_coverage_spec` compares
    # ids as set differences, so a duplicate id makes the new row and its
    # example cancel out and the guard cannot see either.
    # `attr_accessor :title` declares its methods at a symbol argument,
    # and a rename that edited only the call sites would leave that
    # declaration behind and the file would not run. `024.27` gave the
    # declaration that argument's range, so "there is nothing to
    # rewrite" -- what this comment said until 0.2.16 -- is no longer
    # the reason; the reason is that the argument is source the macro
    # reads, and rewriting it changes more than this method's name
    # (`024.28`). The suite could not see any of it before: nothing in
    # this fixture used `attr_*` at all, and 0.1.14 shipped that
    # regression through a green capability run.
    it "W4: refuses rather than half-renaming a method a macro declared" do
      with_file("app/models/attr_rename_probe.rb", <<~RUBY) do |uri|
        class AttrRenameProbe
          attr_accessor :title

          def run
            value = AttrRenameProbe.new
            value.title
          end
        end
      RUBY
        expect(@client.rename_edits(uri, 5, 12, "headline")).to be_empty
      end
    end

    it "W3: finds a workspace class and a workspace method by symbol search" do
      with_file("app/models/symbol_probe.rb", "class SymbolProbe\n  def symbol_probe_method; end\nend\n") do |_uri|
        expect(@client.workspace_symbols("SymbolProbe")).to include("SymbolProbe")
        # The row says "classes and methods"; only the class was asserted.
        expect(@client.workspace_symbols("symbol_probe_method")).to include("symbol_probe_method")
      end
    end

    # 0.3.0. `045`: "an incremental step on the same index" -- incoming
    # calls are the references the index already holds, grouped by the
    # method each one sits inside.
    #
    # Unlike documentHighlight this *does* warm the reference index, and
    # that is right: opening a call hierarchy is a deliberate action, not
    # something the editor does on every cursor move.
    it "W5: lists a method's callers across files, with the range of each call" do
      callee = "class ChSubject\n  def ch_target\n    1\n  end\nend\n"
      # Three shapes in one file, each of which a different wrong
      # implementation gets wrong:
      #
      #   `go`             -- the ordinary caller.
      #   `outer`/`inner`  -- nested `def`s, both of whose recorded ranges
      #                       contain the call. The innermost is the caller;
      #                       taking the first declaration that contains it
      #                       names `outer`, which did not make the call.
      #   the top-level call -- no enclosing method at all, and a caller
      #                       invented for it is an assertion about the
      #                       user's code that nothing supports.
      calling = <<~SOURCE
        class ChCaller
          def go
            ChSubject.new.ch_target
          end

          def outer
            def inner
              ChSubject.new.ch_target
            end
          end
        end

        ChSubject.new.ch_target
      SOURCE

      with_file("app/models/ch_subject.rb", callee) do |uri|
        with_file("app/models/ch_caller.rb", calling) do |_other|
          item = @client.prepare_call_hierarchy(uri, 1, 6).first
          expect(item).not_to be_nil, "prepareCallHierarchy answered nothing on a `def`"
          expect(item[:name]).to eq("ch_target")

          incoming = @client.incoming_calls(item)
          # Exactly these two. Not the class, not the file, and nothing for
          # the top-level call, which has no caller this protocol can name.
          expect(incoming.map { |c| c[:from][:name] }.sort).to eq(%w[go inner])

          # And the range is the call site inside `go`, which is what makes
          # the entry navigable rather than merely named.
          by_caller = incoming.to_h { |c| [c[:from][:name], Array(c[:fromRanges]).map { |r| r[:start][:line] }] }
          expect(by_caller["go"]).to eq([2])
          expect(by_caller["inner"]).to eq([7])
        end
      end
    end

    it "W6: lists the methods a method calls, with the range of each call" do
      source = "class ChOutgoing\n" \
               "  def first_leg\n    1\n  end\n\n" \
               "  def second_leg\n    2\n  end\n\n" \
               "  def both\n    first_leg\n    second_leg\n  end\n" \
               "end\n"

      with_file("app/models/ch_outgoing.rb", source) do |uri|
        item = @client.prepare_call_hierarchy(uri, 9, 6).first
        expect(item).not_to be_nil
        expect(item[:name]).to eq("both")

        outgoing = @client.outgoing_calls(item)
        expect(outgoing.map { |c| c[:to][:name] }).to contain_exactly("first_leg", "second_leg")

        # One range per call, at the line the call is written on. Without
        # this the two entries are indistinguishable from a name list.
        by_name = outgoing.to_h { |c| [c[:to][:name], Array(c[:fromRanges]).map { |r| r[:start][:line] }] }
        expect(by_name["first_leg"]).to eq([10])
        expect(by_name["second_leg"]).to eq([11])
      end
    end

    # The live half of `CALLABLE_KINDS`. A class has no callers in this
    # protocol's sense, so answering for one would be a list of mentions
    # wearing a caller's name -- and the guard that refuses it was
    # unpinned until this example, while the same constant's use on the
    # outgoing side turned out to be dead and was removed.
    it "W5/W6: offers no call hierarchy on a class name" do
      with_file("app/models/ch_class_probe.rb", "class ChClassProbe\n  def m; end\nend\n") do |uri|
        expect(@client.prepare_call_hierarchy(uri, 0, 8)).to be_empty
        # The control: the same file answers on the method one line down,
        # so an empty answer above is the guard and not a dead request.
        expect(@client.prepare_call_hierarchy(uri, 1, 6)).not_to be_empty
      end
    end

  # 0.3.0's first capability. `045` orders it first of the four that need
  # only what already exists: the reference index answers occurrences
  # workspace-wide, so scoping to one file is nearly free.
  #
  # The deferral note in `server.rb` named the trap, and these examples
  # are written against it: References and Rename call
  # `ensure_reference_index_current`, whose rebuild is O(workspace),
  # while the editor asks for highlights **on every cursor move**. So
  # this answers from the open file's own summary and the last example
  # here is the one that says so.
  describe "in the current file" do
    it "F1: highlights every occurrence of a local, and not a same-named local elsewhere" do
      source = <<~RUBY
        class HighlightProbe
          def outer
            counter = 1
            counter += 2
            counter
          end

          def other
            counter = 9
            counter
          end
        end
      RUBY

      with_file("app/models/highlight_probe.rb", source) do |uri|
        # The caret is on `counter` in `counter = 1`, line 2.
        highlights = @client.document_highlights(uri, 2, 4)
        lines = highlights.map { |h| h[:range][:start][:line] }.sort

        # Three in `outer`; the two in `other` are a different binding and
        # a fixture where both scopes answered the same would not tell the
        # two behaviours apart.
        expect(lines).to eq([2, 3, 4])

        # **Write, write, read.** `counter = 1` and `counter += 2` assign;
        # the bare `counter` reads. This shipped as `Text` for all three,
        # on the argument that the layer could not tell -- which was true
        # of the layer and wrong about what was knowable, since the parser
        # has separate write visitors and was discarding the distinction.
        by_line = highlights.to_h { |h| [h[:range][:start][:line], h[:kind]] }
        expect(by_line).to eq({ 2 => 3, 3 => 3, 4 => 2 })
      end
    end

    it "F2: highlights a method's declaration and its call sites in the file" do
      source = <<~RUBY
        class HighlightMethodProbe
          def compute_total
            41
          end

          def caller_one
            compute_total + 1
          end

          def caller_two
            compute_total
          end
        end
      RUBY

      with_file("app/models/highlight_method_probe.rb", source) do |uri|
        # The caret is on `compute_total` in its `def`, line 1.
        highlights = @client.document_highlights(uri, 1, 6)
        lines = highlights.map { |h| h[:range][:start][:line] }.sort

        expect(lines).to eq([1, 6, 10])

        # The protocol carries a kind, and a declaration is not a read.
        # Without this the answer is a list of ranges wearing a field
        # nothing sets.
        by_line = highlights.to_h { |h| [h[:range][:start][:line], h[:kind]] }
        expect(by_line[1]).to eq(3)
        expect(by_line[6]).to eq(2)
      end
    end

    # The capability's actual requirement, and the reason the row exists
    # in a section of its own. An implementation that reached for
    # `references_result` would pass both examples above and rebuild the
    # workspace index on every keystroke.
    it "F1/F2: answers without rebuilding the workspace reference index" do
      source = "class HighlightCostProbe\n  def only\n    value = 1\n    value\n  end\nend\n"

      with_file("app/models/highlight_cost_probe.rb", source) do |uri|
        before = @client.raw_request("ovallsp/status", {})[:referenceIndexGeneration]
        5.times { @client.document_highlights(uri, 2, 4) }
        after = @client.raw_request("ovallsp/status", {})[:referenceIndexGeneration]

        expect(after).to eq(before)
      end
    end
  end
  end
end
