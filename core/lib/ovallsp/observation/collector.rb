# frozen_string_literal: true

require "set"
require_relative "type_normalizer"
require_relative "fingerprint"
require_relative "observed_signature"
require_relative "call_stack_machine"
require_relative "../index/symbol_id"
require_relative "../types"

module Ovallsp
  module Observation
    # TracePoint-based collector, meant to run *inside* the isolated
    # observation runner process (Observation::Runner), never in Core
    # itself -- installing a global TracePoint in the same process
    # serving LSP requests would slow down and destabilize every other
    # feature for the whole session, not just the opt-in observation run
    # ("production process injection" is explicitly out of scope).
    #
    # Only ever reads, from an observed call: the method's own identity
    # (owner/name/kind), its parameters' and return value's *class*
    # (never the value itself -- TypeNormalizer never calls #inspect/
    # #to_s), and whether the call happened at all. Never reads argument
    # names' string contents, SQL, env vars, or file contents ("保存禁止"
    # -- docs/design/tasks/019-runtime-observation.md).
    #
    # The `:call`/`:return`/`:raise` bookkeeping itself -- what to push,
    # what to pop, what a `:raise` does and doesn't mean -- lives in
    # CallStackMachine, not here; this class is purely the translation
    # from real TracePoint events into that machine's inputs, plus
    # method-info caching and aggregate recording. See
    # docs/design/tasks/022.2-collector-tracepoint-state-machine.md for
    # why that split exists and the invariants/transition table it
    # documents.
    class Collector
      def initialize(workspace_root:)
        @workspace_root = File.realpath(workspace_root)
        # Precomputed so #workspace_method? tests containment on a path
        # *component* boundary rather than a bare string prefix -- see its
        # own docs (round 24).
        @workspace_prefix = "#{@workspace_root}#{File::SEPARATOR}"
        @mutex = Mutex.new
        @aggregates = {}
        # One CallStackMachine per fiber -- see #current_stack for why
        # fiber-local storage, rather than a Hash this object owns, is
        # what makes that isolation structural.
        @stack_key = :"ovallsp_observation_stack_#{object_id}"
        # `[defined_class, method_id]` -> the workspace-eligibility check,
        # symbol_id, fingerprint (re-hashes the *whole* source file --
        # deliberately coarse, see Fingerprint's own docs), and parameter
        # name list -- every one of which is invariant across repeated
        # calls to the *same* method within one run. That invariant is a
        # real precondition, not a comment: round 24 found symbol_id
        # violating it for singleton methods (it was derived from the
        # receiver, `tp.self`, which is not part of this key), so the
        # first receiver to call an inherited class method decided how
        # every later caller's evidence was filed. #symbol_id_for's own
        # docs carry that story; anything added here must likewise be a
        # function of `[defined_class, method_id]` alone.
        #
        # Recomputing this
        # (in particular the SHA256 file digest) on every single `:call`
        # event made a tight loop calling one method thousands of times
        # pay for thousands of redundant full-file hashes.
        #
        # Pinned by overhead_spec.rb's "hashes a traced method's source
        # file once per method, not once per call", which counts digests
        # rather than timing them. An earlier version of this comment
        # credited that file's *timing* example instead; round 24 measured
        # it and found deleting this cache leaves that example 50x inside
        # its (deliberately loose) bound, so nothing pinned the cache at
        # all -- the shape round 23 found for #pop_matching, in this same
        # class.
        #
        # Deliberately neither pruned nor mutex-guarded, unlike the call
        # stacks below (round 20) -- checked again in round 21 and left
        # alone on purpose. It is bounded by construction (one entry per
        # method that actually exists in the process, not per call, per
        # thread, or per run), and it is a pure memoization of a
        # deterministic function of its own key, so the worst a lost or
        # duplicated concurrent write can cost is recomputing one entry.
        # A lock on the `:call` path would be paid by every traced call
        # in the user's suite to buy nothing.
        #
        # Also deliberately never invalidated, checked in round 22. A
        # `method_id` is an interned Symbol, so redefining a method
        # (`class_eval { def m; end }` over an already-observed `m`)
        # reuses this exact key and keeps serving the *old* definition's
        # symbol_id, fingerprint and parameter names. The symbol_id is
        # `[kind, owner, name]` and so is unchanged by any redefinition,
        # and a stale parameter-name list degrades to Types::UNKNOWN
        # (#positional_param_types rescues the failed
        # `local_variable_get`) -- i.e. under-collection, which is this
        # module's stated preference. `prepend` and `alias_method`, the
        # two ways real code patches a method, both produce a *different*
        # `defined_class`/`method_id` and so a different key, and the
        # observation run is a single short-lived process. Invalidating
        # would mean an `instance_method(...).source_location` on every
        # traced `:call`, paid by the whole suite, to correct a case that
        # only ever loses evidence.
        @method_cache = {}
      end

      def start
        @trace = TracePoint.new(:call, :return, :raise) { |tp| handle(tp) }
        @trace.enable
      end

      def stop
        @trace&.disable
      end

      def results(run_id:)
        now = Time.now
        @mutex.synchronize do
          @aggregates.map do |symbol_id, agg|
            ObservedSignature.new(
              symbol_id: symbol_id,
              parameter_types: agg[:param_type_sets].map { |set| Types.normalize_union(set.to_a) },
              return_type: Types.normalize_union(agg[:return_type_set].to_a),
              samples: agg[:samples],
              run_id: run_id,
              code_fingerprint: agg[:fingerprint],
              created_at: now
            )
          end
        end
      end

      private

      # A plugin/library's own bug must never take down the actual test
      # run this is silently riding along with -- every event is fully
      # isolated from every other.
      def handle(tp)
        case tp.event
        when :call then handle_call(tp)
        when :return then handle_return(tp)
        when :raise then handle_raise(tp)
        end
      rescue StandardError
        nil
      end

      # Every observed `:call` becomes exactly one CallStackMachine#push,
      # whether or not the method is one this Collector records -- see
      # the machine's own docs (I2) for why an untracked method still
      # needs a stack slot, and
      # docs/design/tasks/022.2-collector-tracepoint-state-machine.md's
      # transition table for the full reasoning this class used to carry
      # inline before it was extracted (round 20's original finding).
      def handle_call(tp)
        key, info = cached_method_info(tp)
        payload = info && call_payload(tp, info)
        current_stack.push(key, payload)
      end

      def call_payload(tp, info)
        {
          symbol_id: info[:symbol_id],
          fingerprint: info[:fingerprint],
          param_types: positional_param_types(tp, info[:param_names])
        }
      end

      # Returns `[key, info]`, where `key` is the `[defined_class,
      # method_id]` identity #handle_call pushes and #handle_return matches
      # on. The key is handed back rather than rebuilt per call site
      # because the cache lookup has to allocate it anyway.
      def cached_method_info(tp)
        key = [tp.defined_class, tp.method_id]
        return [key, @method_cache[key]] if @method_cache.key?(key)

        [key, @method_cache[key] = compute_method_info(tp)]
      end

      def compute_method_info(tp)
        method_obj = defined_method(tp)
        return nil unless method_obj && workspace_method?(method_obj)

        symbol_id = symbol_id_for(tp)
        return nil unless symbol_id

        {
          symbol_id: symbol_id,
          fingerprint: fingerprint_for(method_obj),
          param_names: positional_param_names(method_obj)
        }
      end

      # `:return` is CallStackMachine's only close-out path (see its own
      # docs, and the transition table's rows 1-4 and 7-12) -- every
      # `:call` gets exactly one `:return` from CRuby, abandoned frames
      # included, so matching by identity here is what keeps the stack
      # balanced without `:raise` needing to pop anything itself.
      def handle_return(tp)
        frame = current_stack.pop_matching([tp.defined_class, tp.method_id])
        return unless frame&.payload

        record(frame.payload, return_type: return_type_for(tp, frame))
      end

      # CRuby fires a `:return` event, `return_value = nil`, for a method
      # that never returned at all -- one an exception unwound past --
      # indistinguishable at the event itself from a method that genuinely
      # evaluated to `nil` (transition table row 7). A non-nil value
      # always proves a normal return; only a `nil` needs qualifying,
      # which is exactly what CallStackMachine's per-frame raise_epoch
      # exists to do: trusted exactly when no `:raise` happened on this
      # fiber during the frame's own lifetime (row 8's `ensure`-body case
      # is why this is a per-frame epoch rather than a single "an
      # exception is in flight" flag -- a call made *after* the raise
      # carries the post-raise epoch and so stays trusted).
      #
      # See the state-machine design doc's "what is not fixed" section
      # for the two residues this still doesn't (and structurally cannot,
      # short of tracing :c_call/:b_return) distinguish from a genuine
      # `nil`: a frame the same method's own rescue swallowed, and a frame
      # abandoned by throw/break/non-local-return/Thread#kill rather than
      # a raise.
      def return_type_for(tp, frame)
        value = tp.return_value
        return TypeNormalizer.normalize(value) unless value.nil?
        return nil unless frame.raise_epoch == current_stack.raise_epoch

        Types::NIL
      end

      # Advances this fiber's raise epoch and nothing else -- a `:raise`
      # is not evidence that any particular frame has ended, only that a
      # `nil` return observed later might be fabricated (transition table
      # rows 7, 9, 10; CallStackMachine#note_raise's own docs for why this
      # event must never pop).
      def handle_raise(_tp)
        current_stack.note_raise
      end

      def record(payload, return_type:)
        @mutex.synchronize do
          agg = @aggregates[payload[:symbol_id]] ||= {
            param_type_sets: Array.new(payload[:param_types].size) { Set.new },
            return_type_set: Set.new,
            samples: 0,
            fingerprint: payload[:fingerprint]
          }
          payload[:param_types].each_with_index { |type, index| agg[:param_type_sets][index] << type }
          agg[:return_type_set] << return_type if return_type
          agg[:samples] += 1
        end
      end

      # One CallStackMachine per fiber, in fiber-local storage rather than
      # a Hash this object owns keyed by `Thread.current.object_id`
      # (found by an independent review, round 20 -- the same
      # unbounded-registry class rounds 17/18 fixed in
      # AgentProcessManager, here in code that runs inside the *user's
      # own test-suite process*).
      #
      # A registry Hash was three separate defects at once:
      #
      # 1. Unbounded growth. Nothing ever removed a thread's entry, so
      #    every thread that ever executed one Ruby method left a
      #    permanent entry -- plus any frames stranded on it by an
      #    exception -- for the whole run. `object_id` is a monotonic
      #    counter in modern CRuby, never reused, so a suite that churns
      #    threads (system/Capybara tests, parallel workers, any app that
      #    forks work off per request) grows this monotonically with
      #    nothing that would ever reclaim it.
      # 2. Unsynchronized cross-thread mutation. `@mutex` guards
      #    `@aggregates` only, while this Hash was written from every
      #    traced thread -- including its default block's own `h[k] = []`
      #    insert. CRuby's GVL happens to make that survivable today;
      #    nothing else does, and this codebase's own AgentSupervisor spec
      #    is explicit that "no other Ruby implementation is obligated to
      #    avoid" such an interleaving.
      # 3. Fibers shared one stack per thread. A Fiber has its own call
      #    stack, so an Enumerator or async library switching fibers
      #    mid-call interleaved two unrelated call stacks into one array.
      #
      # Fiber-local storage fixes all three structurally rather than
      # patching any one of them: the stack (now a whole CallStackMachine,
      # including its own raise-epoch counter -- see its docs) is
      # reachable only from the fiber it belongs to, so it is inherently
      # unshared (no lock needed, no fiber crosstalk) and it is reclaimed
      # with that fiber (no registry to prune).
      def current_stack
        Thread.current[@stack_key] ||= CallStackMachine.new
      end

      # The definition the executing frame actually *is* -- the one whose
      # `owner` is `tp.defined_class` itself, never merely the one dispatch
      # would find starting from it.
      #
      # `Module#instance_method` answers the second question, and the two
      # diverge for exactly one construct: `prepend`, which inserts a module
      # *ahead of* a class in that class's own ancestor chain. So for the
      # frame CRuby reports as `defined_class = Patched`, a bare
      # `Patched.instance_method(:perform)` hands back the prepended
      # wrapper's method instead, and everything #compute_method_info
      # derives from it -- the workspace-containment test, the source-file
      # fingerprint and the parameter-name list -- describes the wrong
      # definition (round 25). Measured, all three ways at once:
      #
      # - A gem prepending into a workspace class (`Module#prepend` is how
      #   ActiveSupport and every instrumentation gem patch app code) made
      #   #workspace_method? read the *gem's* source_location, so the app's
      #   own method was silently dropped from the run entirely.
      # - The workspace prepending into a gem's class made the same test
      #   read the *workspace's* source_location, so the gem's method was
      #   collected and reported as the user's own evidence -- round 24's
      #   containment defect again, reached by a different route.
      # - The parameter-name list and fingerprint came from the wrapper, so
      #   a one-parameter method was reported with the wrapper's two
      #   parameter slots (both Types::UNKNOWN, since the names don't
      #   resolve in the real frame's binding) and fingerprinted against a
      #   file whose edits Store#invalidate_changed would then track instead
      #   of its own.
      #
      # Walking `#super_method` down to the owner that matches restores the
      # premise structurally: this is a pure function of `[defined_class,
      # method_id]` (@method_cache's key), as every field derived from it
      # must be. A frame whose definition cannot be resolved this way yields
      # no evidence at all rather than the wrong method's -- this module's
      # stated preference for under-collection over fabrication.
      def defined_method(tp)
        owner = tp.defined_class
        method_obj = owner.instance_method(tp.method_id)
        method_obj = method_obj.super_method while method_obj && method_obj.owner != owner
        method_obj
      rescue StandardError
        nil
      end

      # Filters to methods whose own *definition* lives under the
      # workspace root -- not merely called from workspace test code, so
      # a Gem/stdlib method invoked from a workspace spec is correctly
      # excluded ("workspace外Gemイベントを既定で収集しない").
      #
      # The containment test must be on a path *component* boundary, not a
      # bare string prefix (round 24). A bare `start_with?(@workspace_root)`
      # accepts any sibling directory whose name merely begins with the
      # root's -- `/srv/app` matched `/srv/application/lib/x.rb` -- and
      # every method defined there was then collected and reported as the
      # user's own workspace evidence, which is exactly what this filter
      # exists to prevent. Vendored gems (`/srv/app-vendor`), a sibling
      # engine, or a checkout beside the workspace all hit it. This is the
      # same path-boundary class review rounds 1-2 fixed in
      # BundleEnvironment's chruby/RVM handling, and ColdIndexer's
      # #real_path_stays_inside_root? already uses this exact idiom.
      def workspace_method?(method_obj)
        file, = method_obj.source_location
        return false unless file

        real_path = File.realpath(file)
        real_path == @workspace_root || real_path.start_with?(@workspace_prefix)
      rescue StandardError
        false
      end

      # The owner of a singleton method is the object its singleton class
      # is *attached to* -- the class the `def self.x` was written in --
      # never `tp.self`, the receiver the call was dispatched through.
      #
      # Those differ for every inherited class method (`Child.build` where
      # `build` is defined on `Base`: `tp.defined_class` is
      # `#<Class:Base>`, `tp.self` is `Child`) and for every `super`
      # between two singleton methods (both frames report `tp.self ==
      # Child`). Reading `tp.self` was wrong three ways at once, found by
      # an independent review (round 24):
      #
      # 1. It contradicted the static index, which declares `def self.x`
      #    under the class it is lexically written in (ParserService's
      #    #visit_def_node) -- so the observed evidence was filed under a
      #    symbol_id no declaration ever matches.
      # 2. It made symbol_id a function of the *receiver* while
      #    `@method_cache` is keyed by `[defined_class, method_id]`, whose
      #    own docs above assert every cached field is invariant per key.
      #    It wasn't: the first receiver to call an inherited class method
      #    won, and every sibling subclass's evidence was then recorded
      #    against it. `Base.build` observed after `Child.build` was
      #    reported as `Child.build`.
      # 3. Under `super` it collapsed two genuinely different methods into
      #    one symbol_id, unioning their parameter lists position-wise.
      #    Measured on `Child.build(a) = super(a, :default)`: one
      #    signature, `parameter_types` = `[Integer, Symbol]` -- a second
      #    positional parameter `Child.build` does not have.
      #
      # #attached_object is a pure function of `defined_class`, which both
      # restores the cache's premise structurally and makes the attribution
      # agree with the index. A singleton class attached to a plain object
      # (`def obj.x`) still yields no symbol_id, as before.
      def symbol_id_for(tp)
        defined_class = tp.defined_class
        if singleton_class?(defined_class)
          attached = defined_class.attached_object
          owner_name = attached.is_a?(Module) ? attached.name : nil
          return nil unless owner_name

          Index::SymbolId.new(kind: :singleton_method, owner: "::#{owner_name}", name: tp.method_id.to_s, discriminator: nil)
        else
          owner_name = defined_class.name
          return nil unless owner_name

          Index::SymbolId.new(kind: :instance_method, owner: "::#{owner_name}", name: tp.method_id.to_s, discriminator: nil)
        end
      end

      def singleton_class?(mod)
        mod.respond_to?(:singleton_class?) && mod.singleton_class?
      end

      def fingerprint_for(method_obj)
        file, line = method_obj.source_location
        return nil unless file

        Fingerprint.for_file_and_line(File.realpath(file), line)
      rescue StandardError
        nil
      end

      # Only :req/:opt positional parameters -- keyword/rest/block
      # parameters don't fit ObservedSignature's flat, position-indexed
      # `parameter_types` array, and are rarer in the small, first-hop
      # method summaries this evidence is meant to supplement anyway.
      # Split from #positional_param_types (below) so the name list --
      # invariant per method -- is computed once and cached, while the
      # actual argument *values* (which must be read fresh from each
      # call's own binding) stay per-call.
      #
      # A `nil` entry means "this slot exists but cannot be read by name",
      # which #positional_param_types below degrades to Types::UNKNOWN --
      # deliberately keeping the slot rather than dropping it, so every
      # later slot stays at its own position.
      #
      # Two shapes produce one. A destructuring parameter (`def m(a, (b,
      # c))`) has no name at all. And a name repeated across slots (`def
      # m(_, _)`, which Ruby permits) binds only the *first* occurrence, so
      # `local_variable_get` answers every one of those slots with the same
      # value: measured pre-fix, `m(1, "s")` reported `[Integer, Integer]`
      # -- the wrong class for a slot that plainly holds a String (round
      # 25). The value is genuinely unavailable for the shadowed slots, so
      # they degrade to UNKNOWN rather than being guessed, this module's
      # stated preference for under-collection over fabrication.
      def positional_param_names(method_obj)
        names = method_obj.parameters.select { |(kind, _)| %i[req opt].include?(kind) }.map { |(_, name)| name }
        repeated = names.tally.select { |name, count| name && count > 1 }.keys.to_set
        names.map { |name| repeated.include?(name) ? nil : name }
      rescue StandardError
        []
      end

      def positional_param_types(tp, param_names)
        param_names.map do |name|
          TypeNormalizer.normalize(tp.binding.local_variable_get(name))
        rescue StandardError
          Types::UNKNOWN
        end
      rescue StandardError
        []
      end
    end
  end
end
