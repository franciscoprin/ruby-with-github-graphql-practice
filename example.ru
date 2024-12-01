require_relative 'graphql/github'
require 'dotenv/load'
require 'byebug'

query = "is:open is:pr archived:false org:Microsoft org:Google"
batch_size = 100

GitHubGraphQLPullRequest.fetch(query, batch_size).each do |pr|
    puts "PR's Info:"
    puts " * Title: #{pr.title}"
    puts " * URL: #{pr.url}"
    puts " * Number: #{pr.number}"
    puts " * Created at: #{pr.created_at}"
    puts " * Branch name: #{pr.branches.head}"
    puts " * Base branch name: #{pr.branches.base}"
    puts " * Author's username: #{pr.author&.username}"

    # Labels handling
    if pr.labels
        puts " * Labels:"
        pr.labels do |label|
            puts "   * #{label}"
        end
    end
    
    # Repo handling
    puts " * Repository's Info:"
    puts "   * Name with owner: #{pr.repository.name_with_owner}"
    puts "   * Name: #{pr.repository.name}"

    # Commit handling
    puts " * Commit Info:"
    puts "   * Commit SHA: #{pr.latest_commit.sha}"
    if pr.latest_commit.statuses
        puts "   * Checks:"
        pr.latest_commit.statuses.each do |status|
            puts "     * Name: #{status.name}"
            puts "       Status: #{status.state}"
        end
    end

    puts "-" * 40
end
