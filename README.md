# sitescrape
- A simple script which parses though a sitemap and dumps all urls in the sitemap in a text file
- All urls get listed in a file called `urls.txt` under `/tmp/site/<domain>/` along with the XML version of each sitemap and nested sitemap.

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
