# frozen_string_literal: true

# The Ruby side of G16's probe; `sig/argument_probe.rbs` declares what
# `resize` takes. Both have to exist before Core starts: signatures are
# loaded once at boot, and the workspace pass runs when the cold index
# finishes.
class ArgumentProbe
  def resize(size)
    size
  end
end
