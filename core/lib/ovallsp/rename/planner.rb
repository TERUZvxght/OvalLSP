# frozen_string_literal: true

require_relative "plan"

module Ovallsp
  module Rename
    # Turns a resolved SymbolId into a Rename::Plan
    # (docs/design/tasks/016-guarded-rename.md).
    #
    # Every edit location comes from exactly two places: WorkspaceIndex's
    # own declarations for `symbol_id` (the `def`/`class`/`@ivar =`
    # site(s)) and Semantic::ReferenceIndex's high-confidence-only
    # references for it (Task 014's #references defaults to
    # `minimum_confidence: :high` for exactly this reason -- a Union-
    # receiver call that only *might* be this method never gets edited).
    # Because both are keyed by SymbolId, an override of the same method
    # name on a *different* class has its own distinct SymbolId and is
    # never touched -- "override chain全体のrenameは初期版では明示選択また
    # は拒否する" is satisfied structurally, by construction, rather than
    # needing its own detection pass: there is no code path that could
    # ever reach a different symbol_id's locations in the first place.
    class Planner
      REFUSED_KINDS = %i[route_helper active_record_column active_record_association].freeze

      IDENTIFIER_PATTERNS = {
        local_variable: /\A[a-z_][a-zA-Z0-9_]*\z/,
        instance_method: /\A[a-z_][a-zA-Z0-9_]*[?!=]?\z/,
        singleton_method: /\A[a-z_][a-zA-Z0-9_]*[?!=]?\z/,
        ivar: /\A@[a-zA-Z_][a-zA-Z0-9_]*\z/,
        cvar: /\A@@[a-zA-Z_][a-zA-Z0-9_]*\z/,
        class: /\A[A-Z][a-zA-Z0-9_]*\z/,
        module: /\A[A-Z][a-zA-Z0-9_]*\z/,
        constant: /\A[A-Z][a-zA-Z0-9_]*\z/
      }.freeze

      def initialize(workspace_index:, reference_index:, hierarchy_index: nil)
        @workspace_index = workspace_index
        @reference_index = reference_index
        # Optional so a caller that only plans constant or binding renames
        # need not assemble one; `nil` keeps the owner-only answer, which
        # is what shipped before `024.326`.
        @hierarchy_index = hierarchy_index
      end

      # LSP `textDocument/prepareRename`'s answer: is this symbol
      # renameable at all, and what should the editor pre-fill as the
      # placeholder? nil means "refuse to even start" (nothing found, or
      # a generated/DSL-origin symbol).
      def prepare(symbol_id)
        return nil unless symbol_id
        return nil if symbol_refusal(symbol_id)
        return nil if locations_for(symbol_id).empty?

        { placeholder: simple_name(symbol_id) }
      end

      # **The reasons `prepare` and `plan` must agree about**, in one
      # place because keeping two lists in step is what failed:
      # `024.273` added a third refusal to `plan` and not to `prepare`,
      # so the editor opened its input box for a keyword parameter and
      # the rename that followed answered nothing. A fourth reason
      # cannot now be added to only one of them.
      #
      # `nil`, or the sentence a user is owed.
      def symbol_refusal(symbol_id)
        if REFUSED_KINDS.include?(symbol_id.kind)
          return "`#{simple_name(symbol_id)}` is a generated Rails method (#{symbol_id.kind}) -- " \
                 "rename its source declaration (the association/column, or the route) instead; " \
                 "the call sites are never edited directly here"
        end

        if binding_site_unknown?(symbol_id)
          return "`#{simple_name(symbol_id)}` is a local whose binding site this engine does not record -- a " \
                 "keyword parameter (`def m(by:)`), a hash pattern's shorthand (`in {a:}`), or a numbered " \
                 "block parameter (`_1`). Rewriting the occurrences it can see would leave the binding " \
                 "behind and hand back a file that raises NameError, so nothing is edited here"
        end

        return nil unless (declaration = uneditable_declaration(symbol_id))

        position = declaration.name_location || declaration.location
        "`#{simple_name(symbol_id)}` is declared by a macro rather than by a `def`, at " \
          "#{position[:start][:line] + 1}:#{position[:start][:character] + 1}. That argument is source the " \
          "macro reads, so rewriting it is not the same edit as renaming this method -- the same token also " \
          "spells the ivar an `attr_*` reads, the second method `attr_accessor` declares, the label an " \
          "`enum` uses for its scope and its stored mapping, or the method a `delegate` calls on its " \
          "target. Nothing is edited here: change the macro and its call sites by hand, or write the " \
          "method as a `def`, which this does rename"
      end

      # **A macro's argument is not this method's name, even now that the
      # declaration points at it.** Until `024.27` a generated declaration
      # carried no `name_location`, so `locations_for` dropped it -- and
      # dropping it silently is what turned a rename into a WorkspaceEdit
      # that rewrote every call site and left the declaration behind,
      # producing a file that does not run. That is fixed: the declaration
      # now carries the token's own range.
      #
      # Refusing still is, and the reason is the one below rather than
      # "there is nothing to rewrite" (024.28). The token is source the
      # macro *reads*, and in every macro this parser recognises it spells
      # more than the method being renamed:
      #
      #   - `attr_reader :name` reads `@name`. Rewriting the token to
      #     `:title` makes the reader return `@title`, which nothing in
      #     the class assigns -- a file that still runs and answers nil.
      #   - `attr_accessor :name` declares `name` *and* `name=` from one
      #     token, so one edit renames two methods while the plan holds
      #     one symbol's call sites. The other method's callers break.
      #   - `enum status: { active: 0 }` -- `active` is the *label*, not
      #     the stored value; the column holds `0`. The same label is
      #     also the scope `Order.active`, the key in `Order.statuses`
      #     and what the attribute reads back, so rewriting it renames
      #     three things besides the predicate. Driven against
      #     activerecord 8.1.3.1 in `024.28`.
      #   - `delegate :name, to: :company` calls `company.name`. The token
      #     names the *target's* method, and renaming this method must not
      #     touch it: rewriting it makes the delegation call a method the
      #     target does not have.
      #
      # An earlier version of the bullet above added "and under
      # `prefix: true` it is not even a substring of the generated name",
      # which is false -- `prefix:` prepends, so the token is always the
      # tail. It was written as prose and believed for a review round.
      # Asked of Ruby instead, which is why it is a session:
      #
      #   $ ruby -e '
      #   gem "activesupport"
      #   require "active_support/all"
      #   class Company; def name = "acme"; end
      #   class Order
      #     def company = Company.new
      #     delegate :name, to: :company, prefix: true
      #   end
      #   p Order.instance_methods(false).sort
      #   p "company_name".include?("name")
      #   '
      #   # => [:company, :company_name]
      #   # => true
      #   # ruby 3.4.10, activesupport 8.1.3.1
      #
      # `scope` and `define_method` are the two shapes where the token is
      # exactly the name and nothing else depends on its spelling, and
      # they are refused with the rest because nothing here can tell them
      # apart: `Declaration#origin` says `:generated` and stops there.
      # Separating them is the direction 024.28 records, not a special
      # case to bolt on.
      #
      # The reason reaches the log, not the user: `prepare` answers nil,
      # so the editor shows its own message and never asks for the edit.
      #
      # Keyed on `origin: :generated`, not on a missing `name_location`.
      # A declaration synthesised rather than parsed -- registered by
      # something outside this parser, at a location no file has -- has no
      # `name_location` either, and if that were the key, a synthetic
      # registration of a name the workspace also writes with a real `def`
      # would disable rename for a method that does have an identifier to
      # edit, refusing with a message naming a macro and a position that
      # is not in any file. `origin` says which of the two it is; the
      # absent field does not. (The plugin subsystem was that source until
      # `024.234` removed it in 0.2.16; the argument is about the shape,
      # which is why it survives its example.)
      def uneditable_declaration(symbol_id)
        @workspace_index.declarations_with_uri(symbol_id)
                        .map { |(_uri, declaration)| declaration }
                        .find { |declaration| declaration.origin == :generated }
      end

      def plan(symbol_id, new_name:, generation:)
        return Plan.new(target: nil, generation: generation) unless symbol_id

        if (reason = symbol_refusal(symbol_id))
          return refused_plan(symbol_id, generation, reason)
        end

        unless valid_identifier?(symbol_id.kind, new_name)
          return refused_plan(symbol_id, generation, "`#{new_name}` is not a valid #{symbol_id.kind} name")
        end

        conflicts = conflicts_for(symbol_id, new_name)
        return conflicted_plan(symbol_id, conflicts, generation) unless conflicts.empty?

        edits = locations_for(symbol_id).map do |(uri, range, implicit_hash_value)|
          { uri: uri, range: range, new_text: edit_text(symbol_id, new_name, implicit_hash_value) }
        end
        Plan.new(target: symbol_id, confirmed_edits: edits, generation: generation)
      end

      private

      def refused_plan(symbol_id, generation, warning)
        Plan.new(target: symbol_id, confirmed_edits: [], warnings: [warning], generation: generation)
      end

      def conflicted_plan(symbol_id, conflicts, generation)
        Plan.new(
          target: symbol_id, confirmed_edits: [], conflicts: conflicts,
          warnings: ["rename refused: #{conflicts.map { |c| c[:reason] }.join('; ')}"], generation: generation
        )
      end

      # `decl.name_location`, never `decl.location` -- the latter spans
      # the *whole* declaration (`class Foo\n...\nend`), which as an edit
      # range would replace an entire class/method body with just the
      # new name instead of renaming the identifier.
      def locations_for(symbol_id)
        decl_locations = @workspace_index.declarations_with_uri(symbol_id)
                                          .filter_map do |(uri, decl)|
          [uri, decl.name_location, false] if decl.name_location
        end
        ref_locations = @reference_index.references(symbol_id, minimum_confidence: :high)
                                         .map { |r| [r.uri, r.location, r.implicit_hash_value] }
        (decl_locations + ref_locations).uniq
      end

      # **Ruby's `{ name: }` / `take(name:)` shorthand is one token doing
      # two jobs**, and `Reference#location` covers all of it because
      # there is no sub-range that is only the value. Substituting the
      # new name over it deletes the colon -- a hash literal becomes a
      # syntax error, a keyword argument becomes positional -- and
      # trimming the range to the identifier instead rewrites the *key*,
      # which is a symbol in the hash and the callee's parameter name in
      # the call. Neither is a rename of the local. Writing the key back
      # out with the new name after it is:
      #
      #   $ ruby -e '
      #   def take(name:) = name
      #   label = "n"
      #   p({ name: label })
      #   p take(name: label)
      #   '
      #   # => {name: "n"}
      #   # => "n"
      #   # ruby 3.4.10
      #
      # The key is `simple_name(symbol_id)` rather than anything read
      # back from the file, because the shorthand exists only where the
      # two are the same word -- Ruby has no spelling of it where they
      # differ.
      def edit_text(symbol_id, new_name, implicit_hash_value)
        return new_name unless implicit_hash_value

        "#{simple_name(symbol_id)}: #{new_name}"
      end

      # **Do I know where this local is bound?** Every binding form the
      # parser records is recorded as a *write*, so a local with no write
      # among its occurrences has a binding site this engine cannot see.
      #
      # The one that reaches here today is a keyword parameter, left
      # unrecorded on purpose -- `def m(by:)` binds a local named `by`
      # *because* the keyword is `by`, and Ruby has no spelling that
      # separates them, so renaming the local is renaming the interface.
      # `024.273`.
      #
      # Asked as "is the binding site known" rather than "is this a
      # keyword parameter": the register argued that an occurrence
      # nothing records is one nothing can miss, which is true of the
      # occurrence and false of the *count*. Any binding form added to
      # the parser later is refused here until it is recorded, rather
      # than half-rewritten.
      def binding_site_unknown?(symbol_id)
        return false unless symbol_id.kind == :local_variable

        # **A pattern binds it and the occurrence list does not carry
        # that.** The test below asks whether *any* occurrence is a
        # write, which an ordinary `_a = 0` in the same scope satisfies —
        # so before `024.296` the refusal did not fire and the rename
        # went ahead on what it could see, leaving `in [_a, 1]` bound to
        # the old name while the body read the new one. The file parses
        # and runs, and answers 0 where it answered 5.
        return true if @workspace_index.pattern_bound_name?(simple_name(symbol_id))

        references = @reference_index.references(symbol_id, minimum_confidence: :high)
        references.any? && references.none?(&:write)
      end

      def simple_name(symbol_id)
        symbol_id.name.to_s.split("::").last
      end

      # **The kinds a Ruby keyword breaks.** This was `:local_variable`
      # alone, so `end`, `if` and `class` were accepted as a *method's*
      # new name and the rewritten call sites did not parse.
      #
      # The definition survives -- `def end` is legal Ruby -- and the
      # receiverless call does not, which is exactly what a rename
      # produces, since it rewrites the declaration and every reference
      # including the bare ones:
      #
      #   $ ruby -e 'begin; eval(%q{class Z; def if; 1; end; def go; if; end; end}); puts "legal"; rescue SyntaxError; puts "SyntaxError"; end'
      #   # => SyntaxError
      #   # ruby 3.4.10
      #
      # Constants, classes and modules are absent deliberately rather
      # than forgotten: their patterns require a leading capital and
      # every Ruby keyword is lower case, so no keyword can reach them.
      # `@ivar` and `@@cvar` carry a sigil for the same reason.
      KEYWORD_WOULD_BREAK = %i[local_variable instance_method singleton_method].freeze

      def valid_identifier?(kind, name)
        pattern = IDENTIFIER_PATTERNS[kind]
        return true unless pattern
        return false unless pattern.match?(name.to_s)

        return true unless KEYWORD_WOULD_BREAK.include?(kind)
        return !reserved_word?(name.to_s) if kind == :local_variable

        usable_as_a_bare_call?(name.to_s)
      end

      # **A method's name and a local's are different grammars**, and one
      # question was asked for both. `#reserved_word?` below tests whether
      # the name can be *assigned to*, which `world!` and `world?` cannot
      # -- so the commonest naming convention in Ruby was refused as
      # though it were `end`. Found by the 2026-09-05 critical review, R08.
      #
      # The question a method rename actually asks is the one
      # `KEYWORD_WOULD_BREAK`'s own comment states: a rename rewrites the
      # definition *and* every reference, bare ones included, so the new
      # name has to work as a receiverless call.
      #
      #   $ ruby -rprism -e '
      #   %w[world world! world? nil self if end].each do |n|
      #     r = Prism.parse(n)
      #     node = r.success? ? r.value.statements&.body&.first : nil
      #     puts format("%-7s parse=%-5s node=%s", n, r.success?,
      #                 node ? node.class.name.split("::").last : "-")
      #   end
      #   '
      #   # => world   parse=true  node=CallNode
      #   #    world!  parse=true  node=CallNode
      #   #    world?  parse=true  node=CallNode
      #   #    nil     parse=true  node=NilNode
      #   #    self    parse=true  node=SelfNode
      #   #    if      parse=false node=-
      #   #    end     parse=false node=-
      #   # ruby 3.4.10, prism 1.9.0
      #
      # **Parsing is not enough**, which is the half a success check alone
      # would miss: `nil` and `self` parse and are not calls, so a method
      # renamed to either would break every call site while the file still
      # parsed. The node has to *be* a receiverless call of that name --
      # the structure, not just the absence of an error.
      #
      # `world=` fails this, and keeps failing it: a setter rename has to
      # answer for arity and call syntax too, which is its own decision
      # and not one this method should make by accident.
      def usable_as_a_bare_call?(name)
        result = Prism.parse(name)
        return false unless result.success?

        node = result.value.statements&.body
        return false unless node&.length == 1

        call = node.first
        call.is_a?(Prism::CallNode) && call.receiver.nil? && call.name.to_s == name
      end

      # **Every Ruby keyword matched the local pattern**, so `end`,
      # `class`, `nil` and `self` were all accepted and the applied file
      # did not parse:
      #
      #   $ ruby -e '
      #   %w[beta end class nil self].each do |name|
      #     begin
      #       eval("#{name} = 1")
      #       puts "legal"
      #     rescue SyntaxError
      #       puts "SyntaxError"
      #     end
      #   end
      #   '
      #   # => legal
      #   # => SyntaxError
      #   # => SyntaxError
      #   # => SyntaxError
      #   # => SyntaxError
      #   # ruby 3.4.10
      #
      # Asked of the parser rather than typed out as a list, so it
      # cannot go stale: a keyword is exactly a name no assignment can
      # bind. `name` has already matched the local pattern here, so it
      # is a bare lowercase word and nothing else.
      def reserved_word?(name)
        !Prism.parse("#{name} = nil").success?
      end

      # Constant/class/module: does a type by the renamed fully-qualified
      # name already exist? Method: does the owner, or anything it
      # inherits from, already declare a method by that name? A binding
      # -- local, `@ivar` or `@@cvar` -- is asked whether the new name is
      # already written on the same owner.
      #
      # **The `else` branch used to take ivars and cvars**, on the
      # reasoning that "Ruby itself allows reassigning an ivar freely".
      # It does, and that is not the question a rename asks: merging two
      # variables into one is legal Ruby that answers differently.
      #
      #   $ ruby -e 'class W; def go; @a=1; @b=2; @a+@b; end; end; p W.new.go'
      #   # => 3
      #   # ruby 3.4.10
      #
      #   $ ruby -e 'class W; def go; @b=1; @b=2; @b+@b; end; end; p W.new.go'
      #   # => 4
      #   # ruby 3.4.10
      #
      # The same paragraph also said locals have no collision to check
      # while the code beneath it sent them to a collision check, which
      # is how the ivar half went un-revisited when 0.3.0 corrected the
      # local one.
      def conflicts_for(symbol_id, new_name)
        case symbol_id.kind
        when :class, :module, :constant
          constant_conflicts(symbol_id, new_name)
        when :instance_method, :singleton_method
          method_conflicts(symbol_id, new_name)
        when :local_variable, :ivar, :cvar
          binding_conflicts(symbol_id, new_name)
        else
          []
        end
      end

      # **Renaming one binding onto another captures it silently**, and
      # Ruby refuses the result outright:
      #
      #   $ ruby -e '
      #   begin
      #     eval("def f(b, b); [b]; end")
      #     puts "legal"
      #   rescue SyntaxError
      #     puts "SyntaxError"
      #   end
      #   '
      #   # => SyntaxError
      #   # ruby 3.4.10
      #
      # A local's `owner` already carries its file, its enclosing owner
      # and its scope id, so the same owner *is* "the same scope" --
      # which is the whole check. Reachable in 0.3.0 because recording a
      # parameter's own binding site is what makes rename rewrite the
      # declaration.
      # `kind: symbol_id.kind`, not a hard-coded `:local_variable`: the
      # same question is the right one for an `@ivar` and a `@@cvar`, and
      # asking it under the wrong kind found nothing.
      def binding_conflicts(symbol_id, new_name)
        occupant = Index::SymbolId.new(kind: symbol_id.kind, owner: symbol_id.owner,
                                        name: new_name, discriminator: nil)
        return same_scope_conflict(new_name) if @reference_index.references(occupant, minimum_confidence: :high).any?(&:write)
        return [] unless symbol_id.kind == :local_variable

        elsewhere_in_file(symbol_id, new_name)
      end

      def same_scope_conflict(new_name)
        [{ reason: "`#{new_name}` is already bound in this scope -- renaming onto it would capture it" }]
      end

      # **A local is captured by a binding in a scope it does not own.**
      # `symbol_id.owner` carries the scope id, so the check above sees
      # only the target's own frame -- and a block parameter in a nested
      # scope the target is still visible in captures it, with the file
      # still parsing:
      #
      #   $ ruby -e 'def go; total=0; [1,2].each { |x| total += x }; total; end; p go'
      #   # => 3
      #   # ruby 3.4.10
      #
      #   $ ruby -e 'def go; x=0; [1,2].each { |x| x += x }; x; end; p go'
      #   # => 0
      #   # ruby 3.4.10
      #
      # A receiverless call with no arguments is the same shape from the
      # other side -- the call becomes a read of the local:
      #
      #   $ ruby -e 'class W; def helper; 99; end; def go; total=0; total+helper; end; end; p W.new.go'
      #   # => 99
      #   # ruby 3.4.10
      #
      #   $ ruby -e 'class W; def helper; 99; end; def go; helper=0; helper+helper; end; end; p W.new.go'
      #   # => 0
      #   # ruby 3.4.10
      #
      # **The enclosing `def`, not the file.** Written file-wide first, on
      # the reasoning that a scope id carries no nesting so the file is
      # the only computable unit. Measured over 120 activesupport files,
      # renaming each `def`'s first local onto a local a *different* `def`
      # binds -- which Ruby accepts every time -- it refused **32 of 32**.
      # Rename refuses mutely, so that was the feature silently doing
      # nothing. A `def`'s declaration spans its whole body, which the
      # index already records, and a binding outside it cannot capture
      # anything inside it.
      def elsewhere_in_file(symbol_id, new_name)
        # `SymbolId#initialize` qualifies every owner, so the recorded
        # value is `::<uri>\0<owner>#<scope>` and the leading `::` comes
        # off before the uri is readable.
        uri = symbol_id.owner.to_s.delete_prefix("::").split("\u0000", 2).first
        return [] if uri.to_s.empty?

        summary = @workspace_index.summary_for_uri(uri)
        range = enclosing_body(summary, symbol_id)
        return [] unless range

        occupied = summary.reference_candidates.any? do |candidate|
          within?(range, candidate.location) && binds_or_shadows?(candidate, new_name)
        end
        return [] unless occupied

        [{ reason: "`#{new_name}` already means something in this method -- renaming onto it would change what the code does" }]
      end

      # The `def` whose body contains the target's own occurrences. `nil`
      # when the target is not inside one -- a top-level local, or a file
      # whose summary has gone -- and `nil` declines rather than guessing
      # at a range.
      def enclosing_body(summary, symbol_id)
        return nil unless summary

        occurrences = @reference_index.references(symbol_id, minimum_confidence: :high).map(&:location)
        return nil if occurrences.empty?

        summary.declarations
               .select { |declaration| %i[instance_method singleton_method].include?(declaration.symbol_id.kind) }
               .find { |declaration| occurrences.all? { |at| within?(declaration.location, at) } }
               &.location
      end

      def within?(range, at)
        return false unless range && at

        start_at = range[:start]
        end_at = range[:end]
        line = at[:start][:line]
        return false if line < start_at[:line] || line > end_at[:line]
        return false if line == start_at[:line] && at[:start][:character] < start_at[:character]
        return false if line == end_at[:line] && at[:start][:character] > end_at[:character]

        true
      end

      # A binding written in this body, or a call written with **no
      # receiver and no arguments** -- the only call shape a local of the
      # same name shadows. `helper(1)` stays a call however the local is
      # named, so refusing it would be the rule reaching past what it is
      # for.
      #
      # Read from the parser's candidates rather than the resolved
      # references, because "written without a receiver" is a fact about
      # the source and the resolved form has lost it: a receiverless call
      # still carries the inferred `self` type in `receiver_type`, so
      # asking that question there answered `false` for every call.
      def binds_or_shadows?(candidate, new_name)
        return false unless candidate.name.to_s == new_name

        case candidate.kind
        when :local_variable then !candidate.write.nil? && candidate.write
        when :method_call then candidate.receiver.nil? && no_arguments?(candidate)
        else false
        end
      end

      def no_arguments?(candidate)
        arguments = candidate.arguments
        return true unless arguments

        # `keywords`, `splat` and `block` are booleans here, not lists --
        # taken from the parser's own shape rather than assumed:
        # `{positional: 0, positional_locations: [], splat: false,
        # keywords: false, block: false}`.
        arguments[:positional].to_i.zero? && !arguments[:keywords] && !arguments[:splat] && !arguments[:block]
      end

      def constant_conflicts(symbol_id, new_name)
        namespace = symbol_id.name.to_s.sub(/[^:]+\z/, "")
        candidate_full_name = "#{namespace}#{new_name}"
        return [] unless @workspace_index.resolve_type_name(candidate_full_name) == candidate_full_name

        [{ reason: "a type named `#{candidate_full_name}` already exists" }]
      end

      # **The owner is not the whole answer.** This asked only whether the
      # renamed method's own class declares the new name, so a name an
      # ancestor declares was invisible and the rename silently began
      # overriding it:
      #
      #   $ ruby -e 'class B; def shared; "base"; end; end; class C < B; def own; "own"; end; end; p [C.new.shared, C.new.own]'
      #   # => ["base", "own"]
      #   # ruby 3.4.10
      #
      #   $ ruby -e 'class B; def shared; "base"; end; end; class C < B; def shared; "own"; end; end; p C.new.shared'
      #   # => "own"
      #   # ruby 3.4.10
      #
      # The chain is walked rather than the superclass alone, so an
      # included module counts too. An unidentified entry is skipped for
      # the reason `024.80` gives: there is no owner to look a
      # declaration up under, and a miss computed from a chain with a
      # hole in it is not evidence of anything.
      def method_conflicts(symbol_id, new_name)
        override = override_binding(symbol_id)
        return override if override.any?

        owners = [symbol_id.owner] + inherited_owners(symbol_id.owner)
        owner = owners.uniq.find do |candidate|
          @workspace_index.method_symbol_ids(candidate, kind: symbol_id.kind).any? { |sid| sid.name == new_name }
        end
        return [] unless owner

        return [{ reason: "`#{owner}##{new_name}` is already declared" }] if owner == symbol_id.owner

        [{ reason: "`#{new_name}` is already declared by `#{owner}`, which `#{symbol_id.owner}` inherits from -- " \
                   "renaming onto it would override it" }]
      end

      # **The name is what binds an override, and renaming one end breaks
      # it.** This file's own header argued that leaving an override alone
      # is the safe boundary, because an override has a different
      # SymbolId. It is not:
      #
      #   $ ruby -e '
      #   class Parent2; def world = 1; end
      #   class Child2 < Parent2; def hello = super + 1; end
      #   begin; Child2.new.hello; rescue NoMethodError => e; puts e.message; end
      #   '
      #   # => super: no superclass method 'hello' for an instance of Child2
      #   # ruby 3.4.10
      #
      # That is the tree this planner produced: `Parent#hello` renamed to
      # `world`, the override correctly left alone, and the program
      # stopped working. From the other end it is quieter and no better --
      # renaming `Child#hello` makes `Child.new.hello` reach the parent's
      # instead of raising.
      #
      # **Refused rather than extended.** Rewriting every same-named
      # method on the chain is a different operation: it would have to
      # decide about ancestors outside the index, about a `super` in a
      # third class, and about dynamic sends -- and `042`'s D1, resolution
      # that answers a name *and its basis*, is what a fix that resolves
      # rather than refuses would be built on. Refusing returns no edits
      # at all, which is the contract `#plan`'s callers already handle.
      # Found by the 2026-09-05 critical review, R02.
      #
      # Both directions from one question: an owner that declares this
      # same name and is on a chain with this one, whichever way round.
      # `include` counts as much as a superclass -- it is the same chain.
      def override_binding(symbol_id)
        return [] unless @hierarchy_index && %i[instance_method singleton_method].include?(symbol_id.kind)

        owner = symbol_id.owner.to_s
        related = @workspace_index.method_owners(symbol_id.name, kind: symbol_id.kind)
                                  .reject { |candidate| candidate == owner }
                                  .find { |candidate| chain_relates?(owner, candidate) }
        return [] unless related

        [{ reason: "`#{symbol_id.name}` is declared by both `#{owner}` and `#{related}`, which share an " \
                   "ancestor chain -- renaming one end of an override changes what the other overrides" }]
      end

      # **Both sides qualified.** `WorkspaceIndex#method_owners` answers
      # with stored owners, which are qualified (`::Object`), and
      # `HierarchyIndex#ancestors` names its entries bare (`Object`) --
      # so a workspace `class Object; def blank?` was never seen as the
      # other end of an override, which is exactly the case this file's
      # own comment says `Object`/`Kernel`/`BasicObject` are left in the
      # chain for. Found by cold review.
      def chain_relates?(owner, other)
        wanted = Index::SymbolId.qualify_owner(other)
        mine = Index::SymbolId.qualify_owner(owner)
        qualified_owners(owner).include?(wanted) || qualified_owners(other).include?(mine)
      end

      def qualified_owners(owner)
        inherited_owners(owner).map { |name| Index::SymbolId.qualify_owner(name) }
      end

      # `[]` without a hierarchy index, which is the owner-only answer
      # this had before. `Object`, `Kernel` and `BasicObject` are left in:
      # a workspace method named after one of theirs really would override
      # it, which is the thing being refused.
      def inherited_owners(owner)
        return [] unless @hierarchy_index && owner

        @hierarchy_index.ancestors(owner).select(&:identified?).map(&:name).reject { |name| name == owner }
      rescue StandardError
        []
      end
    end
  end
end
