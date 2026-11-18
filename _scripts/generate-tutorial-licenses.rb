require 'yaml'
require 'date'

# Turn each tutorial's top-level LICENSE / LICENSE.md into a LICENSE.md page
# that Jekyll renders as tutorials/<name>/LICENSE.html.
#
# Safe to run repeatedly: the front matter is rewritten (not duplicated) and the
# licence text is wrapped in exactly one code fence, however many fences earlier
# runs left behind.

FENCE = "```"

# Keys that mark a "---" block at the top as real front matter (see below).
FRONT_MATTER_KEYS = %w[layout title permalink tutorial]

# Only licences directly in a tutorial's root folder (tutorials/<name>/LICENSE*),
# not ones bundled deeper inside data or script folders.
licensearray = Dir.glob("tutorials/*/LICENSE*").reject { |f| f.end_with?(".html") }

licensearray.each { |license|

	# if LICENSE, rename to LICENSE.md
	# if LICENSE.html already exists, remove
	dir = File.dirname(license)
	if File.exist?(dir + "/LICENSE.html")
		File.delete(dir + "/LICENSE.html")
	end
	licensemd = dir + "/LICENSE.md"
	if license != licensemd
		if File.exist?(licensemd) && !File.identical?(license, licensemd)
			# Both LICENSE and LICENSE.md exist: keep LICENSE.md, ignore the other.
			next
		end
		# Rename via a temporary name so a case-only rename (License.md ->
		# LICENSE.md) also works on case-insensitive file systems (macOS).
		tmp = licensemd + ".tmp-rename"
		File.rename(license, tmp)
		File.rename(tmp, licensemd)
		license = licensemd
	end

	# tutorial name: the folder directly under tutorials/
	tutorial_name = File.basename(dir)
	tutorial_name = nil unless tutorial_name =~ /^[^_]/
	# The tutorial layout finds the tutorial's data through `tutorial:` (set
	# below), so the licence page gets the same sidebar as the tutorial. The
	# title only feeds the breadcrumb ("<name> License").
	title = tutorial_name ? "#{tutorial_name}/License" : nil

	# Drop a byte order mark and use LF line endings, so the front matter is
	# found and the generated file has consistent line endings.
	contents = File.read(license, encoding: "bom|utf-8").gsub(/\r\n?/, "\n")

	# Split off existing front matter, if any. Licence files are not usually
	# Markdown with front matter, so text between two "---" lines at the top
	# (a rule, a title, "Copyright: 2020 X", a "# heading") is licence text and
	# is kept. It only counts as front matter when it is empty or a YAML
	# mapping with a key Jekyll or this script writes (every file processed
	# before has `layout: tutorial`, so repeated runs stay idempotent).
	header = {}
	if contents =~ /\A---[ \t]*\n(?:(.*?)\n)?---[ \t]*(?:\n|\z)/m
		block = $1.to_s
		rest = $'
		if block.strip.empty?
			contents = rest
		else
			parsed = begin
				YAML.load(block, permitted_classes: [Date, Time], aliases: true)
			rescue Psych::Exception => e
				puts "WARNING: #{license}: text between the first two '---' lines is not valid YAML (#{e.message.lines.first.strip}); keeping it as licence text"
				nil
			end
			if parsed.is_a?(Hash) && (parsed.keys.map(&:to_s) & FRONT_MATTER_KEYS).any?
				header = parsed
				contents = rest
			end
		end
	end

	header["layout"] = "tutorial"
	if tutorial_name != nil
		header["title"] = title
		header["tutorial"] = tutorial_name
		header["permalink"] = "/:path/:basename:output_ext"
	end

	# strip any code fences left by earlier runs, then wrap exactly once.
	# Only blank lines are trimmed at the ends, so the indentation of the
	# first licence line (e.g. a centred title) is kept.
	trim = ->(s) { s.sub(/\A(?:[ \t]*\n)+/, '').rstrip }
	body = trim.(contents)
	loop do
		stripped = trim.(body.sub(/\A#{FENCE}[^\n]*\n?/, '').sub(/\n?[ \t]*#{FENCE}\z/, ''))
		break if stripped == body
		body = stripped
	end

	# replace links that point to .md files with the equivalent .html file
	body = body.gsub(/\((\S+)\.md\)/, "(\\1.html)")

	File.open(license, "w") do |out|
		out.puts YAML.dump(header)
		out.puts "---"
		out.puts
		out.puts FENCE
		out.puts body
		out.puts FENCE
	end
}
