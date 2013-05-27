require 'json'

module Pod
  module PushApp
    class Travis
      def self.webhook_authorization_token
        Digest::SHA2.hexdigest(ENV['GH_REPO'] + ENV['TRAVIS_API_TOKEN'])
      end

      def self.authorized_webhook_notification?(token)
        webhook_authorization_token == token
      end

      def initialize(payload)
        @payload = payload
      end

      def pull_request?
        !pull_request_number.nil?
      end

      def pull_request_number
        type, number = @payload['compare_url'].split('/').last(2)
        number if type == 'pull'
      end

      def build_success?
        @payload['result'] == 0
      end
    end
  end
end
