require 'graphql/client'
require 'graphql/client/http'
require 'byebug'

module GitHubGraphQL
    HTTP = GraphQL::Client::HTTP.new("https://api.github.com/graphql") do
        def headers(context)
            { "Authorization" => "Bearer #{ENV['GITHUB_TOKEN']}" }
        end
    end

    # Fetch latest schema on init, this will make a network request
    Schema = GraphQL::Client.load_schema(HTTP)


    Client = GraphQL::Client.new(schema: Schema, execute: HTTP)
end

module GitHubGraphQLQuery
    PullRequest = GitHubGraphQL::Client.parse <<-'GRAPHQL'
        query($query: String!, $first: Int!, $after: String) {
            search(query: $query, type: ISSUE, first: $first, after: $after) {
                issueCount
                pageInfo {
                        hasNextPage
                        endCursor
                }
                edges {
                    node {
                        ... on PullRequest {
                            number
                            title
                            repository {
                                name
                                nameWithOwner
                            }
                            createdAt
                            url
                            headRefName  # Branch name
                            baseRefName  # Base branch name
                            labels(first: 10) {
                                edges {
                                    node {
                                        name  # Label name
                                    }
                                }
                            }
                            commits(last: 1) {
                                edges {
                                    node {
                                        commit {
                                            oid  # The commit SHA
                                            status {
                                                contexts {
                                                    context  # CI tool name
                                                    state  # CI status (success/failure)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            author {
                                login  # The username of the author
                                url     # The author's profile URL
                            }
                        }
                    }
                }
            }
        }      
    GRAPHQL
end


# Generator function that fetches PR nodes lazily with pagination
def fetch_pull_requests(query, batch_size)
    Enumerator.new do |yielder|
        after_cursor = nil
        loop do
            # Define the variables for the GraphQL query
            variables = {
                query: query,
                first: batch_size,
                after: after_cursor
            }
            
            # Fetch the data from GitHub GraphQL API
            response = GitHubGraphQL::Client.query(GitHubGraphQLQuery::PullRequest, variables: variables)
            
            # Extract the edges and page information
            edges = response.data.search.edges
            page_info = response.data.search.page_info
    
            # Yield each PR node in the current batch
            edges.each do |edge|
                pr = edge.node
                yielder.yield pr
            end
    
            # Check if there's a next page
            break unless page_info.has_next_page
            
            # Set the cursor for the next page fetch
            after_cursor = page_info.end_cursor
        end
    end
end
  
# Usage
query = "is:open is:pr archived:false org:Microsoft org:Google"
batch_size = 100

# Create the enumerator that fetches pull requests
pr_enumerator = fetch_pull_requests(query, batch_size)

# Iterate over the enumerator
pr_enumerator.each do |pr|
    puts "PR's Info:"
    puts " * Title: #{pr.title}"
    puts " * URL: #{pr.url}"
    puts " * Number: #{pr.number}"
    puts " * Created At: #{pr.created_at}"
    puts " * Branch name: #{pr.head_ref_name}"
    puts " * Base branch name: #{pr.base_ref_name}"
    puts " * Author's username: #{pr.author.login}"

    # Labels handling
    puts " * Labels:"
    pr.labels.edges.each do |label|
      puts "   * #{label.node.name}"
    end
    
    # Repository Info
    puts " * Repository's Info:"
    puts "   * Name with owner: #{pr.repository.name_with_owner}"
    puts "   * Name: #{pr.repository.name}"
    

    # Handle commits if available
    if pr.commits.edges.any?  # Check if there are any commits
        commit = pr.commits.edges.first.node.commit  # Get the first commit if available
        puts " * Commit Info:"
        puts "   * Commit SHA: #{commit.oid}"  # Commit SHA
        if commit.status
            puts "   * Checks:"
            commit.status.contexts.each do |context|
                puts "     * Name: #{context.context}"  # CI status and tool name
                puts "       Status: #{context.state}"
            end
        end 
    else
        puts " * No commits found"
    end
      
    # Add more logic as needed...
    puts "-" * 40
end
