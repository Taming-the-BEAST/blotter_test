# Shared Octokit client builder for the data-generation scripts
# (generate-tutorial-data.rb, generate-project-data.rb).

require 'octokit'
require 'faraday/retry'

module OctokitClient

	RETRY_OPTIONS = {
		max: 3,
		interval: 0.5,
		interval_randomness: 0.5,
		backoff_factor: 2,
		exceptions: [
			Octokit::ServerError,
			Faraday::ConnectionFailed,
			Faraday::TimeoutError
		]
	}.freeze

	MIDDLEWARE = Faraday::RackBuilder.new do |builder|
		builder.use Faraday::Retry::Middleware, RETRY_OPTIONS
		builder.use Octokit::Middleware::FollowRedirects
		builder.use Octokit::Response::RaiseError
		builder.use Octokit::Response::FeedParser
		builder.adapter Faraday.default_adapter
	end

	def self.build
		Octokit::Client.new(:netrc => true, :access_token => ENV['GITHUB_TOKEN'], :middleware => MIDDLEWARE)
	end

end
