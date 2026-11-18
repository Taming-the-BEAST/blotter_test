require 'yaml'
require 'date'

# Turn each tutorial's top-level LICENSE / LICENSE.md into a LICENSE.md page
# that Jekyll renders as tutorials/<name>/LICENSE.html.
#
# Safe to run repeatedly: the front matter is rewritten (not duplicated) and the
# licence text is wrapped in exactly one code fence, however many fences earlier
# runs left behind.

FENCE = "```"

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
	# Must not equal the tutorial's own title (the tutorial layout looks up its
	# metadata by title), and reads well in the breadcrumb.
	title = tutorial_name ? "#{tutorial_name}/License" : nil

	contents = File.read(license)

	# split off existing YAML front matter, if any
	header = {}
	if contents =~ /\A---\s*\n(.*?)\n---\s*\n/m
		header = YAML.load($1, permitted_classes: [Date, Time], aliases: true) || {}
		contents = $'
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
