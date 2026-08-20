# go through tutorials and clean and update
# build latex tutorials

require 'yaml'

$basedir = Dir.pwd						
config = YAML.load_file("_config.yml")

# to_update = ["Mascot-Tutorial",
#              "FBD-tutorial",
#              "Prior-selection",
#              "Troubleshooting",
#              "Skyline-plots",
#              "Structured-birth-death-model"]

config["tutorials"].each do |repo|
	name = repo.split('/').drop(1).join('')		

        unless (not defined?(to_update)) or to_update.include?(name)
          next
        end

        puts "=== Processing tutorial #{name} ==="

	Dir.chdir($basedir + "/tutorials")			
	if !Dir.exist?(name)								# clone tutorial repo
		`git clone --depth 1 https://github.com/#{repo}.git`
	end
	Dir.chdir($basedir + "/tutorials/" + name)			# drop into blotter dir	
	# `git clean -f`										# remove untracked files, but keep directories
	# `git reset --hard HEAD`								# bring back to head state
	# `git pull`							# git pull	

	# Check if license files exist
	if Dir.glob("LICENSE*").length == 0
		`cp ../../_layouts/CCby4.0.txt LICENSE`
	end

	if File.exist?("main.tex")							# build tutorial pdf if main.tex exists
		File.rename("main.tex", "#{name}.tex")
		`pdflatex --interaction nonstopmode #{name}.tex`									
		`bibtex #{name}`
		`pdflatex --interaction nonstopmode #{name}.tex`									
	end

	#{}`python ParseMdtoLatex.py -i README.md -t pandoctemplate.tex -L`
end

Dir.chdir($basedir)
`ruby _scripts/preprocess-tutorial-markdown.rb`
`ruby _scripts/generate-tutorial-licenses.rb`
`ruby _scripts/generate-tutorial-data.rb`
