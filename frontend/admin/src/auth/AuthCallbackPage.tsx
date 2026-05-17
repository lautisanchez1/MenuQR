import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { isAxiosError } from 'axios';
import { jwtDecode } from 'jwt-decode';
import { authApi } from '@/shared/api/authApi';
import { useAuth } from './useAuth';
import { exchangeCodeForTokens, parseCallbackQuery } from './cognito';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';

const SESSION_KEY_ID_TOKEN = 'md_cognito_id_token';
const SESSION_KEY_ACCESS_TOKEN = 'md_cognito_access_token';

interface CognitoIdClaims {
  email?: string;
}

export function AuthCallbackPage() {
  const navigate = useNavigate();
  const { setFederatedEmail, establishSession } = useAuth();
  const [status, setStatus] = useState('Completing sign-in...');
  const [error, setError] = useState('');
  // The token exchange consumes a one-shot PKCE verifier from sessionStorage.
  // React 18 StrictMode mounts effects twice in dev; without this guard the
  // second pass sees the verifier already removed and flashes "Missing PKCE
  // verifier" before the first pass finishes navigating away.
  const hasRun = useRef(false);

  useEffect(() => {
    if (hasRun.current) return;
    hasRun.current = true;

    const completeAuth = async () => {
      const { code, state, error: oauthError, errorDescription } = parseCallbackQuery(window.location.search);

      if (oauthError) {
        setError(errorDescription || oauthError);
        setStatus('Sign-in failed');
        return;
      }

      if (!code || !state) {
        setError('Missing OAuth code or state');
        setStatus('Sign-in failed');
        return;
      }

      let tokens;
      try {
        tokens = await exchangeCodeForTokens(code, state);
      } catch (exchangeError) {
        setError(exchangeError instanceof Error ? exchangeError.message : 'Token exchange failed');
        setStatus('Sign-in failed');
        return;
      }

      const claims = jwtDecode<CognitoIdClaims>(tokens.idToken);
      const email = claims.email?.trim();

      if (!email) {
        setError('Cognito did not return an email address');
        setStatus('Sign-in failed');
        return;
      }

      setFederatedEmail(email);
      // Park both tokens in sessionStorage so the register flow can pick them up if the
      // user has no tenant yet. They are moved to localStorage on a successful session.
      sessionStorage.setItem(SESSION_KEY_ID_TOKEN, tokens.idToken);
      sessionStorage.setItem(SESSION_KEY_ACCESS_TOKEN, tokens.accessToken);
      window.history.replaceState({}, document.title, window.location.pathname);

      try {
        const session = await authApi.bootstrapSession(tokens.idToken);
        establishSession(tokens.accessToken, session);
        sessionStorage.removeItem(SESSION_KEY_ID_TOKEN);
        sessionStorage.removeItem(SESSION_KEY_ACCESS_TOKEN);
        setStatus('Signed in successfully');
        navigate('/admin', { replace: true });
      } catch (authError) {
        if (isAxiosError(authError) && authError.response?.status === 401 && authError.response?.data?.code === 'UNKNOWN_USER') {
          setStatus('Account setup required');
          navigate('/register', { replace: true });
          return;
        }

        sessionStorage.removeItem(SESSION_KEY_ID_TOKEN);
        sessionStorage.removeItem(SESSION_KEY_ACCESS_TOKEN);
        setError('Unable to complete sign-in right now');
        setStatus('Sign-in failed');
      }
    };

    void completeAuth();
  }, [navigate, setFederatedEmail, establishSession]);

  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle className="text-center">MenuDigital</CardTitle>
          <CardDescription className="text-center">{status}</CardDescription>
        </CardHeader>
        <CardContent>
          {error ? (
            <p className="text-sm text-destructive text-center">{error}</p>
          ) : (
            <p className="text-sm text-muted-foreground text-center">You can close this tab once the redirect completes.</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
