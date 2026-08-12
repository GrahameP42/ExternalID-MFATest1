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

    const handleSignIn = async (e) => {
        e.preventDefault();
        setLoading(true);
        try {
            // No login_hint: CIAM email field stays blank so autocomplete="username webauthn"
            // surfaces the registered passkey for one-tap phishing-resistant sign-in.
            await instance.loginRedirect({ ...loginRequest });
        } finally {
            setLoading(false);
        }
    };

    const handleCreateAccount = async (e) => {
        e.preventDefault();
        if (!email.trim()) return;
        setLoading(true);
        try {
            // prompt=create directs CIAM to the sign-up flow.
            // loginHint pre-fills the email so the user doesn't have to re-enter it.
            await instance.loginRedirect({
                ...loginRequest,
                loginHint: email.trim(),
                extraQueryParameters: { prompt: 'create' },
            });
        } finally {
            setLoading(false);
        }
    };

    return (
        <Container className="d-flex justify-content-center align-items-center" style={{ minHeight: '60vh' }}>
            <Card style={{ width: '420px' }} className="p-4 shadow-sm">
                <Card.Body>
                    <h5 className="mb-1">Sign in or create an account</h5>
                    <p className="text-muted small mb-3">
                        Use your email address — personal, work, or any address you own.
                    </p>

                    {/* Sign-in path — no email needed; passkey autofill works on the next page */}
                    <Button
                        variant="primary"
                        className="w-100 mb-3"
                        onClick={handleSignIn}
                        disabled={loading}
                    >
                        {loading ? <><Spinner animation="border" size="sm" className="me-2" />Please wait...</> : 'Sign in'}
                    </Button>

                    <hr className="my-3" />
                    <p className="text-muted small mb-2 text-center">New here? Enter your email to create an account.</p>

                    {/* Sign-up path — email required to pre-fill the CIAM sign-up form */}
                    <Form onSubmit={handleCreateAccount}>
                        <Form.Group className="mb-3">
                            <Form.Control
                                type="email"
                                placeholder="you@example.com"
                                value={email}
                                onChange={e => setEmail(e.target.value)}
                                disabled={loading}
                            />
                        </Form.Group>
                        <Button type="submit" variant="outline-primary" className="w-100" disabled={loading || !email.trim()}>
                            Create account
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