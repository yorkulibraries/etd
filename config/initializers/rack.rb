# frozen_string_literal: true

Rack::Multipart::Parser.const_set('BUFSIZE', 10_000_000) unless Rails.env.test?
