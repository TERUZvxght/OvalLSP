# What every Rails test file looks like, and the case that made the
# receiver-only version of this check useless: once test_helper.rb has
# reopened `ActiveSupport::TestCase`, that name is workspace-declared, so
# this class's static ancestry reaches BasicObject through it and looks
# complete. `assert_equal` comes from the gem (024.R5).
require "test_helper"

class ProbeSubclassTest < ActiveSupport::TestCase
  def test_arithmetic_still_works
    assert_equal 2, 1 + 1
  end
end
