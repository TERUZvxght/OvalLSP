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

  it "records the block's methods where the module form records them" do
    expect(methods_by_owner(summarize(block_form))).to eq(methods_by_owner(summarize(module_form)))
  end

  it "does not leave them on the concern's own instance side" do
    owners = methods_by_owner(summarize(block_form))

    expect(owners["::Taggable"]).to eq(["instance_one"])
    expect(owners["::Taggable::ClassMethods"]).to eq(["cm_public"])
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
