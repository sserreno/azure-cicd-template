# An hourly health check instead of monitoring on the free tier

The free tier has no Application Insights or Log Analytics (ADR-0001). Instead, `.github/workflows/health.yml` calls prod's `/api/health` every hour. When the call fails, it opens a GitHub issue labelled `health`; when it recovers, it closes that issue. `/api/health` fails when the database is unreachable, including when the free offer has paused it for the month.

The paid tier also gets Application Insights. The App Service health check is pointed at `/api/health`, and the hourly workflow keeps running as an outside-in check.

## Consequences

- On free, problems are seen at most an hour late, and only as "down". There are no traces or metrics.
- The check runs hourly rather than every 15 minutes, to stay within a private repository's 2,000 free Actions minutes a month.
