# frozen_string_literal: true

module ::DiscourseScopedMentions
  module UserSearchScope
    def self.filter(users, context)
      return users if context[:search_context] != "mention" || context[:topic]&.private_message?

      category = context[:category] || context[:topic]&.category
      return users unless category&.read_restricted

      group_ids = CategoryGroup.where(category_id: category.id).select(:group_id)
      user_ids = GroupUser.where(group_id: group_ids).select(:user_id)
      allowed_users = users.where(id: user_ids)

      if SiteSetting.suppress_secured_categories_from_admin
        allowed_users
      else
        allowed_users.or(users.where(admin: true))
      end
    end
  end
end
