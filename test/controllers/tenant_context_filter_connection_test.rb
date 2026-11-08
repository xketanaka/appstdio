require "test_helper"

# テストのトランザクションは接続を握ったままにするので、それを外して、リクエストが自分で接続を握るかを確かめる
class TenantContextFilterConnectionTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  class ProbeController < ApplicationController
    skip_before_action :login_required, :tenant_required

    def show
      render plain: ApplicationRecord.connection_pool.active_connection? ? "leased" : "released"
    end
  end

  test "リクエストの間は、テナントを設定した DB 接続を握り続ける" do
    ApplicationRecord.connection_pool.release_connection

    with_routing do |set|
      set.draw { get "probe" => "tenant_context_filter_connection_test/probe#show" }
      get "/probe"

      assert_equal "leased", response.body
      assert_not ApplicationRecord.connection_pool.active_connection?, "終わったら接続をプールに返す"
    end
  end
end
