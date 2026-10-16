# frozen_string_literal: true

RSpec.describe UsersController do
  before_all { SearchIndexer.enable }

  fab!(:members_group, :group)
  fab!(:readers_group, :group)
  fab!(:searching_user) { Fabricate(:user, username: "composer_user", groups: [members_group]) }
  fab!(:member) do
    Fabricate(:user, username: "scoped_member", groups: [members_group], last_seen_at: 1.day.ago)
  end
  fab!(:reader) do
    Fabricate(:user, username: "scoped_reader", groups: [readers_group], last_seen_at: 1.day.ago)
  end
  fab!(:overlapping_member) do
    Fabricate(
      :user,
      username: "scoped_overlap",
      groups: [members_group, readers_group],
      last_seen_at: 1.day.ago,
    )
  end
  fab!(:outsider) { Fabricate(:user, username: "scoped_outsider", last_seen_at: 1.day.ago) }
  fab!(:category) { Fabricate(:private_category, group: members_group) }
  fab!(:topic) { Fabricate(:topic, category: category, user: member) }

  before_all do
    category.set_permissions(members_group => :full, readers_group => :readonly)
    category.save!
  end

  describe "#search_users" do
    let(:search_params) do
      { term: "scoped_", category_id: category.id, search_context: "mention", include_groups: true }
    end

    before do
      SearchIndexer.enable
      SiteSetting.scoped_mentions_enabled = true
      sign_in(searching_user)
    end

    def found_usernames
      response.parsed_body["users"].map { |user| user["username"] }
    end

    it "suggests readers from all category permission groups without duplicates" do
      get "/u/search/users.json", params: search_params

      expect(response.status).to eq(200)
      expect(found_usernames).to contain_exactly(
        member.username,
        reader.username,
        overlapping_member.username,
      )
    end

    it "excludes exact username matches without category access" do
      get "/u/search/users.json", params: search_params.merge(term: outsider.username.upcase)

      expect(response.status).to eq(200)
      expect(found_usernames).to be_empty
    end

    it "restricts full name matches to users with category access" do
      SiteSetting.enable_names = true
      member.update!(name: "Scoped Example")
      outsider.update!(name: "Scoped Example")

      get "/u/search/users.json", params: search_params.merge(term: "Example")

      expect(response.status).to eq(200)
      expect(found_usernames).to contain_exactly(member.username)
    end

    it "excludes former participants from initial suggestions after they lose access" do
      members_group.add(outsider)
      Fabricate(:post, topic: topic, user: outsider)
      members_group.remove(outsider)

      get "/u/search/users.json",
          params: search_params.merge(term: "", category_id: nil, topic_id: topic.id)

      expect(response.status).to eq(200)
      expect(found_usernames).to contain_exactly(
        member.username,
        reader.username,
        overlapping_member.username,
      )
    end

    it "fills the result limit with eligible users when a former participant matches" do
      Fabricate(:post, topic: topic, user: outsider)

      get "/u/search/users.json", params: search_params.merge(topic_id: topic.id, limit: 3)

      expect(response.status).to eq(200)
      expect(found_usernames).to contain_exactly(
        member.username,
        reader.username,
        overlapping_member.username,
      )
    end

    it "uses the selected category when it differs from the existing topic category" do
      other_group = Fabricate(:group, users: [searching_user, outsider])
      other_category = Fabricate(:private_category, group: other_group)
      Fabricate(:post, topic: topic, user: member)

      get "/u/search/users.json", params: search_params.merge(topic_id: topic.id)

      expect(response.status).to eq(200)
      expect(found_usernames).to contain_exactly(
        member.username,
        reader.username,
        overlapping_member.username,
      )

      get "/u/search/users.json",
          params: search_params.merge(topic_id: topic.id, category_id: other_category.id)

      expect(response.status).to eq(200)
      expect(found_usernames).to contain_exactly(outsider.username)
    end

    it "reflects group membership changes on subsequent searches" do
      get "/u/search/users.json", params: search_params.merge(term: reader.username)

      expect(response.status).to eq(200)
      expect(found_usernames).to contain_exactly(reader.username)

      readers_group.remove(reader)

      get "/u/search/users.json", params: search_params.merge(term: reader.username)

      expect(response.status).to eq(200)
      expect(found_usernames).to be_empty
    end

    it "uses the narrower permissions of a restricted subcategory" do
      subcategory = Fabricate(:private_category, parent_category: category, group: members_group)

      get "/u/search/users.json", params: search_params.merge(category_id: subcategory.id)

      expect(response.status).to eq(200)
      expect(found_usernames).to contain_exactly(member.username, overlapping_member.username)
    end

    it "preserves sitewide suggestions when disabled" do
      SiteSetting.scoped_mentions_enabled = false

      get "/u/search/users.json", params: search_params.merge(term: outsider.username)

      expect(response.status).to eq(200)
      expect(found_usernames).to contain_exactly(outsider.username)
    end

    it "preserves sitewide suggestions in public categories" do
      public_category = Fabricate(:category)

      get "/u/search/users.json",
          params: search_params.merge(category_id: public_category.id, term: outsider.username)

      expect(response.status).to eq(200)
      expect(found_usernames).to contain_exactly(outsider.username)
    end

    it "preserves private message suggestions even when a category is supplied" do
      private_message = Fabricate(:private_message_topic, user: searching_user)

      get "/u/search/users.json",
          params: search_params.merge(topic_id: private_message.id, term: outsider.username)

      expect(response.status).to eq(200)
      expect(found_usernames).to contain_exactly(outsider.username)
    end

    it "preserves sitewide suggestions without category or topic context" do
      get "/u/search/users.json",
          params: search_params.merge(category_id: nil, term: outsider.username)

      expect(response.status).to eq(200)
      expect(found_usernames).to contain_exactly(outsider.username)
    end

    it "preserves lookups outside mention autocomplete" do
      [nil, "user-selector"].each do |search_context|
        get "/u/search/users.json",
            params: search_params.merge(term: outsider.username, search_context: search_context)

        expect(response.status).to eq(200)
        expect(found_usernames).to contain_exactly(outsider.username)
      end
    end

    it "includes administrators who can access restricted categories" do
      admin = Fabricate(:admin, username: "scoped_admin")

      get "/u/search/users.json", params: search_params.merge(term: admin.username)

      expect(response.status).to eq(200)
      expect(found_usernames).to contain_exactly(admin.username)
    end

    it "scopes suggestions when the author is an administrator" do
      sign_in(Fabricate(:admin))

      get "/u/search/users.json", params: search_params.merge(term: outsider.username)

      expect(response.status).to eq(200)
      expect(found_usernames).to be_empty
    end

    it "excludes administrators whose secured category access is suppressed" do
      SiteSetting.suppress_secured_categories_from_admin = true
      admin = Fabricate(:admin, username: "scoped_admin")

      get "/u/search/users.json", params: search_params.merge(term: admin.username)

      expect(response.status).to eq(200)
      expect(found_usernames).to be_empty
    end

    it "includes administrators with explicit access when secured categories are suppressed" do
      SiteSetting.suppress_secured_categories_from_admin = true
      admin = Fabricate(:admin, username: "scoped_admin", groups: [readers_group])

      get "/u/search/users.json", params: search_params.merge(term: admin.username)

      expect(response.status).to eq(200)
      expect(found_usernames).to contain_exactly(admin.username)
    end

    it "preserves the usual user eligibility restrictions" do
      SiteSetting.must_approve_users = true
      searching_user.update!(approved: true)
      member.update!(approved: true)
      reader.update!(approved: true)
      overlapping_member.update!(approved: true)
      Fabricate(
        :user,
        username: "scoped_inactive",
        groups: [members_group],
        approved: true,
        active: false,
      )
      Fabricate(:user, username: "scoped_unapproved", groups: [members_group], approved: false)
      Fabricate(
        :user,
        username: "scoped_staged",
        groups: [members_group],
        approved: true,
        staged: true,
      )
      Fabricate(
        :user,
        username: "scoped_suspended",
        groups: [members_group],
        approved: true,
        suspended_till: 1.year.from_now,
      )

      get "/u/search/users.json", params: search_params

      expect(response.status).to eq(200)
      expect(found_usernames).to contain_exactly(
        member.username,
        reader.username,
        overlapping_member.username,
      )
    end

    it "preserves explicitly requested group filters" do
      get "/u/search/users.json", params: search_params.merge(groups: [members_group.name])

      expect(response.status).to eq(200)
      expect(found_usernames).to contain_exactly(member.username, overlapping_member.username)
    end

    it "preserves visible group suggestions" do
      visible_group = Fabricate(:group, name: "scoped_other_group")

      get "/u/search/users.json", params: search_params

      expect(response.status).to eq(200)
      expect(found_usernames).to contain_exactly(
        member.username,
        reader.username,
        overlapping_member.username,
      )
      expect(response.parsed_body["groups"].map { |group| group["name"] }).to contain_exactly(
        visible_group.name,
      )
    end

    it "rejects category contexts the searching user cannot access" do
      inaccessible_category = Fabricate(:private_category, group: Fabricate(:group))

      get "/u/search/users.json", params: search_params.merge(category_id: inaccessible_category.id)

      expect(response.status).to eq(403)
    end

    it "rejects topic contexts the searching user cannot access" do
      inaccessible_category = Fabricate(:private_category, group: Fabricate(:group))
      inaccessible_topic = Fabricate(:topic, category: inaccessible_category)

      get "/u/search/users.json", params: search_params.merge(topic_id: inaccessible_topic.id)

      expect(response.status).to eq(403)
    end
  end
end
