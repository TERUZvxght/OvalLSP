# frozen_string_literal: true

# 024.45: one `analyze` of `net/http.rb` is 2.8 s against a stated 300 ms
# p95, and the profile attributes roughly half of it to constructing and
# hashing `Index::SymbolId`s -- `SymbolId#initialize`, `qualify_owner`,
# and the `String#split`/`#to_s` around them.
#
# Counted rather than inferred, because 024.45's own record says an
# inference from a call count was wrong once already: one `analyze` of
# `net/http.rb` makes **1,961,027** `qualify_owner` calls for **385**
# distinct inputs. Every one of them allocated a new String.
#
# So the memo. These examples pin it by identity, which is the only
# observable difference: `#eql?` was already true before it existed, and
# an example asserting that would pass with the memo reverted.
RSpec.describe Ovallsp::Index::SymbolId do
  describe ".qualify_owner" do
    it "returns the identical object for a repeated name" do
      first = described_class.qualify_owner("Widget")
      expect(described_class.qualify_owner("Widget")).to be(first)
    end

    # **Written first as `be`, and that was a wish rather than a
    # requirement.** The cache is keyed by the argument, so the two
    # spellings of one name are two entries holding two equal Strings.
    # Keying by the normalised name instead would unify them and would
    # have to run `delete_prefix` on every call to find the key -- which
    # is the allocation this memo exists to avoid, paid on the fast path
    # to buy an identity nothing asks for. Two entries for a name, at 385
    # names per file, is the cheaper end of that trade.
    it "gives each spelling its own entry, holding equal strings" do
      qualified = described_class.qualify_owner("::Widget")
      expect(qualified).to eq(described_class.qualify_owner("Widget"))
      expect(qualified).not_to be(described_class.qualify_owner("Widget"))
    end

    # A memo hands the same String to every caller, so a caller that
    # mutated it would corrupt every later answer.
    it "hands back a frozen string" do
      expect(described_class.qualify_owner("Admin::Widget")).to be_frozen
    end

    # The answers themselves, unchanged -- the memo is an optimisation and
    # this is the control that says so.
    it "still answers what it answered before" do
      expect(described_class.qualify_owner("Widget")).to eq("::Widget")
      expect(described_class.qualify_owner("::Widget")).to eq("::Widget")
      expect(described_class.qualify_owner("Admin::Widget")).to eq("::Admin::Widget")
      expect(described_class.qualify_owner(nil)).to be_nil
      expect(described_class.qualify_owner(:Widget)).to eq("::Widget")
    end

    # A caller's String is not the cache's: `Hash#[]=` dups and freezes a
    # String key, so mutating the argument afterwards cannot reach in.
    it "is not aliased to the caller's string" do
      name = +"Widget"
      qualified = described_class.qualify_owner(name)
      name << "Extra"
      expect(qualified).to eq("::Widget")
      expect(described_class.qualify_owner("Widget")).to be(qualified)
    end
  end
end
