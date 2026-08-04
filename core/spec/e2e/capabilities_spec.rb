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
    @state = @client.wait_until_ready
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
    client.wait_until_ready
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
        expect(@client.hover_text(uri, 6, 10)).to include("documented(first, second)")
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

    it "H4: reports literal types" do
      with_file("app/models/literal_probe.rb", <<~RUBY) do |uri|
        class LiteralProbe
          def run
            text = "s"
            text
          end
        end
      RUBY
        expect(@client.hover_text(uri, 3, 6)).to eq("String")
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
        expect(@client.completion_labels(uri, 3, 9)).to include("posts")
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
        expect(@client.completion_labels(uri, 2, 9)).to include("find", "where", "all")
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

    it "C12: offers workspace classes and locals with no receiver in front" do
      with_file("app/models/prefix_probe.rb", <<~RUBY) do |uri|
        class PrefixProbe
          def run
            prefix_local = 1
            pre
          end
        end
      RUBY
        labels = @client.completion_labels(uri, 3, 7)
        expect(labels).to include("prefix_local")
        expect(labels).to include("PrefixProbe")
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
            posts_p
          end
        end
      RUBY
        expect(@client.completion_labels(uri, 2, 11)).to include("posts_path")
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
        client.wait_until_ready

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
  end

  describe "signature help (continued)" do
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
        expect(@client.references(uri, 1, 8)).not_to be_empty
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
    # `attr_accessor` declares a method with no
    # identifier token to rewrite, so a rename that edited only the call
    # sites would leave the declaration behind and the file would not run.
    # The suite could not see this before: nothing in this fixture used
    # `attr_*` at all, and 0.1.14 shipped that regression through a green
    # capability run.
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

    it "W3: finds a workspace class by symbol search" do
      with_file("app/models/symbol_probe.rb", "class SymbolProbe\nend\n") do |_uri|
        expect(@client.workspace_symbols("SymbolProbe")).to include("SymbolProbe")
      end
    end
  end
end
