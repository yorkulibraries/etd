# frozen_string_literal: true

Rails.application.routes.draw do
  # Reports View
  get 'reports/dashboard'
  get 'reports/by_status'
  get 'reports/review_thesis'

  # Student View
  match 'login_as_student/:id' => 'student_view#login_as_student', as: :login_as_student, via: %i[get post]
  match 'logout_as_student' => 'student_view#logout_as_student', as: :logout_as_student, via: %i[get post]
  match 'my' => 'student_view#index', as: :student_view_index, via: %i[get post]
  match 'my/details' => 'student_view#details', as: :student_view_details, via: %i[get post]
  match 'my/thesis/:id/*process_step' => 'student_view#thesis_process_router', as: :student_view_thesis_process,
        via: %i[get post]

  ## LOGIN AND OUT
  get 'logout' => 'sessions#destroy', as: 'logout'
  get 'login' => 'sessions#new', as:  'login'
  get 'invalid_login' => 'sessions#invalid_login', as: 'invalid_login'
  get 'unauthorized' => 'home#unauthorized'

  resources :export_logs, path: 'exports'

  resource :settings, only: %i[edit update] do
    get :dspace
    # get :cat_search, on: :member
    # get :email
    # get :item_request
    # get :help
    # get :acquisition_requests
  end

  resources :users do
    get :activity, on: :member
    post :block, on: :member
    post :unblock, on: :member
    get :blocked, on: :collection
  end
  devise_for :users

  resources :gem_records, except: %i[new edit create update destroy]
  
  resources :students do
    get 'send_invite', on: :member

    resources :theses do
      member do
        post 'organize_student_information'
        post 'update_status'
        post 'accept_licences'
        post 'submit_for_review'
        post 'assign'
        post 'unassign'
      end
      

      resource :embargo, only: %i[new create], controller: 'theses/embargo'

      resources :documents, path: 'files' do
        get 'deleted', on: :collection
      end

      resources :committee_members, only: %i[new create destroy]
    end

    get 'audit_trail', on: :member
    post 'unblock', on: :member
    post 'block', on: :member
    post 'gem_search', on: :collection
  end

  root to: 'home#index'
end
