require 'json'
require 'ovallsp'
include Ovallsp
warn "review-overload: cwd=#{Dir.pwd} ruby=#{RUBY_VERSION} ovallsp=#{VERSION}"
i = Types::Nominal.new(name: 'Integer')
s = Types::Nominal.new(name: 'String')
with_rest = Signatures::Overload.new(required_positionals: [i], rest_positional: s, return_type: s)
with_kwrest = Signatures::Overload.new(required_keywords: {required: i}, rest_keyword: s, return_type: s)
empty = Signatures::Overload.new(return_type: i)
puts JSON.pretty_generate(
  positional: {missing_required_matches: Signatures::OverloadResolver.matches?(with_rest,0,[],false),
    selected_return: Signatures::OverloadResolver.resolve([with_rest,empty],positional_count:0).to_s},
  keywords: {missing_required_matches: Signatures::OverloadResolver.matches?(with_kwrest,0,[],false),
    selected_return: Signatures::OverloadResolver.resolve([with_kwrest,empty],positional_count:0).to_s},
  control: {zero_arity_matches: Signatures::OverloadResolver.matches?(empty,0,[],false),
    required_without_rest_matches: Signatures::OverloadResolver.matches?(Signatures::Overload.new(required_positionals:[i]),0,[],false)})
