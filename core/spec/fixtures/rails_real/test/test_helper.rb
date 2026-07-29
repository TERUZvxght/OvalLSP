# The shape `rails new` generates, and the one that produced two false
# "has no method named" diagnostics in every real Rails application
# (024.R5). `ActiveSupport::TestCase` lives in a gem; reopening it here is
# syntactically identical to defining it, and it is never loaded in the
# environment the Runtime Agent boots -- so only its autoload registration
# can settle where it really comes from.
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    fixtures :all
  end
end

# A positive control for G13. Without it the example asserts only an
# absence, which is equally satisfied by the file never being diagnosed at
# all -- a wrong path, a missing copy, a server that published nothing.
# This call must be reported, so the example can tell "the reopen is fixed"
# from "nothing was checked here".
class TestHelperDiagnosedProbe
  def probe
    definitely_not_a_method_on_this_class
  end
end
