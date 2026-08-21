# frozen_string_literal: true

# `024.32`. `def Foo.bar` defines a *singleton* method on `Foo`, and the
# parser recorded an *instance* method -- so both answers inverted: the
# call Ruby runs was reported, and the call Ruby raises on was accepted.
#
#   $ ruby -e '
#   class Foo; end
#   def Foo.bar; end
#   p [Foo.singleton_methods(false), Foo.instance_methods(false)]
#   p (Foo.new.bar rescue $!.class)
#   '
#   # => [[:bar], []]
#   # => NoMethodError
#   # ruby 3.4.10
#
# And the owner was wrong as well as the kind: `def Fetcher.start` written
# *inside* `class Fetcher` was recorded under `::Fetcher::Fetcher`, a
# class that does not exist. Ruby's constant lookup finds the enclosing
# `Fetcher`, because `Fetcher::Fetcher` is not declared.
RSpec.describe "Ovallsp::ParserService and `def Const.name`" do
  def declarations(text)
    Ovallsp::ParserService.new
      .summarize(Ovallsp::TextDocument.new(uri: "file:///a.rb", text: text, version: 1, language_id: "ruby"))
      .declarations.reject { |d| d.symbol_id.kind == :class || d.symbol_id.kind == :module }
      .map { |d| [d.symbol_id.kind, d.symbol_id.owner, d.symbol_id.name] }
  end

  it "records a singleton method on the named constant" do
    expect(declarations("class Foo\nend\ndef Foo.bar; end\n"))
      .to eq([[:singleton_method, "::Foo", "bar"]])
  end

  # The half round 22 added: `def Fetcher.start` inside `class Fetcher`
  # is the enclosing `Fetcher`, not a nested one that does not exist.
  it "resolves the receiver against the nesting, as Ruby does" do
    expect(declarations("class Fetcher\n  def Fetcher.start; end\nend\n"))
      .to eq([[:singleton_method, "::Fetcher", "start"]])
  end

  # The control, and what an implementation that simply qualified nothing
  # would break: a genuinely nested constant is still nested.
  it "keeps a nested receiver nested when the nesting declares it" do
    expect(declarations("module App\n  class Config\n  end\n  def Config.load; end\nend\n"))
      .to eq([[:singleton_method, "::App::Config", "load"]])
  end

  # And the other control: `def self.x` and a bare `def` are untouched.
  it "leaves def self.x and a bare def alone" do
    expect(declarations("class Foo\n  def self.a; end\n  def b; end\nend\n"))
      .to eq([[:singleton_method, "::Foo", "a"], [:instance_method, "::Foo", "b"]])
  end
end
