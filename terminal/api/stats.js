// Every number the terminal shows, gathered in one call so the page itself
// holds no tokens. Runs as a Vercel serverless function at /api/stats.
//
// Environment variables (Vercel ▸ Project ▸ Settings ▸ Environment Variables):
//   ACCESS_KEY             required; the page sends it, nothing loads without it
//   GOATCOUNTER_TOKEN      GoatCounter API token with "read statistics"
//   GOATCOUNTER_SITE       defaults to anujbajaj4
//   REDDIT_POST_URL        the post: a share link (/s/…) or its full address
//   REDDIT_CLIENT_ID       a Reddit "script" app; without it the public JSON is
//   REDDIT_CLIENT_SECRET   tried, which Reddit often refuses from servers
//   GITHUB_TOKEN           optional; raises GitHub's limit of 60 calls an hour
//
// Each source succeeds or fails on its own, so one outage leaves the rest up.

import { timingSafeEqual } from "node:crypto";

const REPO = "anujbajaj4/wificonnector";
const LAUNCH = "2026-10-26";
// From this moment every CI run installs the latest release to test the
// installer, which GitHub counts as a download. Update it if that step goes.
const TEST_INSTALLS_SINCE = "2026-10-26T17:50:00Z";
const USER_AGENT = "wificonnector-terminal/1.0 (by /u/anujbajaj4)";
const CACHE_MS = 45_000;

let cached = { at: 0, body: null };
let redditToken = { value: null, expires: 0 };
let redditPostId = null;

export default async function handler(req, res) {
    res.setHeader("Cache-Control", "no-store");
    if (!keyMatches(req.headers["x-access-key"])) {
        res.status(401).json({ error: "That access key isn't the one set on Vercel." });
        return;
    }
    if (cached.body && Date.now() - cached.at < CACHE_MS) {
        res.status(200).json(cached.body);
        return;
    }
    const [github, visits, reddit] = await Promise.all([
        settle(githubStats()),
        settle(goatcounterStats()),
        settle(redditStats()),
    ]);
    cached = { at: Date.now(), body: { updated: new Date().toISOString(), github, visits, reddit } };
    res.status(200).json(cached.body);
}

function keyMatches(given) {
    const expected = process.env.ACCESS_KEY;
    if (!expected || typeof given !== "string") return false;
    const a = Buffer.from(given);
    const b = Buffer.from(expected);
    return a.length === b.length && timingSafeEqual(a, b);
}

function settle(promise) {
    return promise.then(
        (data) => ({ ok: true, data }),
        (error) => ({ ok: false, error: String(error && error.message ? error.message : error) }),
    );
}

async function getJSON(url, options = {}) {
    const response = await fetch(url, { ...options, signal: AbortSignal.timeout(8000) });
    if (!response.ok) {
        throw new Error(`${new URL(url).host} answered ${response.status}`);
    }
    return response.json();
}

// --- GitHub: downloads, repository, CI ----------------------------------------

async function githubStats() {
    const headers = { Accept: "application/vnd.github+json", "User-Agent": USER_AGENT };
    if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
    const api = `https://api.github.com/repos/${REPO}`;
    const created = encodeURIComponent(`>=${TEST_INSTALLS_SINCE}`);

    const [releases, repo, mainRuns, ciRuns] = await Promise.all([
        getJSON(`${api}/releases?per_page=100`, { headers }),
        getJSON(api, { headers }),
        getJSON(`${api}/actions/runs?branch=main&per_page=1`, { headers }),
        getJSON(`${api}/actions/workflows/ci.yml/runs?per_page=100&created=${created}`, { headers }),
    ]);

    const versions = releases
        .map((release) => ({
            tag: release.tag_name,
            published: release.published_at,
            downloads: release.assets.reduce((sum, asset) => sum + asset.download_count, 0),
        }))
        .sort((a, b) => new Date(b.published) - new Date(a.published));
    const latestRun = mainRuns.workflow_runs[0];

    return {
        downloads: versions.reduce((sum, v) => sum + v.downloads, 0),
        // A run that got as far as the installer test ended in success or failure.
        testInstalls: ciRuns.workflow_runs.filter((run) => run.conclusion === "success" || run.conclusion === "failure").length,
        versions,
        stars: repo.stargazers_count,
        forks: repo.forks_count,
        watchers: repo.subscribers_count,
        openIssues: repo.open_issues_count,
        ci: latestRun ? {
            workflow: latestRun.name,
            status: latestRun.status,
            conclusion: latestRun.conclusion,
            at: latestRun.updated_at,
            url: latestRun.html_url,
        } : null,
    };
}

// --- GoatCounter: visits, clicks, referrers --------------------------------------

async function goatcounterStats() {
    const token = process.env.GOATCOUNTER_TOKEN;
    if (!token) throw new Error("GOATCOUNTER_TOKEN isn't set on Vercel");
    const site = process.env.GOATCOUNTER_SITE || "anujbajaj4";
    const api = `https://${site}.goatcounter.com/api/v0`;
    const headers = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
    const range = `start=${LAUNCH}&end=${new Date().toISOString().slice(0, 10)}`;

    const [total, hits, refs] = await Promise.all([
        getJSON(`${api}/stats/total?${range}`, { headers }),
        getJSON(`${api}/stats/hits?${range}&limit=100`, { headers }),
        getJSON(`${api}/stats/toprefs?${range}&limit=8`, { headers }),
    ]);

    const count = (row) => row.count ?? row.count_unique ?? 0;
    const events = {};
    const pages = [];
    for (const hit of hits.hits || []) {
        const path = String(hit.path || "").replace(/^\//, "");
        if (hit.event) events[path] = (events[path] || 0) + count(hit);
        else pages.push({ path: hit.path || "/", count: count(hit) });
    }
    const sum = (test) => Object.entries(events).filter(([path]) => test(path)).reduce((n, [, c]) => n + c, 0);

    return {
        visits: total.total ?? 0,
        days: (total.stats || []).map((day) => ({ day: day.day, visits: day.daily ?? 0 })),
        pages: pages.sort((a, b) => b.count - a.count).slice(0, 6),
        referrers: (refs.stats || []).map((ref) => ({ name: ref.name || "(unknown)", count: count(ref) })),
        funnel: {
            visits: total.total ?? 0,
            downloadButton: sum((p) => p.startsWith("download-button-")),
            commandCopies: sum((p) => p.startsWith("copy-install-")),
            dmgClicks: sum((p) => /^download-(hero|section|setup)$/.test(p)),
        },
    };
}

// --- Reddit: the launch post and its comments -------------------------------------

async function redditStats() {
    const postUrl = process.env.REDDIT_POST_URL;
    if (!postUrl) throw new Error("REDDIT_POST_URL isn't set on Vercel");
    const id = await resolvePostId(postUrl);

    let listing;
    const token = await redditAccessToken();
    if (token) {
        listing = await getJSON(`https://oauth.reddit.com/comments/${id}?sort=new&limit=200&raw_json=1`, {
            headers: { Authorization: `Bearer ${token}`, "User-Agent": USER_AGENT },
        });
    } else {
        listing = await getJSON(`https://www.reddit.com/comments/${id}.json?sort=new&limit=200&raw_json=1`, {
            headers: { "User-Agent": USER_AGENT },
        });
    }

    const post = listing[0].data.children[0].data;
    const comments = [];
    const walk = (children, depth) => {
        for (const child of children || []) {
            if (child.kind !== "t1") continue;
            const c = child.data;
            comments.push({
                id: c.id,
                author: c.author,
                body: String(c.body || "").slice(0, 500),
                score: c.score,
                created: new Date(c.created_utc * 1000).toISOString(),
                url: `https://www.reddit.com${c.permalink}`,
                depth,
                byOp: c.is_submitter === true,
            });
            if (c.replies && c.replies.data) walk(c.replies.data.children, depth + 1);
        }
    };
    walk(listing[1].data.children, 0);
    comments.sort((a, b) => new Date(b.created) - new Date(a.created));

    return {
        title: post.title,
        subreddit: post.subreddit_name_prefixed,
        url: `https://www.reddit.com${post.permalink}`,
        created: new Date(post.created_utc * 1000).toISOString(),
        score: post.score,
        upvoteRatio: post.upvote_ratio,
        comments: post.num_comments,
        views: post.view_count ?? null,
        latest: comments.slice(0, 40),
    };
}

// A share link (reddit.com/r/Vit/s/…) redirects to the post; its id is in there.
async function resolvePostId(url) {
    const direct = url.match(/\/comments\/([a-z0-9]+)/i);
    if (direct) return direct[1];
    if (redditPostId) return redditPostId;
    const response = await fetch(url, {
        redirect: "manual",
        headers: { "User-Agent": USER_AGENT },
        signal: AbortSignal.timeout(8000),
    });
    const found = (response.headers.get("location") || "").match(/\/comments\/([a-z0-9]+)/i);
    if (!found) {
        throw new Error("Couldn't open the share link; set REDDIT_POST_URL to the post's full address");
    }
    redditPostId = found[1];
    return redditPostId;
}

async function redditAccessToken() {
    const { REDDIT_CLIENT_ID: id, REDDIT_CLIENT_SECRET: secret } = process.env;
    if (!id || !secret) return null;
    if (redditToken.value && Date.now() < redditToken.expires) return redditToken.value;
    const response = await fetch("https://www.reddit.com/api/v1/access_token", {
        method: "POST",
        headers: {
            Authorization: `Basic ${Buffer.from(`${id}:${secret}`).toString("base64")}`,
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": USER_AGENT,
        },
        body: "grant_type=client_credentials",
        signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) throw new Error(`Reddit refused the app login (${response.status})`);
    const token = await response.json();
    redditToken = { value: token.access_token, expires: Date.now() + (token.expires_in - 60) * 1000 };
    return redditToken.value;
}
