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
RSpec.describe "capability document coverage" do
  CAPABILITY_DOC = File.expand_path("../../../docs/EXTENSION_CAPABILITIES.md", __dir__)
  CAPABILITY_DOC_JA = File.expand_path("../../../docs/EXTENSION_CAPABILITIES.ja.md", __dir__)
  CAPABILITY_SPEC = File.expand_path("capabilities_spec.rb", __dir__)

  # Table rows look like `| C5 | ... |`; example names carry the id they
  # verify, either alone ("C5: ...") or paired ("B1/B2: ...").
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

  let(:documented) { read_utf8(CAPABILITY_DOC).scan(/^\| ([BHCDGSW]\d+) \|/).flatten }
  let(:verified) do
    read_utf8(CAPABILITY_SPEC).scan(/it "([BHCDGSW]\d+)(?:\/([BHCDGSW]\d+))?:/).flatten.compact
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
    statuses = read_utf8(CAPABILITY_DOC).scan(/^\| [BHCDGSW]\d+ \|[^|]*\|[^|]*\| ([^|]+) \|/).flatten.map(&:strip)

    expect(statuses.uniq).to all(match(/\A(PASS|NOT YET)\z/))
  end

  # The Japanese pair is a translation, not a second source of truth: it
  # must list exactly the same capabilities. A row added to one and not
  # the other is how a translated document quietly starts describing a
  # different product.
  it "lists the same capabilities in the Japanese pair" do
    japanese = read_utf8(CAPABILITY_DOC_JA).scan(/^\| ([BHCDGSW]\d+) \|/).flatten

    expect(japanese).to eq(documented)
  end
end
