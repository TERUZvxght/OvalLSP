# frozen_string_literal: true

# Guards the rule docs/EXTENSION_CAPABILITIES.md states about itself: a
# capability with no E2E row is not a capability.
#
# That rule is the whole reason the document is worth reading. Without
# something enforcing it, a row can be added -- or quietly marked PASS --
# with nothing behind it, which is precisely the failure the document was
# written in response to: several releases claiming capabilities that
# nobody had checked from the outside.
#
# Not tagged :e2e: it reads two files and needs no Rails, so it runs
# everywhere the suite runs, including where the capability suite itself
# has to skip.
require_relative "../../../scripts/release"

RSpec.describe "capability document coverage" do
  CAPABILITY_DOC = File.expand_path("../../../docs/EXTENSION_CAPABILITIES.md", __dir__)
  CAPABILITY_DOC_JA = File.expand_path("../../../docs/EXTENSION_CAPABILITIES.ja.md", __dir__)
  CAPABILITY_SPEC = File.expand_path("capabilities_spec.rb", __dir__)

  # Table rows look like `| C5 | ... |`; example names carry the id they
  # verify, either alone ("C5: ...") or paired ("B1/B2: ...").
  #
  # **The letters are matched by shape, not by a list.** This read
  # `[BHCDGSTW]` until 0.3.0, which is the same defect as the one
  # described next and hidden the same way: a capability group under a
  # new letter would have been invisible to *both* directions of this
  # check, so a row with no example and an example with no row would
  # both have passed. Found while adding one, not by a reviewer.
  #
  # `\d+`, not `\d`: with a single digit every id from G10 up matched as
  # "G1", so both directions of the check silently passed for them --
  # G10, G11 and G12 were documented and verified without this guard ever
  # comparing them, which is the exact failure it exists to prevent.
  # Read with an explicit encoding, never the locale's: both files carry
  # non-ASCII (the Japanese link, `…`), and under a C/POSIX locale
  # `File.read` hands back US-ASCII and every scan raises. The same
  # locale-dependent read has already broken this project once.
  def read_utf8(path) = File.read(path, encoding: "UTF-8")

  # Through `Release.capability_rows`, which reads the id and the status
  # from one pattern. This file had two scans of the same table and
  # `release.rb`'s patch rule would have been a third -- the arrangement
  # `024.216` counted six of, each reader the only reader of its own
  # result. The two questions are different; the grammar is one.
  let(:rows) { Release.capability_rows(read_utf8(CAPABILITY_DOC)) }
  let(:documented) { rows.keys }
  let(:verified) do
    read_utf8(CAPABILITY_SPEC).scan(/it "([A-Z]+\d+)(?:\/([A-Z]+\d+))?:/).flatten.compact
  end

  it "verifies every capability the document lists" do
    expect(documented - verified).to be_empty,
                                     "documented with no E2E example: #{(documented - verified).join(', ')}"
  end

  it "documents every capability the suite verifies" do
    expect(verified - documented).to be_empty,
                                     "verified but not documented: #{(verified - documented).join(', ')}"
  end

  it "lists no capability whose status is neither PASS nor an explicit gap" do
    expect(rows.values.uniq).to all(match(/\A(PASS|NOT YET)\z/))
  end

  # The reader has to have read something: an empty table satisfies every
  # example above, and a pattern that stopped matching looks exactly like
  # a document with nothing in it (`024.148`).
  it "read the table it is asking about" do
    expect(rows.length).to be > 20
  end

  # The Japanese pair is a translation, not a second source of truth: it
  # must list exactly the same capabilities. A row added to one and not
  # the other is how a translated document quietly starts describing a
  # different product.
  it "lists the same capabilities in the Japanese pair" do
    # By shape, like the two above. This was a third copy of the
    # letter list and it was missed when they were widened -- which is
    # the list-somebody-remembered defect appearing a third time in the
    # file that was being fixed for it.
    japanese = read_utf8(CAPABILITY_DOC_JA).scan(/^\| ([A-Z]+\d+) \|/).flatten

    expect(japanese).to eq(documented)
  end
end
