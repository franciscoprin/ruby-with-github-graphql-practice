require 'graphql/client'
require 'graphql/client/http'
require 'ostruct'


module GitHubGraphQL
    HTTP = GraphQL::Client::HTTP.new(ENV['GITHUB_GRAPHQL_URL']) do
        def headers(context)
            { 'Authorization' => "Bearer #{ENV['GITHUB_TOKEN']}" }
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
                            headRefName
                            baseRefName
                            labels(first: 10) {
                                edges {
                                    node {
                                        name
                                    }
                                }
                            }
                            commits(last: 1) {
                                edges {
                                    node {
                                        commit {
                                            oid  # The commit SHA
                                            status {
                                                contexts { # Checks
                                                    context  # Check's name
                                                    state  # Check's status (success/failure)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            author {
                                login  # The username of the author
                                url    # The author's profile URL
                            }
                        }
                    }
                }
            }
        }      
    GRAPHQL
end


class GitHubGraphQLPullRequest

    # Fetch pull requests and parse them into clean objects
    def self.fetch(query, batch_size)
      Enumerator.new do |yielder|
        after_cursor = nil
        loop do
            variables = { query: query, first: batch_size, after: after_cursor }
            response = GitHubGraphQL::Client.query(GitHubGraphQLQuery::PullRequest, variables: variables)
    
            edges = response.data.search.edges
            page_info = response.data.search.page_info
    
            edges.each do |edge|
                yielder.yield parse(edge.node)
            end
    
            break unless page_info.has_next_page
            after_cursor = page_info.end_cursor
        end
      end
    end
  
    # Parse a raw pull request node into a clean object
    def self.parse(node)
        OpenStruct.new({
            number: node.number,
            title: node.title,
            repository: OpenStruct.new({
                name: node.repository.name,
                full_name: node.repository.name_with_owner
            }),
            created_at: node.created_at,
            url: node.url,
            branches: OpenStruct.new({
                head: node.head_ref_name,
                base: node.base_ref_name
            }),
            labels: node.labels.edges.map { |label_edge| label_edge.node.name },
            latest_commit: OpenStruct.new({
                sha: node.commits.edges.last&.node&.commit&.oid,
                statuses: node.commits.edges.last&.node&.commit&.status&.contexts&.map do |context|
                    OpenStruct.new({
                        name: context.context,
                        state: context.state
                    })
                end
            }),
            author: OpenStruct.new({
                username: node.author&.login,
                profile_url: node.author.url
            })
        })
    end
end
