# Discourse Scoped Mentions

Limit individual `@mention` autocomplete suggestions in private categories to users who can read the category.

## Setup

Requires Discourse core support for the `user_search_scoped_users` modifier and composer
mention requests marked with `search_context=mention`. Both are prerequisites for filtering
suggestions.

Install the plugin in your Discourse checkout:

```sh
ln -s /path/to/discourse-scoped-mentions plugins/discourse-scoped-mentions
```

Restart Discourse, then enable **scoped mentions enabled** in Admin > Site settings.
The setting is disabled by default and applies to every private category when enabled.

## Behavior

- Applies to new topics, replies, and edits in both composer editors.
- Filters initial suggestions, username matches, and full-name searches before ranking and result limits.
- Uses the currently selected category, including when it changes while composing.
- Includes members of any group with category read access, including read-only groups.
- Includes administrators unless `suppress_secured_categories_from_admin` is enabled; in that case they need explicit group access.
- Applies the same audience filter when the author is a staff member.
- Preserves normal user eligibility rules and result ordering.
- Uses each category's own permissions, including for subcategories.

The filter narrows the existing suggestion pool; initial suggestions are not an exhaustive
list of everyone with access. Subsequent requests use current category permissions and
group membership. The composer retains Discourse's existing short-lived search cache.

Public categories, personal messages, chat, group suggestions, and other user searches
keep their existing behavior. A composer without a category uses the normal suggestions
until a category is selected. Manually typed mentions and notification permissions are
unaffected. This plugin does not hide user accounts elsewhere on the site.

The audience follows Discourse's category permission groups and administrator access
rules. Additional access rules supplied by other plugins require integration with the
scope calculation.

## Development

The plugin registers `user_search_scoped_users`, a core modifier that receives the user
relation and a context hash containing `search_context`, `category`, `topic`, and
`guardian`. The supplied category and topic have already been authorized for the searching
user. The plugin uses the selected category when supplied, falling back to the topic's
saved category. It resolves that fallback only for mention searches while enabled,
avoiding an extra category lookup for ordinary core searches.

The composer identifies autocomplete requests with `search_context=mention`. This is a
presentation context, not an authorization credential. The modifier must preserve the
existing relation's eligibility constraints. Filtering happens before exact matches,
topic participants, category suggestions, global matches, and result limits.

The implementation follows these bundled-plugin patterns:

- [Lazy Videos](https://github.com/discourse/discourse/blob/main/plugins/discourse-lazy-videos/plugin.rb) loads a small namespaced library without a Rails engine.
- [Reactions](https://github.com/discourse/discourse/blob/main/plugins/discourse-reactions/plugin.rb) registers query modifiers in `after_initialize`. The modifier registry checks the plugin's enabled setting on every call, so no second setting check is needed inside the filter.
- [Assign](https://github.com/discourse/discourse/blob/main/plugins/discourse-assign/lib/discourse_assign/assignment_permissions.rb) uses a `GroupUser` subquery to select eligible users. This plugin also keeps both membership and administrator branches on the incoming user relation, preserving core eligibility restrictions.

Run the plugin tests from a Discourse checkout with the required core support:

```sh
LOAD_PLUGINS=1 bin/rspec plugins/discourse-scoped-mentions/spec/requests/users_controller_spec.rb
LOAD_PLUGINS=1 bin/rspec plugins/discourse-scoped-mentions/spec/system/enable_scoped_mentions_spec.rb
bin/rspec spec/models/user_search_spec.rb
bin/rspec spec/requests/users_controller_spec.rb -e '#search_users'
bin/qunit --standalone frontend/discourse/tests/unit/lib/user-search-test.js frontend/discourse/tests/integration/ui-kit/d-editor-mentions-test.gjs
```

Run `bin/lint --fix` from Discourse against the changed plugin files before
committing. No database migrations or plugin frontend assets are required.
