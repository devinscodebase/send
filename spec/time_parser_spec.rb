require 'spec_helper'
require_relative '../lib/time_parser'

RSpec.describe TimeParser do
  describe '.parse_schedule_time' do
    it 'parses "now" correctly' do
      result = described_class.parse_schedule_time('now')
      expect(result).to be_a(String)
      expect(result).to match(/^[A-Z][a-z]{2}, \d{2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} [+-]\d{4}$/)
    end

    it 'parses "tomorrow 9am" correctly' do
      result = described_class.parse_schedule_time('tomorrow 9am')
      expect(result).to be_a(String)
      expect(result).to match(/^[A-Z][a-z]{2}, \d{2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} [+-]\d{4}$/)
    end

    it 'parses "2025-01-20 10:00" correctly' do
      result = described_class.parse_schedule_time('2025-01-20 10:00')
      expect(result).to be_a(String)
      expect(result).to match(/^[A-Z][a-z]{2}, \d{2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} [+-]\d{4}$/)
    end

    it 'raises error for invalid time format' do
      expect { described_class.parse_schedule_time('invalid time') }.to raise_error(TimeParseError)
    end
  end

  describe '.format_for_mailgun' do
    it 'formats time correctly for Mailgun' do
      time = Time.new(2025, 1, 20, 10, 0, 0, '-05:00')
      result = described_class.format_for_mailgun(time)
      
      # Should be in RFC 2822 format
      expect(result).to match(/^[A-Z][a-z]{2}, \d{2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} [+-]\d{4}$/)
    end
  end

  describe '.validate_schedule_time' do
    it 'returns true for valid future times' do
      future_time = (Time.now + 3600).strftime('%Y-%m-%d %H:%M')
      expect(described_class.validate_schedule_time(future_time)).to be true
    end

    it 'raises error for past times' do
      past_time = (Time.now - 3600).strftime('%Y-%m-%d %H:%M')
      expect { described_class.validate_schedule_time(past_time) }.to raise_error(TimeParseError)
    end

    it 'returns true for nil (no scheduling)' do
      expect(described_class.validate_schedule_time(nil)).to be true
    end
  end
end
