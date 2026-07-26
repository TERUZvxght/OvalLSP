# frozen_string_literal: true

# Pins CallStackMachine's own invariants (I1-I8 in
# docs/design/tasks/022.2-collector-tracepoint-state-machine.md) against
# synthetic event sequences -- no TracePoint, no real Ruby call shapes, no
# threads or fibers -- so they can be checked directly rather than only
# inferred from what a particular Ruby snippet happens to make CRuby do.
# Collector's own spec (collector_spec.rb) is the complementary layer:
# real code, real TracePoint, asserting on the ObservedSignature this
# machine's translation ultimately produces.
RSpec.describe Ovallsp::Observation::CallStackMachine do
  subject(:machine) { described_class.new }

  KEY_A = [Object.new, :a].freeze
  KEY_B = [Object.new, :b].freeze
  KEY_C = [Object.new, :c].freeze

  describe "#push / #pop_matching -- ordinary nesting (table rows 1-2)" do
    it "pops the single pushed frame, returning it, and empties the stack" do
      machine.push(KEY_A, :payload_a)

      frame = machine.pop_matching(KEY_A)

      expect(frame.key).to eq(KEY_A)
      expect(frame.payload).to eq(:payload_a)
      expect(machine.depth).to be_zero
    end

    it "unwinds nested calls innermost-first when returns arrive in LIFO order" do
      machine.push(KEY_A, :a)
      machine.push(KEY_B, :b)
      machine.push(KEY_C, :c)

      expect(machine.pop_matching(KEY_C).payload).to eq(:c)
      expect(machine.pop_matching(KEY_B).payload).to eq(:b)
      expect(machine.pop_matching(KEY_A).payload).to eq(:a)
      expect(machine.depth).to be_zero
    end
  end

  describe "#push -- untracked calls still occupy a slot (I2, table row 1)" do
    it "keeps the stack balanced even when payload is nil" do
      machine.push(KEY_A, nil)
      machine.push(KEY_B, :tracked)

      expect(machine.pop_matching(KEY_B).payload).to eq(:tracked)
      # KEY_A's frame is still there, proving the untracked call was not
      # silently dropped from the stack -- only its payload is nil.
      expect(machine.depth).to eq(1)
      frame = machine.pop_matching(KEY_A)
      expect(frame.payload).to be_nil
    end
  end

  describe "#pop_matching -- matches the nearest frame, not merely the top (I3, table rows 3-4)" do
    it "closes the innermost live invocation of a recursive key, not an outer one" do
      machine.push(KEY_A, :outer)
      machine.push(KEY_A, :inner)

      expect(machine.pop_matching(KEY_A).payload).to eq(:inner)
      expect(machine.pop_matching(KEY_A).payload).to eq(:outer)
      expect(machine.depth).to be_zero
    end

    it "discards everything stacked above the match (table row 7: an unwound raise)" do
      machine.push(KEY_A, :a)
      machine.push(KEY_B, :b) # abandoned by a raise; never gets its own pop
      machine.push(KEY_C, :c) # also abandoned

      frame = machine.pop_matching(KEY_A)

      expect(frame.payload).to eq(:a)
      expect(machine.depth).to be_zero
    end

    it "does not disturb frames below a match that is not at the top" do
      machine.push(KEY_A, :a)
      machine.push(KEY_B, :b)
      machine.push(KEY_C, :c)

      machine.pop_matching(KEY_B) # discards B and C, per the row-7 semantics above

      expect(machine.depth).to eq(1)
      expect(machine.pop_matching(KEY_A).payload).to eq(:a)
    end
  end

  describe "#pop_matching -- no match anywhere (I4, table rows 11 and 13)" do
    it "returns nil and leaves a non-empty stack completely untouched" do
      machine.push(KEY_A, :a)

      expect(machine.pop_matching(KEY_B)).to be_nil
      expect(machine.depth).to eq(1)
      expect(machine.pop_matching(KEY_A).payload).to eq(:a) # still there, unharmed
    end

    it "returns nil, never raises, on a completely empty stack" do
      expect(machine.pop_matching(KEY_A)).to be_nil
      expect(machine.depth).to be_zero
    end
  end

  describe "#note_raise -- never touches the stack (I5, table rows 7, 9, 10)" do
    it "leaves stack depth and frame identities unchanged" do
      machine.push(KEY_A, :a)
      machine.push(KEY_B, :b)

      machine.note_raise

      expect(machine.depth).to eq(2)
      expect(machine.pop_matching(KEY_B).payload).to eq(:b)
      expect(machine.pop_matching(KEY_A).payload).to eq(:a)
    end

    it "is safe to call with an empty stack" do
      expect { machine.note_raise }.not_to raise_error
      expect(machine.depth).to be_zero
    end

    it "a frame that rescues its own attributed raise survives to be popped normally (table row 9)" do
      machine.push(KEY_A, :a)
      machine.note_raise # :raise attributed to A's own frame; A does not unwind
      frame = machine.pop_matching(KEY_A) # A's own :return, with its real value

      expect(frame.payload).to eq(:a)
    end
  end

  describe "raise_epoch -- genuine nil vs. an unwound frame's fabricated one (I6, table rows 7-9)" do
    it "stamps a frame with the epoch at push time, unaffected by pushes before it" do
      machine.push(KEY_A, :a)
      epoch_at_push = machine.raise_epoch

      frame = machine.pop_matching(KEY_A)

      expect(frame.raise_epoch).to eq(epoch_at_push)
    end

    it "a frame pushed before a raise has a stale epoch relative to the current one" do
      machine.push(KEY_A, :a)
      machine.note_raise

      frame = machine.pop_matching(KEY_A)

      expect(frame.raise_epoch).not_to eq(machine.raise_epoch)
    end

    it "a frame pushed after a raise (table row 8's ensure-body case) carries the post-raise epoch and stays current" do
      machine.push(KEY_A, :a) # abandoned by the raise below
      machine.note_raise
      machine.push(KEY_B, :b) # an ensure body's own call, made mid-unwind

      frame_b = machine.pop_matching(KEY_B)
      expect(frame_b.raise_epoch).to eq(machine.raise_epoch)

      frame_a = machine.pop_matching(KEY_A)
      expect(frame_a.raise_epoch).not_to eq(machine.raise_epoch)
    end

    it "multiple raises advance the epoch monotonically, never colliding with an earlier frame's stamp" do
      machine.push(KEY_A, :a)
      before = machine.raise_epoch
      3.times { machine.note_raise }

      frame = machine.pop_matching(KEY_A)

      expect(frame.raise_epoch).to eq(before)
      expect(machine.raise_epoch).to eq(before + 3)
    end
  end

  describe "#push / #note_raise / #pop_matching -- never raise, for any input (I7)" do
    it "tolerates an interleaving of pushes, raises and mismatched pops without raising" do
      expect do
        machine.push(KEY_A, :a)
        machine.note_raise
        machine.pop_matching(KEY_B) # no match
        machine.push(KEY_B, :b)
        machine.note_raise
        machine.pop_matching(KEY_C) # no match
        machine.pop_matching(KEY_A) # matches, discarding B above it
        machine.pop_matching(KEY_A) # already gone -- no match, no error
      end.not_to raise_error
    end
  end

  describe "no cleanup responsibility of its own (I8, table row 12)" do
    it "simply retains whatever is left on the stack when 'stopped' -- there is no #stop method to call" do
      machine.push(KEY_A, :a)
      machine.push(KEY_B, :b)

      # There is deliberately nothing to invoke here: the machine has no
      # process-lifecycle awareness at all. Collector's own fiber-local
      # storage is what reclaims a machine (and whatever it's still
      # holding) once the fiber that owns it is gone -- see the machine's
      # own class docs (I8) and Collector#current_stack.
      expect(machine).not_to respond_to(:stop)
      expect(machine.depth).to eq(2)
    end
  end

  # Generative/property section: constructs many synthetic event
  # sequences -- bounded-depth pushes with a small key alphabet (so
  # recursion/repeated keys are common), pops with keys drawn from the
  # same alphabet (so both matching and non-matching pops occur), and
  # raises interleaved at random points -- and checks invariants that must
  # hold for *every* sequence, not just the hand-picked ones above. Never
  # constructs a real Ruby call at all.
  describe "generative: arbitrary event sequences never violate the machine's invariants" do
    let(:alphabet) { [KEY_A, KEY_B, KEY_C] }

    # A single random sequence of push/pop/raise operations, applied to
    # both the machine under test and a plain-Ruby reference model that
    # implements the same "push always; pop scans from top for nearest
    # match, discarding everything above" contract independently (so a
    # bug shared by both would still be caught by the explicit unit
    # examples above, but this catches the machine disagreeing with its
    # own documented contract under sequences no one thought to write by
    # hand).
    def run_sequence(seed)
      rng = Random.new(seed)
      reference = [] # parallel Array-of-[key, payload, epoch] model
      epoch = 0
      op_count = 200

      op_count.times do
        case rng.rand(3)
        when 0 # push
          key = alphabet.sample(random: rng)
          payload = rng.rand(1000)
          machine.push(key, payload)
          reference.push([key, payload, epoch])
        when 1 # pop_matching
          key = alphabet.sample(random: rng)
          actual = machine.pop_matching(key)
          expected = reference_pop(reference, key)
          raise "pop_matching(#{key.inspect}) mismatch at seed #{seed}" unless frames_equivalent?(actual, expected)
        when 2 # note_raise
          machine.note_raise
          epoch += 1
        end
      end

      # Final invariant: whatever's left agrees on depth and on every
      # remaining key/payload, regardless of how the sequence unfolded.
      expect(machine.depth).to eq(reference.size), "depth mismatch at seed #{seed}"
      reference.reverse_each do |key, payload, _epoch|
        frame = machine.pop_matching(key)
        expect(frame&.payload).to eq(payload), "final drain mismatch at seed #{seed} for key #{key.inspect}"
      end
    end

    # Mirrors CallStackMachine#pop_matching's own documented contract
    # (nearest match, discard above) against the parallel reference
    # array, so a generated sequence's expectation is computed the same
    # way the machine itself is documented to behave -- this test is
    # checking internal consistency of that contract under many
    # sequences, not deriving a new specification independently.
    def reference_pop(reference, key)
      index = reference.rindex { |entry_key, _, _| entry_key == key }
      return nil unless index

      frame = reference[index]
      reference.slice!(index, reference.size - index)
      frame
    end

    def frames_equivalent?(actual, expected)
      return actual.nil? if expected.nil?
      return false if actual.nil?

      actual.payload == expected[1]
    end

    # A fixed, small set of seeds rather than truly random ones, so a
    # failure is reproducible by re-running this file -- no seed here is
    # cherry-picked; they are simply 1..20.
    (1..20).each do |seed|
      it "holds for generated sequence seed #{seed}" do
        run_sequence(seed)
      end
    end
  end
end
