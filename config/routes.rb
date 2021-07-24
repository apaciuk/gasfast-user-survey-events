Rails.application.routes.draw do
  post 'users/create', to: 'users#create'
  delete 'users/destroy', to: 'users#destroy'
  root to: 'home#index'

end


