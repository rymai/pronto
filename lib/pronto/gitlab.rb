module Pronto
  class Gitlab < Client
    def pull_comments(sha)
      @comment_cache["#{mr_id}/#{sha}"] ||= begin
        client.merge_request_comments(slug, mr_id).map do |comment|
          Comment.new(sha, comment.note, 42, 42)
        end
      end
    end

    def commit_comments(sha)
      @comment_cache[sha.to_s] ||= begin
        client.commit_comments(slug, sha, per_page: 500).map do |comment|
          Comment.new(sha, comment.note, comment.path, comment.line)
        end
      end
    end

    def create_commit_comment(comment)
      @config.logger.log("Creating commit comment on #{comment.sha}")
      client.create_commit_comment(slug, comment.sha, comment.body,
                                   path: comment.path, line: comment.position,
                                   line_type: 'new')
    end

    def create_pull_comment(comment)
      @config.logger.log("GitLab does not have an API to create MR diff comments yet.")
      create_commit_comment(comment)
    end

    private

    def slug
      return @config.gitlab_slug if @config.gitlab_slug
      @slug ||= begin
        slug = @repo.remote_urls.map do |url|
          match = slug_regex(url).match(url)
          match[:slug] if match
        end.compact.first
        URI.escape(slug, '/') if slug
      end
    end

    def slug_regex(url)
      if url =~ %r{^ssh:\/\/}
        %r{.*#{host}(:[0-9]+)?(:|\/)(?<slug>.*).git}
      else
        %r{.*#{host}(:|\/)(?<slug>.*).git}
      end
    end

    def host
      @host ||= URI.split(gitlab_api_endpoint)[2, 2].compact.join(':')
    end

    def client
      @client ||= ::Gitlab.client(endpoint: gitlab_api_endpoint,
                                  private_token: gitlab_api_private_token)
    end

    def mr_id
      mr ? mr[:number].to_i : env_pull_id.to_i
    end

    def mr_sha
      mr[:sha] if mr
    end

    def mr
      @pull ||= if env_pull_id
                  merge_requests.find { |mr| mr[:iid].to_i == env_pull_id.to_i }
                elsif @repo.branch
                  merge_requests.find { |mr| mr[:source_branch] == @repo.branch }
                end
    end

    def merge_requests
      @merge_requests ||= client.merge_requests(slug)
    end

    def gitlab_api_private_token
      @config.gitlab_api_private_token
    end

    def gitlab_api_endpoint
      @config.gitlab_api_endpoint
    end
  end
end
