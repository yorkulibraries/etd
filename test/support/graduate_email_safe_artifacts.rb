# frozen_string_literal: true

# Prepend before any driver startup. Until clean states are reviewed in Task 7,
# graduate authentication tests capture no browser content, including failures.
module GraduateEmailSafeArtifacts
  def browser_artifact(*, **); end
  def take_screenshot; end
  def take_failed_screenshot; end

  private

  def save_html; end
  def save_image; end
end
