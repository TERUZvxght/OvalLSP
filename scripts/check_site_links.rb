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

puts "Checked #{checked} internal reference(s) across #{pages.length} page(s); " \
     "#{external.length} distinct external URL(s) left unfetched."

if problems.empty?
  puts "OK: every internal link, asset and anchor resolves."
else
  warn "\n#{problems.length} problem(s):"
  problems.each { |p| warn "  - #{p}" }
  exit 1
end
