# WIFI Terminal

A private dashboard for wificonnector's launch: downloads, website visits,
the install funnel, the Reddit post and its comments, and the repository's
health, refreshed every minute. It runs on Vercel's free plan.

- `index.html` is the page. It holds no keys and shows nothing until you
  enter the access key.
- `api/stats.js` runs on Vercel at `/api/stats`. It reads GitHub, GoatCounter
  and Reddit with the keys you give Vercel, and answers only requests that
  carry the access key.

Keyboard: type a code in the command line and press Enter (`DL`, `FUN`, `RDT`,
`CMT`, `WEB`, `GH`, `R` to refresh, `HELP`), press `/` to jump to it, or press
`1` to `6` anywhere.

## Deploy on Vercel

1. Sign in at [vercel.com](https://vercel.com) with GitHub (the free Hobby plan is enough).
2. **Add New ▸ Project**, then import `anujbajaj4/wificonnector`.
3. Set **Root Directory** to `terminal` and **Framework Preset** to **Other**.
   Leave the build settings empty.
4. Under **Environment Variables**, add:

   | Name | Value |
   |---|---|
   | `ACCESS_KEY` | A long password you make up. You type it into the page once. |
   | `GOATCOUNTER_TOKEN` | See [GoatCounter](#goatcounter) below. |
   | `REDDIT_POST_URL` | `https://www.reddit.com/r/Vit/s/9yKyYCcMMV`, or the post's full address |
   | `REDDIT_CLIENT_ID`, `REDDIT_CLIENT_SECRET` | See [Reddit](#reddit) below. |
   | `GITHUB_TOKEN` | Optional. Any GitHub token; raises GitHub's limit of 60 calls an hour. |

5. **Deploy**, open the `….vercel.app` address and enter your access key.

After changing a variable, redeploy (**Deployments ▸ ⋯ ▸ Redeploy**) for it to apply.

### GoatCounter

GoatCounter ▸ your user menu ▸ **API** ▸ **New API token**. Tick
**Read statistics**, create it and copy the token. Visits stay private: only
the Vercel function sees the token.

### Reddit

Reddit often refuses its public data to servers like Vercel's, so the
terminal logs in as a small Reddit app:

1. Go to [reddit.com/prefs/apps](https://www.reddit.com/prefs/apps) and choose
   **create another app…**
2. Name it (say `wificonnector-terminal`), pick **script**, and enter
   `http://localhost:8080` as the redirect URI. Create it.
3. The client ID is the short code under the app's name; the secret is
   labelled **secret**.

Without these the terminal still tries Reddit's public data. If the Reddit
panel says Reddit refused it, add the app.

Reddit doesn't give apps a post's view count. The panel links to the post,
where you can see views in its insights.

## What the numbers mean

- **Downloads** are GitHub's count for every release's `WiFiConnector.dmg`. The
  one-line installer downloads it too, so command installs count.
- **Test installs (est.)** are GitHub's own test runs since
  `TEST_INSTALLS_SINCE` in `api/stats.js`. Each one installs the latest release
  and counts as a download. The funnel's last step subtracts them.
- **Since last look** compares with what the page showed when you last left
  it. That's kept in this browser only.
- Comments marked **NEW** arrived since you last left the page.
