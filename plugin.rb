# frozen_string_literal: true

# name: discourse-scoped-mentions
# about: Limit mention autocomplete suggestions to users who can access the current category.
# version: 0.1.0

enabled_site_setting :scoped_mentions_enabled

module ::DiscourseScopedMentions
end

require_relative "lib/discourse_scoped_mentions/user_search_scope"

after_initialize do
  register_modifier(:user_search_scoped_users) do |users, context|
    DiscourseScopedMentions::UserSearchScope.filter(users, context)
  end
end
