# frozen_string_literal: true

# `024.104`. `ActiveSupport::Concern`'s `class_methods do ... end`
# declares methods on the *class*. Ground truth from the real gem:
#
#   $ ruby -e '
#   gem "activesupport"; require "active_support"; require "active_support/concern"
#   module Taggable
#     extend ActiveSupport::Concern
#     class_methods do
#       def cm_public; :cm; end
#     end
#   end
#   class Article; include Taggable; end
#   p Article.respond_to?(:cm_public)                  # => true
#   p Article.new.respond_to?(:cm_public)              # => false
#   p Taggable.const_defined?(:ClassMethods)           # => true
#   p Taggable::ClassMethods.instance_methods(false)   # => [:cm_public]
#   '
#   # ruby 3.4.10, activesupport 8.1.3.1
#
# The block was recorded against the concern's own instance side, so
# `include Taggable` put `cm_public` on every instance: completion offered
# it after `Article.new.`, hover and go-to-definition answered, and the
# undefined-method check was silent -- four features agreeing and all four
# wrong. The macro is literally sugar for the `module ClassMethods` form,
# which this parser already handles correctly, so it is recorded as that.
RSpec.describe "Ovallsp::ParserService and ActiveSupport::Concern's class_methods block" do
  def summarize(text)
    Ovallsp::ParserService.new.summarize(
      Ovallsp::TextDocument.new(uri: "file:///taggable.rb", text: text, version: 1, language_id: "ruby")
    )
  end

  def methods_by_owner(summary)
    summary.declarations
           .select { |d| d.symbol_id.kind == :instance_method }
           .group_by { |d| d.symbol_id.owner }
           .transform_values { |ds| ds.map { |d| d.symbol_id.name }.sort }
  end

  let(:block_form) do
    <<~RUBY
      module Taggable
        extend ActiveSupport::Concern

        class_methods do
          def cm_public; end
        end

        def instance_one; end
      end
    RUBY
  end

  # The control, and the reason this is a defect rather than a missing
  # feature: the spelled-out form is already right, so the two spellings
  # of one thing disagreed.
  let(:module_form) do
    <<~RUBY
      module Taggable
        extend ActiveSupport::Concern

        module ClassMethods
          def cm_public; end
        end

        def instance_one; end
      end
    RUBY
  end

  # The block form marked the concern's *instance* surface open, because
  # `#record_open_surface` ran before the early return that reads it. So
  # every class including the concern lost instance-side checking
  # entirely -- in a Rails application, most models. The spelled-out form
  # reported `Post.new.total_garbage` and the block form reported nothing.
  it "does not leave the concern's instance surface open, since the block is read" do
    expect(summarize(block_form).open_surface_owners).to eq(summarize(module_form).open_surface_owners)
    expect(summarize(block_form).open_surface_owners).to be_empty
  end

  it "records the block's methods where the module form records them" do
    expect(methods_by_owner(summarize(block_form))).to eq(methods_by_owner(summarize(module_form)))
  end

  it "does not leave them on the concern's own instance side" do
    owners = methods_by_owner(summarize(block_form))

    expect(owners["::Taggable"]).to eq(["instance_one"])
    expect(owners["::Taggable::ClassMethods"]).to eq(["cm_public"])
  end

  # The half `024.104` was marked fixed without: recording the methods in
  # `ClassMethods` puts them nowhere unless including the concern also
  # extends it, which is exactly what `ActiveSupport::Concern` does.
  #
  #   $ ruby -e '
  #   gem "activesupport"; require "active_support"; require "active_support/concern"
  #   module Taggable
  #     extend ActiveSupport::Concern
  #     class_methods do
  #       def cm_public; end
  #     end
  #   end
  #   class Article; include Taggable; end
  #   p [Article.respond_to?(:cm_public), Article.new.respond_to?(:cm_public)]
  #   '
  #   # => [true, false]
  #   # ruby 3.4.10, activesupport 8.1.3.1
  describe "a class including the concern" do
    def chain(*sources)
      workspace_index = Ovallsp::WorkspaceIndex.new
      stack = build_analysis_stack(workspace_index: workspace_index)
      hierarchy_index = stack.hierarchy_index
      sources.each_with_index do |text, i|
        summary = Ovallsp::ParserService.new.summarize(
          Ovallsp::TextDocument.new(uri: "file:///f#{i}.rb", text: text, version: 1, language_id: "ruby")
        )
        workspace_index.replace_file(summary)
        hierarchy_index.replace_file(summary)
      end
      hierarchy_index
    end

    it "reaches the concern's ClassMethods on its class-level chain" do
      hierarchy_index = chain(block_form, "class Article\n  include Taggable\nend\n")

      expect(hierarchy_index.ancestors("::Article", singleton: true).map(&:name_or_nil))
        .to include("::Taggable::ClassMethods")
    end

    # The spelled-out form must answer identically -- the two spellings of
    # one thing disagreeing is what `024.104` is about.
    it "answers the same for the module form" do
      block = chain(block_form, "class Article\n  include Taggable\nend\n")
      spelled = chain(module_form, "class Article\n  include Taggable\nend\n")

      expect(block.ancestors("::Article", singleton: true).map(&:name_or_nil))
        .to eq(spelled.ancestors("::Article", singleton: true).map(&:name_or_nil))
    end

    # **The pre-`ActiveSupport::Concern` spelling.** 0.2.11 narrowed the
    # rule to the `extend ActiveSupport::Concern` line on the stated
    # ground that this shape "is an ordinary `extend` this index has
    # always followed" -- which is false: the receiver is a method
    # *parameter*, and there is no `extend` in a class body to follow.
    # For one round it turned a generation of real concerns into false
    # reports. Verified against Ruby 3.4.10:
    #
    #   $ ruby -e '
    #   module OldStyle
    #     def self.included(base); base.extend(ClassMethods); end
    #     module ClassMethods; def old_cm = :old_cm; end
    #   end
    #   class UOld; include OldStyle; end
    #   p UOld.old_cm
    #   '
    #   # => :old_cm
    it "recognises the self.included hook as a concern marker" do
      hierarchy_index = chain(
        "module OldStyle\n  def self.included(base)\n    base.extend(ClassMethods)\n  end\n" \
        "  module ClassMethods\n    def old_cm; end\n  end\nend\n",
        "class UOld\n  include OldStyle\nend\n"
      )

      expect(hierarchy_index.ancestors("::UOld", singleton: true).map(&:name_or_nil))
        .to include("::OldStyle::ClassMethods")
    end

    # A concern that includes a concern passes the inner one's class
    # methods on -- `append_features` runs the inner module's own hook --
    # and reading the include list one level deep lost them. This is the
    # commonest way a large Rails application composes concerns.
    it "follows a concern that includes another concern" do
      hierarchy_index = chain(
        "module Inner\n  extend ActiveSupport::Concern\n  module ClassMethods\n" \
        "    def inner_cm; end\n  end\nend\n",
        "module OuterC\n  extend ActiveSupport::Concern\n  include Inner\n  module ClassMethods\n" \
        "    def outer_cm; end\n  end\nend\n",
        "class UTrans\n  include OuterC\nend\n"
      )
      names = hierarchy_index.ancestors("::UTrans", singleton: true).map(&:name_or_nil)

      expect(names).to include("::OuterC::ClassMethods", "::Inner::ClassMethods")
    end

    # The control for the transitive rule: a *plain* module that includes
    # a concern does not pass its class methods on, and Ruby raises.
    it "does not follow a plain module that includes a concern" do
      hierarchy_index = chain(
        "module Inner\n  extend ActiveSupport::Concern\n  module ClassMethods\n" \
        "    def inner_cm; end\n  end\nend\n",
        "module UWrapMod\n  include Inner\nend\n",
        "class UWrap\n  include UWrapMod\nend\n"
      )

      expect(hierarchy_index.ancestors("::UWrap", singleton: true).map(&:name_or_nil))
        .not_to include("::Inner::ClassMethods")
    end

    # **Rails writes the marker bare.** `module ActiveSupport` … `extend
    # Concern` is how `callbacks.rb`, `rescuable.rb` and
    # `actionable_error.rb` spell it, and matching the written text
    # missed every one -- fourteen of the fifteen false reports a
    # `reproduce` round measured this release adding, on
    # `ActiveSupport::ExecutionWrapper.define_callbacks` and its
    # neighbours.
    it "recognises the marker written bare from inside ActiveSupport" do
      hierarchy_index = chain(
        "module ActiveSupport\n  module Concern; end\nend\n",
        "module ActiveSupport\n  module Bare\n    extend Concern\n    module ClassMethods\n" \
        "      def bare_cm; end\n    end\n  end\nend\n",
        "class UsesBare\n  include ActiveSupport::Bare\nend\n"
      )

      expect(hierarchy_index.ancestors("::UsesBare", singleton: true).map(&:name_or_nil))
        .to include("::ActiveSupport::Bare::ClassMethods")
    end

    # `024.115`. Keying on "a `ClassMethods` declaration exists" made
    # completion offer a name that raises for any module that merely
    # happens to nest one:
    #
    #   $ ruby -e '
    #   module Mixed
    #     module ClassMethods; def spelled_out; end; end
    #     def helper; end
    #   end
    #   class UsesMixed; include Mixed; end
    #   p (UsesMixed.spelled_out rescue $!.class)
    #   '
    #   # => NoMethodError
    #   # ruby 3.4.10
    #
    # A marker is required now, and there are two of them: this line, and
    # the `self.included` hook the example above pins. 0.2.11 first
    # narrowed to this line alone, on the stated ground that the hook "is
    # an ordinary `extend` this index has always followed" -- which is
    # false, and was written from another round's summary rather than
    # checked.
    it "adds nothing for a module that nests a ClassMethods without being a concern" do
      hierarchy_index = chain(
        "module Mixed\n  module ClassMethods\n    def spelled_out; end\n  end\n  def helper; end\nend\n",
        "class UsesMixed\n  include Mixed\nend\n"
      )

      expect(hierarchy_index.ancestors("::UsesMixed", singleton: true).map(&:name_or_nil))
        .not_to include("::Mixed::ClassMethods")
    end

    # The control: an ordinary module with no `ClassMethods` adds nothing
    # to the class-level chain. Without this, an implementation that
    # appended a `::ClassMethods` name unconditionally would pass both
    # examples above.
    it "adds nothing for a module that has no ClassMethods" do
      hierarchy_index = chain("module Plain\n  def helper; end\nend\n",
                              "class Article\n  include Plain\nend\n")

      expect(hierarchy_index.ancestors("::Article", singleton: true).map(&:name_or_nil))
        .to eq(["::Article", "Class", "Module", "Object", "Kernel", "BasicObject"])
    end
  end

  # A `class_methods` block is the only one treated this way. An ordinary
  # iterator block in a module body still records against the module, and
  # an example that did not check this would pass if every block were
  # namespaced.
  it "leaves an ordinary block in a module body alone" do
    owners = methods_by_owner(summarize(<<~RUBY))
      module Taggable
        [1].each do
          def from_a_plain_block; end
        end
      end
    RUBY

    expect(owners["::Taggable"]).to eq(["from_a_plain_block"])
    expect(owners["::Taggable::ClassMethods"]).to be_nil
  end
end
