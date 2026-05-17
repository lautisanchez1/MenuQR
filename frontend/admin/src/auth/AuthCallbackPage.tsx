import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { isAxiosError } from 'axios';
import { jwtDecode } from 'jwt-decode';
import { Hub } from 'aws-amplify/utils';
import { authApi } from '@/shared/api/authApi';
import { useAuth } from './useAuth';
import { getCurrentTokens } from './cognito';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';

interface CognitoIdClaims {
  email?: string;
}

export function AuthCallbackPage() {
  const navigate = useNavigate();
  const { setFederatedEmail, establishSession } = useAuth();
  const [status, setStatus] = useState('Completing sign-in...');
  const [error, setError] = useState('');
  const hasRun = useRef(false);

  useEffect(() => {
    let cancelled = false;

    const finalize = async () => {
      if (hasRun.current) return;
      hasRun.current = true;

      const tokens = await getCurrentTokens();
      if (!tokens) {
        if (!cancelled) {
          setError('Could not read Cognito session after redirect.');
          setStatus('Sign-in failed');
        }
        return;
      }

      const claims = jwtDecode<CognitoIdClaims>(tokens.idToken);
      const email = claims.email?.trim();
      if (!email) {
        if (!cancelled) {
          setError('Cognito did not return an email address.');
          setStatus('Sign-in failed');
        }
        return;
      }
      if (!cancelled) setFederatedEmail(email);

      try {
        const session = await authApi.bootstrapSession(tokens.idToken);
        if (cancelled) return;
        establishSession(tokens.accessToken, session);
        setStatus('Signed in successfully');
        navigate('/admin', { replace: true });
      } catch (authError) {
        if (
          isAxiosError(authError) &&
          authError.response?.status === 401 &&
          authError.response?.data?.code === 'UNKNOWN_USER'
        ) {
          setStatus('Account setup required');
          navigate('/register', { replace: true });
          return;
        }
        if (!cancelled) {
          setError('Unable to complete sign-in right now.');
          setStatus('Sign-in failed');
        }
      }
    };

    // Two paths to know the redirect finished: the Hub event (fires when
    // Amplify finishes processing the code in the URL) or an existing session
    // (fires if Amplify already processed the redirect before this component
    // mounted — possible under StrictMode or fast navigation).
    const unsubscribe = Hub.listen('auth', ({ payload }) => {
      if (payload.event === 'signInWithRedirect') {
        void finalize();
      } else if (payload.event === 'signInWithRedirect_failure') {
        if (cancelled) return;
        const message = (payload as { data?: { error?: { message?: string } } }).data?.error?.message;
        setError(message || 'Federated sign-in failed.');
        setStatus('Sign-in failed');
      }
    });

    void finalize();

    return () => {
      cancelled = true;
      unsubscribe();
    };
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
