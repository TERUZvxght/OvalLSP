# frozen_string_literal: true

module Ovallsp
  module Index
    # `alias new old` or `alias_method :new, :old` found inside `owner`.
    # `singleton` mirrors Declaration's instance/singleton split: true for
    # an alias inside `class << self` or targeting a `def self.` method
    # (best-effort — only the lexical `class << self` context is tracked,
    # matching ParserService's own singleton-context detection).
    # `visibility` is the alias's *own*, set only when something named it
    # -- `private :aka`. Nil means "whatever the method it names has",
    # which is what Ruby gives an alias at the moment it is made:
    #
    #   $ ruby -e '
    #   class A
    #     def build; end
    #     alias_method :aka, :build
    #     private :aka
    #     private
    #     def sec; end
    #     alias_method :sec_aka, :sec
    #   end
    #   p [A.new.respond_to?(:aka), A.new.respond_to?(:sec_aka)]
    #   '
    #   # => [false, false]
    #   # ruby 3.4.10
    #
    # Recorded here rather than as a Declaration because an alias has no
    # declaration to carry it -- which is why `private :aka` went nowhere
    # and completion offered a name that raises.
    AliasFact = Data.define(:owner, :new_name, :old_name, :singleton, :location, :visibility) do
      def initialize(visibility: nil, **rest)
        super(visibility: visibility, **rest)
      end
    end
  end
end
