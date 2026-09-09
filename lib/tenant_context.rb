# PostgreSQL のセッション変数にテナントコンテキストを設定する。
#
# RLS のポリシーはここで設定した値を参照して、テナントを跨いだ行を遮断する。
# 値が未設定なら NULL となりポリシーに一致しないため、設定漏れは
# 「他テナントが見える」ではなく「0件」になる (fail-closed)。
#
# Web リクエストでは TenantContextFilter が自動で設定・解除する。
# ジョブ・コンソール・テストからは switch を使う。
#
#   TenantContext.switch(tenant: tenant, user: user) do
#     TenantUser.count
#   end
class TenantContext
  TENANT_KEY = "app.tenant_id"
  USER_KEY = "app.user_id"

  class << self
    # ブロックの間だけコンテキストを差し替える。ブロックを抜けたら元の値に戻す。
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

    # コンテキストを設定する。引数を省略した側は解除される。
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

    # 2つのセッション変数を1往復で設定する。
    # キャッシュを経由させないのは、同じ値を再設定する SQL がキャッシュに当たると
    # set_config が実行されず、コンテキストが戻らなくなるため。
    def write(connection, tenant, user)
      tenant_id = connection.quote(identifier(tenant).to_s)
      user_id = connection.quote(identifier(user).to_s)

      connection.uncached do
        connection.select_value(<<~SQL.squish)
          SELECT set_config('#{TENANT_KEY}', #{tenant_id}, false),
                 set_config('#{USER_KEY}', #{user_id}, false)
        SQL
      end

      # クエリキャッシュは SQL 文字列だけをキーにしており、セッション変数の違いを見ない。
      # コンテキストを変えたら必ず捨てないと、切り替える前のテナントの結果が返ってくる。
      connection.clear_query_cache
    end

    def read(connection)
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
