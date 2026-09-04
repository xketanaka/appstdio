class ::Paginator
  # == 引数
  # * page: ページ。nilの場合は1ページ目として処理する
  # * rows_per_page: 1ページあたりの件数(任意)
  # * max_pagination: ページの最大数(任意)
  def initialize(page: nil,
    rows_per_page: Settings.paginator.rows_per_page,
    max_pagination: Settings.paginator.max_pagination)
    @page = (page && page.to_i) || 1
    @rows_per_page = rows_per_page
    @max_pagination = max_pagination
  end

  # 引数で指定されたリレーションオブジェクトに対してページネーションを行う
  # SELECT句を追加したクエリの場合、query.count がエラーとなるので呼び出し元でカウントを取得して
  # 呼び出す必要がある。
  def paginate(query, count = nil)
    @row_count_max = count || query.count
    @result = query.limit(@rows_per_page).offset((@page - 1) * @rows_per_page).to_a
  end

  # 引数で指定された配列に対してページネーションを行う
  def paginate_array(array)
    @row_count_max = array.length
    @result = (array[(@page - 1) * @rows_per_page, @rows_per_page] || [])
  end

  def page
    return @page
  end

  def max_page
    max_p = (row_count_max / @rows_per_page) + (row_count_max % @rows_per_page == 0 ? 0 : 1)
    max_p > @max_pagination ? @max_pagination : max_p
  end

  # 次のページがある場合(最大件数+1が存在する場合)はtrueを返す
  def has_next?
    return @page < @max_pagination && @page * @rows_per_page < row_count_max
  end

  # 前のページがある場合trueを返す
  def has_prev?
    return @page > 1
  end

  # page_count_index
  def row_count_of_page_start
    @rows_per_page * (@page - 1)
  end

  # 現在のページまでの検索結果件数
  def row_count_now
    return @rows_per_page * (@page - 1) + (@result.try(:count) || 0)
  end

  # 検索条件に一致する検索結果件数
  def row_count_max
    return @row_count_max
  end

  def nearly_range(num = Settings.paginator.page_link_count)
    start = page - (num / 2).to_i
    start = start <= 0 ? 1 : start
    (start..(start + num - 1))
  end

  def linkable?(num)
    num <= max_page && num != page
  end
end
