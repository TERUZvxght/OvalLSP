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

      def initialize(workspace_index:, reference_index:)
        @workspace_index = workspace_index
        @reference_index = reference_index
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

        !(KEYWORD_WOULD_BREAK.include?(kind) && reserved_word?(name.to_s))
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
      # name already exist? Method: does the owner already declare a
      # method by that name? Everything else (local variables, ivars,
      # cvars) has no cross-symbol collision to check -- a local's own
      # scope id already keeps it from ever being confused with another
      # scope's same-named local (Task 014), and Ruby itself allows
      # redefining/reassigning an ivar/cvar freely.
      def conflicts_for(symbol_id, new_name)
        case symbol_id.kind
        when :class, :module, :constant
          constant_conflicts(symbol_id, new_name)
        when :instance_method, :singleton_method
          method_conflicts(symbol_id, new_name)
        when :local_variable
          local_conflicts(symbol_id, new_name)
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
      def local_conflicts(symbol_id, new_name)
        occupant = Index::SymbolId.new(kind: :local_variable, owner: symbol_id.owner,
                                        name: new_name, discriminator: nil)
        return [] unless @reference_index.references(occupant, minimum_confidence: :high).any?(&:write)

        [{ reason: "`#{new_name}` is already bound in this scope -- renaming onto it would capture it" }]
      end

      def constant_conflicts(symbol_id, new_name)
        namespace = symbol_id.name.to_s.sub(/[^:]+\z/, "")
        candidate_full_name = "#{namespace}#{new_name}"
        return [] unless @workspace_index.resolve_type_name(candidate_full_name) == candidate_full_name

        [{ reason: "a type named `#{candidate_full_name}` already exists" }]
      end

      def method_conflicts(symbol_id, new_name)
        existing = @workspace_index.method_symbol_ids(symbol_id.owner, kind: symbol_id.kind)
                                    .any? { |sid| sid.name == new_name }
        return [] unless existing

        [{ reason: "`#{symbol_id.owner}##{new_name}` is already declared" }]
      end
    end
  end
end
