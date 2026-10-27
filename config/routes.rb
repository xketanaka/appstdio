Rails.application.routes.draw do
  # Active Storage 標準のダイレクトアップロードの受け口は、ログインも権限も確かめずに保存先への
  # 書き込みを許す。ファイル機能は自前の受け口（files/api/nodes#prepare_upload）を使うので塞ぐ。
  # Active Storage のルートより先に描くこと（先に一致したものが使われる）
  post "/rails/active_storage/direct_uploads" => proc { [404, {}, []] }

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # 運営者画面のプロセスは所有者ロールで RLS を素通りするので、利用テナント側の画面を出さない
  if Rails.configuration.x.ops_console
    namespace :ops do
      get    "login"  => "sessions#new",     as: :login
      post   "login"  => "sessions#create"
      delete "logout" => "sessions#destroy", as: :logout

      resources :tenants, only: [:index]
      root "tenants#index"
    end

    root to: redirect("/ops")
  else
    get    "login"  => "sessions#new",     as: :login
    post   "login"  => "sessions#create"
    delete "logout" => "sessions#destroy", as: :logout

    get  "select_tenant" => "tenant_selections#new", as: :select_tenant
    post "select_tenant" => "tenant_selections#create"

    resource :profile, only: [:show, :update]

    namespace :files do
      # 画面はすべて同じ入れ物のページ。URL は app/javascript/files/router.ts と揃えること
      root "app#show"
      get "my_drive" => "app#show", as: :my_drive
      get "folders/:id" => "app#show", as: :folder
      get "shared" => "app#show", as: :shared_items
      get "trash" => "app#show", as: :trash

      namespace :api, defaults: { format: :json } do
        get "tree" => "trees#show"
        get "tree/children" => "trees#children"
        get "drives/shared" => "folders#show", defaults: { drive: "shared" }
        get "drives/mine" => "folders#show", defaults: { drive: "personal" }
        get "folders/:id" => "folders#show", as: :folder
        post "folders" => "folders#create", as: :folders
        resources :nodes, only: [] do
          collection do
            post :move
            post :trash
            post :restore
            post :prepare_upload
            post :upload
          end
          member do
            get :download
            patch :rename
          end
          resources :versions, only: [:index, :create, :update] do
            collection do
              post :prepare_upload
            end
            member do
              get :download
              post :restore
            end
          end
        end
        get "shared" => "shared_items#index"
        get "trash" => "trash#index"
        resource :privileged_mode, only: [:create, :destroy]
      end
    end

    namespace :management do
      resources :users, only: [:index]
      resources :groups do
        get :suspended, on: :collection
        member do
          get :sub_members
          get :member_candidates
          get :confirm_destroy
          get :confirm_suspend
          post :suspend
          post :reactivate
        end
      end
      resource :tenant_setting, only: [:show, :edit, :update]
      root to: redirect("/management/users")
    end

    get '/', controller: :sessions, action: :index, as: :top_page
  end
end
