# frozen_string_literal: true

# Two decisions in `WorkspaceIndex` are about cost, not about answers, so
# no behavioural spec can hold them: reversing either leaves every one of
# this suite's examples green while multiplying the work a keystroke does.
# Both are justified by measurements recorded next to the code, and both
# are the kind of line a later reader tidies -- a `select` after a `sort`
# reads no worse than before it, and `sort_by { }.first(n)` is the more
# familiar idiom.
#
# Asserting on source text is how this repository pins a decision it
# cannot execute a test against (`spec/meta/ci_skip_guard_spec.rb`,
# `vscode/src/test/unit/versionPairing.test.ts`). The assertions below are
# deliberately about *which method is called*, not about formatting.
RSpec.describe "WorkspaceIndex's cost decisions" do
  let(:source) { File.read(File.expand_path("../../lib/ovallsp/workspace_index.rb", __dir__), encoding: "UTF-8") }

  def body_of(method)
    source[/    def #{Regexp.escape(method)}\b.*?\n    end/m] or
      raise "no method #{method} in workspace_index.rb"
  end

  # A bucket is keyed on the downcased *simple* name, so it mixes kinds: a
  # workspace where 1,200 service objects each define `call` puts 1,200
  # method symbols in the bucket `resolve_type_name("Call")` reads.
  # Sorting before filtering measured 3.7ms per call against 51us, on a
  # path `Diagnostics::Engine` runs per constant candidate.
  it "filters a simple-name bucket before sorting it, not after" do
    body = body_of("ordered_symbol_ids")

    expect(body.index(".select(&matching)")).to be < body.index(".sort_by")
  end

  # `workspace/symbol` truncates, and the picker opens with an empty
  # query, so every declaration in the workspace is a match. Sorting all
  # of them on the seven-element key measured 68ms against 17ms for
  # `min_by(limit)`, which answers identically because the key is total.
  it "takes only the matches it will return, rather than sorting them all" do
    body = body_of("rank")

    expect(body).to include("matches.min_by(limit)")
    expect(body).not_to include("matches.sort_by")
  end

  # A file that reopens one class ten times touches one symbol ten times.
  # Re-sorting an already-sorted list is correct, so nothing behavioural
  # fails without the `uniq` -- it is the same class of decision as the
  # two above.
  it "sorts each touched symbol once per file, not once per declaration" do
    expect(body_of("replace_file")).to include("touched.uniq.each")
  end

  # The limit reaching `rank` needs no assertion of its own: taking it
  # back out of the signature leaves `min_by(limit)` referring to nothing,
  # which is a NameError on the first query rather than a silent revert.
  # `#method_symbol_ids` is asked once per ancestor entry. 0.1.14 grew a
  # class's singleton chain from one entry to six, so a `Widget.`
  # completion went from one scan of every indexed symbol to six.
  # Measured on a 21.7k-symbol workspace, same request, same corpus:
  # 12.97ms per completion scanning, 0.099ms reading a bucket keyed on
  # [owner, kind]. Nothing behavioural can hold this -- the scan returns
  # exactly the same symbols, which is why it survived a release.
  it "reads a bucket keyed on owner and kind rather than scanning every symbol" do
    body = body_of("method_symbol_ids")

    expect(body).to include("@by_owner_kind")
    expect(body).not_to include("@by_symbol.keys")
  end

  # The same two rules, in the method 0.2.0 added. Completion from a bare
  # prefix runs this per keystroke on the request path, and it was
  # written scanning `@by_symbol.keys` -- deriving a simple name per
  # symbol from a structure whose keys already *are* the simple names --
  # and sorting every match to keep `limit` of them. Measured on a
  # 21.7k-symbol workspace, byte-identical answers: 4.8ms per keystroke
  # against 3.0ms.
  it "reads the simple-name index and takes only the matches it returns" do
    body = body_of("prefix_search")

    expect(body).to include("@by_simple_name")
    expect(body).not_to include("@by_symbol.keys")
    expect(body).to include("matches.min_by(limit)")
    expect(body).not_to include(".sort_by")
  end

  # And the third reader of the same structure, `024.137`. `#search` is
  # `workspace/symbol`: it runs per keystroke in the symbol picker, and
  # it asked exactly the question `@by_simple_name` is keyed on -- does
  # this symbol's downcased simple name contain the needle -- by walking
  # `@by_symbol` and deriving that name per symbol instead.
  #
  # Measured on a 14,958-symbol workspace of installed gems (5 Rails
  # components, 1,039 files, 8,259 distinct simple names), four
  # implementations in one process against one index, every answer
  # identical by digest: 3.6-5.5ms per keystroke against 0.7-2.1ms for a
  # two-or-more-character query. The whole method body is inside the
  # mutex, so that is also the fall in how long the call holds it.
  #
  # It buys nothing for the empty query -- 17.9ms against 17.5ms -- which
  # is the state the picker opens in, and `024.137` stays open for that
  # half with a published limitation. The gain here is per keystroke
  # after the first character, which is where the repeats are.
  #
  # The register entry proposed a different countermeasure -- copy
  # `@by_symbol.keys` under the lock, filter outside it, re-take the lock
  # for the survivors -- on the premise that a substring search "cannot
  # use" the simple-name index. It can: that index's keys *are* the
  # downcased simple names. Run in the same process against the same
  # index, the snapshot shape is slower end to end at every one of the
  # nine queries, and holds the lock for less only while a query is being
  # typed: ranking sits in its second critical section, so the picker's
  # opening state holds the mutex 16.6ms of a 21.1ms call. The trade it
  # offers is one this program cannot take anyway -- `Server` holds
  # `@index_mutation_mutex` around the whole request, and indexing
  # commits under that same outer lock, so what indexing waits for is the
  # call's total time and not the inner lock's hold.
  it "reads the simple-name index rather than deriving a name per symbol" do
    body = body_of("search")

    expect(body).to include("@by_simple_name")
    expect(body).not_to include("@by_symbol.each")
    expect(body).not_to include("simple_name(symbol_id)")
  end

  # The bucket key is `simple_name(sid).downcase`, written by
  # `#replace_file`. `#rank` needs exactly that string to decide whether a
  # match is exact, and re-derived it per match -- a `split("::")` and a
  # `downcase` allocated for each of the 16,688 entries an empty query
  # matches, which is the state the picker opens in. Carrying the key
  # answers that query in 17.5ms against 20.1ms re-deriving it; on a
  # typed query the trade runs the other way (0.7-2.1ms against
  # 0.4-1.7ms), and `#rank`'s own comment records why the empty query is
  # the side worth taking.
  #
  # Two decisions, and the needles have to reach the *code*. `body_of`
  # returns the method's comments as well, so a needle spelled the way
  # prose spells it is answered by the prose: the first version of this
  # example asserted the bare `fetch` call, which the explanatory comment
  # inside `#rank` contains verbatim, and subscripting the hash instead
  # left this example green. Verified, not reasoned -- under that
  # mutation this file reported 8 examples, 0 failures, and the
  # behavioural file 82, 0. Both needles below carry syntax no sentence
  # would: the opening bracket of the ranking key, and the receiver.
  #
  # `fetch`, not `[]`: a match assembled without the key ranks as
  # *inexact* under `[]` -- a silently wrong order rather than an error.
  # Nothing behavioural can hold that, because `#search` is the only
  # caller and always sets the key.
  it "ranks on the bucket key rather than deriving the simple name again" do
    body = body_of("rank")

    expect(body).to include("[m.fetch(:simple) == needle")
    expect(body).not_to include("simple_name(m[:symbol_id])")
  end
end

# `SourceLocation.byte_offset_to_utf16` walks a line character by
# character, and it runs once per range of every declaration and every
# argument in every file -- at cold index, twice per `didChange`, and once
# per file in the workspace pass. An ASCII line has one byte, one
# character and one UTF-16 unit per position, so the walk cannot answer
# anything but the offset it was given. Measured over 400 stdlib files:
# `positional_locations` made `summarize` 30% slower without this, and
# 55% faster than the shipped line with it.
#
# Asserted on the source for the same reason as the two above: reversing
# it changes no answer, only what every range costs.
RSpec.describe "SourceLocation's ASCII fast path" do
  it "answers an ASCII line without walking it" do
    source = File.read(File.expand_path("../../lib/ovallsp/index/source_location.rb", __dir__),
                       encoding: "UTF-8")
    body = source[/      def byte_offset_to_utf16.*?\n      end/m]

    expect(body).not_to be_nil, "byte_offset_to_utf16 has been renamed"
    expect(body).to include("return byte_offset if line.ascii_only?")
  end
end
