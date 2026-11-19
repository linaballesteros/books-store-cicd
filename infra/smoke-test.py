import argparse
import json
import time
from urllib.error import URLError
from urllib.request import urlopen


def read_response(url):
    with urlopen(url, timeout=10) as response:
        if response.status != 200:
            raise ValueError(f"{url} returned HTTP {response.status}")
        return response.headers.get_content_type(), response.read()


def check_storefront(base_url):
    content_type, body = read_response(f"{base_url}/")
    if content_type != "text/html" or b"<title>MyBookStore</title>" not in body:
        raise ValueError("The storefront did not return the BookStore HTML")
    print("Storefront returned the BookStore HTML", flush=True)


def check_catalog(base_url):
    content_type, body = read_response(f"{base_url}/api/books?limit=1")
    if content_type != "application/json":
        raise ValueError("The catalog did not return JSON")
    books = json.loads(body)
    if not (
        isinstance(books, list)
        and len(books) == 1
        and isinstance(books[0], dict)
        and books[0].get("isbn")
        and books[0].get("title")
    ):
        raise ValueError("The catalog did not return one seeded book with an ISBN and title")
    print("Catalog returned one seeded book", flush=True)


def main():
    parser = argparse.ArgumentParser(description="Run BookStore smoke tests through its public endpoint.")
    parser.add_argument("base_url", help="Base URL of the deployed environment")
    base_url = parser.parse_args().base_url.rstrip("/")

    for attempt in range(1, 6):
        try:
            check_storefront(base_url)
            check_catalog(base_url)
            return
        except (URLError, OSError, ValueError) as error:
            if attempt == 5:
                raise SystemExit(f"Smoke checks failed: {error}") from error
            print(f"Attempt {attempt} failed: {error}. Retrying in 5 seconds.", flush=True)
            time.sleep(5)


if __name__ == "__main__":
    main()
