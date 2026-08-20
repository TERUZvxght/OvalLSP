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
      hierarchy_index = Ovallsp::Semantic::HierarchyIndex.new(workspace_index: workspace_index)
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

      expect(hierarchy_index.ancestors("::Article", singleton: true).map(&:name))
        .to include("::Taggable::ClassMethods")
    end

    # The spelled-out form must answer identically -- the two spellings of
    # one thing disagreeing is what `024.104` is about.
    it "answers the same for the module form" do
      block = chain(block_form, "class Article\n  include Taggable\nend\n")
      spelled = chain(module_form, "class Article\n  include Taggable\nend\n")

      expect(block.ancestors("::Article", singleton: true).map(&:name))
        .to eq(spelled.ancestors("::Article", singleton: true).map(&:name))
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
    # The marker is required now. The pre-Rails-4 spelling --
    # `def self.included(base); base.extend(ClassMethods); end` -- is not
    # missed by this: it is an ordinary `extend`, which this index has
    # always followed, and 0.2.10's `drive` round verified that path
    # separately.
    it "adds nothing for a module that nests a ClassMethods without being a concern" do
      hierarchy_index = chain(
        "module Mixed\n  module ClassMethods\n    def spelled_out; end\n  end\n  def helper; end\nend\n",
        "class UsesMixed\n  include Mixed\nend\n"
      )

      expect(hierarchy_index.ancestors("::UsesMixed", singleton: true).map(&:name))
        .not_to include("::Mixed::ClassMethods")
    end

    # The control: an ordinary module with no `ClassMethods` adds nothing
    # to the class-level chain. Without this, an implementation that
    # appended a `::ClassMethods` name unconditionally would pass both
    # examples above.
    it "adds nothing for a module that has no ClassMethods" do
      hierarchy_index = chain("module Plain\n  def helper; end\nend\n",
                              "class Article\n  include Plain\nend\n")

      expect(hierarchy_index.ancestors("::Article", singleton: true).map(&:name))
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
