/*
 * Copyright (c) Microsoft Corporation. All rights reserved.
 * Licensed under the MIT License.
 */

import { LogLevel } from '@azure/msal-browser';

// Support both Vite (browser, import.meta.env) and Node.js (cors.js, process.env)
const viteEnv = (typeof import.meta !== 'undefined' && import.meta.env) ? import.meta.env : {};
const nodeEnv = (typeof process !== 'undefined' && process.env) ? process.env : {};
const env = { ...nodeEnv, ...viteEnv };

const _clientId   = env.VITE_CLIENT_ID   || '<your-client-id-here>';
const _tenantId   = env.VITE_TENANT_ID   || '<your-tenant-id>';
const _ciamDomain = env.VITE_CIAM_DOMAIN || '<your-tenant-subdomain>.ciamlogin.com';
const _authority  = `https://${_ciamDomain}/`;
// e.g. petchyentraexternalidtest03.onmicrosoft.com — used as the identity issuer for local accounts
export const tenantIssuer = _ciamDomain.replace('.ciamlogin.com', '.onmicrosoft.com');

/**
 * Configuration object to be passed to MSAL instance on creation. 
 * For a full list of MSAL.js configuration parameters, visit:
 * https://github.com/AzureAD/microsoft-authentication-library-for-js/blob/dev/lib/msal-browser/docs/configuration.md 
 */

export const msalConfig = {
    auth: {
        clientId: _clientId,
        authority: _authority,
        redirectUri: '/',
        postLogoutRedirectUri: '/',
        navigateToLoginRequestUrl: false,
    },
    cache: {
        cacheLocation: 'sessionStorage', // Configures cache location. "sessionStorage" is more secure, but "localStorage" gives you SSO between tabs.
        storeAuthStateInCookie: false, // Set this to "true" if you are having issues on IE11 or Edge
    },
    system: {
        loggerOptions: {
            loggerCallback: (level, message, containsPii) => {
                if (containsPii) {
                    return;
                }
                switch (level) {
                    case LogLevel.Error:
                        console.error(message);
                        return;
                    case LogLevel.Info:
                        console.info(message);
                        return;
                    case LogLevel.Verbose:
                        console.debug(message);
                        return;
                    case LogLevel.Warning:
                        console.warn(message);
                        return;
                    default:
                        return;
                }
            },
        },
    },
};

/**
 * Scopes you add here will be prompted for user consent during sign-in.
 * By default, MSAL.js will add OIDC scopes (openid, profile, email) to any login request.
 * For more information about OIDC scopes, visit: 
 * https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-permissions-and-consent#openid-connect-scopes
 */
const claimsRequestValue = {
    "id_token": {
    "amr": {
        // essential: false allows sign-in for users with no ngcmfa credential yet (bootstrapping).
        // Once a passkey is registered, subsequent sign-ins will satisfy ngcmfa automatically.
        "essential": false,
        "values": ["ngcmfa"]
        }
    },
    access_token: {
        amr: {
            essential: false,
            values: ['ngcmfa']
        }
    }
};
const claims = JSON.stringify(claimsRequestValue);
export const loginRequest = {
    // email scope ensures the email claim is present in the ID token for display purposes.
    scopes: ['email'],
};


/**
 * Application configuration consumed by the SPA at runtime.
 */
export const appConfig = {
    proxyDomain: 'http://localhost:3001/api',
    appId: _clientId,
    tenantId: _tenantId,
    appSecret: env.VITE_APP_SECRET || '',
    customDomain: env.VITE_CUSTOM_DOMAIN || 'login.azddns.top',
    // passkey registration RP origin — must match the domain the app is served from
    // when served via Front Door (login.azddns.top), this ensures the WebAuthn RP ID
    // is a valid suffix of petchyentraexternalidtest03.ciamlogin.com
    passkeyOrigin: env.VITE_PASSKEY_ORIGIN || 'https://login.azddns.top',
};