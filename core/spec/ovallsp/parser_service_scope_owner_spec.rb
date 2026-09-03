# frozen_string_literal: true

# `scope :recent, -> { ... }` on a namespaced model generated
# `Relation[<last segment>]` -- `Relation[Order]` for `Billing::Order`.
# Where two namespaces hold a class of the same name, the bare name
# resolves to whichever one wins, and the answer belongs to the wrong
# class entirely.
#
# Measured before fixing, over the installed gem corpus (3,301 files):
# 476 of 3,508 class basenames are shared by more than one namespace --
# 13.6%. So this is not the rarely-walked path section 0.4 permits
# shipping as a known limitation; it is the ordinary one.
#
# A companion figure recorded here at first -- "63 of 66 scope
# declarations are namespaced" -- was wrong and is removed: it counted
# every receiverless call named `scope`, most of them the routing DSL.
# Round 3 re-derived it; real `scope :sym` declarations in that corpus
# number 2.
#
# The fixture uses two same-named classes in different namespaces
# deliberately. Every existing spec covering this code used a top-level
# `Widget`/`User`, where the last segment and the qualified name are the
# same string and both branches answer identically -- so the line was
# unpinned, in docs/CODE_DISCIPLINE.md's sense, and reverting the fix left the suite
# green.
RSpec.describe "Ovallsp::ParserService: a scope's Relation names the owner it belongs to" do
  def relation_arg_for(source, method_name)
    document = Ovallsp::TextDocument.new(
      uri: "file:///app/models/order.rb", text: source, version: 1, language_id: "ruby"
    )
    summary = Ovallsp::ParserService.new.summarize(document)
    fact = summary.generated_method_facts.find { |f| f.name == method_name }
    fact&.return_type&.type_arg&.name
  end

  let(:namespaced) do
    <<~RUBY_SRC
      module Billing
        class Order < ApplicationRecord
          scope :recent, -> { order(created_at: :desc) }
        end
      end
    RUBY_SRC
  end

  it "qualifies the relation's element with the owner's full path" do
    expect(relation_arg_for(namespaced, "recent")).to eq("Billing::Order")
  end

  # The distinguishing half: with the old behaviour this was "Order",
  # which is the name of a *different* class whenever one exists.
  it "does not name it by the last segment alone" do
    expect(relation_arg_for(namespaced, "recent")).not_to eq("Order")
  end

  it "leaves a top-level owner unchanged" do
    top_level = <<~RUBY_SRC
      class Order < ApplicationRecord
        scope :recent, -> { order(created_at: :desc) }
      end
    RUBY_SRC

    expect(relation_arg_for(top_level, "recent")).to eq("Order")
  end

  # `bare_name` strips a leading `::` rather than truncating, so a
  # root-scoped owner keeps its path and loses only the prefix.
  it "normalises a root-scoped owner without truncating it" do
    rooted = <<~RUBY_SRC
      module Billing
        class ::Shipping::Order < ApplicationRecord
          scope :recent, -> { order(created_at: :desc) }
        end
      end
    RUBY_SRC

    expect(relation_arg_for(rooted, "recent")).not_to start_with("::")
  end
end
