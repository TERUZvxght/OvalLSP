# frozen_string_literal: true

# `024.99`. Completion after a dot offered members that raise if you pick
# them. Measured by 0.2.7's round by asking the running application
# `respond_to?` for every label: `Post.` returned 816 labels of which 91
# were not callable, and a user's own plain-Ruby class returned 121 of
# which **69** were not -- `initialize` among them.
#
# They are Ruby's private methods, and a private method is exactly the
# thing you may not call with a receiver in front:
#
#   $ ruby -e '
#   class Circle; end
#   [-> { Circle.new.puts(1) }, -> { Circle.new.initialize },
#    -> { puts nil }, -> { Circle.new.to_s }].each do |thunk|
#     begin
#       thunk.call
#       puts "ok"
#     rescue NoMethodError => e
#       puts e.message.include?("private method") ? "private method" : "other"
#     end
#   end
#   '
#   # => private method
#   # => private method
#   # =>
#   # => ok
#   # => ok
#   # ruby 3.4.10
#
# (the blank line is `puts nil` doing its job)
#
# RBS carries the same answer -- `accessibility` is `:private` for
# `fork`, `exec`, `abort`, `exit!`, `eval`, `initialize` and `puts` on
# `Object` -- and the enumeration was dropping it.
RSpec.describe "Ovallsp::Semantic::QueryService and an explicit receiver's visibility" do
  def server(source, uri)
    require "stringio"
    require "logger"
    s = Ovallsp::Server.new(input: StringIO.new(""), output: StringIO.new,
                            logger: Logger.new(File::NULL), workspace_root: Dir.pwd)
    s.send(:handle_did_open,
           { textDocument: { uri: uri, text: source, version: 1, languageId: "ruby" } })
    s
  end

  def labels(source, line, character, uri: "file:///vis.rb")
    result = server(source, uri).send(
      :completion_result, { textDocument: { uri: uri }, position: { line: line, character: character } }
    )
    Array(result.is_a?(Hash) ? result[:items] : result).map { |item| item[:label] }
  end

  UNCALLABLE = %w[initialize fork exec abort exit! eval append_features].freeze

  it "offers none of Ruby's private methods after a dot" do
    offered = labels("class Circle\n  def area; end\nend\nCircle.new.\n", 3, 11)

    expect(offered & UNCALLABLE).to be_empty
  end

  # The control, in the same request: the list is not simply empty.
  it "still offers the public members of the same receiver" do
    offered = labels("class Circle\n  def area; end\nend\nCircle.new.\n", 3, 11)

    expect(offered).to include("area", "to_s")
  end

  # **And the receiverless list keeps them**, because that is the one
  # place Ruby lets you call them. Dropping `puts` from here would be
  # this fix overshooting into the case it exists to protect.
  it "still offers a private Kernel method where there is no receiver" do
    expect(labels("def m\n  pu\nend\n", 1, 4)).to include("puts")
  end
end
