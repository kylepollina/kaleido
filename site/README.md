# Kaleido landing page

A one-page static site: `index.html` (inline CSS, one tiny inline script, Google Fonts only) plus `images/`. No build step.

**Preview locally:** open `site/index.html` in a browser, or run `cd site && python3 -m http.server 8000` and visit http://localhost:8000.

## Before it goes live

- **Download buttons** are "Coming soon" placeholders. The two real URLs go in the `#appstore-btn` and `#mac-btn` links (see the comment at the top of `<body>`); then remove `aria-disabled` and the "Coming soon" pills.
- **Screenshots** are placeholders. Capture them, save into `images/`, and swap each `<div class="frame">` for an `<img>` (the comments show where).
- Check the footer name and the GitHub link.

## Hosting options

> **Heads up:** a GitHub Pages site is **publicly visible on the internet even when the repo is private**. Pages from a private repo also needs a paid GitHub plan (Pro, Team or Enterprise). On the free plan, Pages only works for public repos.

### GitHub Pages
Pages can't serve a subfolder named `site` directly. Two ways:
1. **Actions workflow:** Settings → Pages → Source: "GitHub Actions", then add a workflow using `actions/upload-pages-artifact` with `path: site` and `actions/deploy-pages`. Nothing is set up yet; no workflow is included in this repo.
2. **Rename to `/docs`:** `git mv site docs`, then Settings → Pages → "Deploy from a branch" → `main` / `/docs`.

### Custom domain
1. Buy a domain from any registrar.
2. Add a `CNAME` file to the published folder containing just the domain (e.g. `example.com`), or set it in Settings → Pages.
3. At your DNS provider: for an apex domain add `A` records to GitHub's Pages IPs (185.199.108.153, 185.199.109.153, 185.199.110.153, 185.199.111.153; check GitHub's docs for current values); for `www` or another subdomain add a `CNAME` record pointing to `<your-username>.github.io`.
4. Tick "Enforce HTTPS" once the certificate is issued.

### Alternatives
- **Cloudflare Pages** or **Netlify:** connect the repo (or drag-and-drop the `site/` folder), set the publish directory to `site`, no build command. Both support custom domains and HTTPS, and can deploy from a private repo on their free tiers. The site is still public.
- **Cloudflare Pages direct upload / Netlify Drop** need no git integration at all.

Nothing here has been enabled or configured: no Pages, no workflows, no domain, no repo settings.
