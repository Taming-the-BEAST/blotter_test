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

	# Field-by-field merge: a tutorial's own frontmatter always wins per
	# field; only fields the tutorial does not define are filled in from the
	# central fallback file. Warn when a tutorial already defines a field
	# also present in the fallback file, since that fallback entry is now
	# redundant and should be removed upstream.
	def self.merge_fallback_metadata(repo, tutorial_header, fallback_metadata)
		fallback = fallback_metadata[repo]
		return tutorial_header unless fallback

		merged = tutorial_header.dup
		FALLBACK_FIELDS.each do |field|
			own_present = !blank?(tutorial_header[field])
			fallback_present = !blank?(fallback[field])

			if own_present && fallback_present
				puts "\t\tWARNING: #{repo} now defines '#{field}' itself — remove it from #{METADATA_FALLBACK_FILE}"
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
				reponame  = octokit_repo.name

				tutorial_owner = octokit_repo.owner.login
				tutorial_description = octokit_repo.description
				tutorial_url = "/tutorials/#{reponame}/"
				tutorial_date = octokit_repo.updated_at
				tutorial_default_branch = octokit_repo.default_branch
				#puts "\t\tDefault branch #{tutorial_default_branch}"

				# load tutorial header metadata from README.md
				# overwrite description with tutorial header description if not empty
				tutorial_header = YAML.load_file("tutorials/#{reponame}/README.md",
					permitted_classes: [Date, Time], aliases: true)
				# A README without parseable frontmatter yields nil/String, not a Hash.
				unless tutorial_header.is_a?(Hash)
					puts "\t\tWARNING: #{repo} README.md has no usable frontmatter - skipping"
					next
				end
				tutorial_header = merge_fallback_metadata(repo, tutorial_header, fallback_metadata)

				tutorial_level  = tutorial_header["level"]
				tutorial_title  = tutorial_header["title"]
				tutorial_author = tutorial_header["author"]
				tutorial_beast  = tutorial_header["beastversion_tutorial"] || tutorial_header["beastversion"]
				tutorial_beast_package = tutorial_header["beastversion_package"]
				tutorial_workflow = tutorial_header["workflow"] || tutorial_header["tutorial_type"]
				tutorial_packages = tutorial_header["packages"] || []
				tutorial_keywords = tutorial_header["keywords"] || []
				tutorial_status = tutorial_header["status"]
				tutorial_deprecated_reason = tutorial_header["deprecated_reason"]
				tutorial_deprecated_alternative = tutorial_header["deprecated_alternative"]
				tutorial_domains = tutorial_header["domains"] || []
				if (tutorial_header["subtitle"] != nil && tutorial_description != tutorial_header["subtitle"])
				   tutorial_description = tutorial_header["subtitle"]
				end

				# Get all pdfs in the root
				pdf_array = Dir.glob("tutorials/#{reponame}/**/*.pdf").reject{ |f| f['/figures/']}

				# Get data files 
				data_array = Dir.glob("tutorials/#{reponame}/data/*").reject{ |f| f['index.md'] || f['README.mdown'] || f['README.md']}				

				# Get xml files
				xml_array = Dir.glob("tutorials/#{reponame}/xml/*.xml")

				# Get scripts files
				script_array = Dir.glob("tutorials/#{reponame}/scripts/*").reject{ |f| f['index.md'] || f['README.mdown'] || f['README.md']}				

				# Get output files
				out_array = Dir.glob("tutorials/#{reponame}/precooked_runs/*").reject{ |f| f['index.md'] || f['README.mdown'] || f['README.md']}				

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

				# sort by date
				tutorial_data.sort! { |x, y| y["commits"].first["date"] <=> x["commits"].first["date"] } 
			
				puts "\tDone (#{repo})"

			end
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
