# frozen_string_literal: true

# The /__qa hooks Talooner QA drives (talooner-qa-rails). Mounted in config/routes.rb only when
# TALOONER_QA_HOOK_TOKEN is set, and never in production.
return unless defined?(TaloonerQa)

TaloonerQa.configure do |qa|
  # {area => [role, ...]}: what /__qa/roles answers. Leave out roles a person cannot hold.
  qa.roles { { orders: %w[viewer clerk manager] } }

  # A user with exactly these roles ({"orders" => "clerk"}) and no access elsewhere.
  qa.user_for { |roles| QaUsers.with_roles(roles) }

  # Every factory as "order" and every trait as "order:paid".
  qa.seeds_from_factory_bot(attributes: ->(_factory) { { account: QaAccount.current } })

  # Routes no scenario should open.
  qa.exclude_pages(%r{\A/(api|admin/sidekiq)(/|\z)})
end
