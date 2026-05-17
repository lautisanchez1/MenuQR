import { useEffect, useState, type FormEvent } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { isAxiosError } from 'axios';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';
import { toast } from '@/hooks/use-toast';
import { authApi } from '@/shared/api/authApi';
import {
  canUseCognitoAuth,
  confirmSignUpCode,
  getCurrentTokens,
  resendConfirmationCode,
} from './cognito';
import { useAuth } from './useAuth';

interface AmplifyErrorLike { name?: string; message?: string }

function describeConfirmError(err: unknown): string {
  if (err && typeof err === 'object') {
    const e = err as AmplifyErrorLike;
    switch (e.name) {
      case 'CodeMismatchException':
        return 'Incorrect verification code.';
      case 'ExpiredCodeException':
        return 'Code expired. Request a new one.';
      case 'LimitExceededException':
      case 'TooManyRequestsException':
        return 'Too many attempts. Try again in a few minutes.';
    }
    if (e.message) return e.message;
  }
  return 'Verification failed. Try again.';
}

export function ConfirmSignUpPage() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const { establishSession, setFederatedEmail } = useAuth();
  const [email, setEmail] = useState(params.get('email') || '');
  const [code, setCode] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [resending, setResending] = useState(false);
  const configured = canUseCognitoAuth();

  useEffect(() => {
    if (!email && params.get('email')) {
      setEmail(params.get('email') || '');
    }
  }, [params, email]);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (!email.trim() || !code.trim()) {
      setError('Email and code are required.');
      return;
    }
    setError('');
    setLoading(true);
    try {
      await confirmSignUpCode(email.trim(), code.trim());
      // confirmSignUpCode invoked autoSignIn() on our behalf. If a session is
      // available, push the user straight into the restaurant-setup flow.
      const tokens = await getCurrentTokens();
      if (!tokens) {
        toast({ title: 'Email verified', description: 'Please sign in to continue.', variant: 'success' });
        navigate('/login', { replace: true });
        return;
      }
      setFederatedEmail(email.trim());
      try {
        const session = await authApi.bootstrapSession(tokens.idToken);
        establishSession(tokens.accessToken, session);
        navigate('/admin', { replace: true });
      } catch (apiError) {
        if (isAxiosError(apiError) && apiError.response?.status === 401 && apiError.response?.data?.code === 'UNKNOWN_USER') {
          navigate('/register', { replace: true });
          return;
        }
        setError('Verified, but could not start your session. Try signing in.');
      }
    } catch (err) {
      setError(describeConfirmError(err));
    } finally {
      setLoading(false);
    }
  };

  const handleResend = async () => {
    if (!email.trim()) {
      setError('Enter your email first.');
      return;
    }
    setResending(true);
    setError('');
    try {
      await resendConfirmationCode(email.trim());
      toast({ title: 'Code resent', description: 'Check your inbox.', variant: 'success' });
    } catch (err) {
      setError(describeConfirmError(err));
    } finally {
      setResending(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1">
          <CardTitle className="text-2xl font-bold text-center">Verify your email</CardTitle>
          <CardDescription className="text-center">
            Enter the 6-digit code we sent to your inbox
          </CardDescription>
        </CardHeader>
        <form onSubmit={handleSubmit}>
          <CardContent className="space-y-4">
            {error && (
              <div className="p-3 text-sm text-destructive bg-destructive/10 rounded-md">
                {error}
              </div>
            )}
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                disabled={!configured || loading}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="code">Verification code</Label>
              <Input
                id="code"
                inputMode="numeric"
                autoComplete="one-time-code"
                value={code}
                onChange={(e) => setCode(e.target.value)}
                disabled={!configured || loading}
              />
            </div>
            <Button type="submit" className="w-full" disabled={!configured || loading}>
              {loading ? 'Verifying...' : 'Verify email'}
            </Button>
            <Button
              type="button"
              variant="ghost"
              className="w-full"
              onClick={handleResend}
              disabled={!configured || resending}
            >
              {resending ? 'Sending...' : 'Resend code'}
            </Button>
          </CardContent>
          <CardFooter>
            <p className="text-sm text-muted-foreground text-center w-full">
              Wrong account?{' '}
              <Link to="/login" className="text-primary hover:underline">
                Back to sign in
              </Link>
            </p>
          </CardFooter>
        </form>
      </Card>
    </div>
  );
}
