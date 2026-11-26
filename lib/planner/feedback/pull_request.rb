# frozen_string_literal: true

module Planner
  # Domain logic for review feedback that planner turns into iteration files.
  module Feedback
    # A pull request's open review feedback: fetched with gh and rendered as markdown.
    class PullRequest
      URL = %r{\Ahttps?://(?<host>[^/]+)/(?<owner>[^/]+)/(?<name>[^/]+)/pull/\d+}
      STATES = {
        'APPROVED' => 'Approved',
        'CHANGES_REQUESTED' => 'Changes requested',
        'COMMENTED' => 'Commented',
        'DISMISSED' => 'Dismissed'
      }.freeze
      QUERY = <<~GRAPHQL
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              reviewThreads(first: 100) {
                pageInfo { hasNextPage }
                nodes {
                  isResolved
                  isOutdated
                  path
                  line
                  comments(first: 100) {
                    pageInfo { hasNextPage }
                    nodes { author { login } body state }
                  }
                }
              }
              reviews(first: 100) {
                pageInfo { hasNextPage }
                nodes { author { login } state body }
              }
              comments(first: 100) {
                pageInfo { hasNextPage }
                nodes { author { login } body }
              }
            }
          }
        }
      GRAPHQL

      def self.fetch(gh, pr)
        view = gh.json('pr', 'view', pr, '--json', 'number,title,url')
        match = URL.match(view['url'].to_s)
        raise Error, "gh returned an unexpected pull request URL: #{view['url']}" unless match

        data = gh.json('api', 'graphql', '--hostname', match[:host], '-f', "query=#{QUERY}",
                       '-f', "owner=#{match[:owner]}", '-f', "name=#{match[:name]}",
                       '-F', "number=#{view['number']}")
        new(pr:, view:, pull: data.dig('data', 'repository', 'pullRequest'))
      end

      def initialize(pr:, view:, pull:)
        @pr = pr
        @view = view
        @pull = pull
        raise Error, too_many_message if too_many?
      end

      def empty?
        threads.empty? && reviews.empty? && comments.empty?
      end

      def to_markdown
        parts = [header, inline_section, reviews_section, conversation_section].compact
        "#{parts.join("\n\n")}\n"
      end

      private

      def too_many_message
        "#{@pr} has more than 100 review threads, reviews, comments or replies in one list; " \
          'planner cannot fetch them all'
      end

      def too_many?
        lists = %w[reviewThreads reviews comments].map { |key| @pull[key] }
        return true if lists.any? { |list| list.dig('pageInfo', 'hasNextPage') }

        lists.first['nodes'].any? { |thread| thread.dig('comments', 'pageInfo', 'hasNextPage') }
      end

      def blank?(node)
        node['body'].strip.empty?
      end

      def threads
        @threads ||= @pull['reviewThreads']['nodes']
                     .reject { |thread| thread['isResolved'] || thread['isOutdated'] }
                     .map { |thread| thread.merge('kept' => kept_comments(thread)) }
                     .reject { |thread| thread['kept'].empty? }
                     .sort_by { |thread| [thread['path'], thread['line'] || 0] }
      end

      def kept_comments(thread)
        thread['comments']['nodes'].reject { |node| blank?(node) || node['state'] == 'PENDING' }
      end

      def reviews
        @reviews ||= @pull['reviews']['nodes'].select { |node| STATES.key?(node['state']) && !blank?(node) }
      end

      def comments
        @comments ||= @pull['comments']['nodes'].reject { |node| blank?(node) }
      end

      def header
        "# Review feedback — PR ##{@view['number']}: #{@view['title']}\n\n#{@view['url']}\n\n" \
          'Address the review comments below.'
      end

      def inline_section
        return if threads.empty?

        "## Inline comments\n\n#{threads.map { |thread| thread_block(thread) }.join("\n\n")}"
      end

      def thread_block(thread)
        heading = thread['line'] ? "#{thread['path']}:#{thread['line']}" : thread['path']
        "### #{heading}\n\n#{thread['kept'].map { |node| entry(node) }.join("\n")}"
      end

      def reviews_section
        return if reviews.empty?

        entries = reviews.map { |node| entry(node, STATES.fetch(node['state'])) }
        "## Reviews\n\n#{entries.join("\n")}"
      end

      def conversation_section
        return if comments.empty?

        "## Conversation\n\n#{comments.map { |node| entry(node) }.join("\n")}"
      end

      def entry(node, label = nil)
        author = node.dig('author', 'login') || 'ghost'
        first = label ? "- **#{author}** (#{label}):" : "- **#{author}**:"
        lines = node['body'].gsub("\r\n", "\n").strip.split("\n", -1).map { |line| "  > #{line}".rstrip }
        [first, *lines].join("\n")
      end
    end
  end
end
