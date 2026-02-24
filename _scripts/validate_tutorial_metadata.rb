#!/usr/bin/env ruby
# Tutorial Metadata Validator
# This script validates tutorial YAML frontmatter against the schema

require 'yaml'
require 'set'

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

    validate_required_fields(tutorial_frontmatter)
    validate_workflow(tutorial_frontmatter)
    validate_status(tutorial_frontmatter)
    validate_keywords(tutorial_frontmatter)
    validate_packages(tutorial_frontmatter)
    validate_legacy_fields(tutorial_frontmatter)
    check_recommended_fields(tutorial_frontmatter)

    {
      valid: @errors.empty?,
      errors: @errors,
      warnings: @warnings
    }
  end
  
  private
  
  def validate_required_fields(frontmatter)
    @schema['required_fields'].each do |field|
      unless frontmatter.key?(field) && !frontmatter[field].to_s.strip.empty?
        @errors << "Missing required field: #{field}"
      end
    end
  end
  
  def validate_workflow(frontmatter)
    if frontmatter['workflow']
      unless @schema['workflows'].include?(frontmatter['workflow'])
        @errors << "Invalid workflow '#{frontmatter['workflow']}'. Must be one of: #{@schema['workflows'].join(', ')}"
      end
    else
      @warnings << "Required field 'workflow' is missing"
    end
  end
  
  def validate_status(frontmatter)
    if frontmatter['status']
      unless @schema['status_values'].include?(frontmatter['status'])
        @errors << "Invalid status '#{frontmatter['status']}'. Must be one of: #{@schema['status_values'].join(', ')}"
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
      
      rules = @schema['validation_rules']['keywords']
      
      if keywords.length < rules['min']
        @warnings << "Only #{keywords.length} keywords provided. Recommended minimum: #{rules['min']}"
      end
      
      if keywords.length > rules['max']
        @warnings << "#{keywords.length} keywords provided. Recommended maximum: #{rules['max']}"
      end
      
      # Check if keywords are from recommended taxonomy
      all_keywords = collect_all_keywords(@schema['keyword_taxonomy'])
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
      
      rules = @schema['validation_rules']['packages']
      
      if packages.length > rules['max']
        @warnings << "#{packages.length} packages listed. Consider limiting to #{rules['max']} most important packages."
      end
      
      # Check if packages are known
      unknown_packages = packages - @schema['packages']
      
      if unknown_packages.any?
        @warnings << "Unknown packages detected: #{unknown_packages.join(', ')}. If these are valid BEAST2 packages, please add them to the schema."
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
    @schema['recommended_fields'].each do |field|
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
  
  schema_file = options[:schema] || '_data/tutorial_schema.yml'
  tutorial_file = ARGV[0]
  
  # Extract frontmatter from tutorial file
  content = File.read(tutorial_file)
  
  if content =~ /\A---\s*\n(.*?)\n---\s*\n/m
    frontmatter = YAML.load($1)
    
    validator = TutorialMetadataValidator.new(schema_file)
    result = validator.validate(frontmatter)
    
    puts "Validating: #{tutorial_file}"
    puts "=" * 60
    
    if result[:valid]
      puts "✓ VALID"
    else
      puts "✗ INVALID"
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
