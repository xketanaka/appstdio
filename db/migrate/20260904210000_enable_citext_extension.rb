class EnableCitextExtension < ActiveRecord::Migration[8.1]
  def change
    # users.email を大文字小文字を区別しないログインIDとして扱うために使用する
    enable_extension "citext"
  end
end
