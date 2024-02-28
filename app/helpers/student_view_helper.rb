# frozen_string_literal: true

module StudentViewHelper
  def show_accordion(specific_status)
    "accordion-collapse collapse #{@thesis.status == specific_status ? 'show' : ''}"
  end

  def show_badge(specific_status)
    @thesis.status == specific_status ? 'badge text-bg-primary' : 'badge text-bg-dark'
  end

  def collapse_accordion(specific_status)
    "accordion-button #{@thesis.status == specific_status ? '' : 'collapsed'}"
  end
end
