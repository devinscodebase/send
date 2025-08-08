# frozen_string_literal: true

require 'resend'
require 'parallel'

class ResendClient
  # Custom error class for Resend API specific issues
  class ResendError < StandardError; end

  def initialize(api_key)
    raise ArgumentError, 'Resend API key is required' if api_key.nil? || api_key.empty?

    Resend.api_key = api_key
  end

  # Fetch all domains verified with Resend
  def list_domains
    handle_api_errors do
      result = Resend::Domains.list
      result[:data] || []
    end
  end

  # Send a batch of emails. The `emails` parameter should be an array of hashes,
  # where each hash represents an email to be sent.
  # Example: [{ from: '..', to: '..', subject: '..', html: '..' }, ...]
  def send_batch(emails)
    handle_api_errors do
      Resend::Batch.send(emails)
    end
  end

  private

  # Wraps API calls in a standard error handler
  def handle_api_errors
    yield
  rescue Resend::Error => e
    raise ResendError, "Resend API Error: #{e.message}"
  rescue StandardError => e
    raise ResendError, "An unexpected error occurred: #{e.message}"
  end
end
