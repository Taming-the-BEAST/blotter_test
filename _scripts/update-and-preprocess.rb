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
		unless system("git", "clone", "--depth", "1", "https://github.com/#{repo}.git")
			puts "WARNING: could not clone #{repo} - skipping"
			next
		end
	elsif ENV["TTB_NO_REFRESH"] == "1"
		puts "TTB_NO_REFRESH=1: keeping existing clone of #{name} as is"
	else
		# Bring an existing clone to the upstream default branch, so builds that
		# reuse tutorials/ (servers, Docker volumes) publish current tutorials.
		# This DISCARDS uncommitted changes and untracked files in the clone,
		# including gitignored build outputs (git clean -x), so after a
		# successful refresh no stale generated file is left; preprocessing
		# edits and the PDF (from main.tex) are regenerated below. Set TTB_NO_REFRESH=1 to skip this
		# step, e.g. while editing a tutorial locally.
		#
		# Only touch folders that are their own git repository. tutorials/ sits
		# inside the site repo, so in a plain folder (copied by hand, unpacked
		# zip, interrupted clone) git would otherwise walk up and reset the
		# site repo itself. GIT_CEILING_DIRECTORIES stops that walk as well.
		dir = File.realpath($basedir + "/tutorials/" + name)
		git_env = { "GIT_CEILING_DIRECTORIES" => File.realpath($basedir + "/tutorials") }
		toplevel = IO.popen(git_env, ["git", "-C", dir, "rev-parse", "--show-toplevel"], err: File::NULL, &:read).to_s.strip
		if !File.exist?(File.join(dir, ".git")) || toplevel.empty? || File.realpath(toplevel) != dir
			puts "WARNING: tutorials/#{name} is not its own git clone - not refreshing it"
		else
			ok = system(git_env, "git", "-C", dir, "fetch", "--depth", "1", "origin") &&
				system(git_env, "git", "-C", dir, "reset", "--hard", "FETCH_HEAD") &&
				system(git_env, "git", "-C", dir, "clean", "-fdx", "--quiet")
			puts "WARNING: could not refresh #{name}; using the existing clone" unless ok
		end
	end
	Dir.chdir($basedir + "/tutorials/" + name)			# drop into blotter dir

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
# `system(..., exception: true)` rather than backticks: backticks swallow both the
# output and the exit status, so a crash here used to leave _data/tutorials.yml
# missing while the build still reported success.
system("ruby", "_scripts/preprocess-tutorial-markdown.rb", exception: true)
system("ruby", "_scripts/generate-tutorial-licenses.rb", exception: true)
system("ruby", "_scripts/generate-tutorial-data.rb", exception: true)
