# Preprocessing script
# Run before `jekyll build` to go through _config.yml and use octokit to fill out metadata
# 
# Gathers tutorial metadata from _config.yml, github and the yaml header for the tutorial and 
# save in tutorials.yml
#
# Example:
# - repo: taming-the-beast/Introduction-to-BEAST2
#   url: /tutorials/Introduction-to-BEAST2/
#   title: Introduction to BEAST2
#   description: This is a simple introductory tutorial to help you get started with
#     using BEAST2 and its accomplices.
#   owner: Taming-the-BEAST
#   author: Jūlija Pečerska,Veronika Bošková
#   contributors:
#   - login: laduplessis
#     avatar: https://avatars0.githubusercontent.com/u/8872277?v=3&s=50
#     url: https://github.com/laduplessis
#   beastversion_tutorial:
#   commits:
#   - date: 2017-01-18 15:02:03.000000000 Z
#     message: Add license
#     url: https://github.com/Taming-the-BEAST/Introduction-to-BEAST2/commit/97763b6b679d208c094790f3aa437298e568f562
#     author_login: laduplessis
#     author_url: https://github.com/laduplessis
#   pdfs:
#   - tutorials/Introduction-to-BEAST2/Introduction-to-BEAST2.pdf
#   data:
#   - tutorials/Introduction-to-BEAST2/data/primate-mtDNA.nex
#   xmls:
#   - tutorials/Introduction-to-BEAST2/xml/Primates.xml
#   - tutorials/Introduction-to-BEAST2/xml/Primates_long.xml
#   scripts: []
#   outputs:
#   - tutorials/Introduction-to-BEAST2/precooked_runs/primate-mtDNA.log
#   - tutorials/Introduction-to-BEAST2/precooked_runs/primate-mtDNA.trees
#   - tutorials/Introduction-to-BEAST2/precooked_runs/primate-mtDNA_long.log
#   - tutorials/Introduction-to-BEAST2/precooked_runs/primate-mtDNA_long.trees
#   - tutorials/Introduction-to-BEAST2/precooked_runs/Primates.MCC.tree

  
require 'octokit'
require 'yaml'
require 'date'
require_relative 'octokit_client'
require_relative 'tutorial_metadata_aliases'

module Tutorials

	METADATA_FALLBACK_FILE = "tutorials_metadata.yml"

	# Fields that may be centrally provided in tutorials_metadata.yml until a
	# tutorial defines them in its own README.md frontmatter (see
	# MIGRATION_PLAN.md, task 1).
	FALLBACK_FIELDS = %w[beastversion_tutorial workflow status keywords packages domains beastversion_package]

	def self.load_fallback_metadata(file = METADATA_FALLBACK_FILE)
		return {} unless File.exist?(file)
		YAML.load_file(file, permitted_classes: [Date, Time], aliases: true) || {}
	end

	def self.blank?(value)
		value.nil? || (value.respond_to?(:empty?) && value.empty?)
	end

	# Normalise a BEAST version value to "major.minor" ("2.7.x", "2.7.7",
	# ">= 2.7", "v2.7" -> "2.7"). Returns nil for missing or unparsable values.
	# Versions should be quoted in YAML: an unquoted 2.10 is read as the Float
	# 2.1 and cannot be recovered, so Floats are reported.
	def self.normalise_minor(value, repo = nil, field = nil)
		return nil if value.nil?
		if value.is_a?(Float)
			puts "\t\tWARNING: #{repo} #{field}: #{value} is unquoted - quote it (an unquoted 2.10 would be read as 2.1)"
		end
		s = value.to_s.strip.sub(/\A(>=|<=|>|<|~>?|\^|=)\s*/, '').sub(/\Av/i, '')
		return nil if s.empty?
		m = s.match(/\A(\d+)\.(\d+)/)
		unless m
			puts "\t\tWARNING: #{repo} #{field}: cannot parse version '#{value}'"
			return nil
		end
		"#{m[1].to_i}.#{m[2].to_i}"
	end

	# Package and domain vocabularies from the schema, for canonical spelling.
	def self.schema
		@schema ||= begin
			YAML.load_file(SCHEMA_FILE) || {}
		rescue StandardError => e
			puts "WARNING: cannot read #{SCHEMA_FILE}: #{e.message}"
			{}
		end
	end

	# Rewrite package names to the schema's spelling, matching
	# case-insensitively ("StarBeast3" -> "starbeast3"), so the listing has
	# one filter option per package. Unknown names are kept and reported.
	def self.canonical_packages(repo, packages)
		known = Array(schema["packages"]).map(&:to_s)
		by_lower = known.each_with_object({}) { |name, h| h[name.downcase] = name }
		packages.map do |pkg|
			name = pkg.to_s.strip
			canonical = by_lower[name.downcase]
			if canonical.nil?
				puts "\t\tWARNING: #{repo} package '#{name}' is not in #{SCHEMA_FILE}" unless known.empty?
				name
			else
				puts "\t\tWARNING: #{repo} package '#{name}' -> '#{canonical}' (schema spelling)" if canonical != name
				canonical
			end
		end.uniq
	end

	def self.check_domains(repo, domains)
		known = Array(schema["domains"]).map(&:to_s)
		return if known.empty?
		domains.each do |d|
			puts "\t\tWARNING: #{repo} domain '#{d}' is not in #{SCHEMA_FILE}" unless known.include?(d.to_s)
		end
	end

	def self.defined_value?(header, field)
		TutorialMetadataAliases.defined_value?(header, field)
	end

	SCHEMA_FILE = "tutorials/tutorial_schema.yml"

	# Allowed workflow values. A legacy `tutorial_type` from the old
	# vocabulary (Core / Model set-up / Applied) is not a valid workflow and
	# must not override a curated fallback value.
	def self.allowed_workflows
		@allowed_workflows ||= Array(schema["workflows"])
	end

	# Legacy keys (beastversion, tutorial_type): shared with the validator.
	def self.resolve_aliases(repo, tutorial_header)
		header, messages = TutorialMetadataAliases.resolve(tutorial_header, allowed_workflows)
		messages.each do |level, text|
			text += " - ignored" if level == :invalid
			puts "\t\t#{level == :info ? 'INFO' : 'WARNING'}: #{repo} #{text}"
		end
		header
	end

	# Field-by-field merge: a tutorial's own frontmatter always wins per
	# field; only fields the tutorial does not define are filled in from the
	# central fallback file. A field counts as defined when the key is present
	# with a non-nil value, so an explicit empty list (`packages: []`) wins.
	# Warn when a tutorial already defines a field also present in the
	# fallback file, since that fallback entry is now redundant and should be
	# removed upstream. Fallback keys are matched case-insensitively.
	def self.merge_fallback_metadata(repo, tutorial_header, fallback_metadata)
		fallback = fallback_metadata[repo] ||
			fallback_metadata.find { |key, _| key.to_s.casecmp?(repo) }&.last
		return tutorial_header unless fallback

		merged = tutorial_header.dup
		FALLBACK_FIELDS.each do |field|
			own_present = defined_value?(tutorial_header, field)
			fallback_present = !blank?(fallback[field])

			if own_present && fallback_present
				puts "\t\tWARNING: #{repo} now defines '#{field}' itself - remove it from #{METADATA_FALLBACK_FILE}"
			elsif !own_present && fallback_present
				merged[field] = fallback[field]
			end
		end
		merged
	end

	def self.find_files(prefix, wildcard)

		ignore_list = ["README.md", "README.mdown", "readme.md"]

		file_list = Dir.glob(prefix+"/"+wildcard)
		ignore_list.each do |str|
			file_list.delete(prefix+"/"+str)
		end

		return file_list
	end

	def self.generate_data(config_file)
	
		tutorial_data = {}
	
		config = YAML.load_file(config_file)
		tutorials_array = config["tutorials"]

		puts "Generating tutorials"
		# create octokit client
		client = OctokitClient.build

		fallback_metadata = load_fallback_metadata

		tutorial_data = Array.new
		if tutorials_array.length > 0
			tutorials_array.each do |repo|
		
				puts "\tGenerating #{repo}"
			
				# load repo metadata
				octokit_repo = client.repository(repo)
				# The clone lives in tutorials/<folder>, named after the config
				# entry (as in update-and-preprocess.rb), which can differ from
				# GitHub's canonical name (case, renamed repos). Use the folder
				# for file paths and the page URL.
				reponame  = repo.split('/').drop(1).join('')

				tutorial_owner = octokit_repo.owner.login
				tutorial_description = octokit_repo.description
				tutorial_url = "/tutorials/#{reponame}/"
				tutorial_date = octokit_repo.updated_at
				tutorial_default_branch = octokit_repo.default_branch
				#puts "\t\tDefault branch #{tutorial_default_branch}"

				# load tutorial header metadata from README.md
				# overwrite description with tutorial header description if not empty
				readme = "tutorials/#{reponame}/README.md"
				unless File.exist?(readme)
					puts "\t\tWARNING: #{repo} has no #{readme} (clone failed?) - skipping"
					next
				end
				tutorial_header = YAML.load_file(readme,
					permitted_classes: [Date, Time], aliases: true)
				# A README without parseable frontmatter yields nil/String, not a Hash.
				unless tutorial_header.is_a?(Hash)
					puts "\t\tWARNING: #{repo} README.md has no usable frontmatter - skipping"
					next
				end
				tutorial_header = resolve_aliases(repo, tutorial_header)
				tutorial_header = merge_fallback_metadata(repo, tutorial_header, fallback_metadata)

				tutorial_level  = tutorial_header["level"]
				tutorial_title  = tutorial_header["title"]
				tutorial_author = tutorial_header["author"]
				tutorial_beast  = tutorial_header["beastversion_tutorial"]   # legacy beastversion handled in resolve_aliases
				tutorial_beast_package = tutorial_header["beastversion_package"]
				normalise_minor(tutorial_beast, repo, "beastversion_tutorial")   # only for its warnings
				tutorial_beast_package_minor = normalise_minor(tutorial_beast_package, repo, "beastversion_package")
				tutorial_workflow = tutorial_header["workflow"]   # legacy tutorial_type handled in resolve_aliases
				tutorial_packages = canonical_packages(repo, Array(tutorial_header["packages"]).reject { |v| v.to_s.strip.empty? })
				tutorial_keywords = Array(tutorial_header["keywords"]).reject { |v| v.to_s.strip.empty? }
				tutorial_status = tutorial_header["status"]
				tutorial_deprecated_reason = tutorial_header["deprecated_reason"]
				tutorial_deprecated_alternative = tutorial_header["deprecated_alternative"]
				tutorial_domains = Array(tutorial_header["domains"]).reject { |v| v.to_s.strip.empty? }
				check_domains(repo, tutorial_domains)
				if (tutorial_header["subtitle"] != nil && tutorial_description != tutorial_header["subtitle"])
				   tutorial_description = tutorial_header["subtitle"]
				end

				# Get all pdfs in the root
				pdf_array = Dir.glob("tutorials/#{reponame}/**/*.pdf").reject{ |f| f['/figures/']}

				# Get data files (files only: directories have no raw download URL)
				data_array = Dir.glob("tutorials/#{reponame}/data/*").select { |f| File.file?(f) }.reject{ |f| f['index.md'] || f['README.mdown'] || f['README.md']}

				# Get xml files
				xml_array = Dir.glob("tutorials/#{reponame}/xml/*.xml")

				# Get scripts files
				script_array = Dir.glob("tutorials/#{reponame}/scripts/*").select { |f| File.file?(f) }.reject{ |f| f['index.md'] || f['README.mdown'] || f['README.md']}

				# Get output files
				out_array = Dir.glob("tutorials/#{reponame}/precooked_runs/*").select { |f| File.file?(f) }.reject{ |f| f['index.md'] || f['README.mdown'] || f['README.md']}

				# load contributor metadata
				octokit_contributors = client.contributors(repo)					
				tutorial_contributors = Array.new
				for i in 0 ... [octokit_contributors.size, 5].min
					contributor = octokit_contributors[i]					
					contributor_login = contributor.login
					contributor_avatar = contributor.rels[:avatar].href + "&s=50"
					contributor_url = contributor.rels[:html].href
					tutorial_contributors = tutorial_contributors.push(
						"login" => contributor_login,
						"avatar" => contributor_avatar,
						"url" => contributor_url
					)
				end
			
				# load commit metadata
				octokit_commits = client.commits(repo)
				tutorial_commits = Array.new		
				for i in 0 ... [octokit_commits.size, 5].min	
					commit = octokit_commits[i]		
					commit_date = commit.commit.author.date
					commit_message = commit.commit.message
					commit_url = commit.rels[:html].href
					if commit.author == nil then 
					   	commit.author = "Unknown"
					   	commit_author_login = "Unknown"
					   	commit_author_url = "" 
					else
						commit_author_login = commit.author.login
						commit_author_url = commit.author.rels[:html].href		
					end
					
					tutorial_commits = tutorial_commits.push(
						"date" => commit_date,
						"message" => commit_message,
						"url" => commit_url,
						"author_login" => commit_author_login,							
						"author_url" => commit_author_url					
					)
				
				end
			
				# assemble metadata
				tutorial_data = tutorial_data.push(
					"repo" => repo,
					"url" => tutorial_url,
					"title" => tutorial_title,						
					"description" => tutorial_description,
					"owner" => tutorial_owner,
					"author" => tutorial_author,
					"contributors" => tutorial_contributors,
					"level" => tutorial_level,
					"beastversion_tutorial" => tutorial_beast,
					"beastversion_package" => tutorial_beast_package,
					# Derived fields for the tutorial listing (_includes/tutorial_card.html):
					# beast_package_minor drives the BEAST version filter, sort and badge;
					# updated is the card's "Updated" date.
					"beast_package_minor" => tutorial_beast_package_minor,
					"slug" => reponame,
					"folder" => reponame,
					"updated" => (tutorial_commits.first && tutorial_commits.first["date"].respond_to?(:strftime)) ? tutorial_commits.first["date"].strftime("%Y-%m-%d") : nil,
					"workflow" => tutorial_workflow,
					"packages" => tutorial_packages,
					"keywords" => tutorial_keywords,
					"status" => tutorial_status,
					"deprecated_reason" => tutorial_deprecated_reason,
					"deprecated_alternative" => tutorial_deprecated_alternative,
					"domains" => tutorial_domains,
					"commits" => tutorial_commits,
					"default_branch" => tutorial_default_branch,
					"pdfs" => pdf_array,
					"data" => data_array,
					"xmls" => xml_array,
					"scripts" => script_array,
					"outputs" => out_array
				)

				puts "\tDone (#{repo})"

			end
		end

		# Sort by date of the latest commit, newest first. Done once after the
		# loop; tutorials without commits sort last.
		latest = lambda do |t|
			d = (t["commits"] || []).first&.dig("date")
			d.respond_to?(:to_time) ? d.to_time.utc : Time.at(0).utc
		end
		tutorial_data.sort_by! { |t| latest.(t) }.reverse!
			
		missing = tutorial_data.select { |t| t["beast_package_minor"].nil? }.map { |t| t["repo"] }
		unless missing.empty?
			puts "INFO: #{missing.size} of #{tutorial_data.size} tutorials have no beastversion_package " \
				"(shown as 'Not specified' in the BEAST version filter):"
			missing.each { |r| puts "\t#{r}" }
		end

		return tutorial_data
			
	end
	
	def self.write_data(tutorial_data, data_file)

		puts "Writing tutorial data"
		File.write(data_file, tutorial_data.to_yaml)

	end

	# Values of a field across all tutorials, ranked by tutorial count (desc), ties alphabetical.
	def self.rank_by_count(tutorial_data, field)
		tutorial_data
			.flat_map { |t| t[field] || [] }
			.reject { |v| v.nil? || v.to_s.strip.empty? }
			.tally
			.sort_by { |val, count| [-count, val] }
			.map(&:first)
	end

	def self.write_ranked(tutorial_data, field, data_file, limit = nil)
		ranked = rank_by_count(tutorial_data, field)
		ranked = ranked.first(limit) if limit
		puts "Writing #{ranked.size} ranked #{field}"
		File.write(data_file, ranked.to_yaml)
	end

end

tutorial_data = Tutorials.generate_data("_config.yml")
Tutorials.write_data(tutorial_data, "_data/tutorials.yml")
Tutorials.write_ranked(tutorial_data, "keywords", "_data/popular_keywords.yml", 20)
Tutorials.write_ranked(tutorial_data, "packages", "_data/popular_packages.yml")
# Workflow filter options on the tutorial listing, in schema order.
File.write("_data/tutorial_workflows.yml", Array(Tutorials.schema["workflows"]).to_yaml)
