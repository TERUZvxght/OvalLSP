# frozen_string_literal: true

module Ovallsp
  module Index
    # A single method parameter, as declared (no type inference here — that
    # arrives with the type engine in a later task).
    #
    # kind: :required, :optional, :rest, :keyword, :keyword_optional, :keyrest, :block
    Parameter = Data.define(:name, :kind, :default_source)
  end
end
