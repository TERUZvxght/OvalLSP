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

  # No `as:` — must not produce a named helper (Task 006 "no named route").
  get "/ping", to: "health#ping"

  unlocatable(name: :unlocatable, path: "/mystery", action: "show", controller: "mystery")
end
