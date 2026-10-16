# frozen_string_literal: true

module PageObjects
  module Components
    class ScopedMentionsComposer < Composer
      def has_mention?(user)
        has_css?("#{MENTION_MENU} .username", text: user.username, exact_text: true)
      end

      def has_no_mention?(user)
        has_no_css?("#{MENTION_MENU} .username", text: user.username, exact_text: true)
      end
    end
  end
end
