# frozen_string_literal: true

require 'pathname'

# Apache must enforce the same denial before serving files itself. This guard
# covers Puma/Rails and runs before Static even when Static is not installed.
class GraduateUploadsGuard
  def initialize(app, enabled:)
    @app = app
    @enabled = enabled
  end

  def call(env)
    return unavailable if @enabled && protected_path?(env['PATH_INFO'])

    @app.call(env)
  end

  private

  def protected_path?(raw_path)
    path = Rack::Utils.unescape_path(raw_path.to_s).tr('\\', '/')
    normalized = Pathname.new(path).cleanpath.to_s.downcase
    normalized == '/uploads' || normalized.start_with?('/uploads/')
  rescue ArgumentError
    true
  end

  def unavailable
    [404, { 'Content-Type' => 'text/plain; charset=utf-8', 'Cache-Control' => 'no-store',
            'X-Content-Type-Options' => 'nosniff' }, ['This file is unavailable.']]
  end
end
