# frozen_string_literal: true

# Every script in this directory reads this tree, and this tree is
# substantially non-ASCII: the Japanese documents, the Japanese halves of
# `KNOWN_LIMITATIONS`, `SUPPORT_MATRIX` and `CONTRIBUTING`, and the
# Japanese failure messages the suite prints.
#
# Ruby hands back a String in `Encoding.default_external`, which is
# whatever the invoking shell's locale says. Under `LC_ALL=C`, or a cron
# job, or a CI step with no locale set, that is **US-ASCII** — and then
# the first `String#[]`, `#scan` or `#include?` against a byte above 127
# raises `invalid byte sequence in US-ASCII`.
#
# It is the shape that hurts: the script does not read the file wrongly,
# it *crashes*, and it crashes on exactly the input a check exists to
# report. `scripts/preflight.rb`'s first version died with this while
# printing a suite failure whose message contained Japanese — the gate
# built to catch a failure, killed by one.
#
# Found four separate times in this repository before it was fixed here
# rather than at each call site: `generate_sbom.rb` (Task 023.8, running
# the release gate under a locale-less shell), `preflight.rb`,
# `documented_counts.rb`, and a hand-run probe. Each fix was correct and
# local, and the fifth call site would have been written the same way.
#
#   require_relative "utf8"
#
# One line, at the top, before anything reads or shells out.
# `core/spec/meta/script_encoding_spec.rb` requires it of every script
# here that reads a file or runs a subprocess.
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = nil
