# frozen_string_literal: true

# A tiny stand-in for ActiveRecord::Base. Real `activerecord` isn't a
# dependency of this repo (docs/design/tasks/007-active-record-snapshot.md),
# so this exposes just enough of the real interface for
# Ovallsp::RuntimeAgent::Agent's model extraction to work unchanged against
# it and against real ActiveRecord later: `.columns` (name/type/null),
# `.reflect_on_all_associations` (macro/name/class_name/options), and
# `.table_name`/`.abstract_class?`/`.descendants`.
module ActiveRecord
  FakeColumn = Struct.new(:name, :type, :null, keyword_init: true)
  FakeReflection = Struct.new(:macro, :name, :class_name, :options, keyword_init: true)

  class Base
    class << self
      def descendants
        @descendants ||= []
      end

      def inherited(subclass)
        super
        Base.descendants << subclass unless subclass == Base
      end

      def abstract_class?
        !!@abstract_class
      end

      def abstract_class=(value)
        @abstract_class = value
      end

      # Declares a column at class-definition time — always available, no
      # DB needed, same as a real Rails schema being loaded from
      # db/schema.rb rather than queried live.
      def column(name, type, null: true)
        declared_columns << FakeColumn.new(name: name, type: type, null: null)
      end

      def declared_columns
        @declared_columns ||= []
      end

      # Simulates a DB connection outage for Task 007's "DB unavailable
      # partial result" acceptance criterion — reflections (associations,
      # table_name) don't need a live DB connection in real ActiveRecord,
      # only schema introspection does.
      def columns
        raise "database unavailable" if ENV["OvalLSP_FIXTURE_DB_DOWN"] == "1"

        declared_columns
      end

      def belongs_to(name, class_name: nil, optional: true)
        reflections << FakeReflection.new(
          macro: :belongs_to, name: name, class_name: class_name || camelize(name), options: { optional: optional }
        )
      end

      def has_many(name, class_name: nil)
        reflections << FakeReflection.new(
          macro: :has_many, name: name, class_name: class_name || camelize(singularize(name.to_s)), options: {}
        )
      end

      def has_one(name, class_name: nil)
        reflections << FakeReflection.new(
          macro: :has_one, name: name, class_name: class_name || camelize(name), options: {}
        )
      end

      def reflections
        @reflections ||= []
      end

      def reflect_on_all_associations
        reflections
      end

      def table_name
        @table_name ||= "#{name.downcase}s"
      end

      private

      def camelize(value)
        value.to_s.split("_").map { |part| part[0].upcase + part[1..].to_s }.join
      end

      def singularize(value)
        value.sub(/s\z/, "")
      end
    end
  end
end
