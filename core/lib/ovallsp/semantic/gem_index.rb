# frozen_string_literal: true

module Ovallsp
  module Semantic
    # What the gems define, as the running application reported it.
    #
    # `024.R7`. The undefined-method check fires only on a *closed*
    # receiver, and until 0.3.0 "closed" meant "the workspace can see the
    # whole ancestry". In a Rails application that is a minority of
    # classes -- a controller inherits from `ApplicationController`,
    # whose parent is in a gem -- so the check worked where it was least
    # needed and stayed silent where most code is written.
    #
    # **Closedness and members arrive together, or not at all.** Telling
    # the engine a gem class is closed without also telling it that
    # class's methods turns every correct call on a gem into a report.
    # Both come out of one payload here for that reason, and
    # `gem_index_spec.rb` holds them against each other.
    #
    # **A class that defines `method_missing` is never knowable**,
    # whatever this holds about it: it answers to names no enumeration
    # can list, so reporting against it would be asserting from a
    # question that cannot be asked. `#knows?` refuses it, and
    # `#defines_method_missing?` says why.
    #
    # Every absence is "I do not know", never "there is nothing there" --
    # the ordinary state is no Agent at all, and a reader that read an
    # empty index as authoritative would report every method in the
    # workspace as missing.
    class GemIndex
      Entry = Data.define(:instance_methods, :singleton_methods, :ancestors, :defines_method_missing)

      def self.empty = new({})

      # Tolerant by construction: the payload crosses a process boundary
      # and an Agent that answered something unexpected must leave this
      # empty rather than raise on the request path.
      def self.from_agent(payload)
        gems = payload.is_a?(Hash) ? payload[:gems] || payload["gems"] : nil
        return empty unless gems.is_a?(Hash)

        entries = {}
        gems.each_value do |gem|
          classes = gem.is_a?(Hash) ? gem[:classes] || gem["classes"] : nil
          Array(classes).each do |klass|
            next unless klass.is_a?(Hash)

            name = klass[:name] || klass["name"]
            next unless name

            entries[Index::SymbolId.bare_name(name.to_s)] = Entry.new(
              instance_methods: Array(klass[:instanceMethods] || klass["instanceMethods"]).map(&:to_s).to_set,
              singleton_methods: Array(klass[:singletonMethods] || klass["singletonMethods"]).map(&:to_s).to_set,
              ancestors: Array(klass[:ancestors] || klass["ancestors"]).map(&:to_s),
              defines_method_missing: klass[:definesMethodMissing] || klass["definesMethodMissing"] ? true : false
            )
          end
        end
        new(entries)
      end

      def initialize(entries)
        @entries = entries
        freeze
      end

      def empty? = @entries.empty?

      def size = @entries.size

      # Whether this index can account for the class's whole method set.
      # False for a `method_missing` class, which is the one case where
      # holding an entry does not mean knowing the surface.
      def knows?(name)
        entry = entry_for(name)
        !entry.nil? && !entry.defines_method_missing
      end

      def defines_method_missing?(name) = entry_for(name)&.defines_method_missing || false

      def instance_methods(name) = entry_for(name)&.instance_methods || Set.new

      def singleton_methods(name) = entry_for(name)&.singleton_methods || Set.new

      def ancestors(name) = entry_for(name)&.ancestors || []

      private

      def entry_for(name)
        return nil if name.nil?

        @entries[Index::SymbolId.bare_name(name.to_s)]
      end
    end
  end
end
