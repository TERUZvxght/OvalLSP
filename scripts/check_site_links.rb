#!/usr/bin/env ruby
# frozen_string_literal: true

# Verifies every internal link and asset reference in `site/` before it is
# published to GitHub Pages.
#
# The site is hand-written static HTML with no build step, so nothing else
# would notice a renamed page, a mistyped asset path, or an anchor that no
# longer exists -- the page would simply 404 (or scroll nowhere) for a
# reader, and only for a reader. This script is the check that fails first.
#
# It deliberately does *not* touch the network: external URLs are recorded
# and reported as a count, never fetched. A CI job that depends on a third
# party's uptime is a CI job that goes red for reasons unrelated to this
# repository.
#
# Usage: ruby scripts/check_site_links.rb [site_dir]
# Exits non-zero, listing every problem found, if anything is broken.

require "set"

SITE = File.expand_path(ARGV[0] || File.join(__dir__, "..", "site"))

# GitHub Pages serves this project site under /<repo>/, so a root-absolute
# reference in the published HTML carries that prefix. 404.html is the one
# page that must use root-absolute paths -- it is served for URLs at any
# depth, so a relative path there would resolve differently every time.
BASE_PATH = "/OvalLSP"

abort "No such directory: #{SITE}" unless File.directory?(SITE)

# The Japanese pages are UTF-8 and the default external encoding depends on
# the caller's locale, which on a CI runner is usually US-ASCII. Reading
# with an explicit encoding keeps the result identical everywhere.
def read_page(path)
  File.read(path, encoding: "UTF-8")
end

pages = Dir.glob(File.join(SITE, "**", "*.html")).sort
abort "No HTML files under #{SITE}" if pages.empty?

# id="..." and name="..." targets, per page, so cross-page #fragments can be
# checked as strictly as same-page ones.
ids = pages.each_with_object({}) do |page, acc|
  html = read_page(page)
  acc[page] = Set.new(html.scan(/\bid\s*=\s*"([^"]+)"/).flatten)
end

problems = []
external = Set.new
checked = 0

pages.each do |page|
  html = read_page(page)
  rel_page = page.delete_prefix("#{SITE}/")

  # href= and src= on any element. The site has no framework-generated
  # markup, so a regex over the source is exactly as accurate as a parser
  # here, and needs no gem.
  refs = html.scan(/\b(?:href|src)\s*=\s*"([^"]*)"/).flatten

  refs.each do |ref|
    next if ref.empty?

    if ref.start_with?("http://", "https://", "mailto:", "data:", "//")
      external << ref
      next
    end

    checked += 1
    path, fragment = ref.split("#", 2)

    target =
      if path.nil? || path.empty?
        page # a same-page #anchor
      elsif path.start_with?("/")
        unless path.start_with?("#{BASE_PATH}/")
          problems << "#{rel_page}: root-absolute reference #{ref.inspect} does not start with " \
                      "#{BASE_PATH}/, so it would leave the project site once published"
          next
        end
        File.join(SITE, path.delete_prefix("#{BASE_PATH}/"))
      else
        File.expand_path(path, File.dirname(page))
      end

    unless File.exist?(target)
      problems << "#{rel_page}: missing target #{ref.inspect} -> #{target.delete_prefix("#{SITE}/")}"
      next
    end

    next if fragment.nil? || fragment.empty?

    # Fragments only mean something in a page we can read the ids of.
    next unless target.end_with?(".html")

    unless ids.fetch(target, Set.new).include?(fragment)
      problems << "#{rel_page}: #{ref.inspect} points at ##{fragment}, which does not exist in " \
                  "#{target.delete_prefix("#{SITE}/")}"
    end
  end
end

# Every page must carry the things that make it a page of *this* site --
# each has been forgotten at least once in a hand-written multi-page site.
pages.each do |page|
  html = read_page(page)
  rel_page = page.delete_prefix("#{SITE}/")

  problems << "#{rel_page}: no <title>" unless html.include?("<title>")
  problems << "#{rel_page}: no lang attribute" unless html.match?(/<html\s+lang="[^"]+"/)
  problems << "#{rel_page}: no meta description" unless html.include?('name="description"')
  problems << "#{rel_page}: no canonical URL" unless html.include?('rel="canonical"')
  problems << "#{rel_page}: does not load the stylesheet" unless html.include?("assets/css/site.css")
  problems << "#{rel_page}: does not load the script" unless html.include?("assets/js/site.js")
end

# --- The capability matrix, against README's ---------------------------
#
# `site/capabilities.html` restates README's matrix row for row, and
# nothing compared the two. That is how the site came to mark all six of
# 0.2.0's capabilities `planned` on the day they shipped: the matrix was
# copied once, at 0.1.10, and six releases moved underneath it.
#
# Compared by *status*, not by exact HTML: the site renders "Verified"
# where README writes ✅ and a version where README writes a version, and
# the question is whether the two agree about what a reader is promised.
#
# English is compared by feature name. Japanese is compared *positionally*
# -- same number of rows, same statuses in the same order -- because the
# site's Japanese was translated independently of `README.ja.md` and the
# two disagree about wording that means the same thing (`Coreが起動し` vs
# `Core が起動し`, `あと` vs `後`). Rewriting one to match the other would
# buy a stricter check by making the prose worse; the order of the table
# is the thing both copies really do share.
REPO = File.expand_path(File.join(__dir__, ".."))

# README writes ✅ / ⚠️ / a version / —; the site writes Verified /
# Unverified / a version / n/a. Reduced to the states both spell, and nil
# for anything that is not a status at all -- which is what filters out
# the header row and the legend table without naming either.
def normalise_status(text)
  # The site's own CSS classes carry the state, and they are the one part
  # of the cell that is not translated: `mark--yes` reads "Verified" in
  # English and 検証済み in Japanese. Keying on the word instead is how a
  # first version of this check silently compared 15 of 39 Japanese rows
  # and called the rest "not a status".
  #
  # A cell can hold two of them. README writes `⚠️ 1.0.0` for thirty rows
  # -- "unverified there, and planned for that release" -- and the site
  # rendered only the version, so its own legend read those cells as "not
  # built" where README means "probably works, unverified". Both marks are
  # part of the state, so both are read.
  marks = text.scan(/mark--(yes|warn|plan|none)/).flatten
  unless marks.empty?
    version = text[/(\d+\.\d+\.\d+)/, 1]
    states = []
    states << "verified" if marks.include?("yes")
    states << "unverified" if marks.include?("warn")
    states << "planned:#{version}" if marks.include?("plan") && version
    states << "none" if marks.include?("none")
    return states.empty? ? nil : states.join("+")
  end

  stripped = text.gsub(/<[^>]+>/, " ").gsub(/\[\^[a-z]+\]/, "").gsub(/\s+/, " ").strip
  version = stripped[/(\d+\.\d+\.\d+)/, 1]
  states = []
  states << "verified" if stripped.include?("✅")
  states << "unverified" if stripped.include?("⚠️")
  states << "planned:#{version}" if version
  states << "none" if states.empty? && stripped.match?(/\A(—|―)/)
  states.empty? ? nil : states.join("+")
end

# Footnote markers, emphasis and code ticks are presentation. What has to
# match is which capability the row is about.
def normalise_feature(text)
  # A `<small>` note on the site and a `[^footnote]` in README are the
  # same thing -- a qualification hanging off the row -- and neither is
  # the row's identity. Both come out.
  text.gsub(%r{<small.*?</small>}m, "").gsub(/\[\^[a-z]+\]/, "")
      .gsub(/[`*_]/, "").gsub(/<[^>]+>/, "")
      .gsub(/\s*([\/,])\s*/, '\1').gsub(/\s+/, " ").strip.downcase
end

def readme_matrix(path)
  return [] unless File.exist?(path)

  File.read(path, encoding: "UTF-8").lines.filter_map do |line|
    next unless line.start_with?("| ") && line.count("|") >= 5

    cells = line.split("|").map(&:strip)
    statuses = cells[2, 3].to_a.map { |cell| normalise_status(cell.to_s) }
    next if statuses.compact.empty?

    [normalise_feature(cells[1].to_s), statuses]
  end
end

# All three environment columns, not just the first. Restricting it to
# column one is how `⚠️ 1.0.0` went unnoticed in thirty rows: the column a
# reader acts on was right and the two beside it were not.
#
# Matched on the *cells*, not on `<tr data-status>`. Keying on that
# attribute meant this only ever saw `capabilities.html`, because it is
# the only page that carries it -- so the excerpt table on both index
# pages went unchecked and marked two of 0.2.0's shipped capabilities
# `0.2.0`, which the page's own legend defines as "not built yet", under
# a header badge reading "Preview 0.2.0". Verified by mutation: flipping
# a status on `index.html` left this green.
def site_matrix(html)
  html.scan(%r{<tr[^>]*>\s*<td>(.*?)</td>\s*((?:<td class="col-status">.*?</td>\s*){3})</tr>}m).filter_map do |feature, cells|
    statuses = cells.scan(%r{<td class="col-status">(.*?)</td>}m).flatten.map { |cell| normalise_status(cell) }
    statuses.compact.empty? ? nil : [normalise_feature(feature), statuses]
  end
end

# The index pages carry an *excerpt* of the matrix -- a subset, in the
# same order -- so every row they do have must agree, and rows they omit
# are not an error.
# The row *count* the index pages advertise, against the matrix they link
# to. Round 23 corrected it from 39 to 41 by hand and round 25 found it
# saying 41 against 42 — the same sentence, one release later, on the same
# two pages. Counting is the one thing a check does better than a reader.
#
# The capability pages ship a static count of their own inside
# `result-count`, which the page's JavaScript overwrites on load; it is
# only visible with JavaScript off, and it was a third number again.
[["index.html", "capabilities.html"], [File.join("ja", "index.html"), File.join("ja", "capabilities.html")]]
  .each do |page_rel, matrix_rel|
  page = read_page(File.join(SITE, page_rel))
  total = read_page(File.join(SITE, matrix_rel)).scan(/<tr[^>]*data-status/).length
  advertised = page.scan(/(\d+)(?:\s*(?:rows|項目))/).flatten.map(&:to_i)
  next problems << "#{page_rel}: advertises no matrix row count" if advertised.empty?

  advertised.reject { |count| count == total }.each do |count|
    problems << "#{page_rel}: advertises #{count} matrix rows and #{matrix_rel} has #{total}"
  end
end

[["capabilities.html", nil], [File.join("ja", "capabilities.html"), nil]].each do |page_rel, _|
  page = read_page(File.join(SITE, page_rel))
  total = page.scan(/<tr[^>]*data-status/).length
  page.scan(%r{<p class="result-count"[^>]*>([^<]*)</p>}).flatten.each do |text|
    text.scan(/(\d+)/).flatten.map(&:to_i).reject { |count| count == total }.each do |count|
      problems << "#{page_rel}: its no-JavaScript row count says #{count} and the table has #{total}"
    end
  end
end

english_excerpt = site_matrix(read_page(File.join(SITE, "index.html")))
expected = readme_matrix(File.join(REPO, "README.md")).to_h
problems << "index.html: no capability rows found -- the excerpt markup changed shape" if english_excerpt.empty?
english_excerpt.each do |feature, statuses|
  reference = expected[feature]
  if reference.nil?
    problems << "index.html: has a row for #{feature.inspect} that README.md does not"
  elsif statuses != reference
    problems << "index.html: #{feature.inspect} is #{statuses.inspect} and README.md says #{reference.inspect}"
  end
end

# The Japanese excerpt is compared against the *English excerpt*,
# positionally, rather than against `README.ja.md` by name.
#
# By name it was compared to nothing at all: the site's Japanese was
# translated independently of `README.ja.md` and no row name matches
# ("ホバー: リテラル…" against "Hover: リテラル…"), so every row fell into
# the "not in the README" branch, which was skipped for `ja/`. Eight rows,
# none checked, on the Japanese landing page -- the second of the two
# pages this check was added to cover, and the mutation test that caught
# it the first time was only ever run against the English one.
#
# Positionally against English works because both are excerpts of the same
# matrix in the same order, and the English one is checked by name above.
# `ja/capabilities.html` is compared the same way and for the same reason.
japanese_excerpt = site_matrix(read_page(File.join(SITE, "ja", "index.html")))
if japanese_excerpt.length != english_excerpt.length
  problems << "ja/index.html: has #{japanese_excerpt.length} matrix rows and index.html has #{english_excerpt.length}"
else
  japanese_excerpt.zip(english_excerpt).each_with_index do |((ja_feature, ja_statuses), (_, en_statuses)), row|
    next if ja_statuses == en_statuses

    problems << "ja/index.html: row #{row + 1} (#{ja_feature.inspect}) is #{ja_statuses.inspect} " \
                "and index.html's row #{row + 1} is #{en_statuses.inspect}"
  end
end

english = site_matrix(read_page(File.join(SITE, "capabilities.html")))
english_expected = readme_matrix(File.join(REPO, "README.md"))
problems << "capabilities.html: no capability rows found -- the matrix markup changed shape" if english.empty?

english_expected.to_h.each do |feature, status|
  actual = english.to_h[feature]
  if actual.nil?
    problems << "capabilities.html: README.md has a row for #{feature.inspect} and the site does not"
  elsif actual != status
    problems << "capabilities.html: #{feature.inspect} is #{actual.inspect} on the site and #{status.inspect} in README.md"
  end
end
(english.to_h.keys - english_expected.to_h.keys).each do |feature|
  problems << "capabilities.html: has a row for #{feature.inspect} that README.md does not"
end

japanese = site_matrix(read_page(File.join(SITE, "ja", "capabilities.html")))
japanese_expected = readme_matrix(File.join(REPO, "README.ja.md"))
if japanese.length != japanese_expected.length
  problems << "ja/capabilities.html: has #{japanese.length} rows, README.ja.md has #{japanese_expected.length}"
else
  japanese.each_with_index do |(feature, status), index|
    expected_status = japanese_expected[index].last
    next if status == expected_status

    problems << "ja/capabilities.html: row #{index + 1} (#{feature.inspect}) is #{status.inspect} " \
                "and README.ja.md's row #{index + 1} is #{expected_status.inspect}"
  end
end

# --- The roadmap pages, against ROADMAP.md -----------------------------
#
# By item count per version, in both languages. Not by name: the site's
# Japanese is translated independently of `ROADMAP.ja.md` and never
# matches it verbatim, which is the mistake the index-excerpt check above
# records making once already.
#
# `core/spec/meta/roadmap_parity_spec.rb` pairs README's matrix with
# `ROADMAP.md`, and nothing paired either with the site. So when 0.2.1
# moved `activeParameter` to 0.4.0, the Markdown and README were updated
# and `site/roadmap.html` was not -- for a whole release, on the page a
# reader is most likely to be sent to when they ask what is coming.
#
# The site drifting from a Markdown document it mirrors is now the second
# occurrence of one shape: 0.2.1's was `capabilities.html`, and the row
# count above is the countermeasure that came out of it. It was aimed at
# capabilities alone. This is the same countermeasure aimed at the pair it
# missed.
def roadmap_items(markdown)
  return nil unless File.exist?(markdown)

  # `filter_map` on the *sections*, not `compact` on the Hash. `Hash#compact`
  # drops nil values and a count is never nil, so a `## ` heading that is
  # not a version -- the first prose section anyone adds -- survived as a
  # nil key and was reported as `plans  and the page has no section for
  # it`, a blank-version false failure at release time.
  File.read(markdown, encoding: "UTF-8").split(/^## /).drop(1).filter_map do |section|
    version = section[/\A(\d+\.\d+\.\d+)/, 1]
    next unless version

    [version, section.lines.count { |line| line.start_with?("- ") }]
  end.to_h
end

# Released versions from the changelog, newest first. A section headed
# `## 0.2.2 — unreleased` is not one of them, which is what keeps this
# from demanding a panel for a release that has not happened.
def released_versions(changelog)
  return [] unless File.exist?(changelog)

  File.read(changelog, encoding: "UTF-8")
      .scan(/^## (\d+\.\d+\.\d+)\s+[-—]\s*(.+)$/)
      .reject { |(_, title)| title.strip.match?(/\Aunreleased\z/i) }
      .map(&:first)
end

def site_roadmap_items(html)
  html.scan(%r{<span class="v">(\d+\.\d+\.\d+)</span>(.*?)</ul>}m).to_h do |version, body|
    [version, body.scan("<li>").length]
  end
end

[["roadmap.html", "docs/ROADMAP.md"], [File.join("ja", "roadmap.html"), "docs/ROADMAP.ja.md"]]
  .each do |page_rel, markdown_rel|
  page = File.join(SITE, page_rel)
  next problems << "#{page_rel}: missing" unless File.exist?(page)

  expected = roadmap_items(File.join(REPO, markdown_rel))
  # A missing source is a problem, not a pass. `{}` compared against a
  # populated page reports nothing at all, which is the quietest way for a
  # check to stop checking.
  next problems << "#{markdown_rel}: missing, so #{page_rel} is unchecked" if expected.nil?

  actual = site_roadmap_items(read_page(page))
  next problems << "#{page_rel}: no roadmap items found -- the markup changed shape" if actual.empty?
  next problems << "#{markdown_rel}: no version sections found -- the heading shape changed" if expected.empty?

  expected.each do |version, count|
    listed = actual[version]
    if listed.nil?
      problems << "#{page_rel}: #{markdown_rel} plans #{version} and the page has no section for it"
    elsif listed != count
      problems << "#{page_rel}: #{version} lists #{listed} item(s) and #{markdown_rel} has #{count}"
    end
  end

  # The other direction, which iterating the Markdown alone cannot see.
  # `ROADMAP.md` lists only what is *planned*, so the site's shipped
  # panels answer to nothing in it -- and nothing kept them current: 0.2.1
  # shipped eight user-visible fixes and the newest panel still said
  # 0.2.0.
  #
  # A shipped panel is a reasonable thing for a roadmap page to carry, so
  # the rule is not "must be planned" but "must have actually shipped",
  # which the changelog knows.
  released = released_versions(File.join(REPO, "vscode", "CHANGELOG.md"))
  (actual.keys - expected.keys).sort.each do |version|
    next if released.include?(version)

    problems << "#{page_rel}: has a #{version} section that is neither planned in #{markdown_rel} " \
                "nor released in vscode/CHANGELOG.md"
  end
  if released.first && !actual.key?(released.first)
    problems << "#{page_rel}: #{released.first} has shipped and the page has no section for it"
  end
end

# --- The version the site advertises, against package.json -------------
#
# `Preview 0.1.10` was hard-coded into both index pages and stayed there
# through six releases.
package_json = File.join(REPO, "vscode", "package.json")
if File.exist?(package_json)
  version = File.read(package_json, encoding: "UTF-8")[/"version":\s*"([^"]+)"/, 1]
  pages.each do |page|
    rel_page = page.delete_prefix("#{SITE}/")
    read_page(page).scan(/(?:Preview|preview)\s+v?(\d+\.\d+\.\d+)/) do |(shown)|
      next if shown == version

      problems << "#{rel_page}: advertises version #{shown}, but vscode/package.json says #{version}"
    end
  end
end

puts "Checked #{checked} internal reference(s) across #{pages.length} page(s); " \
     "#{external.length} distinct external URL(s) left unfetched."

if problems.empty?
  puts "OK: every internal link, asset and anchor resolves."
else
  warn "\n#{problems.length} problem(s):"
  problems.each { |p| warn "  - #{p}" }
  exit 1
end
