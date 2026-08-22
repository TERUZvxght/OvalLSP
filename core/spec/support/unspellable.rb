# frozen_string_literal: true

# Build a path, name or marker that this repository's own checks cannot
# read as a real one.
#
# `024.126`. Every check here scans tracked content, and a spec is
# tracked content — so an example that spells a path, a register number
# or a scanner's needle the way a real one is spelled becomes a finding
# about the spec that tests the checker. It happened **seven times during
# 0.2.14 alone**, in seven different files, and every one took the same
# repair: assemble the string so no contiguous literal exists.
#
# The entry's rule is to make the example unspellable rather than exempt
# the file, because exempting stops checking a file that carries real
# citations. That rule held every time. What kept failing was *rembering
# to apply it*, which is not a rule problem — so it stops being something
# to remember:
#
#     unspellable("docs/design/tasks", "999-never-existed.md")
#     unspellable_number(999)
#
# Both return the string at runtime while leaving nothing in the source
# for another check to match.
#
# **This comment cannot show what the second one returns.** Writing the
# result out made `measured_claims_spec`'s pointer guard report a
# dangling register citation — in the file whose subject is exactly that
# — which was the eighth occurrence of `024.126` and the first inside its
# own countermeasure. A prose example is the residue the helper cannot
# reach: a call can be assembled, an illustration has to be legible.
# Describe the result instead of spelling it.
module Unspellable
  # Joins with "/" — the parts are what keeps it out of a scanner's reach,
  # so pass at least two.
  def unspellable(*parts)
    raise ArgumentError, "pass at least two parts, or the literal survives in the source" if parts.length < 2

    parts.join("/")
  end

  # A register number that `measured_claims_spec`'s pointer guard will
  # not read as a citation of a real entry.
  def unspellable_number(tail)
    ["024", tail.to_s].join(".")
  end
end

RSpec.configure { |config| config.include(Unspellable) }
