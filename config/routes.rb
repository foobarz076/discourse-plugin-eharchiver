# frozen_string_literal: true

Eharchiver::Engine.routes.draw do
  post "/tasks" => "tasks#create"
  get "/tasks/:task_id" => "tasks#show"
  post "/tasks/:task_id/cancel" => "tasks#cancel"
  post "/webhooks/task-status" => "webhooks#task_status"

  namespace :admin, constraints: AdminConstraint.new do
    get "/tasks" => "tasks#index"
    post "/tasks/:task_id/retry" => "tasks#retry"
  end
end

Discourse::Application.routes.draw do
  mount ::Eharchiver::Engine, at: "/eharchiver"
  get "/admin/plugins/discourse-eharchiver/tasks(/*path)" => "admin/plugins#index",
      :constraints => AdminConstraint.new
end
