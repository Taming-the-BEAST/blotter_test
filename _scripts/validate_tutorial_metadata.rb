#!/usr/bin/env ruby
# Tutorial Metadata Validator
# This script validates tutorial YAML frontmatter against the schema

require 'yaml'
require 'date'
require 'set'
require_relative 'tutorial_metadata_aliases'

class TutorialMetadataValidator
  attr_reader :schema, :errors, :warnings
  
  def initialize(schema_file)
    @schema = YAML.load_file(schema_file)
    @errors = []
    @warnings = []
  end
  
  def validate(tutorial_frontmatter)
    @errors = []
    @warnings = []

    tutorial_frontmatter = apply_legacy_aliases(tutorial_frontmatter || {})
    validate_required_fields(tutorial_frontmatter)
    validate_workflow(tutorial_frontmatter)
    validate_status(tutorial_frontmatter)
    validate_keywords(tutorial_frontmatter)
    validate_packages(tutorial_frontmatter)
    validate_domains(tutorial_frontmatter)
    validate_legacy_fields(tutorial_frontmatter)
    validate_versions(tutorial_frontmatter)
    check_recommended_fields(tutorial_frontmatter)

    {
      valid: @errors.empty?,
      errors: @errors,
      warnings: @warnings
    }
  end
  
  private

  # Schema sections may be missing; treat them as empty instead of crashing.
  def schema_list(key)
    Array(@schema[key])
  end

  # Same legacy-key handling as generate-tutorial-data.rb (shared module).
  def apply_legacy_aliases(frontmatter)
    fm, messages = TutorialMetadataAliases.resolve(frontmatter, schema_list('workflows'))
    messages.each do |level, text, canonical, legacy|
      if level == :invalid
        # The generator ignores this value; here it is validated as the
        # canonical field, so the author gets one "Invalid workflow" error.
        fm[canonical] = frontmatter[legacy]
        @warnings << "Legacy field '#{legacy}' used; rename it to '#{canonical}'"
      else
        @warnings << text.sub(/\Alegacy/, 'Legacy')
      end
    end
    fm
  end

  def validate_domains(frontmatter)
    domains = frontmatter['domains']
    return if domains.nil?
    unless domains.is_a?(Array)
      @errors << "Domains must be a list"
      return
    end
    allowed = schema_list('domains')
    unknown = domains.reject { |d| allowed.include?(d) }
    if unknown.any?
      @errors << "Unknown domain(s): #{unknown.join(', ')}. Must be one of: #{allowed.join(', ')}"
    end
  end

  def validate_required_fields(frontmatter)
    schema_list('required_fields').each do |field|
      unless frontmatter.key?(field) && !frontmatter[field].to_s.strip.empty?
        @errors << "Missing required field: #{field}"
      end
    end
  end
  
  def validate_workflow(frontmatter)
    if frontmatter['workflow']
      unless schema_list('workflows').include?(frontmatter['workflow'])
        @errors << "Invalid workflow '#{frontmatter['workflow']}'. Must be one of: #{schema_list('workflows').join(', ')}"
      end
    else
      @warnings << "Required field 'workflow' is missing"
    end
  end
  
  def validate_status(frontmatter)
    if frontmatter['status']
      unless schema_list('status_values').include?(frontmatter['status'])
        @errors << "Invalid status '#{frontmatter['status']}'. Must be one of: #{schema_list('status_values').join(', ')}"
      end
    else
      @warnings << "Recommended field 'status' is missing (defaulting to 'current')"
    end
  end
  
  def validate_keywords(frontmatter)
    if frontmatter['keywords']
      keywords = frontmatter['keywords']
      
      unless keywords.is_a?(Array)
        @errors << "Keywords must be a list"
        return
      end
      
      rules = (@schema['validation_rules'] || {})['keywords'] || {}
      
      if rules['min'] && keywords.length < rules['min']
        @warnings << "Only #{keywords.length} keywords provided. Recommended minimum: #{rules['min']}"
      end
      
      if rules['max'] && keywords.length > rules['max']
        @warnings << "#{keywords.length} keywords provided. Recommended maximum: #{rules['max']}"
      end
      
      # Check if keywords are from recommended taxonomy
      all_keywords = collect_all_keywords(@schema['keyword_taxonomy'] || {})
      unknown_keywords = keywords - all_keywords
      
      if unknown_keywords.any?
        @warnings << "Non-standard keywords detected: #{unknown_keywords.join(', ')}. Consider using keywords from the recommended taxonomy."
      end
    else
      @warnings << "Recommended field 'keywords' is missing"
    end
  end
  
  def validate_packages(frontmatter)
    if frontmatter['packages']
      packages = frontmatter['packages']
      
      unless packages.is_a?(Array)
        @errors << "Packages must be a list"
        return
      end
      
      rules = (@schema['validation_rules'] || {})['packages'] || {}
      
      if rules['max'] && packages.length > rules['max']
        @warnings << "#{packages.length} packages listed. Consider limiting to #{rules['max']} most important packages."
      end
      
      # Check if packages are known
      unknown_packages = packages - schema_list('packages')
      
      if unknown_packages.any?
        @warnings << "Unknown packages detected: #{unknown_packages.join(', ')}. If these are valid BEAST2 packages, please add them to the schema."
      end
    end
  end
  
  # BEAST versions: quoted strings like '2.7', '2.7.x' or '2.7.7'.
  VERSION_FIELDS = %w[beastversion_tutorial beastversion_package].freeze

  def validate_versions(frontmatter)
    VERSION_FIELDS.each do |field|
      next unless frontmatter.key?(field) && !frontmatter[field].nil?
      v = frontmatter[field]
      if v.is_a?(Float) || v.is_a?(Integer)
        @warnings << "#{field}: #{v} is unquoted; write it as '#{v}' (an unquoted 2.10 is read as 2.1)"
        next
      end
      s = v.to_s.strip
      if s =~ /\A(>=|<=|>|<|~|\^)/
        @warnings << "#{field}: '#{s}' is a range; use the concrete version (e.g. '2.7')"
      elsif s !~ /\A\d+\.\d+(\.(\d+|x))?\z/
        @errors << "#{field}: '#{s}' is not a version like '2.7', '2.7.x' or '2.7.7'"
      end
    end
  end

  def validate_legacy_fields(frontmatter)
    if frontmatter['status'] == 'deprecated'
      unless frontmatter['deprecated_reason'] && !frontmatter['deprecated_reason'].to_s.strip.empty?
        @errors << "Deprecated tutorials must include 'deprecated_reason'"
      end

      unless frontmatter['deprecated_alternative']
        @warnings << "Deprecated tutorial should provide 'deprecated_alternative' link to updated tutorial if available"
      end
    end
  end
  
  def check_recommended_fields(frontmatter)
    schema_list('recommended_fields').each do |field|
      unless frontmatter.key?(field)
        @warnings << "Recommended field '#{field}' is missing"
      end
    end
  end
  
  def collect_all_keywords(taxonomy, result = Set.new)
    taxonomy.each do |key, value|
      if value.is_a?(Array)
        result.merge(value)
      elsif value.is_a?(Hash)
        collect_all_keywords(value, result)
      end
    end
    result.to_a
  end
end

# Example usage
if __FILE__ == $0
  require 'optparse'
  
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: validate_tutorial_metadata.rb [options] tutorial_file.md"
    
    opts.on("-s", "--schema FILE", "Path to schema file") do |s|
      options[:schema] = s
    end
    
    opts.on("-h", "--help", "Prints this help") do
      puts opts
      exit
    end
  end.parse!
  
  if ARGV.empty?
    puts "Error: No tutorial file specified"
    exit 1
  end
  
  # tutorials/tutorial_schema.yml is the tracked schema; _data/ is generated and gitignored.
  schema_file = options[:schema] || 'tutorials/tutorial_schema.yml'
  tutorial_file = ARGV[0]
  
  # Extract frontmatter from tutorial file
  content = File.read(tutorial_file)
  
  if content =~ /\A---\s*\n(.*?)\n---\s*\n/m
    frontmatter = YAML.load($1, permitted_classes: [Date, Time], aliases: true)
    
    validator = TutorialMetadataValidator.new(schema_file)
    result = validator.validate(frontmatter)
    
    puts "Validating: #{tutorial_file}"
    puts "=" * 60
    
    if result[:valid]
      puts "OK: VALID"
    else
      puts "ERROR: INVALID"
      puts "\nErrors:"
      result[:errors].each { |e| puts "  - #{e}" }
    end
    
    if result[:warnings].any?
      puts "\nWarnings:"
      result[:warnings].each { |w| puts "  - #{w}" }
    end
    
    puts "=" * 60
    
    exit(result[:valid] ? 0 : 1)
  else
    puts "Error: No YAML frontmatter found in #{tutorial_file}"
    exit 1
  end
end
