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

    it "W3: finds a workspace class by symbol search" do
      with_file("app/models/symbol_probe.rb", "class SymbolProbe\nend\n") do |_uri|
        expect(@client.workspace_symbols("SymbolProbe")).to include("SymbolProbe")
      end
    end
  end
end
