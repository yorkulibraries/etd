# frozen_string_literal: true

# The HTTPS edge must forward the actual scheme before production activation.
# Never weaken this cookie to accommodate HTTP or a misconfigured proxy.
Rails.application.config.session_store :cookie_store, key: '_etd_session',
  secure: Rails.env.production?, httponly: true, same_site: :lax
