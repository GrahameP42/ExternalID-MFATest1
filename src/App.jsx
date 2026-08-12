import { MsalProvider, AuthenticatedTemplate, UnauthenticatedTemplate, useMsal } from '@azure/msal-react';
import { Container, Form, Button, Card, Spinner } from 'react-bootstrap';
import { useState } from 'react';
import { PageLayout } from './components/PageLayout';
import { SecurityPage } from './components/SecurityPage';
import { loginRequest, appConfig, tenantIssuer } from './authConfig';
import { getAppToken } from './utils/tokenUtils';

import './styles/App.css';

/**
 * Resolve a consumer email (e.g. g.petch@gmail.com) to the user's tenant UPN
 * (e.g. <oid>@PetchyEntraExternalIDTest03.onmicrosoft.com) so that login_hint
 * doesn't trigger Microsoft home-realm-discovery and route to MSA.
 * Returns null if the user doesn't exist or the lookup fails.
 */
async function resolveLoginHint(email) {
    try {
        const appToken = await getAppToken(appConfig.proxyDomain, appConfig.appId, appConfig.appSecret);
        if (!appToken) return null;
        const filter = encodeURIComponent(
            `identities/any(i:i/issuerAssignedId eq '${email}' and i/issuer eq '${tenantIssuer}')`
        );
        const resp = await fetch(
            `https://graph.microsoft.com/v1.0/users?$filter=${filter}&$select=userPrincipalName`,
            { headers: { Authorization: `Bearer ${appToken}` } }
        );
        if (!resp.ok) return null;
        const data = await resp.json();
        return data.value?.[0]?.userPrincipalName ?? null;
    } catch {
        return null;
    }
}

const LandingPage = () => {
    const { instance } = useMsal();
    const [email, setEmail] = useState('');
    const [loading, setLoading] = useState(false);

    const handleContinue = async (e) => {
        e.preventDefault();
        if (!email.trim()) return;
        setLoading(true);
        try {
            // Check whether the account already exists in the directory.
            // • Existing user  → redirect WITHOUT login_hint so the CIAM email field is
            //   blank; autocomplete="username webauthn" then surfaces the registered passkey
            //   as a browser autofill suggestion for a single-gesture phishing-resistant sign-in.
            // • New user       → redirect WITH login_hint so CIAM pre-fills the email and
            //   routes straight to the sign-up/verify flow (no need to re-enter the address).
            // • Lookup failure → fall back to no login_hint (safe; existing behaviour).
            const upn = await resolveLoginHint(email.trim());
            const request = upn
                ? { ...loginRequest }                                    // existing: let passkey autofill work
                : { ...loginRequest, loginHint: email.trim() };          // new user: pre-fill sign-up form
            await instance.loginRedirect(request);
        } finally {
            setLoading(false);
        }
    };

    return (
        <Container className="d-flex justify-content-center align-items-center" style={{ minHeight: '60vh' }}>
            <Card style={{ width: '400px' }} className="p-4 shadow-sm">
                <Card.Body>
                    <h5 className="mb-1">Sign in or create an account</h5>
                    <p className="text-muted small mb-4">
                        Use your email address — personal, work, or any address you own.
                    </p>
                    <Form onSubmit={handleContinue}>
                        <Form.Group className="mb-3">
                            <Form.Label>Email address</Form.Label>
                            <Form.Control
                                type="email"
                                placeholder="you@example.com"
                                value={email}
                                onChange={e => setEmail(e.target.value)}
                                autoFocus
                                disabled={loading}
                            />
                            <Form.Text className="text-muted">
                                New users will be prompted to verify their email and set a password.
                            </Form.Text>
                        </Form.Group>
                        <Button type="submit" variant="primary" className="w-100" disabled={loading || !email.trim()}>
                            {loading ? <><Spinner animation="border" size="sm" className="me-2" />Resolving...</> : 'Continue'}
                        </Button>
                    </Form>
                </Card.Body>
            </Card>
        </Container>
    );
};

const MainContent = () => {
    const { instance } = useMsal();
    const activeAccount = instance.getActiveAccount();

    return (
        <div className="App">
            <AuthenticatedTemplate>
                {activeAccount ? (
                    <Container>
                        <SecurityPage />
                    </Container>
                ) : null}
            </AuthenticatedTemplate>
            <UnauthenticatedTemplate>
                <LandingPage />
            </UnauthenticatedTemplate>
        </div>
    );
};

/**
 * msal-react is built on the React context API and all parts of your app that require authentication must be 
 * wrapped in the MsalProvider component. You will first need to initialize an instance of PublicClientApplication 
 * then pass this to MsalProvider as a prop. All components underneath MsalProvider will have access to the 
 * PublicClientApplication instance via context as well as all hooks and components provided by msal-react. For more, visit:
 * https://github.com/AzureAD/microsoft-authentication-library-for-js/blob/dev/lib/msal-react/docs/getting-started.md
 */
const App = ({ instance }) => {
    return (
        <MsalProvider instance={instance}>
            <PageLayout>
                <MainContent />
            </PageLayout>
        </MsalProvider>
    );
};

export default App;