require 'spec_helper'

module GithubWebhook
  describe Processor do

    class Request
      attr_accessor :headers, :body

      def initialize
        @headers = {}
        @body = StringIO.new
      end
    end

    class ControllerWithoutSecret
      ### Helpers to mock ActionController::Base behavior
      attr_accessor :request, :pushed

      def self.skip_before_filter(*args); end
      def self.before_filter(*args); end
      def head(*args); end
      ###

      include GithubWebhook::Processor

      def github_push(payload)
        @pushed = payload[:foo]
      end
    end

    class Controller < ControllerWithoutSecret
      def webhook_secret(payload)
        "secret"
      end
    end

    let(:controller) do
      controller = Controller.new
      controller.request = Request.new
      controller
    end

    let(:controller_without_secret) do
      ControllerWithoutSecret.new
    end

    describe "#create" do
      it "raises an error when secret is not defined" do
        expect { controller_without_secret.send :authenticate_github_request! }.to raise_error(Processor::UnspecifiedWebhookSecretError)
      end

      it "calls the #push method in controller" do
        controller.request.body = StringIO.new({ :foo => "bar" }.to_json.to_s)
        controller.request.headers['X-Hub-Signature'] = "sha1=52b582138706ac0c597c315cfc1a1bf177408a4d"
        controller.request.headers['X-GitHub-Event'] = 'push'
        controller.send :authenticate_github_request!  # Manually as we don't have the before_filter logic in our Mock object
        controller.create
        expect(controller.pushed).to eq "bar"
      end

      it "raises an error when signature does not match" do
        controller.request.body = StringIO.new({ :foo => "bar" }.to_json.to_s)
        controller.request.headers['X-Hub-Signature'] = "sha1=FOOBAR"
        controller.request.headers['X-GitHub-Event'] = 'push'
        expect { controller.send :authenticate_github_request! }.to raise_error(Processor::SignatureError)
      end

      it "raises an error when the github event method is not implemented" do
        controller.request.headers['X-GitHub-Event'] = 'deployment'
        expect { controller.create }.to raise_error(NoMethodError)
      end

      it "raises an error when the github event is not in the whitelist" do
        controller.request.headers['X-GitHub-Event'] = 'fake_event'
        expect { controller.send :check_github_event! }.to raise_error(Processor::UnsupportedGithubEventError)
      end
    end
  end
end
