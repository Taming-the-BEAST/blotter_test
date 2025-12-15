require 'yaml'
require_relative 'validate_tutorial_metadata'

# Load validator
VALIDATOR = TutorialMetadataValidator.new('tutorials/tutorial_schema.yml')

# Preprocessing script
# Run before `jekyll build` to walk through directories and add YAML front matter to Markdown files
# and to rename readme.md files to index.md

# collect all markdown files 
mdarray = Dir.glob("tutorials/**/*.md")

# go through each markdown file
mdarray.each { |md|
	
	# if readme.md, rename to index.md
	# if index.html already exists, remove
	if File.basename(md) =~ /readme/i
		if File.exists?(File.dirname(md) + "/index.html")
			File.delete(File.dirname(md) + "/index.html")
		end
		indexmd = File.dirname(md) + "/index.md"
		File.rename(md, indexmd)
		md = indexmd
	end
	
	# get tutorial name if possible
	tutorial_name = nil
	dirarray = File.dirname(md).split('/')
	temp_name = dirarray[dirarray.index("tutorials") + 1]
	if temp_name =~ /^[^_]/
		tutorial_name = temp_name
		title = md.sub(/^.*tutorials\//, '').sub(/.md$/, '').sub(/index$/, '')

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
			out.puts "permalink: /:path/:basename:output_ext"
		end
		out.puts "---"
		out.puts
	else
		pos = contents.enum_for(:scan, /\A---(.|\n)*?---/).map { Regexp.last_match.end(0) }

		header   = YAML.load(contents[0..pos[0]])
		contents = contents[pos[0]..-1]

		# VALIDATE METADATA
  		if (tutorial_name != nil)
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
			header["permalink"] = "/:path/:basename:output_ext"
		end

		out.puts YAML.dump(header)
		out.puts "---"
		out.puts
	end
	
	# go through file and replace all links that point to .md files with the equivalent .html file
	contents.gsub!(/\((\S+)\.md\)/, "(\\1.html)")
	out.puts contents	

}
