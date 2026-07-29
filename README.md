# sitescrape
- A simple script which parses though a sitemap and dumps all urls in the sitemap in a text file
- All urls get listed in a file called `urls.txt` under `/tmp/site/<domain>/` along with the XML version of each sitemap and nested sitemap.
- The command exits with a non-zero status if any sitemap cannot be fetched or written, and only reports completion after all nested sitemaps finish.
- Each successful run deletes and replaces the previous results for every domain processed by that invocation.
- Sitemap URLs are fetched in batches of up to five, and each exact sitemap URL is fetched at most once per invocation.
- Sitemap documents are identified by their `sitemapindex` or `urlset` root element, so sitemap URLs do not need an `.xml` suffix.
- Every command-line argument must return a sitemap document; page URLs passed directly are rejected.
- Both HTTP and HTTPS sitemap URLs are supported, and a leading `www.` is omitted from the output directory name.
- Namespace-prefixed XML, encoded URL characters, and gzip-compressed sitemap responses are supported.

## Requirements

- Bash 3.2 or newer
- `curl`
- `gzip`
- `od`
- `xsltproc`

macOS includes these commands. On Debian or Ubuntu, install `xsltproc` if it is not already available:

```bash
sudo apt-get install xsltproc
```

## Manual validation

Run the script with a sitemap URL:

```bash
./sitescrape https://example.com/sitemap.xml
```

Then confirm it wrote the expected files under `/tmp/site`:

```bash
find /tmp/site -maxdepth 2 -type f
```

You should see a domain folder containing `urls.txt` and any fetched sitemap XML files.
