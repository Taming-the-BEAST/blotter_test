#!/usr/bin/env ruby
require 'yaml'
require 'fileutils'

class TutorialMigrator
  def analyze_content(text)
    text_lower = text.downcase
    
    {
      keywords: detect_keywords(text_lower),
      packages: detect_packages(text_lower),
      tutorial_type: detect_type(text_lower),
      domains: detect_domains(text_lower)
    }
  end
  
  def detect_keywords(text)
    keywords = []
    
    patterns = {
      'coalescent' => /coalescent/,
      'birth-death' => /birth.?death/,
      'molecular clock' => /molecular clock/,
      'calibration' => /calibrat/,
      'phylogeography' => /phylogeograph/,
      'structured population' => /structured|population structure/,
      'skyline' => /skyline/,
      'migration' => /migration/,
      'MCMC' => /mcmc/,
      'Bayesian inference' => /bayesian/
    }
    
    patterns.each do |keyword, pattern|
      keywords << keyword if text =~ pattern
    end
    
    keywords.take(8)
  end
  
  def detect_packages(text)
    packages = []
    
    patterns = {
      'BDSKY' => /bdsky|birth.?death skyline/,
      'MASCOT' => /mascot/,
      'MultiTypeTree' => /multitypetree|mtt/,
      'StarBeast3' => /starbeast3/,
      'StarBeast2' => /starbeast2/,
      'StarBeast' => /starbeast(?!2|3)/,
      'SCOTTI' => /scotti/,
      'SA' => /sampled ancestor/
    }
    
    patterns.each do |package, pattern|
      packages << package if text =~ pattern
    end
    
    packages
  end
  
  def detect_type(text)
    return 'Core' if text =~ /introduction|getting started|basic/
    return 'Applied' if text =~ /case study|application/
    'Model set-up'
  end
  
  def detect_domains(text)
    domains = []
    
    patterns = {
      'virology' => /virus|viral|influenza/,
      'epidemiology' => /epidem|outbreak|transmission/,
      'phylogeography' => /phylogeograph|geographic/,
      'speciation' => /speciation|species tree/
    }
    
    patterns.each do |domain, pattern|
      domains << domain if text =~ pattern
    end
    
    domains.empty? ? ['general'] : domains
  end
  
  def migrate(readme_path)
    content = File.read(readme_path)
    
    unless content =~ /\A---\s*\n(.*?)\n---\s*\n/m
      return { error: "No frontmatter found" }
    end
    
    existing = YAML.load($1)
    rest = $'
    
    suggestions = analyze_content(content)
    
    updated = existing.merge(
      'keywords' => suggestions[:keywords],
      'packages' => suggestions[:packages],
      'tutorial_type' => suggestions[:tutorial_type],
      'status' => 'current',
      'domains' => suggestions[:domains]
    )
    
    {
      existing: existing,
      suggested: suggestions,
      updated: updated,
      content: rest
    }
  end
  
  def write_updated(readme_path, frontmatter, content)
    FileUtils.cp(readme_path, "#{readme_path}.backup")
    
    File.open(readme_path, 'w') do |f|
      f.write("---\n")
      f.write(YAML.dump(frontmatter).sub(/\A---\n/, ''))
      f.write("---\n")
      f.write(content)
    end
  end
end

if __FILE__ == $0
  tutorial_dir = ARGV[0]
  
  unless tutorial_dir
    puts "Usage: migrate_tutorial.rb TUTORIAL_DIR"
    exit 1
  end
  
  readme_path = File.join(tutorial_dir, 'README.md')
  
  unless File.exist?(readme_path)
    puts "Error: #{readme_path} not found"
    exit 1
  end
  
  migrator = TutorialMigrator.new
  result = migrator.migrate(readme_path)
  
  if result[:error]
    puts "Error: #{result[:error]}"
    exit 1
  end
  
  puts "\n" + "=" * 70
  puts "Tutorial: #{tutorial_dir}"
  puts "=" * 70
  
  puts "\nSuggested metadata:"
  puts result[:suggested].to_yaml
  
  puts "\nUpdated frontmatter:"
  puts result[:updated].to_yaml
  
  print "\nApply changes? (y/n): "
  response = gets.chomp.downcase
  
  if response == 'y'
    migrator.write_updated(readme_path, result[:updated], result[:content])
    puts "✓ Updated #{readme_path}"
    puts "  Backup: #{readme_path}.backup"
  else
    puts "No changes applied"
  end
end
