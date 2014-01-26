require 'app/controllers/app_controller'
require 'app/models/session'

require 'newrelic_rpm'

module Pod
  module TrunkApp
    class APIController < AppController

      private

      # --- Request / Response --------------------------------------------------------------------

      before do
        type = content_type(:json)
        if (request.post? || request.put?) && request.media_type != 'application/json'
          json_error(415, "Unable to accept input with Content-Type `#{request.media_type}`, " \
                          "must be `application/json`.")
        end
      end

      def json_error(status, message)
        error(status, { 'error' => message }.to_json)
      end

      def json_message(status, content)
        halt(status, content.to_json)
      end

      # --- Errors --------------------------------------------------------------------------------

      error JSON::ParserError do
        json_error(400, 'Invalid JSON data provided.')
      end

      error Sequel::ValidationFailed do |error|
        json_error(422, error.errors)
      end

      def catch_unexpected_errors?
        settings.environment != :test
      end

      error 500 do |error|
        if catch_unexpected_errors?
          NewRelic::Agent.notice_error(error, :uri => request.path,
                                              :referer => request.referrer.to_s,
                                              :request_params => request.params)
          json_error(500, 'An internal server error occurred. Please try again later.')
        else
          raise error
        end
      end

      # --- Authentication ------------------------------------------------------------------------

      # Always try to find the owner and prolong the session.
      #
      before do
        if @session = Session.with_token(authentication_token)
          @owner = @session.owner
          @session.prolong!
        end
      end

      # Returns if there is an authenticated owner or throws an error in case there isn't.
      #
      set :requires_owner do |required|
        condition do
          if required && @owner.nil?
            if authentication_token.blank?
              json_error(401, 'Please supply an authentication token.')
            else
              json_error(401, 'Authentication token is invalid or unverified.')
            end
          end
        end
      end

      class << self
        # Override all the route methods to ensure an ACL rule is specified.
        #
        [:get, :post, :put, :patch, :delete].each do |verb|
          class_eval <<-EOS, __FILE__, __LINE__+1
            def #{verb}(route, options, &block)
              unless options.has_key?(:requires_owner)
                raise "Must specify a ACL rule for #{name} #{verb.to_s.upcase} \#{route}"
              end
              super
            end
          EOS
        end
      end

      # Returns the Authorization header if the value of the header starts with ‘Token’.
      #
      def authorization_header
        authorization = env['HTTP_AUTHORIZATION'].to_s.strip
        unless authorization == ''
          if authorization.start_with?('Token')
            authorization
          end
        end
      end

      # Returns the token value from the Authorization header if the header starts with ‘Token’.
      #
      def token_from_authorization_header
        if authorization = authorization_header
          authorization.split(' ', 2)[-1]
        end
      end

      # Returns the authentication token from any possible location.
      #
      # Currently supported is the Authorization header.
      #
      #   Authorization: Token 34jk45df98
      #
      def authentication_token
        if token = token_from_authorization_header
          logger.debug("Got authentication token: #{token}")
          token
        end
      end
      
      # --- Post Receive Hook -------------------------------------------------------------------
      
      # TODO Return good errors.
      #
      post "/post-receive-hook/#{ENV['HOOK_PATH']}" do
        push_data = nil
        
        begin
          push_data = JSON.parse(request.body.read)
        rescue JSON::ParserError
          return
        end
        
        payload = push_data['payload']
        
        return unless payload.respond_to?(:to_h)
        
        manual_commits = payload['commits'].select { |commit| commit['message'] !~ /\A\[Add\]/ }
        
        manual_commits.each do |manual_commit|
          commit_sha = manual_commit['id']
          manual_commit['modified'].each do |modified_file|
            # github = GitHub.new(ENV['GH_REPO'], :username => ENV['GH_TOKEN'], :password => 'x-oauth-basic')
            
            # data_url_template = "https://raw.github.com/#{ENV['GH_REPO']}/%s/%s"
            data_url_template = "https://raw.github.com/alloy/trunk.cocoapods.org-test/%s/%s"
            data_url = data_url_template % [commit_sha, modified_file] if commit_sha
            
            puts
            puts data_url
            
            # TODO Get the data from data_url here and update the database.
          end
        end
        
        200
      end
      
    end
  end
end
