from locust import HttpUser, task, between

TARGET_URLS = [
    "http://example.com/",
    "http://www.wikipedia.org/",
    "http://www.github.com/",
    "http://www.stackoverflow.com/",
    "http://www.python.org/",
    "http://www.ruby-lang.org/",
    "http://www.mozilla.org/",
    "http://www.w3.org/",
    "http://www.ietf.org/",
    "http://www.debian.org/",
]


class LinkExtractorUser(HttpUser):
    wait_time = between(0.5, 1.5)

    @task
    def extract_links_sequence(self):
        for url in TARGET_URLS:
            with self.client.get(
                f"/api/{url}",
                name="/api/[url]",
                catch_response=True,
            ) as resp:
                if resp.status_code == 200:
                    resp.success()
                else:
                    resp.failure(f"HTTP {resp.status_code} – {url}")
