# frozen_string_literal: true

# `024.87`. `Post.where(published: true)` inferred `Relation[Post]` and
# `Post.where(published: true).where(user_id: 1)` inferred nothing. So
# did `.order`, `.limit`, `.includes` and a second scope. `#first` and
# `#to_a` survived because they are modelled; the relation-*returning*
# methods were not.
#
# The cost was not only hover. `Post.published.where(user_id: 1).titel`
# produced no diagnostic in a run where `post.titel` did — the
# undefined-method check switched off at the second link of the most
# common Rails expression there is.
#
# **Probed against real Rails rather than assumed**, which is how the
# rules beside these were established. ActiveRecord 8.1.3.1, in-memory
# sqlite3, `rel = Post.where(title: "x")`:
#
#     where order limit offset includes joins distinct group having
#     preload eager_load references reorder readonly none unscope
#         -> Post::ActiveRecord_Relation   (all sixteen)
#     count -> Integer
#     to_a  -> Array
#
# `select` is deliberately absent: on a Relation it returns a Relation
# without a block and an Array with one, and there is already an
# `ENUMERABLE_LIKE` rule for the block form. Adding a relation rule would
# make the answer depend on which rule matched first.
RSpec.describe "a relation chain" do
  let(:workspace_index) { Ovallsp::WorkspaceIndex.new }
  let(:model_registry) { Ovallsp::Models::ModelRegistry.new }
  let(:signatures) { Ovallsp::Signatures::Environment.new.tap { |e| e.load(workspace_root: nil) } }
  let(:stack) do
    build_analysis_stack(workspace_index: workspace_index, model_registry: model_registry, signatures: signatures)
  end

  before do
    model_registry.replace({ "Post" => { tableName: "posts",
                                         columns: [{ name: "id", type: "integer" }],
                                         associations: [], partial: false } })
    index("class Post < ApplicationRecord\nend\n", "file:///p.rb")
  end

  def index(text, uri)
    document = Ovallsp::TextDocument.new(uri: uri, text: text, version: 1, language_id: "ruby")
    summary = Ovallsp::ParserService.new.summarize(document)
    workspace_index.replace_file(summary)
    stack.hierarchy_index.replace_file(summary)
    document
  end

  def type_of(expression)
    document = index("x = #{expression}\nx\n", "file:///a.rb")
    stack.local_inferencer.infer_at(document, { line: 1, character: 0 }).to_s
  end

  it "stays a relation through a second where" do
    expect(type_of("Post.where(a: 1).where(b: 2)")).to eq("Relation[Post]")
  end

  it "stays a relation through order, limit and offset" do
    expect(type_of("Post.where(a: 1).order(:id)")).to eq("Relation[Post]")
    expect(type_of("Post.all.limit(3)")).to eq("Relation[Post]")
    expect(type_of("Post.all.offset(3)")).to eq("Relation[Post]")
  end

  it "stays a relation through a long chain" do
    expect(type_of("Post.all.where(a: 1).order(:id).limit(3).distinct")).to eq("Relation[Post]")
  end

  # **The diagnostic half is not asserted here, and the reason is worth
  # writing down.** The entry's sharper complaint is that
  # `Post.published.where(user_id: 1).titel` produced no report where
  # `post.titel` did. In this unit fixture the ActiveRecord class-method
  # API is not known to the diagnostic path, so the *first* hop is
  # already reported as ``Post has no method named `where` `` -- the
  # fixture cannot tell the second link from the first, and an example
  # built on it would assert nothing.
  #
  # What is fixed and testable here is the type, which is what the
  # diagnostic consumes: a chain that used to end in `Unknown` now ends
  # in `Relation[Post]`, and a check that declines on `Unknown` no
  # longer has cause to. Confirming the report itself needs the e2e
  # path with a real Agent, which `024.87` called its remaining half.
  # 0.3.0 added it: `G19` in `core/spec/e2e/capabilities_spec.rb`
  # measures the same chain through the real server, and the answer is
  # that silence is correct there -- a relation reaches
  # `ActiveRecord::AttributeMethods`, which answers at call time, so a
  # report would be a wrong answer. The entry closed with it.

  # The distinguishing half. A method that does *not* return a relation
  # must not become one, or "everything on a Relation is a Relation"
  # would pass every example above and be wrong in the place it matters.
  it "does not make a terminal method return a relation" do
    expect(type_of("Post.where(a: 1).first")).to eq("Post | nil")
    expect(type_of("Post.all.to_a")).to eq("Array[Post]")
  end
end
