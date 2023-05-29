import mkdocs


def on_page_read_source(page, config):
    if page.title == "Home":
        return open("README.md").read().replace("docs/", "")
