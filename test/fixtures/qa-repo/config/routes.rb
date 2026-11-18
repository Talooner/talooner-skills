Rails.application.routes.draw do
  mount TaloonerQa::Engine, at: "/__qa" if defined?(TaloonerQa) && TaloonerQa.enabled?
  resources :orders
end
