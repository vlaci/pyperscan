from pathlib import Path


def on_page_read_source(page, **_kw):
    if page.title != "Home":
        return None

    return Path("README.md").read_text().replace("docs/", "")
