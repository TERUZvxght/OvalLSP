# frozen_string_literal: true

require "stringio"
require "logger"

# **An `@ivar` written in the class body belongs to the class object, not
# to an instance**, exactly as one written in `def self.x` does. Ruby:
#
#   $ ruby -e '
#   class Widget
#     @class_body_ivar = 1
#     def self.build; @singleton_ivar = 2; end
#     def inst; @instance_ivar = 3; end
#   end
#   Widget.build
#   p Widget.instance_variables
#   p Widget.new.tap(&:inst).instance_variables
#   '
#   # => [:@class_body_ivar, :@singleton_ivar]
#   # => [:@instance_ivar]
#   # ruby 3.4.10
#
# 0.3.0 excluded the `def self.x` side from the instance-side completion
# list and stopped there. The class body is the other half of the same
# split, and it was still offered: a name picked from that list reads
# `nil` on an instance.
#
# `ClassBodyIvarWrites` walks the class body precisely so a
# `define_method` block's writes are seen, which is why a write sitting
# directly in the body reaches it too.
RSpec.describe "Ovallsp::Server and which side a class-body `@ivar` belongs to" do
  let(:source) do
    <<~RUBY
      class Widget
        @class_body_ivar = 1

        def self.build
          @singleton_ivar = 2
        end

        def inst
          @instance_ivar = 3
        end

        def here
          @
        end
      end
    RUBY
  end

  def offered_at(line, character)
    server = Ovallsp::Server.new(input: StringIO.new(""), output: StringIO.new,
                                 logger: Logger.new(File::NULL), workspace_root: Dir.pwd)
    server.send(:handle_did_open,
                { textDocument: { uri: "file:///w.rb", text: source, version: 1, languageId: "ruby" } })
    result = server.send(:completion_result,
                         { textDocument: { uri: "file:///w.rb" }, position: { line: line, character: character } })
    Array(result.is_a?(Hash) ? result[:items] : result).map { |i| i[:label] }.select { |l| l.start_with?("@") }
  end

  it "does not offer a class-body ivar inside an instance method" do
    expect(offered_at(12, 5)).not_to include("@class_body_ivar")
  end

  # **The control, in the same fixture.** Without it this passes if the
  # list is simply empty, which is what a fix that switched the feature
  # off would produce -- and C15 is a capability this release ships.
  it "still offers the instance side's own" do
    expect(offered_at(12, 5)).to include("@instance_ivar")
  end

  # The half 0.3.0 already fixed, kept so the two cannot drift apart.
  it "still does not offer a `def self.` ivar there" do
    expect(offered_at(12, 5)).not_to include("@singleton_ivar")
  end
end
