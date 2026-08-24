# frozen_string_literal: true

module Ovallsp
  module Views
    # What instance variables a controller action leaves for its view.
    #
    # **This was 395 lines inside `Server`**, the LSP dispatch layer.
    # Measured before the move: the region touched the protocol zero
    # times -- no `@writer`, no `send_response`, no `message[:...]` --
    # and every collaborator it named was an analysis one
    # (`@local_inferencer` 9 references, `@document_store` 5,
    # `@workspace_index` 4, `@hierarchy_index` 3). Register entry
    # `024.63` says the dispatch layer owns view inference; this is that,
    # moved out (`048`).
    #
    # `file_summaries` is **`Server`'s hash, passed by reference.**
    # `Server` writes it on every index and this reads it. The first
    # version of this extraction gave the class its own empty one --
    # the "two representations of one value" shape this audit is about,
    # introduced by the change fixing it. Seven examples caught it.
    class ControllerIvars
      def initialize(document_store:, workspace_index:, hierarchy_index:, local_inferencer:,
                     parser_service:, logger:, file_summaries:)
        @document_store = document_store
        @workspace_index = workspace_index
        @hierarchy_index = hierarchy_index
        @local_inferencer = local_inferencer
        @parser_service = parser_service
        @logger = logger
        @file_summaries = file_summaries
        # This one is this class's own: it caches a helper's parsed ivar
        # names by fingerprint, and nothing else reads it.
        @helper_ivars = {}
      end

      # The one predicate this region borrowed from `Server`; both
      # callers of it are here.
      def erb_view?(uri)
        uri.end_with?(".erb")
      end

      def load_document_from_disk(uri)
        DocumentFromDisk.load(uri, logger: @logger)
      end

      # The instance variables this document is *given*, or nil when nobody
      # can say (0.2.0's unassigned-@ivar check).
      #
      # Only a view has an answer: it is handed exactly what its controller
      # action and callback chain assign, which is already computed for
      # type propagation. Everything else -- a controller, a model, a plain
      # Ruby file -- receives its ivars from wherever it likes, and nil is
      # the honest answer rather than the empty set.
      def assigned_ivars_for(uri, view_document = nil)
        return nil unless erb_view?(uri)

        context = view_action_context(uri)
        return nil unless context
        # An `instance_variable_set` anywhere in the chain assigns names
        # this cannot enumerate, so the set stops being a complete answer
        # and there is nothing safe to report against.
        documents = controller_ancestor_documents(context[:owner])
        return nil if controller_sets_ivars_dynamically?(documents)
        return nil unless whole_chain_was_read?(context[:owner], documents)
        return nil unless declared_once_each?(documents)
        return nil unless ivar_sources_fully_enumerable?(context[:owner], documents)
        return nil unless class_body_is_accounted_for?(documents)
        # A view that renders a partial receives whatever the partial
        # assigns, and this walk reads the view's own text only. Resolving
        # the partial and reading it is the precise answer and belongs with
        # the rest of 024.18; until then a render is a contributor that has
        # not been read.
        return nil if renders_something?(uri, view_document)

        method_maps = controller_method_maps(documents)
        actions = contributing_actions(documents, method_maps, context[:action], context[:view_key])
        # No action renders this view, so nothing establishes what it is
        # given. That is a different fact from "the action assigns nothing",
        # and the empty set would say the second while meaning the first.
        return nil if actions.empty?

        # The union of what the inference walk resolved and every ivar the
        # controller chain assigns *syntactically*. The walk's set is the
        # attributed one -- which action assigns what -- but it folds only
        # the statement shapes it models, and a shape it does not fold
        # arrives here as a complete-looking set with a name missing, which
        # is a warning on a view that renders (`@user ||= ...`, an
        # assignment inside `respond_to do |format|`, a `case`, a `rescue`,
        # a multiple assignment).
        #
        # Widening to the whole chain rather than to the contributing
        # action's body alone is deliberate: an ivar assigned in a sibling
        # action silences this check for this view, which is a missed
        # report. The standard here is that a missed report beats a wrong
        # one, and a name the controller never writes at all -- the typo
        # this check exists for -- is still caught.
        (ivars_for_view(uri).keys.map(&:to_s) +
         documents.flat_map { |_, document| @local_inferencer.assigned_ivar_names(document) } +
         helper_assigned_ivar_names).uniq
      rescue StandardError => e
        @logger.error("failed to compute assigned ivars for #{uri}: #{e.class}: #{e.message}")
        nil
      end

      DYNAMIC_IVAR_ASSIGNMENT = /\binstance_variable_set\b/

      # Takes the chain rather than the owner: building it re-reads and
      # re-parses every controller in it from disk, and the caller has
      # already done that.
      def controller_sets_ivars_dynamically?(documents)
        documents.any? do |_ancestor_name, document|
          document.text.match?(DYNAMIC_IVAR_ASSIGNMENT)
        end
      end

      # Whether the instance variables a view receives can be *completely*
      # enumerated (0.2.0).
      #
      # The chain builder was written for type propagation, where missing a
      # source is harmless: the ivar simply infers Unknown. Reused as the
      # input to a diagnostic, every omission becomes a wrong report on code
      # that runs -- and `around_action`, `prepend_before_action`, a
      # block-form callback and a Rails concern are not edge cases. So the
      # answer here is "no" whenever the chain contains anything this cannot
      # follow, and the check above turns that into silence.
      # `controller_ancestor_documents` drops an ancestor whose file it
      # cannot resolve, and says nothing about having done so -- so a class
      # this walk never read looks exactly like a class that assigns
      # nothing. `class UsersController < ApplicationController` analyzed
      # before the cold index reaches the parent reported the parent's
      # `@current_user` as never assigned, on a view that renders; and for a
      # controller whose parent lives outside the workspace it never stops.
      #
      # The chain from the hierarchy index is the authority on what should
      # have been read, and this is where the two are compared, because
      # nowhere else has both.
      def whole_chain_was_read?(owner_name, documents)
        # The *immediate* superclass, whatever its `kind`. One the index has
        # not seen declared arrives with `kind: nil`, which is the case that
        # matters: `controller_ancestor_documents` filters on
        # `kind == :class` and so never even tries to read it.
        #
        # Only the immediate one, because the chain does not end in the
        # workspace -- every Rails controller reaches `ActionController::Base`
        # and beyond, which no document will ever be produced for, so
        # demanding the whole chain switches the check off for every real
        # controller. A framework base does not assign the instance
        # variables a view reads; the class the user wrote `< X` against
        # does, and that is the one worth insisting on.
        # The view's own controller's immediate superclass, and only that
        # one. Applying the same rule to every class that was read is the
        # correct depth -- `UsersController < BaseController <
        # ApplicationController` with the top unread is the same failure one
        # level up, and it is not caught here -- but it cannot be told from
        # the ordinary case: the last class the workspace declares inherits
        # from a gem, which no document will ever exist for, so demanding it
        # silences every real controller. Separating "a workspace class not
        # read yet" from "a base class in a gem" is what 024.R7's index
        # provides, and 024.18 records this as waiting on it.
        parent = @hierarchy_index.ancestors(owner_name).find { |entry| entry.origin == :superclass }
        return true unless parent

        read = documents.map { |name, _| Index::SymbolId.qualify_owner(name) }
        read.include?(Index::SymbolId.qualify_owner(parent.name))
      end

      # Rails mixes every module under `app/helpers` into the view context
      # (`include_all_helpers` is on by default), so an ivar a helper
      # assigns is one the view receives. The controller walk cannot see
      # them, and no other guard notices: the controller's body is clean and
      # its ancestry carries no module.
      #
      # Every helper rather than the ones this view calls, for the same
      # reason the controller chain is taken whole -- a name assigned
      # anywhere a view can reach means "do not warn", and a name no helper
      # writes at all, which is the typo this check exists for, is still
      # caught.
      HELPER_PATH = %r{/app/helpers/}
      def helper_assigned_ivar_names
        uris = (@workspace_index.uris_by_source(:disk) + @document_store.open_documents.map(&:uri))
        uris.uniq.filter_map do |uri|
          next unless uri.match?(HELPER_PATH)

          # The index's own content hash, which costs neither a read nor a
          # parse and tracks an open buffer as well as a file on disk --
          # `didOpen` and `didChange` both re-index. This runs on the
          # dispatch thread once per `didChange`, per keystroke in a view,
          # and once per view in the workspace pass, inside the lock every
          # hover needs: reading and parsing every helper each time measured
          # 17ms on sixty of them, loading and hashing the text 5.8ms, this
          # 0.22ms.
          #
          # A version cannot be the key: it restarts at 1 every time the
          # editor opens the file, so it names a text only within one open
          # session while this cache outlives it, and a helper reopened at
          # version 1 with different content answered from the previous
          # session.
          open_document = @document_store.fetch(uri: uri)
          fingerprint = @workspace_index.summary_for_uri(uri)&.content_hash
          cached = @helper_ivars[uri]
          next cached[1] if fingerprint && cached && cached[0] == fingerprint

          document = open_document || load_document_from_disk(uri)
          next unless document

          # A failure here has to reach `#assigned_ivars_for`'s rescue,
          # which switches the check off for the view rather than checking
          # against a set that is quietly short by one file (`024.122`).
          names = @local_inferencer.assigned_ivar_names(document)
          @helper_ivars[uri] = [fingerprint, names] if fingerprint
          names
        end.flatten
      end

      # `controller_ancestor_documents` resolves each ancestor to *one* uri,
      # so a second file reopening the class is never read -- and the set
      # the check then compares against looks complete rather than partial.
      # `def show; load_user; end` in one file with `load_user` assigning in
      # another produced a warning on a view that renders.
      def declared_once_each?(documents)
        documents.all? { |name, _| @workspace_index.class_declaration_uris(name).size <= 1 }
      end

      # The class-level declarations this analysis accounts for. Everything
      # else in a controller's class body is a call whose effect it has not
      # read -- and a gem's macro is the ordinary case: CanCanCan's
      # `load_and_authorize_resource`, `expose`, Devise and ActiveAdmin all
      # install a callback that assigns at runtime, none of it visible to a
      # walk over `def` bodies.
      #
      # A whitelist rather than a blacklist, because the failure direction
      # matters: a name nobody thought of has to mean "stay silent", not
      # "assume harmless". `private`/`protected`/`public` and the callback
      # forms the chain builder reads are the ones accounted for by
      # construction.
      #
      # This is the blunt form of the question. 024.R7 lets the index
      # attribute a class-body call to the gem that defines it, at which
      # point this narrows to the calls still unaccounted for -- which
      # *widens* the check rather than changing an answer it gives today.
      MODELLED_CLASS_BODY_CALLS = %w[
        private protected public
        before_action skip_before_action
      ].freeze

      # Any `render` in the template's own Ruby regions. Deliberately not
      # only the partial forms: `render` with a non-literal target is
      # exactly the case that cannot be resolved later either.
      def renders_something?(view_uri, view_document = nil)
        document = view_document || @document_store.fetch(uri: view_uri) || load_document_from_disk(view_uri)
        return false unless document

        Erb::RubyRegionExtractor.extract_ruby_source(document.text).match?(/(?:\A|[^\w.:])render\b/)
      rescue StandardError
        true
      end

      def class_body_is_accounted_for?(documents)
        documents.all? do |ancestor_name, document|
          (@local_inferencer.class_body_call_names(document, owner_name: Index::SymbolId.qualify_owner(ancestor_name)) -
            MODELLED_CLASS_BODY_CALLS).empty?
        end
      end

      def ivar_sources_fully_enumerable?(owner_name, documents)
        # `:default` entries are Object/Kernel/BasicObject, which every
        # class has and none of which assigns a controller's ivars. What
        # matters is a module the workspace mixes in, whose methods
        # `controller_ancestor_documents` does not walk.
        mixed_in = @hierarchy_index.ancestors(owner_name).any? do |entry|
          %i[include extend prepend].include?(entry.origin)
        end
        !mixed_in
      end

      # No caching here by design: recomputed fresh from the controller's
      # *current* text on every call, so an edited action's ivar types are
      # immediately reflected — there's no stale view context to invalidate
      # (docs/design/tasks/008-controller-view-propagation.md "action変更時に
      # view contextをinvalidate"). Returns {} (-> Unknown for every @ivar)
      # when the view doesn't match the app/views/<controller>/<action>.*.erb
      # convention or its controller can't be found.
      def ivars_for_view(view_uri)
        context = view_action_context(view_uri)
        return {} unless context

        controller_document = @document_store.fetch(uri: context[:controller_uri]) ||
                               load_document_from_disk(context[:controller_uri])
        return {} unless controller_document

        documents = controller_ancestor_documents(context[:owner])
        method_maps = controller_method_maps(documents)
        environments = contributing_actions(documents, method_maps, context[:action], context[:view_key]).map do |action_name|
          infer_controller_action_ivars(
            context[:owner], action_name, documents: documents, method_maps: method_maps
          )
        end
        merge_alternative_ivar_environments(environments)
      end

      # Rails inherits callback declarations. Build the effective callback
      # chain from the oldest controller superclass to the concrete
      # controller, applying skip_before_action in declaration order. Each
      # callback method itself follows normal Ruby lookup from child to
      # parent, so an override is evaluated exactly once.
      def infer_controller_action_ivars(owner_name, action_name, documents: controller_ancestor_documents(owner_name),
                                        method_maps: controller_method_maps(documents))
        operations = documents.reverse.flat_map do |ancestor_name, document|
          @local_inferencer.before_action_operations(
            document, owner_name: ancestor_name, action_name: action_name
          )
        end
        callbacks = operations.each_with_object([]) do |(verb, name), names|
          verb == :add ? names << name : names.delete(name)
        end

        @local_inferencer.begin_ivar_inference
        env = callbacks.reduce({}) do |callback_env, callback_name|
          declaration = documents.find { |ancestor_name, _document| method_maps[ancestor_name].key?(callback_name) }
          next callback_env unless declaration

          ancestor_name, = declaration
          @local_inferencer.infer_ivars_for_method_node(
            method_maps[ancestor_name][callback_name], initial_env: callback_env,
            self_type_name: owner_name, reset_budget: false
          )
        end

        action_declaration = documents.find { |ancestor_name, _document| method_maps[ancestor_name].key?(action_name) }
        return env unless action_declaration

        ancestor_name, = action_declaration
        @local_inferencer.infer_ivars_for_method_node(
          method_maps[ancestor_name][action_name], initial_env: env, self_type_name: owner_name, reset_budget: false
        )
      end

      def controller_ancestor_documents(owner_name)
        ancestors = @hierarchy_index.ancestors(owner_name).select do |entry|
          entry.kind == :class && %i[self superclass].include?(entry.origin)
        end
        names = ([owner_name] + ancestors.map(&:name)).uniq
        names.filter_map do |name|
          uri = find_controller_uri(name)
          document = uri && (@document_store.fetch(uri: uri) || load_document_from_disk(uri))
          [name, document] if document
        end
      end

      def controller_method_maps(documents)
        documents.to_h do |ancestor_name, document|
          [ancestor_name, @local_inferencer.method_nodes(document, owner_name: ancestor_name)]
        end
      end

      def merge_alternative_ivar_environments(environments)
        return {} if environments.empty?

        environments.reduce do |left, right|
          (left.keys | right.keys).to_h do |name|
            [name, Types.normalize_union([left.fetch(name, Types::NIL), right.fetch(name, Types::NIL)])]
          end
        end
      end

      VIEW_PATH_PATTERN = %r{app/views/(?<dir>.+)/(?<action>[^/.]+)\.[^/]*\.erb\z}

      def view_action_context(view_uri)
        path = UriUtil.to_path(view_uri) || view_uri
        match = VIEW_PATH_PATTERN.match(path)
        return nil unless match

        owner = Routes::ControllerNaming.owner_name(match[:dir])
        return nil unless owner

        controller_uri = find_controller_uri(owner)
        return nil unless controller_uri

        { owner: owner, action: match[:action], view_key: "#{match[:dir]}/#{match[:action]}", controller_uri: controller_uri }
      end

      # Looked up by qualified *name*, never by a reconstructed SymbolId.
      # `owner` is recorded lexically, so one class has as many SymbolIds as
      # there are ways to spell it -- `module Api; module V1; class
      # UsersController`, `class Api::V1::UsersController`, and the partly
      # compact `module Api; class V1::UsersController` are three different
      # keys. Any owner-derived lookup matches some and misses the rest, and
      # a miss silently stops a whole controller's ivars from reaching its
      # views; enumerating candidate owners only moves which spelling
      # breaks. The name is already fully qualified and unique, so asking by
      # it answers every shape at once.
      # The `::` normalisation this used to do by hand now lives in
      # `class_declaration_uris` itself, where every caller gets it and a
      # test can see the difference — measured: both of this method's own
      # callers already pass a qualified name, so the hand-written copy
      # could not change any answer and nothing could ever have pinned it
      # (0.1.12, round 5).
      def find_controller_uri(owner_name)
        @workspace_index.class_declaration_uris(owner_name).first
      end

      # An action contributes its ivars to this view if it either *is* the
      # view's own action, or explicitly `render`s it — propagating e.g. a
      # failed #update's ivars into "edit.html.erb"
      # (docs/design/tasks/008-controller-view-propagation.md "render :edit
      # 先へ伝播").
      def contributing_actions(documents, method_maps, view_action, view_key)
        effective_visibilities = {}
        documents.each do |ancestor_name, document|
          summary = @file_summaries[document.uri] || @parser_service.summarize(document)
          canonical_owner = Index::SymbolId.qualify_owner(ancestor_name)
          owner_visibilities = {}
          summary.declarations.each do |declaration|
            symbol = declaration.symbol_id
            next unless symbol.kind == :instance_method
            next unless symbol.owner == canonical_owner
            next unless method_maps.fetch(ancestor_name).key?(symbol.name)

            owner_visibilities[symbol.name] = declaration.visibility
          end
          # Documents are child-first. The first declaration reached for a
          # name is therefore Ruby's effective override; a private child
          # method must hide a public action inherited from its parent.
          owner_visibilities.each { |name, visibility| effective_visibilities[name] ||= visibility }
        end
        action_names = effective_visibilities.filter_map { |name, visibility| name if visibility == :public }

        action_names.select do |action_name|
          next true if action_name == view_action

          declaration = documents.find { |ancestor_name, _document| method_maps[ancestor_name].key?(action_name) }
          next false unless declaration

          ancestor_name, = declaration
          target = @local_inferencer.static_render_target_for_node(method_maps[ancestor_name][action_name])
          target && (target.include?("/") ? target.delete_prefix("/") == view_key : target == view_action)
        end
      end
    end
  end
end
