# frozen_string_literal: true

Rails.application.routes.draw do
  resources :posts do
    member do
      post :publish
    end
    collection do
      get :search
    end

    resources :comments
  end

  namespace :admin do
    resources :projects
  end

  get "/about", to: "pages#about", as: :about

  # Toggled by a flag file rather than an ENV var: agent/reload runs in the
  # already-spawned child process, so a test can't change its ENV after
  # the fact, but it can drop/remove a file for the next `load` to see
  # (Task 006 "reload後に削除routeが消える").
  unless File.exist?(File.join(__dir__, ".disable_archived_route"))
    get "/archived", to: "archive#show", as: :archived
  end

  # No `as:` — must not produce a named helper (Task 006 "no named route").
  get "/ping", to: "health#ping"

  unlocatable(name: :unlocatable, path: "/mystery", action: "show", controller: "mystery")
end
