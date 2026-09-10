Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  get    "login"  => "sessions#new",     as: :login
  post   "login"  => "sessions#create"
  delete "logout" => "sessions#destroy", as: :logout

  get  "select_tenant" => "tenant_selections#new", as: :select_tenant
  post "select_tenant" => "tenant_selections#create"

  get '/', controller: :sessions, action: :index, as: :top_page
end
