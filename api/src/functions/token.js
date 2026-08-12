const { app } = require('@azure/functions');

/**
 * Server-side proxy for CIAM client_credentials token requests.
 *
 * The SPA cannot call client_credentials directly — CIAM blocks cross-origin
 * requests for this grant type. This function runs server-side (no CORS issue)
 * and forwards the token to the browser.
 *
 * Route: POST /api/oauth2/v2.0/token
 * Mirrors the CIAM token endpoint path so authConfig.proxyDomain = '/api' works
 * without any changes to tokenUtils.getAppToken().
 *
 * Environment variables (set in SWA app settings):
 *   CLIENT_ID      — app registration client ID
 *   CLIENT_SECRET  — app registration client secret (never exposed to browser)
 *   TENANT_ID      — Entra External ID tenant ID
 *   CIAM_DOMAIN    — e.g. petchyentraexternalidtest03.ciamlogin.com
 */
app.http('token', {
    methods: ['POST', 'OPTIONS'],
    authLevel: 'anonymous',
    route: 'oauth2/v2.0/token',
    handler: async (request, context) => {
        // CORS preflight
        if (request.method === 'OPTIONS') {
            return {
                status: 204,
                headers: {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Methods': 'POST, OPTIONS',
                    'Access-Control-Allow-Headers': 'Content-Type',
                },
            };
        }

        const clientId     = process.env.CLIENT_ID;
        const clientSecret = process.env.CLIENT_SECRET;
        const tenantId     = process.env.TENANT_ID;
        const ciamDomain   = process.env.CIAM_DOMAIN;

        if (!clientId || !clientSecret || !tenantId || !ciamDomain) {
            context.error('Missing required environment variables');
            return { status: 500, body: JSON.stringify({ error: 'server_misconfiguration' }) };
        }

        // Read the incoming body and override client credentials with server-side values.
        // The browser sends client_id + scope + grant_type; we inject the secret.
        const bodyText = await request.text();
        const params = new URLSearchParams(bodyText);
        params.set('client_id', clientId);
        params.set('client_secret', clientSecret);

        const tokenUrl = `https://${ciamDomain}/${tenantId}/oauth2/v2.0/token`;

        try {
            const resp = await fetch(tokenUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: params.toString(),
            });

            const data = await resp.json();

            return {
                status: resp.status,
                headers: {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                },
                body: JSON.stringify(data),
            };
        } catch (err) {
            context.error('Token proxy error:', err);
            return {
                status: 502,
                body: JSON.stringify({ error: 'upstream_error', message: err.message }),
            };
        }
    },
});
