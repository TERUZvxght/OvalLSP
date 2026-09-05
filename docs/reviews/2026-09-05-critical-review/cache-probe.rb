require 'json'
require 'tmpdir'
require 'fileutils'
require 'ovallsp'
warn "review-cache: cwd=#{Dir.pwd} ruby=#{RUBY_VERSION} ovallsp=#{Ovallsp::VERSION}"
result = nil
Dir.mktmpdir('ovallsp-review-cache-') do |temporary|
  cache = File.join(temporary, 'cache')
  outside = File.join(temporary, 'outside')
  victim = File.join(outside, 'victim')
  kept = Array.new(Ovallsp::Cache::Store::DEFAULT_MAX_GENERATIONS) { |i| File.join(outside, "keep-#{i}") }
  keep = kept.last
  untouched = File.join(temporary, 'control.txt')
  FileUtils.mkdir_p([cache, victim, *kept])
  File.write(File.join(victim, 'valuable.txt'), 'synthetic user data')
  File.write(untouched, 'control')
  File.utime(Time.now - 3600, Time.now - 3600, victim)
  scope = File.join(cache, 'scope'); File.symlink(outside, scope)
  before = File.file?(File.join(victim, 'valuable.txt'))
  Ovallsp::Cache::Store.prune_generations(cache_root: cache, current: File.join(scope, File.basename(keep)))
  result = {outside_victim_before: before, outside_victim_after: File.exist?(victim),
    retained_generation_exists: File.directory?(keep), unrelated_control_exists: File.file?(untouched)}
end
puts JSON.pretty_generate(result)
