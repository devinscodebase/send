require 'spec_helper'
require_relative '../lib/csv_validator'
require 'tempfile'

RSpec.describe CsvValidator do
  let(:temp_csv) do
    file = Tempfile.new(['test', '.csv'])
    file.write("email,firstname,lastname,company\njohn@example.com,John,Doe,Company A\njane@example.com,Jane,Smith,Company B")
    file.close
    file.path
  end

  let(:validator) { described_class.new(temp_csv) }

  after do
    File.delete(temp_csv) if File.exist?(temp_csv)
  end

  describe '#initialize' do
    it 'sets the CSV file path' do
      expect(validator.instance_variable_get(:@csv_file_path)).to eq(temp_csv)
    end

    it 'initializes empty arrays and hashes' do
      expect(validator.contacts).to eq([])
      expect(validator.errors).to eq([])
      expect(validator.warnings).to eq([])
    end
  end

  describe '#validate_and_parse' do
    it 'returns true for valid CSV' do
      expect(validator.validate_and_parse).to be true
    end

    it 'parses contacts correctly' do
      validator.validate_and_parse
      
      expect(validator.contacts.length).to eq(2)
      expect(validator.contacts.first[:email]).to eq('john@example.com')
      expect(validator.contacts.first[:firstname]).to eq('John')
      expect(validator.contacts.first[:lastname]).to eq('Doe')
      expect(validator.contacts.first[:company]).to eq('Company A')
      expect(validator.contacts.first[:valid]).to be true
    end

    it 'returns false for non-existent file' do
      invalid_validator = described_class.new('nonexistent.csv')
      expect(invalid_validator.validate_and_parse).to be false
      expect(invalid_validator.errors).to include('CSV file not found: nonexistent.csv')
    end
  end

  describe '#contact_count' do
    it 'returns the number of contacts' do
      validator.validate_and_parse
      expect(validator.contact_count).to eq(2)
    end
  end

  describe '#valid_contact_count' do
    it 'returns the number of valid contacts' do
      validator.validate_and_parse
      expect(validator.valid_contact_count).to eq(2)
    end
  end

  describe '#generate_valid_csv' do
    it 'creates a temporary CSV with valid contacts' do
      validator.validate_and_parse
      temp_file_path = validator.generate_valid_csv
      
      expect(File.exist?(temp_file_path)).to be true
      
      content = File.read(temp_file_path)
      expect(content).to include('address,firstname,lastname,company')
      expect(content).to include('john@example.com,John,Doe,Company A')
      expect(content).to include('jane@example.com,Jane,Smith,Company B')
      
      File.delete(temp_file_path)
    end
  end
end
