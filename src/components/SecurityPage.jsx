import { useState, useEffect } from 'react';
import { Container, Alert, Spinner, Button } from 'react-bootstrap';
import { FaBell, FaShieldAlt } from 'react-icons/fa';
import { useMsal } from '@azure/msal-react';
import { loginRequest, appConfig } from '../authConfig';
import { calculateNgcmfaExpiration, getAccessToken, getCachedAppToken } from '../utils/tokenUtils';

import { UserProfileHeader, SecurityAlert } from './common/UIComponents';
import ToastNotifications from './common/ToastNotifications';
import PasskeysSection from './passkeys/PasskeysSection';

const NGCMFA_EXPIRY_MINUTES = 15;
const SECONDS_PER_MINUTE = 60;

// Phishing-resistant AMR values (FIDO2 passkey, Windows Hello, hardware key, certificate)
// These are the ONLY values considered compliant — email OTP ("mfa","otp") is explicitly excluded.
const PHISHING_RESISTANT_AMR = ['hwk', 'fido', 'ngcmfa', 'swk', 'pop', 'rsa'];

// Broad MFA values including OTP — used only for determining session state, not compliance.
const MFA_AMR_VALUES = ['mfa', 'otp', ...PHISHING_RESISTANT_AMR];

function hasMfaEvidence(decodedToken) {
    if (!decodedToken) return false;
    const amr = decodedToken.amr;
    if (!amr || !Array.isArray(amr)) return false;
    return amr.some(v => MFA_AMR_VALUES.includes(v.toLowerCase()));
}

// Returns true only when the token carries a phishing-resistant method — not OTP/email.
function hasPhishingResistantMfa(decodedToken) {
    if (!decodedToken) return false;
    const amr = decodedToken.amr;
    if (!amr || !Array.isArray(amr)) return false;
    return amr.some(v => PHISHING_RESISTANT_AMR.includes(v.toLowerCase()));
}

export const SecurityPage = () => {
    const { instance, accounts } = useMsal();
    const [accessToken, setAccessToken] = useState(null);
    const [appToken, setAppToken] = useState(null);
    const [ngcmfaExpiration, setNgcmfaExpiration] = useState(null);
    const [mfaElevated, setMfaElevated] = useState(false);
    const [phishingResistant, setPhishingResistant] = useState(false);
    const [passkeyCount, setPasskeyCount] = useState(null); // null = not yet loaded
    const [loading, setLoading] = useState(true);
    const [accessTokenError, setAccessTokenError] = useState(null);
    const [appTokenError, setAppTokenError] = useState(null);
    const [toasts, setToasts] = useState([]);
    const [stepUpLoading, setStepUpLoading] = useState(false);
    const [userEmail, setUserEmail] = useState(null);


    useEffect(() => {
        const fetchAccessToken = async () => {
            try {
                const result = await getAccessToken(instance, accounts, loginRequest);

                if (result.error) {
                    setAccessTokenError(result.error);
                    setLoading(false);
                } else {
                    setAccessTokenError(null);
                    setAccessToken(result.decodedToken);
                    setLoading(false);
                }
            } catch (error) {
                setAccessTokenError(`Failed to get access token: ${error.message}`);
                setLoading(false);
            }
        };

        fetchAccessToken();
    }, [instance, accounts]);

    useEffect(() => {
        const fetchAppToken = async () => {
            try {
                const token = await getCachedAppToken(
                    instance, 
                    appConfig.proxyDomain, 
                    appConfig.appId, 
                    import.meta.env.VITE_APP_SECRET
                );
                
                if (token) {
                    setAppTokenError(null);
                    setAppToken(token);
                } else {
                    throw new Error('App token request returned empty result');
                }
            } catch (error) {
                // App token failure is non-critical — passkey count and group-enroll
                // will be skipped, but sign-in and banner validation still work.
                console.warn('App token unavailable:', error.message);
                setAppToken(null);
            }
        };

        if (instance) {
            fetchAppToken();
        }
    }, [instance, accessToken]);

    // Auto-enrol new users into the MFA group and load their passkey count.
    // Runs once the app token and user OID are both available.
    useEffect(() => {
        if (!appToken || !accessToken?.oid) return;
        const MFA_GROUP_ID = '5e67e0a8-0153-415e-a6af-9e339750cd0b';
        const userId = accessToken.oid;
        const headers = { Authorization: `Bearer ${appToken}` };

        // Fetch user email from Graph (most reliable for External ID local accounts
        // where the email claim is not returned in the token by default)
        fetch(`https://graph.microsoft.com/v1.0/users/${userId}?$select=mail,displayName,identities`, { headers })
            .then(r => r.json())
            .then(d => {
                // mail is the primary address; fall back to emailAddress identity
                const mail = d?.mail ||
                    d?.identities?.find(i => i.signInType === 'emailAddress')?.issuerAssignedId;
                if (mail) setUserEmail(mail);
            })
            .catch(() => {});

        // Add user to MFA group (idempotent — 400 if already a member, safe to ignore)
        fetch(`https://graph.microsoft.com/v1.0/groups/${MFA_GROUP_ID}/members/$ref`, {
            method: 'POST',
            headers: { ...headers, 'Content-Type': 'application/json' },
            body: JSON.stringify({ '@odata.id': `https://graph.microsoft.com/v1.0/directoryObjects/${userId}` })
        }).catch(() => {}); // 400 = already a member; ignore silently

        // Load passkey count so we know if this is a first-time user
        fetch(`https://graph.microsoft.com/beta/users/${userId}/authentication/fido2Methods`, { headers })
            .then(r => r.json())
            .then(d => setPasskeyCount(d?.value?.length ?? 0))
            .catch(() => setPasskeyCount(0));
    }, [appToken, accessToken]);

    useEffect(() => {
        if (accessToken) {
            const expiration = calculateNgcmfaExpiration(accessToken, NGCMFA_EXPIRY_MINUTES, SECONDS_PER_MINUTE);
            setNgcmfaExpiration(expiration);
            // Real MFA check: amr must contain a recognised MFA method.
            // External ID emits amr only when CA policy triggered MFA — absent amr means password-only.
            setMfaElevated(hasMfaEvidence(accessToken));
            setPhishingResistant(hasPhishingResistantMfa(accessToken));
        } else {
            setNgcmfaExpiration(null);
            setMfaElevated(false);
            setPhishingResistant(false);
        }
    }, [accessToken]);

    const getUserId = () => {
        if (accessToken && accessToken.oid) {
            return accessToken.oid;
        }
        return null;
    };

    const getUserData = () => {
        const defaultUserData = {
            name: "User",
            email: "user@example.com",
        };

        if (accessToken) {
            // Email priority: Graph-fetched (most reliable for CIAM local accounts)
            // → token email claim → skip OID UPN → fallback placeholder
            let email = userEmail;
            if (!email) {
                const candidate = accessToken.email || accessToken.preferred_username || accessToken.unique_name;
                const isOidUpn = candidate && /^[0-9a-f-]{36}@/i.test(candidate);
                if (candidate && !isOidUpn) email = candidate;
            }

            // Name: prefer display name parts, fall back to email prefix
            const nameParts = [accessToken.given_name, accessToken.family_name].filter(Boolean);
            const name = accessToken.name ||
                (nameParts.length ? nameParts.join(' ') : null) ||
                (email ? email.split('@')[0] : defaultUserData.name);

            return { name, email: email || defaultUserData.email };
        }

        return defaultUserData;
    };

    const displayError = accessTokenError; // appTokenError is non-critical: passkey ops silently degrade
    const userData = !loading && !accessTokenError ? getUserData() : { name: "Loading...", email: "Loading..." };
    const userId = !loading && !accessTokenError ? getUserId() : null;

    const handleStepUp = async () => {
        setStepUpLoading(true);
        try {
            // prompt=login forces fresh authentication with no login_hint so CIAM
            // shows the email/passkey chooser. The user can then sign in with their
            // registered passkey (gives hwk/fido in amr) rather than being funnelled
            // into the password → phone-OTP path where CIAM has a 500 error.
            await instance.loginRedirect({
                ...loginRequest,
                prompt: 'login',
            });
        } catch (err) {
            console.error('Step-up redirect failed', err);
            setStepUpLoading(false);
        }
    };

    const showToast = (toastData) => {
        // Check if this is a sessionExpiredWithAction toast and if one already exists
        if (toastData.type === 'sessionExpiredWithAction') {
            const existingSessionExpiredToast = toasts.find(
                toast => toast.type === 'sessionExpiredWithAction' && toast.show
            );
            
            // If a session expired toast is already showing, don't add another one
            if (existingSessionExpiredToast) {
                return;
            }
        }

        const newToast = {
            id: `${Date.now()}-${Math.random().toString(36).substring(2, 8)}`,
            show: true,
            ...toastData
        };
        setToasts(prev => [...prev, newToast]);
    };

    const closeToast = (toastId) => {
        setToasts(prev => prev.filter(toast => toast.id !== toastId));
    };

    if (loading) {
        return (
            <Container className="py-4">
                <div className="d-flex justify-content-center">
                    <Spinner animation="border" role="status">
                        <span className="visually-hidden">Loading...</span>
                    </Spinner>
                </div>
            </Container>
        );
    }

    if (displayError) {
        return (
            <Container className="py-4">
                <Alert variant="danger">
                    <Alert.Heading>Authentication Error</Alert.Heading>
                    <p>{displayError}</p>
                </Alert>
            </Container>
        );
    }

    if (!userId) {
        return (
            <Container className="py-4">
                <Alert variant="warning">
                    <Alert.Heading>User ID Not Available</Alert.Heading>
                    <p>Unable to extract user ID from token claims. Please try logging in again.</p>
                </Alert>
            </Container>
        );
    }

    return (
        <Container className="py-4">
            <UserProfileHeader
                name={userData.name}
                email={userData.email}
            />

            {/* MFA status banner */}
            {phishingResistant ? (
                <Alert variant="success" className="d-flex align-items-center gap-2">
                    <FaShieldAlt />
                    <span>MFA verified — passkey operations are unlocked for this session.</span>
                    <small className="ms-auto text-muted">amr: {accessToken?.amr?.join(', ')}</small>
                </Alert>
            ) : mfaElevated && passkeyCount === 0 ? (
                // Bootstrap: new user with no passkeys — allow registration with OTP so they can enrol
                <Alert variant="info" className="d-flex align-items-center gap-2">
                    <FaShieldAlt className="flex-shrink-0" />
                    <span>
                        Welcome! You must register a passkey before you can use this app.
                        Use the <strong>+ Add Passkey</strong> button below to set one up now.
                        Future sign-ins will use your passkey instead of a one-time code.
                    </span>
                </Alert>
            ) : mfaElevated ? (
                // MFA was completed but via OTP — not phishing-resistant
                <Alert variant="warning" className="d-flex align-items-center gap-2 flex-wrap">
                    <FaBell className="flex-shrink-0" />
                    <span className="me-auto">
                        Your session used one-time passcode (email OTP), which does not meet the
                        phishing-resistant MFA requirement. Sign in with a passkey or security key instead.
                    </span>
                    <Button variant="warning" size="sm" onClick={handleStepUp} disabled={stepUpLoading} className="flex-shrink-0">
                        {stepUpLoading
                            ? <><Spinner animation="border" size="sm" className="me-1" />Redirecting...</>
                            : 'Sign in with passkey'}
                    </Button>
                </Alert>
            ) : (
                <Alert variant="warning" className="d-flex align-items-center gap-2 flex-wrap">
                    <FaBell className="flex-shrink-0" />
                    <span className="me-auto">
                        Multi-factor authentication is required before managing passkeys.
                        Your current session used password only.
                    </span>
                    <Button
                        variant="warning"
                        size="sm"
                        onClick={handleStepUp}
                        disabled={stepUpLoading}
                        className="flex-shrink-0"
                    >
                        {stepUpLoading
                            ? <><Spinner animation="border" size="sm" className="me-1" />Redirecting...</>
                            : 'Elevate with MFA'}
                    </Button>
                </Alert>
            )}

            <PasskeysSection
                onShowToast={showToast}
                appToken={appToken}
                userId={userId}
                ngcmfaExpiry={phishingResistant || (mfaElevated && passkeyCount === 0) ? ngcmfaExpiration : null}
            />

            {/* Toast Notifications */}
            <ToastNotifications
                toasts={toasts}
                onCloseToast={closeToast}
            />
        </Container>
    );
};

export default SecurityPage;
