# frozen_string_literal: true

RSpec.describe "Enable scoped mentions" do
  fab!(:admin)
  fab!(:group)
  fab!(:member) { Fabricate(:user, username: "chapter_member", groups: [group]) }
  fab!(:outsider) { Fabricate(:user, username: "chapter_outsider") }
  fab!(:category) { Fabricate(:private_category, group: group) }
  fab!(:topic) { Fabricate(:topic, category: category, user: member) }
  fab!(:post) { Fabricate(:post, topic: topic, user: member) }

  let(:admin_settings) { PageObjects::Pages::AdminSiteSettings.new }
  let(:topic_page) { PageObjects::Pages::Topic.new }
  let(:composer) { PageObjects::Components::ScopedMentionsComposer.new }

  it "lets an administrator enable suggestions limited to the category audience" do
    admin.user_option.update!(composition_mode: UserOption.composition_mode_types[:markdown])
    sign_in(admin)

    admin_settings.visit("scoped_mentions_enabled")
    expect(admin_settings).to have_setting("scoped_mentions_enabled")
    expect(page).to have_text(I18n.t("site_settings.scoped_mentions_enabled"))

    admin_settings.toggle_bool_setting("scoped_mentions_enabled")
    expect(admin_settings).to have_overridden_setting("scoped_mentions_enabled")

    page.refresh
    expect(admin_settings.bool_setting_checkbox("scoped_mentions_enabled")).to be_checked

    topic_page.visit_topic(topic)
    topic_page.click_reply_button
    composer.type_content("@chapter_")

    expect(composer).to have_mention(member)
    expect(composer).to have_no_mention(outsider)
  end
end
