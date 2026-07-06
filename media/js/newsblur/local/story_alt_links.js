(function () {
    function install() {
    if (!window.NEWSBLUR || !NEWSBLUR.Reader || !NEWSBLUR.Views || !NEWSBLUR.Views.StoryDetailView || NEWSBLUR.Reader.prototype._tinkdeck_alt_links) return false;

    NEWSBLUR.Reader.prototype._tinkdeck_alt_links = true;

    var providers = [
        {
            id: "oldreddit",
            title: "Open in OldReddit",
            build_url: function (url) {
                var parsed = parse_url(url);
                if (!parsed) return null;
                return "https://old.reddit.com" + parsed.pathname + parsed.search + parsed.hash;
            },
            matches: function (url) {
                var parsed = parse_url(url);
                return parsed && /(^|\.)reddit\.com$/i.test(parsed.hostname);
            }
        }
    ];

    function parse_url(url) {
        try {
            return new URL(url);
        } catch (e) {
            return null;
        }
    }

    function story_for_menu($menu) {
        var story_id = $menu.data("story_id");
        return story_id && (
            NEWSBLUR.assets.get_story(story_id) ||
            NEWSBLUR.reader.model.get_story(story_id)
        );
    }

    function actions_for_story(story) {
        var story_url = story && story.get("story_permalink");
        if (!story_url) return [];

        return _.compact(_.map(providers, function (provider) {
            if (!provider.matches(story_url)) return null;

            var action_url = provider.build_url(story_url);
            if (!action_url) return null;

            return $.make("li", {
                className: "NB-menu-item NB-menu-manage-story-alt-link NB-menu-manage-story-alt-link-" + provider.id,
                role: "button",
                "data-url": action_url
            }, [
                $.make("div", { className: "NB-menu-manage-image" }),
                $.make("div", { className: "NB-menu-manage-title" }, provider.title)
            ]);
        }));
    }

    function render_header_links(story) {
        var story_url = story && story.get("story_permalink");
        if (!story_url) return null;

        var links = _.compact(_.map(providers, function (provider) {
            if (!provider.matches(story_url)) return null;

            var action_url = provider.build_url(story_url);
            if (!action_url) return null;

            return $.make("a", {
                className: "NB-feed-story-alt-link NB-feed-story-alt-link-" + provider.id,
                href: action_url,
                target: "_blank",
                rel: "noopener noreferrer"
            }, provider.title.replace("Open in ", ""));
        }));

        if (!links.length) return null;

        var items = [];
        _.each(links, function ($link, index) {
            if (index) items.push($.make("span", { className: "NB-middot" }, "\u00b7"));
            items.push($link);
        });

        return $.make("div", { className: "NB-feed-story-alt-links" }, items);
    }

    function add_header_links(story_view) {
        if (!story_view || !story_view.model || !story_view.$el) return;
        if (story_view.$(".NB-feed-story-alt-links").length) return;

        var $links = render_header_links(story_view.model);
        if (!$links) return;

        story_view.$(".NB-feed-story-date-line").first().append($links);
    }

    function add_alt_links($menu) {
        if (!$menu || !$menu.hasClass("NB-menu-manage-story")) return;
        if ($menu.data("tinkdeck_alt_links")) return;

        var story = story_for_menu($menu);
        var actions = actions_for_story(story);
        if (!actions.length) return;

        $menu.data("tinkdeck_alt_links", true);
        $(".NB-menu-manage-story-open", $menu).after(actions);
    }

    var original_make_manage_menu = NEWSBLUR.Reader.prototype.make_manage_menu;
    NEWSBLUR.Reader.prototype.make_manage_menu = function () {
        var $menu = original_make_manage_menu.apply(this, arguments);
        add_alt_links($menu);
        return $menu;
    };

    var original_story_render = NEWSBLUR.Views.StoryDetailView.prototype.render;
    NEWSBLUR.Views.StoryDetailView.prototype.render = function () {
        var response = original_story_render.apply(this, arguments);
        add_header_links(this);
        return response;
    };

    var original_story_render_header = NEWSBLUR.Views.StoryDetailView.prototype.render_header;
    NEWSBLUR.Views.StoryDetailView.prototype.render_header = function () {
        var response = original_story_render_header.apply(this, arguments);
        add_header_links(this);
        return response;
    };

    $("<style>")
        .attr("id", "NB-tinkdeck-alt-links-style")
        .text([
            ".NB-feed-story-alt-links { display: inline-flex; gap: 6px; align-items: center; margin-left: 6px; }",
            ".NB-feed-story-alt-link { color: #547A35; font-weight: 600; text-decoration: none; }",
            ".NB-feed-story-alt-link:hover { text-decoration: underline; }"
        ].join("\n"))
        .appendTo("head");

    $(document).on("click", ".NB-menu-manage-story-alt-link", function (e) {
        e.preventDefault();
        e.stopPropagation();

        var url = $(this).data("url");
        if (url) window.open(url, "_blank");
    });

    return true;
    }

    if (!install()) {
        $(install);
    }
}());
