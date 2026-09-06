const path = require('path');
const root = process.argv[2];
const glob = require(path.join(root, 'out/watchedFiles.js')).WATCHED_FILES_GLOB;
const mmModule = require(path.join(root, 'node_modules/minimatch'));
const matches = mmModule.minimatch || mmModule;
const rr = require(path.join(root, 'out/rubyResolver.js'));
const brew='/opt/homebrew/opt/ruby/bin/ruby';
const active='/review/active-ruby/bin/ruby';
const result = {
  watcher: {pattern:glob, matches: Object.fromEntries(['lib/task.rake','lib/a.rb','sig/a.rbs','sig/a.rbi','rbs_collection.lock.yaml','Gemfile.lock'].map(p=>[p,matches(p,glob)])), note:'glob-library probe; not a VS Code host run'},
  ruby_resolution: rr.resolveRuby({platform:'darwin',home:'/review/user-root',pathEnv:'/review/active-ruby/bin:/usr/bin',existsSync:p=>[brew,active].includes(p)})
};
console.log(JSON.stringify(result,null,2));
