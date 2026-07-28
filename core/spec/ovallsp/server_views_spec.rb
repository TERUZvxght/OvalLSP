# frozen_string_literal: true

require "stringio"

RSpec.describe "Ovallsp::Server controller-to-view instance variable propagation (Task 008)" do
  let(:output) { StringIO.new }
  let(:logger) { instance_double(Ovallsp::Logger, info: nil, warn: nil, error: nil) }
  let(:model_registry) do
    registry = Ovallsp::Models::ModelRegistry.new
    registry.register_from_agent_response("User", { tableName: "users", partial: false, columns: [], associations: [] })
    registry
  end

  def frame(hash)
    json = JSON.generate(hash)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  def build_server(input_string)
    Ovallsp::Server.new(input: StringIO.new(input_string), output: output, logger: logger, model_registry: model_registry)
  end

  def sent_messages
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.reject { |m| m[:method] == "textDocument/publishDiagnostics" }
  end

  def open(uri, text, language_id: "ruby")
    frame(
      jsonrpc: "2.0", method: "textDocument/didOpen",
      params: { textDocument: { uri: uri, text: text, version: 1, languageId: language_id } }
    )
  end

  it "propagates UsersController#show's @user into show.html.erb as User" do
    input =
      open("file:///app/controllers/users_controller.rb",
           "class UsersController\n  def show\n    @user = User.find(params[:id])\n  end\nend\n") +
      open("file:///app/views/users/show.html.erb", "<p><%= @user %></p>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: { textDocument: { uri: "file:///app/views/users/show.html.erb" }, position: { line: 0, character: 8 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "User")
  end

  it "propagates ivars from an action that explicitly renders another view (render :edit)" do
    input =
      open("file:///app/controllers/posts_controller.rb", <<~RUBY) +
        class PostsController
          def update
            @post = 42
            render :edit
          end

          def edit
          end
        end
      RUBY
      open("file:///app/views/posts/edit.html.erb", "<%= @post %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: { textDocument: { uri: "file:///app/views/posts/edit.html.erb" }, position: { line: 0, character: 4 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "Integer | nil")
  end

  it "recognizes a controller-qualified render target for the same view" do
    input =
      open("file:///app/controllers/posts_controller.rb", <<~RUBY) +
        class PostsController
          def update
            @post = 42
            render "posts/edit"
          end

          def edit
          end
        end
      RUBY
      open("file:///app/views/posts/edit.html.erb", "<%= @post %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: { textDocument: { uri: "file:///app/views/posts/edit.html.erb" }, position: { line: 0, character: 4 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "Integer | nil")
  end

  it "does not treat private controller helpers as renderable actions" do
    input =
      open("file:///app/controllers/posts_controller.rb", <<~RUBY) +
        class PostsController
          def edit
          end

          private

          def prepare_edit
            @secret = 42
            render :edit
          end
        end
      RUBY
      open("file:///app/views/posts/edit.html.erb", "<%= @secret %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: { textDocument: { uri: "file:///app/views/posts/edit.html.erb" }, position: { line: 0, character: 4 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "Unknown")
  end

  it "does not treat a public inherited action as effective when a child overrides it privately" do
    input =
      open("file:///app/controllers/application_controller.rb", <<~RUBY) +
        class ApplicationController
          def show
            @record = User.new
          end
        end
      RUBY
      open("file:///app/controllers/users_controller.rb", <<~RUBY) +
        class UsersController < ApplicationController
          private

          def show
            @record = Secret.new
          end
        end
      RUBY
      open("file:///app/views/users/show.html.erb", "<%= @record %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: { textDocument: { uri: "file:///app/views/users/show.html.erb" }, position: { line: 0, character: 4 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "Unknown")
  end

  # Regression: `class << self` bodies contain receiverless defs, so
  # without a visit_singleton_class_node override the locator registered
  # them as this controller's *instance* methods -- letting a singleton
  # `self.edit` be chosen as the action body and leak its ivars into
  # edit.html.erb, ahead of the real (empty) action.
  it "does not treat a `class << self` method as the action body" do
    input =
      open("file:///app/controllers/posts_controller.rb", <<~RUBY) +
        class PostsController
          def edit
          end

          class << self
            def edit
              @secret = User.find(1)
            end
          end
        end
      RUBY
      open("file:///app/views/posts/edit.html.erb", "<%= @secret %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: { textDocument: { uri: "file:///app/views/posts/edit.html.erb" }, position: { line: 0, character: 5 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "Unknown")
  end

  # Regression: `private def prepare; end` is idiomatic in Rails
  # controllers, but only the bare `private` section form was recognized,
  # so the helper counted as a public action and its ivars reached the
  # view it rendered.
  it "does not treat a `private def` helper as a public action" do
    input =
      open("file:///app/controllers/posts_controller.rb", <<~RUBY) +
        class PostsController
          def edit
          end

          private def prepare_edit
            @secret = User.find(1)
            render :edit
          end
        end
      RUBY
      open("file:///app/views/posts/edit.html.erb", "<%= @secret %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: { textDocument: { uri: "file:///app/views/posts/edit.html.erb" }, position: { line: 0, character: 5 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "Unknown")
  end

  it "propagates ivars assigned by a before_action into the corresponding view" do
    input =
      open("file:///app/controllers/users_controller.rb", <<~RUBY) +
        class UsersController
          before_action :load_user, only: :show

          def load_user
            @user = User.find(params[:id])
          end

          def show
          end
        end
      RUBY
      open("file:///app/views/users/show.html.erb", "<%= @user %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: { textDocument: { uri: "file:///app/views/users/show.html.erb" }, position: { line: 0, character: 4 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "User")
  end

  it "propagates inherited before_actions and honors a child skip_before_action" do
    inherited_input =
      open("file:///app/controllers/application_controller.rb", <<~RUBY) +
        class ApplicationController
          before_action :load_user
          def load_user = @user = User.new
        end
      RUBY
      open("file:///app/controllers/users_controller.rb", <<~RUBY) +
        class UsersController < ApplicationController
          def show; end
        end
      RUBY
      open("file:///app/views/users/show.html.erb", "<%= @user %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: { textDocument: { uri: "file:///app/views/users/show.html.erb" }, position: { line: 0, character: 4 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(inherited_input).run
    expect(sent_messages.first[:result]).to eq(type: "User")

    output.truncate(0)
    output.rewind
    skipped_input =
      open("file:///app/controllers/application_controller.rb", <<~RUBY) +
        class ApplicationController
          before_action :load_user
          def load_user = @user = User.new
        end
      RUBY
      open("file:///app/controllers/users_controller.rb", <<~RUBY) +
        class UsersController < ApplicationController
          skip_before_action :load_user, only: :show
          def show; end
        end
      RUBY
      open("file:///app/views/users/show.html.erb", "<%= @user %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 2, method: "ovallsp/explainType",
        params: { textDocument: { uri: "file:///app/views/users/show.html.erb" }, position: { line: 0, character: 4 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(skipped_input).run
    expect(sent_messages.first[:result]).to eq(type: "Unknown")
  end

  it "dispatches implicit-self calls in an inherited callback against the concrete controller" do
    input =
      open("file:///app/controllers/application_controller.rb", <<~RUBY) +
        class ApplicationController
          before_action :load_actor
          def load_actor = @actor = current_actor
          def current_actor = Account.new
        end
      RUBY
      open("file:///app/controllers/users_controller.rb", <<~RUBY) +
        class UsersController < ApplicationController
          def current_actor = Admin.new
          def show; end
        end
      RUBY
      open("file:///app/views/users/show.html.erb", "<%= @actor %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: { textDocument: { uri: "file:///app/views/users/show.html.erb" }, position: { line: 0, character: 4 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "Admin")
  end

  it "keeps the full namespace when dispatching an inherited callback against the concrete controller" do
    input =
      open("file:///app/controllers/application_controller.rb", <<~RUBY) +
        class ApplicationController
          before_action :load_actor
          def load_actor = @actor = current_actor
        end
      RUBY
      open("file:///app/controllers/admin/users_controller.rb", <<~RUBY) +
        module Admin
          class UsersController < ApplicationController
            def current_actor = AdminUser.new
            def show; end
          end
        end
      RUBY
      open("file:///app/views/admin/users/show.html.erb", "<%= @actor %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: {
          textDocument: { uri: "file:///app/views/admin/users/show.html.erb" },
          position: { line: 0, character: 4 }
        }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "AdminUser")
  end

  # Regression: the spec above writes the controller in nested form, and
  # `owner` is recorded lexically -- so it pins only one of the two
  # SymbolIds the same class can have. Deriving the owner from the name
  # made the nested form work and broke the compact form, which is the
  # one `rails g controller admin/users` emits; the previous nil-owner
  # version had it exactly the other way round. Either way an entire
  # namespaced controller's ivars stop reaching its views.
  it "keeps the full namespace for a compact-form namespaced controller" do
    input =
      open("file:///app/controllers/application_controller.rb", <<~RUBY) +
        class ApplicationController
          before_action :load_actor
          def load_actor = @actor = current_actor
        end
      RUBY
      open("file:///app/controllers/admin/users_controller.rb", <<~RUBY) +
        class Admin::UsersController < ApplicationController
          def current_actor = AdminUser.new
          def show; end
        end
      RUBY
      open("file:///app/views/admin/users/show.html.erb", "<%= @actor %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: {
          textDocument: { uri: "file:///app/views/admin/users/show.html.erb" },
          position: { line: 0, character: 4 }
        }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "AdminUser")
  end

  # The third spelling, which neither owner-derived candidate matched:
  # `owner` is "::Api" while the name is "::Api::V1::UsersController".
  # Enumerating owner shapes only moves which spelling breaks, so the
  # lookup goes by qualified name instead.
  it "keeps the full namespace for a partly compact namespaced controller" do
    input =
      open("file:///app/controllers/application_controller.rb", <<~RUBY) +
        class ApplicationController
          before_action :load_actor
          def load_actor = @actor = current_actor
        end
      RUBY
      open("file:///app/controllers/api/v1/users_controller.rb", <<~RUBY) +
        module Api
          class V1::UsersController < ApplicationController
            def current_actor = AdminUser.new
            def show; end
          end
        end
      RUBY
      open("file:///app/views/api/v1/users/show.html.erb", "<%= @actor %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: {
          textDocument: { uri: "file:///app/views/api/v1/users/show.html.erb" },
          position: { line: 0, character: 4 }
        }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "AdminUser")
  end

  # The lookup goes through a secondary index keyed by *simple* name, so
  # the exact qualified-name check is the only thing keeping
  # `::Admin::UsersController` from matching a plain `::UsersController`.
  # None of the three specs above can see that: their namespaces collide
  # with nothing. `rails g controller admin/users` alongside an existing
  # top-level UsersController produces exactly this collision, and which
  # one an unguarded lookup returns depends on index insertion order --
  # so the failure is not a miss but the *other* controller's ivar types
  # in this view.
  it "does not confuse a namespaced controller with a same-named top-level one" do
    input =
      open("file:///app/controllers/users_controller.rb", <<~RUBY) +
        class UsersController
          def show
            @actor = TopLevelUser.new
          end
        end
      RUBY
      open("file:///app/controllers/admin/users_controller.rb", <<~RUBY) +
        class Admin::UsersController
          def show
            @actor = AdminUser.new
          end
        end
      RUBY
      open("file:///app/views/admin/users/show.html.erb", "<%= @actor %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: {
          textDocument: { uri: "file:///app/views/admin/users/show.html.erb" },
          position: { line: 0, character: 4 }
        }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "AdminUser")
  end

  it "infers an inherited action body using the concrete controller as self" do
    input =
      open("file:///app/controllers/application_controller.rb", <<~RUBY) +
        class ApplicationController
          def show = @user = current_user
          def current_user = User.new
        end
      RUBY
      open("file:///app/controllers/users_controller.rb", <<~RUBY) +
        class UsersController < ApplicationController
          def current_user = Admin.new
        end
      RUBY
      open("file:///app/views/users/show.html.erb", "<%= @user %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: { textDocument: { uri: "file:///app/views/users/show.html.erb" }, position: { line: 0, character: 4 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "Admin")
  end

  it "unions nil when an alternative rendering action leaves an ivar unset" do
    input =
      open("file:///app/controllers/posts_controller.rb", <<~RUBY) +
        class PostsController
          def edit
            @record = User.new
          end

          def update
            render :edit
          end
        end
      RUBY
      open("file:///app/views/posts/edit.html.erb", "<%= @record %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: { textDocument: { uri: "file:///app/views/posts/edit.html.erb" }, position: { line: 0, character: 4 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result]).to eq(type: "User | nil")
  end

  it "unions conflicting ivar types from alternative actions that render the same view" do
    input =
      open("file:///app/controllers/posts_controller.rb", <<~RUBY) +
        class PostsController
          def edit
            @record = User.new
          end

          def update
            @record = Admin.new
            render :edit
          end
        end
      RUBY
      open("file:///app/views/posts/edit.html.erb", "<%= @record %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: { textDocument: { uri: "file:///app/views/posts/edit.html.erb" }, position: { line: 0, character: 4 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    expect(sent_messages.first[:result][:type].split(" | ")).to contain_exactly("User", "Admin")
  end

  it "reflects an edited controller action immediately (no stale view context)" do
    controller_uri = "file:///app/controllers/users_controller.rb"
    view_uri = "file:///app/views/users/show.html.erb"

    input =
      open(controller_uri, "class UsersController\n  def show\n    @user = 1\n  end\nend\n") +
      open(view_uri, "<%= @user %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: { textDocument: { uri: view_uri }, position: { line: 0, character: 4 } }
      ) +
      frame(
        jsonrpc: "2.0", method: "textDocument/didChange",
        params: {
          textDocument: { uri: controller_uri, version: 2 },
          contentChanges: [{ text: "class UsersController\n  def show\n    @user = \"changed\"\n  end\nend\n" }]
        }
      ) +
      frame(
        jsonrpc: "2.0", id: 2, method: "ovallsp/explainType",
        params: { textDocument: { uri: view_uri }, position: { line: 0, character: 4 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    messages = sent_messages
    expect(messages[0][:result]).to eq(type: "Integer")
    expect(messages[1][:result]).to eq(type: "String")
  end

  it "degrades to Unknown when no controller action corresponds to the view" do
    view_uri = "file:///app/views/mystery/whoami.html.erb"

    input =
      open(view_uri, "<%= @thing %>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "ovallsp/explainType",
        params: { textDocument: { uri: view_uri }, position: { line: 0, character: 4 } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    expect { build_server(input).run }.not_to raise_error
    expect(sent_messages.first[:result]).to eq(type: "Unknown")
  end

  # Task 008.6: didOpen must run a .erb document's declaration extraction
  # (WorkspaceIndex/documentSymbol) through the same ERB-aware parsing
  # Cold Index already used — before this, opening a .erb file fed its
  # raw HTML+`<% %>` source directly to Prism, which parsed it as invalid
  # Ruby and never captured a constant assigned inside a tag (and could
  # raise on some HTML shapes, silently swallowed by #reindex's rescue).
  it "indexes a constant assigned inside a <% %> tag on didOpen, not just via Cold Index" do
    view_uri = "file:///app/views/widgets/index.html.erb"
    input =
      open(view_uri, "<div class=\"x\"><% WidgetLimit = 10 %></div>\n", language_id: "erb") +
      frame(
        jsonrpc: "2.0", id: 1, method: "textDocument/documentSymbol",
        params: { textDocument: { uri: view_uri } }
      ) +
      frame(jsonrpc: "2.0", method: "exit", params: nil)

    build_server(input).run

    symbols = sent_messages.first[:result]
    expect(symbols.map { |s| s[:name] }).to include("WidgetLimit")
  end
end
