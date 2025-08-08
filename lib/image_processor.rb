# frozen_string_literal: true

require 'mini_magick'
require 'securerandom'
require 'tempfile'
require 'fileutils'

class ImageProcessor
  TARGET_SIZE_BYTES = 200 * 1024
  MAX_DIM = 250

  # Returns: path to compressed JPG file
  # If output_path is provided, writes there (creating directories as needed);
  # otherwise writes to a temp file and returns its path.
  def self.compress_to_avatar(input_path, output_path: nil)
    raise ArgumentError, "File not found: #{input_path}" unless File.exist?(input_path)

    image = MiniMagick::Image.open(input_path)

    # Resize to fit within 250x250 (preserving aspect), then pad/crop to square
    image.combine_options do |i|
      i.resize "#{MAX_DIM}x#{MAX_DIM}>"
      i.gravity 'center'
      i.background 'white'
      i.extent "#{MAX_DIM}x#{MAX_DIM}"
    end

    # Convert to JPEG
    image.format 'jpg'

    # Prepare output
    out_path = output_path
    temp = nil
    if out_path.nil?
      temp = Tempfile.new(["avatar_#{SecureRandom.hex(4)}", '.jpg'])
      temp.binmode
      out_path = temp.path
    else
      FileUtils.mkdir_p(File.dirname(out_path))
    end

    # Iteratively adjust quality to approach ~200 KB
    quality = 85
    10.times do
      image.quality quality.to_s
      image.interlace 'JPEG'
      image.strip
      image.write(out_path)

      size = File.size(out_path)
      break if size <= TARGET_SIZE_BYTES || quality <= 50

      # reduce quality and retry
      quality -= 5
    end

    temp&.close!
    out_path
  end
end
