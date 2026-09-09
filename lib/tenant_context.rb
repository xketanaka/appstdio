# RLS のポリシーが参照する PostgreSQL のセッション変数を設定する。
#
# Web リクエストでは TenantContextFilter が自動で設定・解除する。
# リクエスト外（ジョブ・コンソール・テスト）からは switch を使う。
#
#   TenantContext.switch(tenant: tenant, user: user) do
#     TenantUser.count
#   end
class TenantContext
  TENANT_KEY = "app.tenant_id"
  USER_KEY = "app.user_id"

  class << self
    def switch(tenant: nil, user: nil)
      ApplicationRecord.with_connection do |connection|
        previous = read(connection)
        write(connection, tenant, user)

        begin
          yield
        ensure
          write(connection, previous["tenant_id"], previous["user_id"])
        end
      end
    end

    # 省略した側は据え置きではなく解除される
    def apply(tenant: nil, user: nil)
      ApplicationRecord.with_connection { |connection| write(connection, tenant, user) }
    end

    def clear
      apply
    end

    def tenant_id
      ApplicationRecord.with_connection { |connection| read(connection)["tenant_id"].presence }
    end

    def user_id
      ApplicationRecord.with_connection { |connection| read(connection)["user_id"].presence }
    end

    private

    def write(connection, tenant, user)
      tenant_id = connection.quote(identifier(tenant).to_s)
      user_id = connection.quote(identifier(user).to_s)

      # uncached: 同じ値を再設定する SQL がキャッシュに当たると set_config が実行されない
      connection.uncached do
        connection.select_value(<<~SQL.squish)
          SELECT set_config('#{TENANT_KEY}', #{tenant_id}, false),
                 set_config('#{USER_KEY}', #{user_id}, false)
        SQL
      end

      # クエリキャッシュのキーは SQL 文字列のみ。捨てないと切り替える前のテナントの結果が返る
      connection.clear_query_cache
    end

    def read(connection)
      # uncached: write と同じ理由
      connection.uncached do
        connection.select_one(<<~SQL.squish)
          SELECT current_setting('#{TENANT_KEY}', true) AS tenant_id,
                 current_setting('#{USER_KEY}', true) AS user_id
        SQL
      end
    end

    def identifier(value)
      value.is_a?(ActiveRecord::Base) ? value.id : value
    end
  end
end
