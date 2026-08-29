# frozen_string_literal: true

require_relative "../types"
require_relative "../index/symbol_id"
require_relative "method_resolver"

module Ovallsp
  module Semantic
    # One completion/member candidate, already carrying enough for a
    # caller to rank and render it without reaching back into whichever
    # subsystem produced it — the "same expression -> same receiver type"
    # guarantee (docs/design/tasks/013-unified-semantic-queries-and-lsp-features.md
    # acceptance: "同一式についてHoverとCompletionが同じreceiver型を利用する")
    # comes from every one of Completion/Hover/Definition/SignatureHelp
    # calling #type_at the same way, then feeding the result into these
    # same #members_of/#definitions_of/#signatures_of methods.
    #
    # - origin: :source (a workspace Declaration), :model_column,
    #   :model_association (Active Record facts), :signature (RBS/RBI) —
    #   "Overload selection MVP"'s authority ranking
    #   (docs/design/tasks/012-rbs-rbi-and-external-signatures.md
    #   Precedence) reduced to what's actually wired at this layer:
    #   project source ranks above Active Record deterministic facts,
    #   which rank above a Gem/stdlib signature.
    # - conditional: true if this candidate isn't present on every member
    #   of a Union receiver.
    # `parameters` is what a completion needs to write a call: the
    # declared parameter names where they are known, `:unknown_arity`
    # where the method takes arguments whose names are not (Rails' own
    # `(*, **, &)` methods), and `[]` where it takes none.
    #
    # `conditional` defaults **because none of the sources that build a
    # Member can compute it**: it is a fact about the *receiver's*
    # branches, not about the name, and `QueryService#merge_branches`
    # sets it on every Member that leaves this class. Stating it at each
    # of the four construction sites was four places asserting a value
    # none of them could know, and none of those assertions survived the
    # fold. Nothing can read the default.
    Member = Data.define(:name, :origin, :conditional, :visibility, :detail, :parameters) do
      def initialize(parameters: [], conditional: false, **rest)
        super(parameters: parameters, conditional: conditional, **rest)
      end
    end

    ORIGIN_AUTHORITY = {
      source: 0, model_column: 1, model_association: 1, signature: 2, model_api: 3
    }.freeze
    private_constant :ORIGIN_AUTHORITY

    # The shared semantic layer behind Completion/Hover/Definition/
    # Signature Help (docs/design/tasks/013-unified-semantic-queries-and-lsp-features.md).
    # Every one of these calls the *same* #type_at for a given
    # document/position, then answers member/definition/signature queries
    # off that one type — the point being that a hover and a completion
    # request for the identical expression can never quietly disagree.
    #
    # Every dependency after `local_inferencer` is optional (nil-safe):
    # a caller with no Rails Runtime Agent connected, or no RBS
    # environment loaded, still gets source-only results rather than an
    # error — matching the same "degrade, never crash" posture every
    # other subsystem in this codebase already follows.
    class QueryService
      def initialize(local_inferencer:, method_resolver: nil, model_registry: nil, signatures: nil, workspace_index: nil)
        @local_inferencer = local_inferencer
        @method_resolver = method_resolver
        @model_registry = model_registry
        @signatures = signatures
        @workspace_index = workspace_index
      end

      # The type of the expression at `document`/`position` — the single
      # source of truth every other QueryService method builds on.
      # `budget` (typically a QueryContext#budget) overrides
      # LocalInferencer's own per-instance step budget for this one call.
      def type_at(document, position, initial_env: {}, budget: nil)
        @local_inferencer.infer_at(document, position, initial_env: initial_env, max_steps: budget)
      end

      # The names in scope at a position, rather than the type of the
      # expression there -- what completion from a bare prefix needs
      # (0.2.0). Passes through for the same reason `type_at` does: the
      # inference budget and the inferencer instance are this service's to
      # own, not every caller's.
      def scope_at(document, position, budget: nil)
        @local_inferencer.scope_at(document, position, max_steps: budget)
      end

      # Every distinct member name starting with `prefix` reachable from
      # `receiver_type`, merged across source declarations, Active Record
      # model facts, and RBS/Gem signatures, ranked by
      # [conditional, origin authority, name].
      #
      # **One branch at a time.** The four sources used to be handed the
      # whole receiver, which flattened a Union into its Nominals and lost
      # which branch supplied each name -- and `conditional`, the only
      # thing separating "every branch has this" from "picking this raises
      # NoMethodError on the other branch", was then re-derived from the
      # name alone by a *fifth* lookup that agreed with none of the four.
      # It disagreed in both directions at once: it asked RBS about the
      # branch's own name with no ancestor chain, so every name Ruby gives
      # every object came back absent (`024.249`, `024.253` -- 121 of 122
      # items in the one-branch-only band, which inverts the list
      # 0.2.15's `sortText` work exists to order); it asked
      # `MethodResolver#resolve`, which does not filter visibility, so a
      # method one branch declares `private` came back present
      # (`024.252`, and offering a call that raises is the direction
      # section 0 ranks worst); Active Record's own API was not something
      # it asked about at all (`024.254`); and a `nil` branch it could not
      # unwrap answered `false` for every name (`024.250`).
      #
      # Enumerating per branch answers it by construction: a name is
      # unconditional exactly when every branch's own enumeration produced
      # it, so the enumeration that offers a member is the one that counts
      # it and nothing is left to agree with anything.
      def members_of(receiver_type, prefix: "", context: {})
        per_branch = receiver_members(receiver_type).map { |branch| [branch, branch_members(branch, prefix, context)] }

        merge_branches(per_branch)
          .sort_by { |m| [m.conditional ? 1 : 0, ORIGIN_AUTHORITY.fetch(m.origin, 9), m.name] }
      end

      # Every location `receiver_type#method_name` could resolve to:
      # source declarations first (in ancestor order), then a signature's
      # own file location (RBS/RBI) if nothing in the workspace declares
      # it, then — for an Active Record association/column with no
      # physical declaration of its own — the owning model class's
      # declaration as a best-effort "go to the generating type"
      # (docs/design/tasks/013-unified-semantic-queries-and-lsp-features.md
      # "generated symbol自体に物理位置がない場合は、生成元DSLまたはschemaへ移動する").
      #
      # **The source band asks one branch at a time**, the same move
      # `#source_signatures` already makes and for the same reason
      # `#receiver_members` exists: `MethodResolver#nominal_members` reads
      # a Union by dropping every member it cannot name, and a
      # `ClassOf[Foo]` member is one of those -- only `MethodResolver`
      # knows to read it as Foo's singleton chain, and it is told that by
      # `#normalize_class_receiver`, which a Union never reaches. So
      # `k = cond ? Foo : Bar` then `k.shared_cm` resolved to nothing at
      # all, for a name completion now offers at that very position
      # (`024.256`). The *bands* stay whole-receiver: they are ordered by
      # authority, not by branch, and each of them already asks per
      # nominal.
      def definitions_of(receiver_type, method_name, context: {})
        source = receiver_members(receiver_type).flat_map do |branch|
          @method_resolver ? @method_resolver.resolve(receiver_type: branch, name: method_name, context: context) : []
        end
        locations = source.flat_map do |candidate|
          candidate.declarations.map { |uri, decl| { uri: uri, range: decl.location } }
        end.uniq
        return locations unless locations.empty?

        # The same rule `#signatures_of` applies, for the same reason: an
        # ancestor's `new` is not the method `X.new(` reaches, so jumping
        # to it lands the reader on somebody else's constructor.
        if constructor_call?(receiver_type, method_name)
          # RBS declaring `new` on the receiver's *own* type is a
          # declaration of this constructor (`String.new`), so it is
          # tried first -- the same order `#signatures_of` takes.
          own = chain_definition_locations(rbs_own_chains(receiver_type, context), method_name)
          return own unless own.empty?

          candidate = constructor_candidate(receiver_type, context)
          return candidate ? candidate.declarations.map { |uri, decl| { uri: uri, range: decl.location } } : []
        end

        signature_locations = signature_definition_locations(receiver_type, method_name, context)
        return signature_locations unless signature_locations.empty?

        model_definition_locations(receiver_type, method_name)
      end

      # Overload label/parameter info for `receiver_type#method_name`,
      # from whichever of source declarations or a loaded signature
      # actually has it — "route/通常method/RBSでSignature Helpが統一的に
      #動く": this is the non-route half; Server still merges in route
      # helper signatures itself, since routes have no Types receiver at
      # all.
      def signatures_of(receiver_type, method_name, context: {})
        if receiver_type.is_a?(Types::Union)
          return receiver_type.members.flat_map do |member|
            member == Types::NIL ? [] : signatures_of(member, method_name, context: context)
          end.uniq
        end

        # Three bands, and the source band's position is the whole reason
        # there is more than one RBS band: what RBS declares *directly*
        # on the receiver's own type outranks the workspace's declaration
        # (a `sig/` file describing the class the workspace also
        # declares, or a reopened core class), while what RBS says about
        # an *ancestor* does not -- an override is nearer than the thing
        # it overrides. So `#ancestor_signatures` is correct only
        # below the source band; walking the chain above it would answer
        # `MyStr#sub` with `String`'s signature, which the controls in
        # `spec/ovallsp/semantic/inherited_rbs_signatures_spec.rb` pin.
        #
        # Bands 1 and 2 are what this method already did -- band 1 is the
        # old `direct: true` half. The old `direct: false` half asked the
        # receiver's own name a second time, and band 3 subsumes it: band
        # 3 walks the chain whose *head* is that same name with that same
        # filter, so for every name but `new` the two make the identical
        # call. `new` is where they differed, and it is a rule rather
        # than a band -- see `#constructor_call?`.
        rbs_own_signatures(receiver_type, method_name, context) ||
          source_signatures(receiver_type, method_name, context) ||
          ancestor_signatures(receiver_type, method_name, context)
      end

      # A minimal evidence trail for `type_at`'s result: what the type
      # is, and (best-effort) which subsystem is why. Never more precise
      # than "the first subsystem that produced a non-Unknown answer" —
      # full precedence-aware evidence merging across every contributing
      # source is deferred (docs/design/tasks/012-rbs-rbi-and-external-signatures.md's
      # own "矛盾時は...evidenceへ残す" is explicitly left to a future
      # richer evidence model; this is the MVP "型の根拠を確認できる" slice).
      # Left exactly as it was: no production code calls #explain
      # (`explain_type_result` uses #type_at, `show_type_evidence_result`
      # reads the observation store directly). Routing it through a new
      # two-pass evidence API added a second full inference per query and
      # an `origin:` field for a caller that does not exist -- AGENTS.md
      # is explicit that functionality is not implemented in advance. If
      # #explain is to be wired up, that is the change to make; until
      # then there is nothing here to enrich.
      def explain(document, position, initial_env: {})
        type = type_at(document, position, initial_env: initial_env)
        { type: type, confidence: type == Types::UNKNOWN ? :low : :high }
      end

      private

      # One branch's members, keyed by name. The same four calls the whole
      # receiver used to get, in the order `SOURCE_ORDER` names as
      # origins -- `#add_model_members` produces two of them -- and the
      # first to produce a name keeps it, which is all the `||=` in each
      # of them does. That is what makes a source declaration outrank a
      # column and a column outrank RBS.
      #
      # **`MethodResolver#complete` caps its answer, so the cap is now per
      # branch** rather than over the flattened receiver. That is the one
      # way this is weaker than the pass it replaces, and it errs the
      # cheap way round: truncation only ever removes a name from a
      # branch, so it can only move a label *toward* conditional, never
      # into the every-branch band on a receiver that would raise. The
      # list still offers the name either way.
      def branch_members(branch, prefix, context)
        receiver = branch_receiver(branch)
        candidates = {}
        add_source_members(candidates, receiver, prefix, context)
        add_model_members(candidates, receiver, prefix)
        add_active_record_api_members(candidates, receiver, prefix)
        add_signature_members(candidates, receiver, prefix, context)
        candidates
      end

      # The receiver a branch is enumerated as -- itself, except `nil`.
      #
      # Every one of the four sources keys on a class name and
      # `Types::NilType` is not one, so a `nil` branch produced no names
      # at all and the fold below then called *every* member of a nilable
      # Union one-branch-only -- `to_s`, `inspect` and `frozen?` among
      # them, which `nil` answers as readily as anything else does. That
      # is `024.250`, and `Widget | nil` is the commonest Union this
      # engine builds, so it was most of what a user sees.
      #
      # Only half of that entry is a defect, and this fixes that half:
      # the class's own method really *is* conditional on a nilable
      # receiver, because the nil branch really does raise.
      # `query_service_spec`'s "keeps members conditional on a nilable
      # receiver" is the control that says so, and it still passes.
      #
      # Which class `nil` is an instance of is `Types.class_of`'s to say
      # and is not restated here; `Types.class_object_lookup` is the one
      # place that takes the `ClassOf` it answers apart. The side that
      # lookup pairs with the class is the side to ask *a class object*
      # for, which is a different question from the one here -- a `nil`
      # branch is an ordinary instance -- so it is dropped and the
      # caller's own `context[:singleton]` still decides.
      def branch_receiver(branch)
        return branch unless branch.is_a?(Types::NilType)

        Types.class_object_lookup(Types.class_of(branch)).first
      end

      # The order the four sources run in, which is also the order that
      # decides which one owns a name two of them produce. Written down
      # because it now has a second reader -- the fold below, choosing
      # between two branches' answers for one name -- and a fold that
      # ranked by `ORIGIN_AUTHORITY` instead would put an RBS signature
      # above Active Record's API, which is the opposite of what a single
      # branch does. `union_branch_members_spec`'s "keeps the
      # higher-authority origin" is the example that tells the two apart.
      SOURCE_ORDER = %i[source model_column model_association model_api signature].freeze
      private_constant :SOURCE_ORDER

      # **`conditional` is decided here and nowhere else**: a name every
      # branch's enumeration produced is unconditional, and any other name
      # is not. There is no availability question left to ask, because the
      # enumeration that offers the member is the same one that counts it.
      def merge_branches(per_branch)
        merged = {}
        per_branch.each do |branch, candidates|
          next unless offers_names?(branch, per_branch.length)

          candidates.each do |name, member|
            held = merged[name]
            merged[name] = member if held.nil? || source_rank(member) < source_rank(held)
          end
        end
        merged.map do |name, member|
          member.with(conditional: per_branch.any? { |_, candidates| !candidates.key?(name) })
        end
      end

      # **A `nil` branch decides availability without being a source of
      # members**, and it is the only branch treated that way.
      #
      # The two halves of what a Union's list is for come apart here.
      # *Which names are safe* is a question about every branch, `nil`
      # included -- that is `024.250`, and answering it needs the nil
      # branch enumerated. *Which names to offer* is a question about what
      # the user is reaching for, and on `Widget | nil` that is never the
      # nil branch: nobody types `widget.` meaning `NilClass#to_r`.
      #
      # Measured over activesupport 8.1.3.1's `lib` (289 files, 1,569
      # receiver positions) before deciding, because letting nil offer its
      # names too is the simpler rule and would have been the one to keep
      # if the difference were small. It is not. **The simpler rule** moves
      # 37 positions, 27 of them `Unknown | nil` -- where nothing else can
      # be enumerated, so the whole offer would have been `NilClass`'s 150
      # names at a receiver whose only certain property is that it is not
      # what the caller wants (`@max_key_size.` and
      # `module_parent_name.split(` are two of them). **This rule** moves
      # 8, and every one of the 8 is a receiver that gains a real answer.
      #
      # A receiver that is *only* `nil` still offers them, because there
      # is nothing else it could mean and `nil.to_s` is a real call.
      def offers_names?(branch, branch_count)
        branch_count == 1 || !branch.is_a?(Types::NilType)
      end

      def source_rank(member) = SOURCE_ORDER.index(member.origin) || SOURCE_ORDER.length

      # `MethodResolver#complete` answers a `conditional` of its own, and
      # it is deliberately **not** read here: it is handed one branch, so
      # its answer is always `false`, and passing it through would make it
      # a second opinion about a question `#merge_branches` owns -- which
      # is the arrangement this change removed.
      def add_source_members(candidates, receiver_type, prefix, context)
        return unless @method_resolver

        @method_resolver.complete(receiver_type: receiver_type, prefix: prefix, context: context).each do |result|
          candidates[result[:name]] ||= Member.new(
            name: result[:name], origin: :source,
            visibility: nil, detail: nil,
            parameters: source_parameter_names(receiver_type, result[:name], context)
          )
        end
      end

      # Active Record's own API, as the Runtime Agent read it off the
      # really-loaded classes. A model's ancestors above ApplicationRecord
      # are outside the workspace and have no signatures, so without this
      # completion on a model offered its columns and nothing else -- no
      # `save`, no `destroy`, and on the class no `find`, `where` or
      # `all`. Ranked below columns, associations and source declarations,
      # all of which say something more specific about *this* model.
      #
      # `ClassOf[Model]` takes the class API, a plain `Model` the instance
      # API. That distinction is the whole reason a constant now infers as
      # a class object rather than Unknown.
      def add_active_record_api_members(candidates, receiver_type, prefix)
        return unless @model_registry

        subject, singleton = Types.class_object_lookup(receiver_type)
        return unless each_nominal(subject).any? { |nominal| @model_registry.known_model?(nominal.name) }

        api = @model_registry.active_record_api
        names = singleton ? api[:singleton] : api[:instance]
        # Plus whatever each model adds on top: attribute and dirty
        # methods, association accessors, enum predicates, scopes.
        each_nominal(subject).each do |nominal|
          model = @model_registry.model(nominal.name)
          next unless model

          names += singleton ? model.singleton_methods : model.instance_methods
        end
        takes_arguments = singleton ? api[:singleton_with_arguments] : api[:instance_with_arguments]
        names.uniq.each do |name|
          next unless name.start_with?(prefix)

          candidates[name] ||= Member.new(
            name: name, origin: :model_api, visibility: nil, detail: nil,
            parameters: takes_arguments&.include?(name) ? :unknown_arity : []
          )
        end
      end

      # Declared parameter names for a source method, in call order, so a
      # completion can offer them as tab stops. Only positional and
      # keyword parameters are offered: a block is written after the call,
      # and a splat has no name worth typing.
      def source_parameter_names(receiver_type, method_name, context)
        return [] unless @method_resolver

        found = @method_resolver.resolve(receiver_type: receiver_type, name: method_name, context: context)
        declaration = found.first&.declarations&.first&.last
        return [] unless declaration

        Array(declaration.parameters).filter_map do |parameter|
          parameter.name if %i[required optional keyword keyword_optional].include?(parameter.kind)
        end
      end

      def add_model_members(candidates, receiver_type, prefix)
        return unless @model_registry

        details = {}
        each_nominal(receiver_type).each do |nominal|
          next unless @model_registry.known_model?(nominal.name)

          model = @model_registry.model(nominal.name)
          next unless model

          model.columns.each do |column|
            next unless column.name.start_with?(prefix)

            details[[:model_column, column.name]] = column.ruby_type
          end
          model.associations.each do |association|
            next unless association.name.start_with?(prefix)

            details[[:model_association, association.name]] = association.class_name
          end
        end

        details.each do |(origin, name), detail|
          candidates[name] ||= Member.new(
            name: name, origin: origin, visibility: :public, detail: detail
          )
        end
      end

      def add_signature_members(candidates, receiver_type, prefix, context)
        return unless @signatures

        # `ClassOf[X]` is the class object, and a member of it lives on
        # X's *singleton* chain -- the same normalisation
        # `#add_active_record_api_members` makes and
        # `MethodResolver#normalize_class_receiver` makes. This source made
        # neither, so `each_nominal` yielded a nominal named "ClassOf" and
        # RBS was asked about a class of that name, which does not exist.
        #
        # This was the reader that got the chain right, and it now reads
        # the same `#rbs_owner_chains` the signature and definition
        # lookups do, so the three cannot drift apart again (`024.43`).
        # Every owner, not the first: a completion list is the union of
        # what the chain offers, which is the opposite of the
        # nearest-wins question a single call asks.
        names = rbs_owner_chains(receiver_type, context).flatten(1).flat_map do |owner, owner_singleton|
          @signatures.member_names(qualify(owner), prefix: prefix, singleton: owner_singleton)
        end
        names.each do |name|
          candidates[name] ||= Member.new(
            name: name, origin: :signature, visibility: nil, detail: nil
          )
        end
      end

      # Which RBS/RBI owners a receiver's members can come from, paired
      # with the side to ask each for.
      #
      # It was the receiver's own name and nothing else, so a signature
      # inherited from an ancestor was never offered. The visible one is
      # `new`: `Article.` is a class object, `new` is `Class`'s *instance*
      # method, and `EXTENSION_CAPABILITIES.md`'s C5 row names it in the
      # list it promises. Its example asked for `find`, `where` and `all`
      # -- all of which the Runtime Agent supplies -- so the row read PASS
      # with the one member RBS had to answer for missing.
      #
      # The side comes from `AncestorEntry#declaration_kind`, which is
      # where this project keeps that rule: a class object is an
      # *instance* of `Class`, so the tail is asked for instance members
      # even though the walk is a singleton one. `MethodResolver` and
      # `Diagnostics::Engine` were taught this in 0.1.15; completion is
      # the third reader and was not.
      # Only the no-resolver case needs a fallback: an empty result here
      # means the argument was not a Nominal, and `#each_nominal` only
      # ever yields Nominals.
      #
      # **It does not open the chain with the receiver.** This comment
      # said it did until `024.43` drove it over the stdlib:
      # `HierarchyIndex` resolves a bare name against whatever the
      # workspace declares with that last segment, so a name some nested
      # class shares is answered with the nested class.
      # `#rbs_lookup_chains` is where the receiver's own name is put back
      # at the head, and it is deliberately not done here -- completion
      # reads this one, and prepending there is what `024.47` decided
      # against.
      def signature_owners(nominal, singleton)
        return [[nominal.name, singleton]] unless @method_resolver

        @method_resolver.lookup_owners(nominal, singleton: singleton)
      end

      # Reached only when the workspace declares nothing, so there is no
      # source declaration for an ancestor's signature to outrank and the
      # whole chain is in scope -- unlike `#signatures_of`'s bands.
      #
      # This carried a byte-identical copy of the receiver's-own-name
      # lookup, so a fix to signature help alone would have left go to
      # definition unable to jump for exactly the calls it repaired
      # (`024.43`). It reads the same `#rbs_lookup_chains` now.
      def signature_definition_locations(receiver_type, method_name, context)
        chain_definition_locations(rbs_lookup_chains(receiver_type, context), method_name)
      end

      # The nearest owner in each chain that answers, for the same reason
      # `#rbs_overloads` stops there: `Object` and `Kernel` both carry
      # `puts`, and go to definition offering two identical jumps is
      # offering a choice the call does not have.
      def chain_definition_locations(chains, method_name)
        return [] unless @signatures

        chains.filter_map do |chain|
          chain.lazy.filter_map { |owner, singleton| rbs_method(owner, singleton, method_name)&.location }.first
        end
      end

      def model_definition_locations(receiver_type, method_name)
        return [] unless @workspace_index && @model_registry

        each_nominal(receiver_type).filter_map do |nominal|
          next unless @model_registry.known_model?(nominal.name)
          next unless @model_registry.column(nominal.name, method_name) || @model_registry.association(nominal.name, method_name)

          # Ask by qualified name, never by a reconstructed SymbolId:
          # `owner` is recorded lexically, so `module Admin; class
          # Company` and `class Admin::Company` are two different keys for
          # one class and an `owner: nil` guess only ever matches the
          # second (0.1.12, the same move as `Server#find_controller_uri`).
          @workspace_index.class_declarations(nominal.name).first
        end
      end

      def source_signatures(receiver_type, method_name, context)
        return nil unless @method_resolver

        # One entry per receiver *member*, not per candidate. `#resolve`
        # answers the override and the method it overrides, in lookup
        # order -- which is what makes go-to-definition land on the
        # nearest -- and turning both into labels showed
        # `["area()", "area()"]` for a method that merely overrides
        # another. Ruby calls exactly one of them, so the popup was
        # offering a choice that does not exist.
        #
        # 0.2.9 deduplicated on the rendered label, which collapsed the
        # pair only when the override happened to reuse its parent's
        # parameter *names*; an override that renames one -- the ordinary
        # case -- still showed both. The label was never the question.
        # Asking each member for its own lowest-ranked candidate is: a
        # Union legitimately produces two *different* signatures for one
        # name, and that is what this popup is for, while within one
        # member there is only ever one method to call.
        signatures = receiver_members(receiver_type).filter_map do |member|
          callable = @method_resolver.resolve(receiver_type: member, name: method_name, context: context).first
          decl = callable&.declarations&.first&.last
          next unless decl

          # The per-parameter labels are what `activeParameter` would point
          # into, so they have to be spelled the same way as the label they
          # are cut from -- otherwise the highlight names something the
          # signature line does not contain.
          { label: signature_label(method_name, decl.parameters),
            parameters: decl.parameters.map { |p| { label: p.label } } }
        end.uniq { |signature| signature[:label] }
        signatures.empty? ? nil : signatures
      end

      # What RBS declares on the receiver's **own** type, and only that.
      #
      # `String.new` types as `ClassOf[String]`; without the
      # normalisation the lookup asks RBS about a class named `ClassOf`
      # and every stdlib `Klass.method(` answered nothing (`024.228`).
      #
      # Deliberately not the ancestor chain: this band outranks the
      # workspace's own declaration, and an ancestor's signature does not
      # -- see `#signatures_of`.
      def rbs_own_signatures(receiver_type, method_name, context)
        return nil unless @signatures

        rbs_own_chains(receiver_type, context).flat_map do |chain|
          rbs_overloads(chain, method_name, direct: true)
        end.tap { |result| return nil if result.empty? }
      end

      # Band 3, and the reach this entry adds: what RBS declares on the
      # receiver's own type however the method got there, and then on an
      # *ancestor* the workspace's chain reaches.
      #
      # The RBS bands asked about the receiver's own name and nothing
      # else, so a method declared only on an RBS ancestor of a name RBS
      # has never heard of was unreachable: a receiverless `puts(` inside
      # a class body, `MyErr < StandardError` and its `full_message`,
      # `MyStr < String` and its `sub`. `#add_signature_members` had
      # already made the move for completion, which is why bare-prefix
      # completion offers `puts` in the very body where signature help
      # said nothing (`024.43`).
      #
      # The whole chain, head included: the head is the receiver's own
      # type, and asking it here is the same call the old `direct:
      # false` band made. A `.drop(1)` would be the shape to use if
      # something above had already asked it, and nothing does.
      #
      # `new` never reaches the walk, because an ancestor's `new` is the
      # ancestor's constructor -- see `#constructor_call?`. That test is
      # deliberately *above* the `@signatures` guard: the workspace's own
      # `initialize` is a fact about the workspace, so an engine with no
      # RBS environment loaded still answers `X.new(` from it. Pinned by
      # `inherited_rbs_signatures_spec.rb`'s "with no RBS environment
      # loaded".
      def ancestor_signatures(receiver_type, method_name, context)
        return constructor_signatures(receiver_type, context) if constructor_call?(receiver_type, method_name)
        return [] unless @signatures

        rbs_lookup_chains(receiver_type, context).flat_map do |chain|
          rbs_overloads(chain, method_name, direct: nil)
        end
      end

      # The **first** owner in `chain` RBS answers for, not every one of
      # them. Ruby calls the method on the nearest ancestor that has one,
      # and RBS's own definition builder has already merged that owner's
      # ancestors into the answer -- so a nearer owner's reply is the
      # whole reply, and collecting the rest would offer a choice the
      # call does not have. `Object` and `Kernel` are both in every
      # chain and both answer for `puts`.
      def rbs_overloads(chain, method_name, direct:)
        chain.each do |owner, singleton|
          sm = rbs_method(owner, singleton, method_name)
          next unless sm
          next unless direct.nil? || sm.direct == direct

          # Two RBS overloads can spell the same part list -- `upcase` has
          # two that both read `(Symbol, Symbol) -> String` -- and an
          # editor showing the same line twice is showing noise.
          return sm.overloads.map { |o| rbs_signature(method_name, o) }.uniq { |signature| signature[:label] }
        end
        []
      end

      # **`new` is the one name an ancestor cannot answer for.** Every
      # other method keeps the parameter list it is inherited with;
      # `Class#new` forwards its arguments to the receiver's *own*
      # `initialize`, so a declaration of `new` found on an ancestor
      # describes that ancestor's constructor.
      #
      #     $ ruby -e '
      #       class Report; def initialize(a, b); end; end
      #       class Plain; end
      #       p Report.instance_method(:initialize).parameters
      #       p Plain.instance_method(:initialize).owner
      #       begin; Report.new(1); rescue ArgumentError => e; p e.message; end'
      #     [[:req, :a], [:req, :b]]
      #     BasicObject
      #     "wrong number of arguments (given 1, expected 2)"
      #     # ruby 3.4.10
      #
      # Walking the singleton chain without this answered `new() -> Object`
      # -- RBS's rendering of `Object#initialize`, which takes nothing --
      # on 31 of 253 newly answered call sites across the Ruby 3.4.10
      # standard library, and sent go to definition into `basic_object.rbs`.
      # A constructor reported as taking no arguments when it takes two is
      # the wrong answer this walk had to not introduce.
      #
      # Reached only after `#rbs_own_signatures` and `#source_signatures`,
      # so a class RBS declares a constructor for *directly*
      # (`String.new`) and a class that writes its own `def self.new` are
      # both answered before this, from their own declarations. A class
      # RBS carries `new` for only by inheritance -- every
      # `StandardError` subclass RBS knows -- is answered *by* this rule,
      # from the receiver's own type: see `#constructor_signatures`.
      def constructor_call?(receiver_type, method_name)
        method_name == "new" && Types.class_object?(receiver_type)
      end

      # `X#initialize` as the workspace declares it, looked up on the
      # instance side so an inherited constructor is found where the
      # workspace wrote one.
      #
      # Its caller deliberately does not fall through to an *ancestor's*
      # RBS declaration when this answers nothing: `Object#initialize` is
      # `() -> void` there, and rendering that as `new()` for every class
      # whose constructor this engine cannot see would restate the same
      # false claim one layer down. Nothing is what the engine can honestly
      # say. The receiver's *own* RBS type is a different matter and is
      # asked first -- see `#constructor_signatures`.
      def constructor_candidate(receiver_type, context)
        return nil unless @method_resolver

        @method_resolver.resolve(
          receiver_type: receiver_type.type_arg, name: "initialize", context: context.merge(singleton: false)
        ).first
      end

      # RBS declaring `new` on the receiver's **own** type is a
      # declaration of *this* constructor (`String.new`, `Struct.new`),
      # however RBS came to carry it -- it builds a definition per type
      # and resolves `instance` and `self` against the type it was asked
      # for, so `singleton(::ArgumentError)`'s inherited `new` still
      # reads `-> ArgumentError`. So it is asked first, and only the
      # chain *below* the head is refused. `#definitions_of` takes the
      # same two steps in the same order.
      def constructor_signatures(receiver_type, context)
        own = if @signatures
                rbs_own_chains(receiver_type, context).flat_map { |chain| rbs_overloads(chain, "new", direct: nil) }
              else
                []
              end
        return own unless own.empty?

        decl = constructor_candidate(receiver_type, context)&.declarations&.first&.last
        return [] unless decl

        [{ label: signature_label("new", decl.parameters),
           parameters: decl.parameters.map { |parameter| { label: parameter.label } } }]
      end

      # **The one place that answers "which RBS owners does this receiver
      # reach".** One chain per nominal, because a Union reaches each
      # member's ancestors separately and an answer found on one member
      # is not an answer for the other.
      #
      # Three readers had three copies of this question and two of them
      # answered it with the receiver's own name -- the RBS signature
      # lookup and `#signature_definition_locations` -- so signature
      # help, hover and go to definition all stopped at the receiver
      # while completion, which had already moved to
      # `MethodResolver#lookup_owners`, walked the chain (`024.43`). The
      # countermeasure for two readers that must agree is one
      # implementation both read, not a fix to each.
      def rbs_owner_chains(receiver_type, context)
        subject, singleton = Types.class_object_lookup(receiver_type, singleton: context[:singleton] == true)
        each_nominal(subject).map { |nominal| signature_owners(nominal, singleton) }
      end

      # The same chains, each opened with the receiver's **own** name.
      #
      # `#signature_owners`'s comment already claimed `#lookup_owners`
      # does that; driven over the stdlib it does not. `HierarchyIndex`
      # resolves a bare name against whatever the workspace declares with
      # that last segment, so `Nominal("EOFError")` opened a chain at a
      # nested `EOFError` a gem declares, `Nominal("Encoding")` at one
      # RDoc declares and `Nominal("Marshal")` at one OpenSSL declares --
      # and RBS, asked about those, says nothing. Handing the bare chain
      # to the RBS readers lost two signatures and eight definition jumps
      # they had been answering, out of 12,609 probes.
      #
      # So the receiver's own name is asked first and the chain is the
      # extension: each of these walks is then a *superset* of the
      # receiver's-own-name lookup it replaces, and cannot answer less
      # than it did.
      #
      # **Not folded into `#rbs_owner_chains`**, which completion reads:
      # for a Union or a shadowed name, opening the chain with the bare
      # name is what `024.47` decided against and
      # `query_service_spec.rb`'s "answers an inferred String with the
      # workspace class alone" pins in both directions until that entry
      # is settled. A single call asking "what could this reach" and a
      # completion list asking "what should I offer" are different
      # questions, and this is where they differ.
      #
      # **Not deduplicated.** The receiver's own link usually arrives
      # twice -- once bare from `Nominal#name` and once qualified from
      # `#lookup_owners` -- and no reader can see the repeat: every one
      # of them takes the head (`#rbs_own_chains`) or stops at the first
      # owner that answers (`#rbs_overloads`,
      # `#chain_definition_locations`). A second copy is therefore only
      # ever reached when the first did not answer, and it cannot answer
      # either. A `.uniq` here was a line no example could fail on,
      # which this project counts as a defect of its own.
      #
      # **One branch at a time**, because `Types.class_object_lookup`
      # answers about one receiver and a Union of class objects is not
      # one: handed the whole thing it declined to unwrap, `#each_nominal`
      # then read each `ClassOf[Foo]` member as a class literally named
      # `ClassOf`, and every chain asked RBS about a class that does not
      # exist. `024.228`'s defect surviving in the one receiver shape that
      # entry's fix does not reach (`024.255`, `024.256`). Each branch
      # gets its own unwrap and so its own side, which is what a mixed
      # Union -- one class object and one instance -- needs and what a
      # single lookup over the whole receiver cannot express.
      def rbs_lookup_chains(receiver_type, context)
        receiver_members(receiver_type).flat_map do |branch|
          subject, singleton = Types.class_object_lookup(branch, singleton: context[:singleton] == true)
          each_nominal(subject).map do |nominal|
            [[nominal.name, singleton]] + signature_owners(nominal, singleton)
          end
        end
      end

      # Just the head of each of those: the receiver's own type, asked on
      # its own. Cut from `#rbs_lookup_chains` rather than rebuilt, so
      # "what is the receiver's own name" is decided once and the band
      # that outranks the workspace can never mean something different by
      # it than the band below does.
      def rbs_own_chains(receiver_type, context)
        rbs_lookup_chains(receiver_type, context).map { |chain| chain.take(1) }
      end

      # One owner asked of the signature environment. `singleton` is the
      # *side* to ask that owner for, which `#signature_owners` pairs with
      # each name and is not the same question as the side of the walk.
      def rbs_method(owner, singleton, method_name)
        @signatures.method_signatures(
          Index::SymbolId.new(
            kind: singleton ? :singleton_method : :instance_method, owner: qualify(owner), name: method_name,
            discriminator: nil
          )
        )
      end

      # `Index::Parameter#label` spells each one the way the source does.
      # Joining bare names here dropped every default, `*`, `:`, `**` and
      # `&`, so a required keyword read as a positional (`024.89`).
      def signature_label(method_name, parameters)
        "#{method_name}(#{parameters.map(&:label).join(', ')})"
      end

      # The label is what signature help shows while the user is typing
      # arguments into the call, so anything it leaves out reads as "this
      # takes nothing more".
      #
      # Positionals were all it rendered. That made `(?)` -- RBS for
      # "takes anything", which `Proc#call` and `Method#call` are declared
      # as -- come out as `call()`, and made every signature with no
      # *named* positionals but some keyword come out the same way (29
      # methods in the RBS core this loads, 33 counting each overload,
      # `Array#shuffle` among them; three of them -- `Dir.[]`,
      # `Kernel#warn`, `Ractor.new` -- also take a `*rest` *positional*,
      # which is the whole difference between this count and the 26 an
      # earlier revision gave. `Exception#detailed_message` has a `**`
      # rest and is not one of the three; a reviewer read "`*rest`" as
      # "any rest slot" and made it four, so it is spelled out here).
      # Before 0.1.12 the `(?)` ones failed to build at all so
      # nothing was shown; making them build has to not make them lie, and
      # the keyword case was already lying.
      # Label and parameters together, because they are the same list read
      # twice and an editor needs both: `activeParameter` is an index into
      # `parameters`, so a signature carrying none can never highlight
      # anything however well the index is computed. Only source
      # declarations carried them, so the promise held for a method you
      # wrote and quietly did not for `"abc".sub(` or `where(`.
      #
      # Each parameter is an [start, end) offset pair into the label
      # rather than the substring: two positionals of the same type spell
      # the same string, and a client matching by substring highlights the
      # first of them for both.
      def rbs_signature(method_name, overload)
        parts = rbs_signature_parts(overload)
        label = +"#{method_name}("
        parameters = parts.map do |part|
          start = label.length
          label << part
          offsets = [start, label.length]
          label << ", "
          { label: offsets }
        end
        label.delete_suffix!(", ") unless parts.empty?
        # `#return_label`, not `#return_type` (`024.42`). The converted
        # type maps `self`, `void` and `untyped` all to `Unknown`, which
        # is right for the model and wrong for prose a person reads --
        # `push(...) -> Unknown` where RBS wrote `-> self`.
        { label: "#{label})#{rbs_block_suffix(overload)} -> #{overload.return_label}", parameters: parameters }
      end

      def rbs_signature_parts(overload)
        parts = overload.required_positionals.map(&:to_s) +
                overload.optional_positionals.map { |t| "?#{t}" } +
                overload.trailing_positionals.map(&:to_s)
        parts.concat(overload.required_keywords.keys.map { |name| "#{name}:" })
        parts.concat(overload.optional_keywords.keys.map { |name| "?#{name}:" })
        # One marker for either rest slot: the label says the call accepts
        # more than it names, and which slot that came from is not
        # something a reader of the label can act on.
        parts << "..." if overload.rest_positional || overload.rest_keyword
        parts
      end

      # The block, written where a caller writes it: after the closing
      # parenthesis, not as an argument. Dropped entirely until 0.2.1, so
      # `each` and `map` -- whose whole point is the block -- read as
      # taking nothing at all.
      def rbs_block_suffix(overload)
        return "" unless overload.block_type || overload.block_required

        parameters = overload.block_type.to_s[/\A\((.*?)\)/, 1].to_s
        body = parameters.empty? ? "..." : "|#{parameters}| ..."
        overload.block_required ? " { #{body} }" : " [{ #{body} }]"
      end

      # The receiver split into the things a lookup happens against,
      # *unchanged* -- a `ClassOf[Widget]` member names no class and only
      # `MethodResolver` knows to read it as Widget's singleton chain, so
      # unwrapping one here (as `#each_nominal` does, correctly, for the
      # signature-environment paths that key on a type name) answered
      # nothing for `Widget.build(`.
      def receiver_members(type)
        type.is_a?(Types::Union) ? type.members : [type]
      end

      def each_nominal(type)
        return to_enum(:each_nominal, type) unless block_given?

        case type
        when Types::Nominal then yield type
        when Types::Generic then yield Types::Nominal.new(name: type.name)
        when Types::Union then type.members.each { |member| each_nominal(member) { |nominal| yield nominal } }
        end
      end

      # Signatures::Environment keys everything by RBS's fully-qualified
      # "::Name" form; the internal type model uses bare simple names
      # (Types::Nominal#name). Delegates rather than restating the rule:
      # writing it per call site is what 0.1.11 was spent undoing.
      def qualify(name)
        Index::SymbolId.qualify_owner(name)
      end
    end
  end
end
