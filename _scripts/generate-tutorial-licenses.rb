require 'yaml'
require 'date'

# collect all license files 
licensearray = Dir.glob("tutorials/**/LICENSE*")

# go through each markdown file
licensearray.each { |license|
	
	# if LICENSE, rename to LICENSE.md
	# if LICENSE.html already exists, remove
	if File.basename(license) =~ /LICENSE/i
		if File.exist?(File.dirname(license) + "/LICENSE.html")
			File.delete(File.dirname(license) + "/LICENSE.html")
		end
		licensemd = File.dirname(license) + "/LICENSE.md"
		File.rename(license, licensemd)
		license = licensemd
	end
	
	# get tutorial name if possible
	tutorial_name = nil
	dirarray = File.dirname(license).split('/')
	temp_name = dirarray[dirarray.index("tutorials") + 1]
	if temp_name =~ /^[^_]/
		tutorial_name = temp_name
		title = license.sub(/^.*tutorials\//, '').sub(/.md$/, '').sub(/LICENSE$/, '')
	end

	# if file is lacking YAML front matter, add some
	contents = File.open(license, "r").read	
	out = File.new(license, "w")	
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

		header   = YAML.load(contents[0..pos[0]], permitted_classes: [Date, Time], aliases: true)
		contents = contents[pos[0]..-1]

		if (tutorial_name != nil)
			header["layout"] = "tutorial"
			header["title"] = title
			header["tutorial"] = tutorial_name
			header["permalink"] = "/:path/:basename:output_ext"
		end

		out.puts YAML.dump(header)
		out.puts "---"
		out.puts
	end
	
	# go through file and replace all links that point to .md files with the equivalent .html file
	contents.gsub!(/\((\S+)\.md\)/, "(\\1.html)")
	out.puts "```"
	out.puts contents		
	out.puts "```"
	
}

