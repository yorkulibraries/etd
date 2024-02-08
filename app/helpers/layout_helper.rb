# frozen_string_literal: true

# These helper methods can be called in your template to set variables to be used in the layout
# This module should be included in all views globally,
# to do so you may need to add this line to your ApplicationController
#   helper :layout
module LayoutHelper
  def title(page_title, show_title = true)
    content_for(:title) { h(page_title.to_s) }
    @show_title = show_title
  end

  def title_html(&block)
    content_for(:title_html) do
      yield block
    end
  end

  def progress_bar(which_to_activate)
    render partial: 'student_view/progress_bar', locals: { activate: which_to_activate }
  end

  def show_title?
    @show_title
  end

  def stylesheet(*args)
    content_for(:head) { stylesheet_link_tag(*args) }
  end

  def javascript(*args)
    content_for(:head) { javascript_include_tag(*args) }
  end

  def sidebar(&block)
    content_for(:sidebar) do
      yield block
    end
  end

  def show_system_message
    false
  end

  def system_message
    content_tag :h4, 'We are upgrading. ETD will be unavailable today April 7, 2014 from 2:00 pm to 3:00 pm.'
  end
end
