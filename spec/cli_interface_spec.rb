require 'spec_helper'
require_relative '../lib/cli_interface'
require 'tempfile'

RSpec.describe CliInterface do
  let(:cli) { described_class.new }

  describe '#initialize' do
    it 'creates a new CLI interface' do
      expect(cli).to be_a(described_class)
    end

    it 'initializes with default options' do
      expect(cli.instance_variable_get(:@options)).to eq({})
    end
  end

  describe '#initialize' do
    it 'creates a new CLI interface' do
      expect(cli).to be_a(described_class)
    end

    it 'initializes with default options' do
      expect(cli.instance_variable_get(:@options)).to eq({})
    end
  end

  # Note: Most CLI methods are private and tested through integration tests
  # These tests focus on the public interface and basic functionality
end
