# Legacy front matter keys, shared by generate-tutorial-data.rb and
# validate_tutorial_metadata.rb so both treat old-style READMEs the same way.

module TutorialMetadataAliases
	# canonical key => legacy keys accepted in its place
	ALIASES = {
		"beastversion_tutorial" => ["beastversion"],
		"workflow" => ["tutorial_type"],
	}.freeze

	# A field counts as defined when present and not nil or a blank string.
	# An explicit empty list (`packages: []`) IS defined.
	def self.defined_value?(header, field)
		return false unless header.key?(field)
		v = header[field]
		!(v.nil? || (v.is_a?(String) && v.strip.empty?))
	end

	# Copy legacy keys into their canonical key when the canonical key is not
	# defined. A legacy `tutorial_type` from the old vocabulary (Core / Model
	# set-up / Applied) is not a valid workflow and is ignored, so a curated
	# fallback value can still apply.
	#
	# Returns [header, messages]; messages are [level, text, canonical, legacy]
	# with level :info (legacy key used) or :invalid (legacy value not valid,
	# not used). The generator only warns about :invalid (a fallback value can
	# apply); the validator reports it as an invalid workflow.
	def self.resolve(tutorial_header, allowed_workflows = [])
		header = tutorial_header.dup
		messages = []
		ALIASES.each do |canonical, legacy_keys|
			next if defined_value?(header, canonical)
			legacy_keys.each do |legacy|
				next unless defined_value?(header, legacy)
				if canonical == "workflow" && !allowed_workflows.empty? &&
					!allowed_workflows.include?(header[legacy])
					messages << [:invalid, "legacy '#{legacy}: #{header[legacy]}' is not a valid workflow", canonical, legacy]
					break
				end
				header[canonical] = header[legacy]
				messages << [:info, "legacy field '#{legacy}' used as '#{canonical}'; rename it to '#{canonical}'", canonical, legacy]
				break
			end
		end
		[header, messages]
	end
end
