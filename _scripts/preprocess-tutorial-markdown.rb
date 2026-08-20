require 'yaml'
require_relative 'validate_tutorial_metadata'

# Load validator
VALIDATOR = TutorialMetadataValidator.new('tutorials/tutorial_schema.yml')

# Preprocessing script
# Run before `jekyll build` to walk through directories and add YAML front matter to Markdown files

# collect all markdown files
mdarray = Dir.glob("tutorials/**/*.md")

# go through each markdown file
mdarray.each { |md|

	# Check if this is the main README.md file for a tutorial (directly in tutorials/TutorialName/)
	is_main_readme = (File.basename(md) =~ /readme/i) && (File.dirname(md) =~ /^tutorials\/[^\/]+$/)

	# get tutorial name if possible
	tutorial_name = nil
	dirarray = File.dirname(md).split('/')
	temp_name = dirarray[dirarray.index("tutorials") + 1]
	if temp_name =~ /^[^_]/
		tutorial_name = temp_name
		# For main README, title should be the tutorial name; for other files, use the path
		if is_main_readme
			title = tutorial_name
		else
			title = md.sub(/^.*tutorials\//, '').sub(/.md$/, '').sub(/index$/, '').sub(/README$/i, '')
		end

	end

	# if file is lacking YAML front matter, add some
	contents = File.open(md, "r").read
	out = File.new(md, "w")
	#if contents !~ /^(---\s*\n.*?\n?)^(---\s*$\n?)/m
	if contents !~ /\A---(.|\n)*?---/
		out.puts "---"
		out.puts "layout: tutorial"
		if tutorial_name != nil
			out.puts "title: #{title}"
			out.puts "tutorial: #{tutorial_name}"
			# Main README serves at directory URL; other files use their basename
			if is_main_readme
				out.puts "permalink: /tutorials/#{tutorial_name}/"
			else
				out.puts "permalink: /:path/:basename:output_ext"
			end
		end
		out.puts "---"
		out.puts
	else
		pos = contents.enum_for(:scan, /\A---(.|\n)*?---/).map { Regexp.last_match.end(0) }

		header   = YAML.load(contents[0..pos[0]])
		contents = contents[pos[0]..-1]

		# VALIDATE METADATA (only the tutorial's main README, not LICENSE.md etc.)
		if (tutorial_name != nil && is_main_readme)
			validation_result = VALIDATOR.validate(header)
			unless validation_result[:valid]
			puts "  WARNING: #{tutorial_name} has validation errors:"
			validation_result[:errors].each { |e| puts "    - #{e}" }
			end
		end

		if (tutorial_name != nil)
			header["layout"] = "tutorial"
			unless (header.key?("title"))
				header["title"] = title
			end
			header["tutorial"]  = tutorial_name
			# Main README serves at directory URL; other files use their basename
			if is_main_readme
				header["permalink"] = "/tutorials/#{tutorial_name}/"
			else
				header["permalink"] = "/:path/:basename:output_ext"
			end
		end

		out.puts YAML.dump(header)
		out.puts "---"
		out.puts
	end
	
	# go through file and replace all links that point to .md files with the equivalent .html file
	contents.gsub!(/\((\S+)\.md\)/, "(\\1.html)")
	out.puts contents	

}
