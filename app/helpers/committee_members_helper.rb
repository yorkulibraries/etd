# frozen_string_literal: true

module CommitteeMembersHelper
  def sort_by_last_name(list, double = true)
    return [] if list.blank?

    sorted = []
    list.each do |member|
      names = member.strip.rpartition(' ')

      sorted.push ["#{names.last}, #{names.first}", member.to_s] if double
      sorted.push "#{names.first} #{names.last}" unless double
    end

    sorted.sort
  end
end
