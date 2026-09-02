# frozen_string_literal: true

# `024.274`. An underscore-prefixed binding was declined *everywhere*,
# because a pattern may bind such a name twice and renaming both ranges
# to a name without the underscore produces a file that does not parse.
#
# That rule is Ruby's, and it is about patterns alone:
#
#   $ ruby -e '
#   ["_a, _a = 1, 2; [_a]",
#    "for _a in [1] do end; _a",
#    "begin; raise; rescue => _e; end; _e",
#    "case [1, 2]; in [_a, _a] then :ok; end",
#    "case [1, 2]; in [zz, zz] then :ok; end"].each do |src|
#     begin
#       eval(src)
#       puts "legal"
#     rescue SyntaxError
#       puts "SyntaxError"
#     rescue StandardError
#       puts "legal"
#     end
#   end
#   '
#   # => legal
#   # => legal
#   # => legal
#   # => legal
#   # => SyntaxError
#   # ruby 3.4.10
#
# So a multiple assignment, a `for` variable and a `rescue => _e` cannot
# produce the illegal pair, and declining them cost documentHighlight and
# Find References an occurrence for no reason.
RSpec.describe "Ovallsp::ParserService and an underscore-prefixed binding" do
  def bindings(text)
    Ovallsp::ParserService.new.summarize(
      Ovallsp::TextDocument.new(uri: "file:///u.rb", text: text, version: 1, language_id: "ruby")
    ).reference_candidates.select { |c| c.kind == :local_variable && c.write }
     .map { |c| [c.name, c.location[:start][:line]] }.sort
  end

  it "records an underscore multiple-assignment target" do
    expect(bindings("def m\n  _a, b = 1, 2\n  [_a, b]\nend\n"))
      .to eq([["_a", 1], ["b", 1]])
  end

  it "records an underscore `rescue` binding" do
    expect(bindings("def m\n  begin\n    nil\n  rescue => _e\n    _e\n  end\nend\n"))
      .to eq([["_e", 3]])
  end

  # **Still declined inside a pattern**, which is the case the rule was
  # written for: both ranges really are the name, and only the *pair* is
  # illegal, so nothing asked at one range can see it.
  it "declines an underscore target inside a pattern" do
    expect(bindings("def m(pair)\n  case pair\n  in [_a, _a]\n    _a\n  end\nend\n"))
      .to eq([["pair", 0]])
  end

  # The control: a name a pattern may not repeat is recorded as before.
  it "still records a non-underscore pattern target" do
    expect(bindings("def m(pair)\n  case pair\n  in [zz, 1]\n    zz\n  end\nend\n"))
      .to eq([["pair", 0], ["zz", 2]])
  end

  # **An `in` clause's body is not a pattern.** The depth was raised
  # around the whole clause, so an ordinary assignment written *inside*
  # the branch was declined as though it were a pattern target -- and a
  # rename from a read then rewrote the reads and left the assignment,
  # which changes what the method returns:
  #
  #   $ ruby -e '
  #   def f(h)
  #     case h
  #     in [z]
  #       _p = 0
  #       _p, _q = 1, 2
  #       _p
  #     end
  #   end
  #   p f([1])
  #   '
  #   # => 1
  #   # ruby 3.4.10
  #
  # CONTROL, in the same example: the underscore target in the *pattern*
  # on the same clause must still be declined, so widening the whole
  # rule would not pass.
  it "records an underscore binding in an `in` clause's body, but not in its pattern" do
    recorded = bindings(
      "def f(h)\n  case h\n  in [_z, _z]\n    _p = 0\n    _p, _q = 1, 2\n    _p\n  end\nend\n"
    )

    expect(recorded).to eq([["_p", 3], ["_p", 4], ["_q", 4], ["h", 0]])
  end
end
