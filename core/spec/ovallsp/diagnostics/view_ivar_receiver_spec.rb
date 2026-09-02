# frozen_string_literal: true

# **What 0.3.0 ships for an `@ivar` receiver, in a plain class and in a
# template, neither of which any example held.**
#
# 0.3.0's H8 made an instance variable's type available to the
# undefined-method check in ordinary Ruby: `@article.no_such_method` is
# reported where the ivar was assigned in another method of the same
# class. Mutating that away left **1,156 examples green** across
# `diagnostics/`, `semantic/`, `server_views`, `server_unassigned_ivar`
# and every other spec file naming `unknown-method`. A capability the
# release counts, with nothing failing when it goes, is the defect
# `CLAUDE.md` names in its own right: correct code with no test is one
# refactor away from incorrect code with no test.
#
# The template half is the same value not arriving. `Views::ControllerIvars`
# computes `{"@article" => Nominal("Post")}` for a view and `Server` hands
# it to hover, completion, explainType and go-to-definition -- but the two
# diagnostics call sites build their context with `assigned_ivars:` only,
# a *name* set, and `Diagnostics::SemanticContext` has no field for ivar
# types. The seam is `Semantic::ReceiverResolution.receiver_type_for`,
# which calls `infer_at` with no `initial_env:`.
#
# **This file pins the behaviour; it does not argue that the silence is
# right.** Two review agents drove it and disagreed about the
# disposition. Seeding the view's ivar types into diagnostics produces a
# demonstrably wrong report where a second controller renders the same
# template -- and the blindness that causes it is *already* user-visible
# through hover, completion and a published `unassigned-ivar`, so the
# silence here is not the engine being careful. `024.18` already owns that shape --
# "a view rendered by *another* controller's action" -- and its stated
# blocker, `024.R7`, shipped in 0.3.0. What this file guarantees is that
# whichever way it is settled, it is settled deliberately: today the
# template is silent and the plain class is not, and changing either
# fails an example.
RSpec.describe "an @ivar receiver, in a class and in a template" do
  let(:workspace) { Ovallsp::WorkspaceIndex.new }
  let(:stack) do
    Ovallsp::AnalysisStack.build(signatures: AnalysisStackHelper.shared_signatures, workspace_index: workspace)
  end

  def index(uri, text, language_id: "ruby")
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: language_id)
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace.replace_file(summary)
    stack.hierarchy_index.replace_file(summary)
    document
  end

  def messages(document)
    context = stack.semantic_context(route_registry: Ovallsp::Routes::RouteRegistry.new, generation: 1)
    Ovallsp::Diagnostics::Engine.new.analyze(document: document, semantic_context: context, mode: :standard)
                                .map(&:message)
  end

  before do
    index("file:///app/models/post.rb", "class Post\n  def title; \"t\"; end\nend\n")
    index("file:///app/controllers/articles_controller.rb", <<~RUBY)
      class ArticlesController
        def show
          @article = Post.new
        end
      end
    RUBY
  end

  # The half 0.3.0 shipped, and the half `024.294` said was missing until
  # this release drove it. The ivar is written in `#show` and read in
  # `#other`, so the answer comes from the sibling-method environment
  # rather than from the line above.
  it "reports a typo on an @ivar receiver in a plain class" do
    document = index("file:///app/controllers/articles_controller.rb", <<~RUBY)
      class ArticlesController
        def show
          @article = Post.new
        end

        def other
          @article.no_such_method_zz
        end
      end
    RUBY

    expect(messages(document)).to include(/Post has no method named `no_such_method_zz`/)
  end

  # The control for the example above: with the assignment gone the ivar
  # has no type, and the report goes with it. Without this, the example
  # would pass just as well if the engine reported every unknown name on
  # every receiver.
  it "says nothing about the same call when nothing assigns the ivar" do
    document = index("file:///app/controllers/widgets_controller.rb", <<~RUBY)
      class WidgetsController
        def other
          @article.no_such_method_zz
        end
      end
    RUBY

    expect(messages(document)).not_to include(/no_such_method_zz/)
  end

  describe "in an ERB template" do
    let(:template) do
      index("file:///app/views/articles/show.html.erb",
            "<%= @article.no_such_method_zz %>\n<%= Post.no_such_class_method_yy %>\n",
            language_id: "erb")
    end

    # The behaviour as shipped. It is unpinned in every other spec file:
    # wiring the view's ivar environment into diagnostics left 380
    # examples green, so the next person to notice `view_initial_env` does
    # not reach the engine can wire it and ship a wrong report with a
    # clean suite. See `024.18` before changing this.
    it "says nothing about an @ivar receiver" do
      expect(messages(template)).not_to include(/no_such_method_zz/)
    end

    # **The load-bearing control.** Without it the example above passes
    # equally well if ERB diagnostics were switched off wholesale, and
    # this file would assert nothing at all -- the shape `CLAUDE.md`'s
    # "an assertion that cannot fail is not a test" is about.
    it "still reports a typo on a constant receiver in the same template" do
      expect(messages(template)).to include(/Post has no method named `no_such_class_method_yy`/)
    end
  end
end
