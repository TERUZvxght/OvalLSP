# frozen_string_literal: true

require "stringio"

# Reading an instance variable nothing assigns (0.2.0, closes 024.R6).
#
# Ruby returns `nil` for an unassigned instance variable rather than
# raising, so `@usr` where the code meant `@user` is a mistake the
# language itself never surfaces: the view renders empty and nobody is
# told why.
#
# The information was already here. Controller-to-view propagation
# already infers the set of instance variables an action assigns,
# including through the `before_action` chain — so a read of one that the
# effective chain never produces is reportable with high confidence.
RSpec.describe "Ovallsp::Server unassigned instance variable reads (0.2.0)" do
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

  def open(uri, text, language_id: "ruby")
    frame(
      jsonrpc: "2.0", method: "textDocument/didOpen",
      params: { textDocument: { uri: uri, text: text, version: 1, languageId: language_id } }
    )
  end

  def diagnostics_for(uri)
    output.rewind
    reader = Ovallsp::IO::FramedReader.new(output)
    messages = []
    loop { messages << reader.read_message }
  rescue Ovallsp::IO::FramedReader::EOF
    messages.select { |m| m[:method] == "textDocument/publishDiagnostics" && m[:params][:uri] == uri }
           .last&.dig(:params, :diagnostics) || []
  end

  VIEW_URI = "file:///app/views/users/show.html.erb"

  def run_server(controller:, view:, also: nil)
    input = open("file:///app/controllers/users_controller.rb", controller) +
            (also ? open("file:///app/controllers/users_controller_extra.rb", also) : "") +
            open(VIEW_URI, view, language_id: "erb") +
            frame(jsonrpc: "2.0", method: "exit", params: nil)
    Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger,
                        model_registry: model_registry).run
    diagnostics_for(VIEW_URI).select { |d| d[:code] == "unassigned-ivar" }
  end

  ASSIGNS_USER = <<~RUBY
    class UsersController
      def show
        @user = User.find(params[:id])
      end
    end
  RUBY

  it "reports an @ivar the action never assigns" do
    found = run_server(controller: ASSIGNS_USER, view: "<%= @usr %>\n")

    expect(found.size).to eq(1)
    expect(found.first[:message]).to include("@usr")
  end

  it "says nothing about an @ivar the action does assign" do
    expect(run_server(controller: ASSIGNS_USER, view: "<%= @user %>\n")).to be_empty
  end

  it "underlines the read itself" do
    found = run_server(controller: ASSIGNS_USER, view: "<p><%= @usr %></p>\n")

    expect(found.first[:range][:start][:character]).to eq(7)
  end

  # The chain is where most controller ivars actually come from, and a
  # check that did not follow it would report every one of them.
  it "counts an @ivar assigned by a before_action" do
    controller = <<~RUBY
      class UsersController
        before_action :load_user

        def load_user
          @user = User.find(params[:id])
        end

        def show
        end
      end
    RUBY

    expect(run_server(controller: controller, view: "<%= @user %>\n")).to be_empty
  end

  # Every silence below is a case where an assignment could exist somewhere
  # this cannot see, and the standard is the one every other check here is
  # held to: a wrong report is worse than a missed one.
  # The enumeration walks the callback chain and the action's own body.
  # An action that calls a sibling method assigns through a body it never
  # reads -- and the answer it produces then looks like a complete set
  # that happens not to contain `@user`, which is a warning on code that
  # renders correctly. The whole check is built on being able to say "I
  # cannot enumerate this" instead.
  it "says nothing when the action delegates the assignment to another method" do
    controller = <<~RUBY
      class UsersController
        def show
          load_user
        end

        def load_user
          @user = User.find(params[:id])
        end
      end
    RUBY

    expect(run_server(controller: controller, view: "<%= @user.name %>")).to be_empty
  end

  # Private, because that is how such a helper is usually written and the
  # visibility filter is a different code path.
  it "says nothing when the action delegates to a private method" do
    controller = <<~RUBY
      class UsersController
        def show
          load_user
        end

        private

        def load_user
          @user = User.find(params[:id])
        end
      end
    RUBY

    expect(run_server(controller: controller, view: "<%= @user.name %>")).to be_empty
  end

  # The gate is about calls this analysis cannot follow, not about calls.
  # An action calling something the controller does not define -- Rails'
  # own `render`, a helper, anything -- is still fully enumerable, and
  # treating it otherwise would switch the check off for every action.
  it "still reports when the action's calls are not to methods of this controller" do
    controller = <<~RUBY
      class UsersController
        def show
          @user = User.find(params[:id])
          render :show
        end
      end
    RUBY

    expect(run_server(controller: controller, view: "<%= @usr.name %>").size).to eq(1)
  end

  # A call *with* a receiver reaches a different object's body, which
  # cannot assign this controller's instance variables however the method
  # happens to be named. Counting it would switch the check off for any
  # action that calls something sharing a name with a controller method.
  it "still reports when a call naming a controller method has a receiver" do
    controller = <<~RUBY
      class UsersController
        def show
          presenter.load_user
        end

        def load_user
          @user = User.find(params[:id])
        end
      end
    RUBY

    expect(run_server(controller: controller, view: "<%= @usr.name %>").size).to eq(1)
  end

  # The hierarchy index knows the chain; the text regex knows the file.
  # `include(Concerns::Loader)` -- parenthesised, which is ordinary Ruby
  # -- is invisible to `MIXED_IN_MODULE` and plain to the chain, so this
  # is the fixture that says which of the two is load-bearing. The module
  # carries its own methods, and `controller_ancestor_documents` walks
  # only classes.
  it "says nothing when a module is mixed in by a call the text guard cannot see" do
    controller = <<~RUBY
      class UsersController
        include(Concerns::Loader)

        def show
        end
      end
    RUBY

    expect(run_server(controller: controller, view: "<%= @user.name %>")).to be_empty
  end

  # The set the check compares against came from the *type-propagation*
  # walk, which folds the statement shapes it models and infers `Unknown`
  # for the rest. That is harmless for types and wrong for a diagnostic:
  # a shape the walk does not fold produces a complete-looking set with a
  # name missing, which is a warning on a view that renders. `||=` and
  # `respond_to do |format|` are not edge cases -- they are two of the
  # most common lines in a Rails action.
  {
    "an ||= assignment" => "@user ||= User.find(params[:id])",
    "an &&= assignment" => "@user = 1
    @user &&= User.find(params[:id])",
    "an assignment inside a block" => "[1].each { |n| @user = n }",
    "an assignment inside respond_to" => "respond_to { |f| @user = 1 }",
    "an assignment inside a case" => "case params[:id]
    when \"1\" then @user = 1
    else @user = 2
    end",
    "an assignment inside begin/end" => "begin
      @user = 1
    end",
    "an assignment inside a while" => "while false
      @user = 1
    end",
    "an assignment in a rescue clause" => "@user = 1
  rescue StandardError
    @user = 2",
    "a multiple assignment" => "@acct, @user = 1, 2"
  }.each do |description, body|
    it "says nothing about an @ivar assigned by #{description}" do
      controller = "class UsersController\n  def show\n    #{body}\n  end\nend\n"

      expect(run_server(controller: controller, view: "<%= @user.name %>")).to be_empty
    end
  end

  # `controller_ancestor_documents` drops any ancestor whose file it
  # cannot resolve, silently. The chain is then short one class, and a
  # class this walk never read is indistinguishable from a class that
  # assigns nothing -- so the parent's `@current_user` looks unassigned.
  # This is the ordinary startup ordering: the editor restores a group and
  # sends didOpen for a view before the cold index has reached
  # `application_controller.rb`. And it is permanent for any controller
  # whose parent lives outside the workspace.
  it "says nothing when an ancestor of the controller could not be read" do
    controller = <<~RUBY
      class UsersController < ApplicationController
        def show
        end
      end
    RUBY

    expect(run_server(controller: controller, view: "<%= @current_user.name %>")).to be_empty
  end

  # A gem's class-level macro installs a callback that assigns at
  # runtime: `load_and_authorize_resource` (CanCanCan) produces `@users`,
  # and `expose`, Devise and ActiveAdmin do the same shape. None of them
  # is visible to a walk over `def` bodies, and every one of them is an
  # ordinary line in an ordinary controller.
  #
  # Until 024.R7 lets the index attribute such a call to the gem that
  # defines it, the honest answer is that a class-body call this analysis
  # does not model is a contributor it has not read. R7 narrows this to
  # the calls it still cannot account for, which widens the check rather
  # than changing its answers.
  it "says nothing when the class body calls something this analysis does not model" do
    controller = <<~RUBY
      class ApplicationController
      end

      class UsersController < ApplicationController
        load_and_authorize_resource

        def show
        end
      end
    RUBY

    expect(run_server(controller: controller, view: "<%= @user.name %>")).to be_empty
  end

  # Not every class-body call: the visibility modifiers and the callback
  # forms the chain builder already reads are accounted for by definition,
  # and treating them as unknown would switch the check off for every
  # controller that writes `private`.
  it "still reports for a controller whose class body only declares visibility and callbacks" do
    controller = <<~RUBY
      class ApplicationController
      end

      class UsersController < ApplicationController
        before_action :set_user

        def show
        end

        private

        def set_user
          @user = User.find(params[:id])
        end
      end
    RUBY

    expect(run_server(controller: controller, view: "<%= @usr.name %>").size).to eq(1)
  end

  # A view that renders a partial receives whatever the partial assigns,
  # and `<% @breadcrumbs = [] %>` at the top of `_header.html.erb` is an
  # ordinary thing to write. The walk reads the view's own text only, so
  # the read below looked unassigned.
  #
  # Resolving the partial is the precise answer and is left to the same
  # task as the rest (024.18); until then a render this analysis cannot
  # account for means the set is not complete, which is the answer the
  # check is built on.
  it "says nothing about a view that renders a partial" do
    controller = <<~RUBY
      class UsersController
        def show
          @user = User.find(params[:id])
        end
      end
    RUBY

    expect(run_server(controller: controller, view: "<%= render \"header\" %>\n<%= @breadcrumbs %>")).to be_empty
  end

  # `skip_before_action` is on the whitelist because the chain builder
  # reads it -- without this fixture, removing it from the list left the
  # whole suite green while switching the check off for every controller
  # that skips an inherited callback.
  it "still reports for a controller whose class body skips a callback" do
    controller = <<~RUBY
      class ApplicationController
      end

      class UsersController < ApplicationController
        skip_before_action :verify_authenticity_token

        def show
          @user = User.find(params[:id])
        end
      end
    RUBY

    expect(run_server(controller: controller, view: "<%= @usr.name %>").size).to eq(1)
  end

  # `render` the method, not the six letters. A view calling
  # `post.render` or naming a local `pre_render` is not rendering a
  # partial, and silencing a whole view on the substring would switch the
  # check off wherever those appear.
  {
    "a method named render on a receiver" => "<%= post.render %>",
    "an identifier that merely contains render" => "<%= pre_render %>"
  }.each do |description, extra|
    it "still reports for a view containing #{description}" do
      controller = <<~RUBY
        class UsersController
          def show
            @user = User.find(params[:id])
          end
        end
      RUBY

      expect(run_server(controller: controller, view: "#{extra}\n<%= @usr.name %>").size).to eq(1)
    end
  end

  # `find_controller_uri` answers with *one* uri per ancestor, so a second
  # file reopening the class is never read -- and the set the check then
  # compares against looks complete rather than partial. A controller
  # split across two files is unusual under Zeitwerk but legal, and this
  # is a warning on a view that renders.
  it "says nothing when a controller in the chain is declared in more than one file" do
    controller = <<~RUBY
      class UsersController
        def show
          load_user
        end
      end
    RUBY
    extra = <<~RUBY
      class UsersController
        def load_user
          @user = User.find(params[:id])
        end
      end
    RUBY

    expect(run_server(controller: controller, view: "<%= @user.name %>", also: extra)).to be_empty
  end

  it "says nothing when the controller uses instance_variable_set" do
    controller = <<~RUBY
      class UsersController
        def show
          instance_variable_set(:"@user", User.new)
        end
      end
    RUBY

    expect(run_server(controller: controller, view: "<%= @anything %>\n")).to be_empty
  end

  # The chain builder was written for type propagation, where missing a
  # source is harmless -- the ivar just infers Unknown. As the input to a
  # diagnostic, every omission becomes a wrong report on code that runs,
  # and none of these is an edge case in a Rails app.
  {
    "an around_action" => "around_action :with_tenant",
    "a prepend_before_action" => "prepend_before_action :with_tenant",
    "a block-form callback" => "before_action { @tenant = Tenant.current }",
    "a mixed-in concern" => "include Tenantable"
  }.each do |description, declaration|
    it "says nothing when the chain contains #{description}" do
      controller = <<~RUBY
        class UsersController
          #{declaration}

          def show
          end
        end
      RUBY

      expect(run_server(controller: controller, view: "<%= @tenant %>\n")).to be_empty
    end
  end

  it "says nothing when no controller action corresponds to the view" do
    controller = <<~RUBY
      class UsersController
        def index
          @users = User.all
        end
      end
    RUBY

    expect(run_server(controller: controller, view: "<%= @usr %>\n")).to be_empty
  end

  # An .erb file outside the app/views/<controller>/<action> convention
  # has no action context at all. Reaching for one anyway raises, and the
  # rescue turns that into the same silence -- so the silence alone
  # cannot tell a decision from an accident, and the log line can.
  it "says nothing, and reports no failure, for a view outside the naming convention" do
    stray = "file:///app/views/layouts/application.html.erb"
    input = open("file:///app/controllers/users_controller.rb", ASSIGNS_USER) +
            open(stray, "<%= @usr %>\n", language_id: "erb") +
            frame(jsonrpc: "2.0", method: "exit", params: nil)
    Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger,
                        model_registry: model_registry).run

    expect(diagnostics_for(stray).select { |d| d[:code] == "unassigned-ivar" }).to be_empty
    expect(logger).not_to have_received(:error)
  end

  # A view whose Ruby will not parse already has a syntax error reported.
  # Guessing at its assignments on top of that adds a second, wrong
  # finding to a file whose real problem is already named.
  it "says nothing about ivars in a view whose Ruby does not parse" do
    found = run_server(controller: ASSIGNS_USER, view: "<%= @usr %><% def %>\n")

    expect(found).to be_empty
    # Silent by decision rather than by exception: without the check on
    # the parse result, the empty write list is `nil` and the comparison
    # below it raises into a rescue that produces the same silence.
    expect(logger).not_to have_received(:error)
  end

  # `@x ||= ...` and `@x += ...` are assignments. Recognising only plain
  # `=` reports a variable the file visibly assigns two lines up, which is
  # the most obviously wrong report this check could make.
  it "counts `||=` as an assignment" do
    expect(run_server(controller: ASSIGNS_USER, view: "<% @total ||= 1 %><%= @total %>\n")).to be_empty
  end

  # The operator write has to be the *only* assignment to its name, or a
  # plain `=` to the same name covers for it and the fixture passes with
  # the operator form unrecognised.
  it "counts an operator assignment as an assignment" do
    expect(run_server(controller: ASSIGNS_USER, view: "<% @tally += 1 %><%= @tally %>\n")).to be_empty
  end

  it "says nothing when the view's controller cannot be found at all" do
    input = open(VIEW_URI, "<%= @usr %>\n", language_id: "erb") +
            frame(jsonrpc: "2.0", method: "exit", params: nil)
    Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger).run

    expect(diagnostics_for(VIEW_URI).select { |d| d[:code] == "unassigned-ivar" }).to be_empty
  end

  # A view that assigns to an ivar and reads it back is assigning it, and
  # a read of a name the *view itself* introduces is not a mistake.
  it "counts an @ivar the view assigns itself" do
    expect(run_server(controller: ASSIGNS_USER, view: "<% @total = 1 %><%= @total %>\n")).to be_empty
  end

  # A controller file is not a view: it has no action context, and its own
  # `@ivar` reads are ordinary Ruby whose assignments may be anywhere.
  it "says nothing for an @ivar read in a controller file" do
    input = open("file:///app/controllers/users_controller.rb", <<~RUBY) +
      class UsersController
        def show
          @usr
        end
      end
    RUBY
            frame(jsonrpc: "2.0", method: "exit", params: nil)
    Ovallsp::Server.new(input: StringIO.new(input), output: output, logger: logger).run

    found = diagnostics_for("file:///app/controllers/users_controller.rb")
    expect(found.select { |d| d[:code] == "unassigned-ivar" }).to be_empty
    # Not merely absent: absent *because it was not asked*, rather than
    # because the attempt raised and was swallowed.
    expect(logger).not_to have_received(:error)
  end

  # Working out a view context means parsing a path and consulting the
  # index. A Ruby file can never have one, and every publishDiagnostics
  # for every Ruby file would otherwise pay for finding that out.
  it "does not go looking for a view context for a file that is not a view" do
    server = Ovallsp::Server.new(input: StringIO.new(""), output: output, logger: logger)
    document = Ovallsp::TextDocument.new(uri: "file:///app/models/user.rb", text: "class User\nend\n",
                                         version: 1, language_id: "ruby")

    expect(server).not_to receive(:view_action_context)

    server.send(:assigned_ivars_for, document.uri)
  end

  # The one thing `ivar_sources_fully_enumerable?` still decides on its
  # own, and the one no source fixture can reach: a module mixed in by
  # the *running application* rather than by any file in the workspace --
  # a gem's concern included into `ApplicationController` by the gem's
  # own code. The hierarchy index knows it because the Runtime Agent
  # said so; no workspace class body mentions it, so
  # `class_body_is_accounted_for?` sees nothing, and its methods are
  # never walked. Asserted through the predicate directly because
  # standing up an Agent for it is not something this suite can do.
  describe "a mixin known only to the running application" do
    let(:server) do
      Ovallsp::Server.new(input: StringIO.new(""), output: output, logger: logger)
    end
    let(:document) do
      Ovallsp::TextDocument.new(uri: "file:///c.rb", text: "class UsersController\nend\n",
                                version: 1, language_id: "ruby")
    end

    def entry(origin)
      Ovallsp::Semantic::AncestorEntry.new(
        name: "Tenantable", kind: :module, origin: origin, location: nil
      )
    end

    it "is not enumerable when the chain carries an included module" do
      allow(server.instance_variable_get(:@hierarchy_index)).to receive(:ancestors).and_return([entry(:include)])

      expect(server.send(:ivar_sources_fully_enumerable?, "::UsersController",
                         [["::UsersController", document]])).to be(false)
    end

    # And the call site, not only the predicate: removing the line that
    # asks it left every example above green, because each was written
    # for a shape another guard also rejects.
    it "reaches the check, so a view under such a controller is left alone" do
      server = Ovallsp::Server.new(input: StringIO.new(""), output: output, logger: logger)
      allow(server.instance_variable_get(:@hierarchy_index)).to receive(:ancestors).and_return([entry(:include)])
      server.send(:handle_did_open, textDocument: {
                    uri: "file:///app/controllers/users_controller.rb", version: 1, languageId: "ruby",
                    text: "class UsersController\n  def show\n  end\nend\n"
                  })
      server.send(:handle_did_open, textDocument: {
                    uri: VIEW_URI, version: 1, languageId: "erb", text: "<%= @user.name %>\n"
                  })

      expect(diagnostics_for(VIEW_URI).select { |d| d[:code] == "unassigned-ivar" }).to be_empty
    end

    it "is enumerable when the chain carries only a superclass" do
      allow(server.instance_variable_get(:@hierarchy_index)).to receive(:ancestors).and_return([entry(:superclass)])

      expect(server.send(:ivar_sources_fully_enumerable?, "::UsersController",
                         [["::UsersController", document]])).to be(true)
    end
  end
end
