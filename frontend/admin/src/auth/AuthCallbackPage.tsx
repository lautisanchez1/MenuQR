import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { isAxiosError } from 'axios';
import { jwtDecode } from 'jwt-decode';
import { authApi } from '@/shared/api/authApi';
import { useAuth } from './useAuth';
import { exchangeCodeForTokens, parseCallbackQuery } from './cognito';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';

interface CognitoTokenClaims {
  email?: string;
}

export function AuthCallbackPage() {
  const navigate = useNavigate();
  const { setFederatedEmail } = useAuth();
  const [status, setStatus] = useState('Completing sign-in...');
  const [error, setError] = useState('');

  useEffect(() => {
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

      const claims = jwtDecode<CognitoTokenClaims>(tokens.idToken);
      const email = claims.email?.trim();

      if (!email) {
        setError('Cognito did not return an email address');
        setStatus('Sign-in failed');
        return;
      }

      setFederatedEmail(email);
      window.history.replaceState({}, document.title, window.location.pathname);

      try {
        const response = await authApi.login({ email });
        localStorage.setItem('md_token', response.token);
        setStatus('Signed in successfully');
        navigate('/admin', { replace: true });
      } catch (authError) {
        if (isAxiosError(authError) && authError.response?.status === 401) {
          setStatus('Account setup required');
          navigate('/register', { replace: true });
          return;
        }

        setError('Unable to complete sign-in right now');
        setStatus('Sign-in failed');
      }
    };

    void completeAuth();
  }, [navigate, setFederatedEmail]);

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