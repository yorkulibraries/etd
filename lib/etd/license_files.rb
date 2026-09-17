# frozen_string_literal: true

module ETD
  module LicenseFiles
    FILES = [
      {
        name: 'license.txt',
        size: 1913,
        md5: 'ad94d0cd27da622da832da123b629d9c',
        sha256: '3887c1cf7f92224425250ff451b1f5e098c301710dbd59996a33f2280a01bd0c',
        existing_variants: [{
          size: 1878,
          md5: 'd2ddb30347de82f6d980c0edc2730402',
          sha256: '2bbfdca29ecb8d562e17986a98bda43690ca57b435e431dae6b75f4712d9a1bb'
        }]
      },
      {
        name: 'YorkU_ETDlicense.txt',
        size: 3476,
        md5: 'fff9673a29a2f5114b5773983cc2c94d',
        sha256: 'afdff8088f1ee77bcdb007ca632af8d21d35adb32364967560b46380d0d63f79'
      }
    ].freeze

    def self.canonical
      FILES.map do |file|
        file.merge(path: Rails.root.join('config', 'dspace', 'licenses', file.fetch(:name)).to_s)
      end
    end
  end
end
