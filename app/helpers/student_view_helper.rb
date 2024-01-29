# frozen_string_literal: true

module StudentViewHelper
    def show_accordion(current_status)
        "accordion-collapse collapse" + (@thesis.status == current_status ? "show" : "")
    end
    def show_badge(current_status)
        @thesis.status == current_status ? "badge text-bg-primary" : "badge text-bg-dark"
    end
end
