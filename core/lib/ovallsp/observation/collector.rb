# frozen_string_literal: true

require "set"
require_relative "type_normalizer"
require_relative "fingerprint"
require_relative "observed_signature"
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
    class Collector
      Frame = Struct.new(:symbol_id, :fingerprint, :param_types)
      private_constant :Frame

      def initialize(workspace_root:)
        @workspace_root = File.realpath(workspace_root)
        @mutex = Mutex.new
        @aggregates = {}
        @stacks = Hash.new { |h, k| h[k] = [] }
        # `[defined_class, method_id]` -> the workspace-eligibility check,
        # symbol_id, fingerprint (re-hashes the *whole* source file --
        # deliberately coarse, see Fingerprint's own docs), and parameter
        # name list -- every one of which is invariant across repeated
        # calls to the *same* method within one run. Recomputing this
        # (in particular the SHA256 file digest) on every single `:call`
        # event made a tight loop calling one method thousands of times
        # pay for thousands of redundant full-file hashes; caught by
        # this module's own overhead regression test
        # (spec/ovallsp/observation/overhead_spec.rb).
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

      def handle_call(tp)
        info = cached_method_info(tp)
        return unless info

        param_types = positional_param_types(tp, info[:param_names])
        current_stack.push(Frame.new(info[:symbol_id], info[:fingerprint], param_types))
      end

      def cached_method_info(tp)
        key = [tp.defined_class, tp.method_id]
        return @method_cache[key] if @method_cache.key?(key)

        @method_cache[key] = compute_method_info(tp)
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

      def handle_return(tp)
        frame = current_stack.pop
        return unless frame

        record(frame, return_type: TypeNormalizer.normalize(tp.return_value))
      end

      # No :return event ever fires for a call that raised instead --
      # the call still happened (and its argument types still count
      # toward evidence), but it contributed no return value at all, so
      # nothing is added to the return-type union for this call
      # ("1回しか観測されていない型を網羅的型と断定しない" -- a call that
      # never returned must never contribute a fabricated return type).
      def handle_raise(tp)
        frame = current_stack.pop
        return unless frame

        record(frame, return_type: nil)
      end

      def record(frame, return_type:)
        @mutex.synchronize do
          agg = @aggregates[frame.symbol_id] ||= {
            param_type_sets: Array.new(frame.param_types.size) { Set.new },
            return_type_set: Set.new,
            samples: 0,
            fingerprint: frame.fingerprint
          }
          frame.param_types.each_with_index { |type, index| agg[:param_type_sets][index] << type }
          agg[:return_type_set] << return_type if return_type
          agg[:samples] += 1
        end
      end

      def current_stack
        @stacks[Thread.current.object_id]
      end

      def defined_method(tp)
        tp.defined_class.instance_method(tp.method_id)
      rescue StandardError
        nil
      end

      # Filters to methods whose own *definition* lives under the
      # workspace root -- not merely called from workspace test code, so
      # a Gem/stdlib method invoked from a workspace spec is correctly
      # excluded ("workspace外Gemイベントを既定で収集しない").
      def workspace_method?(method_obj)
        file, = method_obj.source_location
        return false unless file

        File.realpath(file).start_with?(@workspace_root)
      rescue StandardError
        false
      end

      def symbol_id_for(tp)
        defined_class = tp.defined_class
        if singleton_class?(defined_class)
          owner_name = tp.self.is_a?(Module) ? tp.self.name : nil
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
      def positional_param_names(method_obj)
        method_obj.parameters.select { |(kind, _)| %i[req opt].include?(kind) }.map { |(_, name)| name }
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
