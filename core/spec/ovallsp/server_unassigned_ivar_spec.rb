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

  def run_server(controller:, view:)
    input = open("file:///app/controllers/users_controller.rb", controller) +
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
end
