# frozen_string_literal: true

require 'test_helper'
require 'digest'
require 'etd/license_files'

class LicenseFilesTest < ActiveSupport::TestCase
  should 'accept only the verified LF and final-newline variant of the YorkSpace licence' do
    file = ETD::LicenseFiles.canonical.first
    bytes = File.binread(file.fetch(:path)).gsub("\r\n", "\n") + "\n"
    variant = file.fetch(:existing_variants).sole
    assert_equal variant.fetch(:size), bytes.bytesize
    assert_equal variant.fetch(:md5), Digest::MD5.hexdigest(bytes)
    assert_equal variant.fetch(:sha256), Digest::SHA256.hexdigest(bytes)
  end

  should 'expose the approved YorkSpace licence payloads and hashes' do
    files = ETD::LicenseFiles.canonical

    assert_equal [
      ['license.txt', 1913, 'ad94d0cd27da622da832da123b629d9c'],
      ['YorkU_ETDlicense.txt', 3476, 'fff9673a29a2f5114b5773983cc2c94d']
    ], files.map { |file| [file.fetch(:name), file.fetch(:size), file.fetch(:md5)] }
    files.each do |file|
      assert File.file?(file.fetch(:path))
      assert_equal file.fetch(:size), File.size(file.fetch(:path))
      assert_equal file.fetch(:md5), Digest::MD5.file(file.fetch(:path)).hexdigest
      assert_equal file.fetch(:sha256), Digest::SHA256.file(file.fetch(:path)).hexdigest
    end
  end
end
