module FormatUtils
  def date_to_s(d)
    d.try(:strftime, "%Y/%m/%d")
  end

  def time_to_s(d)
    d.try(:strftime, "%Y/%m/%d %H:%M")
  end

  def str_to_s(s, limit = nil)
    limit ||= 100
    (s.try(:length) || 0) > limit ? s[0..limit] + "..." : s
  end

  def escape_like(str)
    str.gsub(/[\\%_]/) { |m| "\\#{m}" }
  end
end
