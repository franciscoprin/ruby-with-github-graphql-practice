# frozen_string_literal: true

# This module provides access to GitHub GraphQL API using the graphql-client gem.
module GitHubGraphQL
  require 'graphql/client'
  require 'graphql/client/http'

  HTTP = GraphQL::Client::HTTP.new(ENV['GITHUB_GRAPHQL_URL']) do
    def headers(_context)
      { 'Authorization' => "Bearer #{ENV['GITHUB_TOKEN']}" }
    end
  end

  # Fetch latest schema on init; this will make a network request
  Schema = GraphQL::Client.load_schema(HTTP)

  Client = GraphQL::Client.new(schema: Schema, execute: HTTP)
end

# This module defines GraphQL queries used in the GitHubGraphQL client.
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

# Structs for representing parsed pull request data
RepositoryStruct = Struct.new(:name, :full_name, keyword_init: true)
BranchesStruct = Struct.new(:head, :base, keyword_init: true)
CommitStatusStruct = Struct.new(:name, :state, keyword_init: true)
LatestCommitStruct = Struct.new(:sha, :statuses, keyword_init: true)
AuthorStruct = Struct.new(:username, :profile_url, keyword_init: true)

# Provides methods to fetch and parse pull requests from the GitHub GraphQL API.
class GitHubGraphQLPullRequest
  attr_reader :number, :title, :repository, :created_at, :url, :branches,
              :labels, :latest_commit, :author

  # Constructor for GitHubGraphQLPullRequest
  #
  # @param number [Integer] The pull request number.
  # @param title [String] The title of the pull request.
  # @param repository [Hash] A hash containing repository details:
  #   - :name [String] The repository's short name.
  #   - :full_name [String] The full name of the repository (e.g., "owner/repo").
  # @param created_at [String] The creation timestamp of the pull request in ISO 8601 format.
  # @param url [String] The URL to the pull request.
  # @param branches [Hash] A hash containing branch information:
  #   - :head [String] The name of the head branch.
  #   - :base [String] The name of the base branch.
  # @param labels [Array<String>] A list of label names associated with the pull request.
  # @param latest_commit [Hash] A hash containing information about the latest commit:
  #   - :sha [String, nil] The SHA of the latest commit.
  #   - :statuses [Array<Hash>, nil] A list of status checks for the commit, each represented as:
  #     - :name [String] The name of the check.
  #     - :state [String] The state of the check (e.g., "success", "failure").
  # @param author [Hash] A hash containing author details:
  #   - :username [String, nil] The username of the pull request author.
  #   - :profile_url [String] The URL to the author's profile.
  def initialize(
    number:, title:, repository:, created_at:, url:, branches:,
    labels:, latest_commit:, author:
  )
    @number = number
    @title = title
    @repository = repository
    @created_at = created_at
    @url = url
    @branches = branches
    @labels = labels
    @latest_commit = latest_commit
    @author = author
  end

  # Fetch pull requests and parse them into clean objects
  def self.fetch(query, batch_size)
    Enumerator.new do |yielder|
      after_cursor = nil
      loop do
        variables = { query: query, first: batch_size, after: after_cursor }
        response = GitHubGraphQL::Client.query(GitHubGraphQLQuery::PullRequest, variables: variables)

        process_edges(response.data.search.edges, yielder)
        after_cursor = response.data.search.page_info.end_cursor

        break unless response.data.search.page_info.has_next_page
      end
    end
  end

  # Parse pull requests edges and yield each node
  def self.process_edges(edges, yielder)
    edges.each do |edge|
      yielder.yield parse(edge.node)
    end
  end

  # Parse a raw pull request node into a clean object
  def self.parse(node)
    GitHubGraphQLPullRequest.new(
      number: node.number,
      title: node.title,
      repository: parse_repository(node.repository),
      created_at: node.created_at,
      url: node.url,
      branches: parse_branches(node),
      labels: parse_labels(node.labels),
      latest_commit: parse_latest_commit(node.commits),
      author: parse_author(node.author)
    )
  end

  def self.parse_repository(repository)
    RepositoryStruct.new(
      name: repository.name,
      full_name: repository.name_with_owner
    )
  end

  def self.parse_branches(node)
    BranchesStruct.new(
      head: node.head_ref_name,
      base: node.base_ref_name
    )
  end

  def self.parse_labels(labels)
    labels.edges.map { |label_edge| label_edge.node.name }
  end

  def self.parse_latest_commit(commits)
    last_commit = commits.edges.last&.node&.commit
    LatestCommitStruct.new(
      sha: last_commit&.oid,
      statuses: last_commit&.status&.contexts&.map { |context| parse_status(context) }
    )
  end

  def self.parse_status(context)
    CommitStatusStruct.new(
      name: context.context,
      state: context.state
    )
  end

  def self.parse_author(author)
    return unless author

    AuthorStruct.new(
      username: author.login,
      profile_url: author.url
    )
  end
end
