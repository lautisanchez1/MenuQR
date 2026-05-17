import { useState, type FormEvent } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';
import { toast } from '@/hooks/use-toast';
import { canUseCognitoAuth, confirmPasswordReset, requestPasswordReset } from './cognito';

const MIN_PASSWORD_LENGTH = 12;
const PASSWORD_RULE = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{12,}$/;

interface AmplifyErrorLike { name?: string; message?: string }

function describeResetError(err: unknown): string {
  if (err && typeof err === 'object') {
    const e = err as AmplifyErrorLike;
    switch (e.name) {
      case 'CodeMismatchException':
        return 'Incorrect verification code.';
      case 'ExpiredCodeException':
        return 'Code expired. Request a new one.';
      case 'InvalidPasswordException':
        return 'Password does not meet the required policy.';
      case 'UserNotFoundException':
        return 'No account found for this email.';
      case 'LimitExceededException':
      case 'TooManyRequestsException':
        return 'Too many attempts. Try again in a few minutes.';
    }
    if (e.message) return e.message;
  }
  return 'Password reset failed. Try again.';
}

type Stage = 'request' | 'confirm';

export function ForgotPasswordPage() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const [stage, setStage] = useState<Stage>('request');
  const [email, setEmail] = useState(params.get('email') || '');
  const [code, setCode] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const configured = canUseCognitoAuth();

  const handleRequest = async (e: FormEvent) => {
    e.preventDefault();
    if (!email.trim()) {
      setError('Email is required.');
      return;
    }
    setError('');
    setLoading(true);
    try {
      await requestPasswordReset(email.trim());
      toast({ title: 'Code sent', description: 'Check your inbox for the reset code.', variant: 'success' });
      setStage('confirm');
    } catch (err) {
      setError(describeResetError(err));
    } finally {
      setLoading(false);
    }
  };

  const handleConfirm = async (e: FormEvent) => {
    e.preventDefault();
    if (!code.trim()) {
      setError('Verification code is required.');
      return;
    }
    if (!PASSWORD_RULE.test(newPassword)) {
      setError(`Password must be at least ${MIN_PASSWORD_LENGTH} characters and include upper, lower, number, and symbol.`);
      return;
    }
    if (newPassword !== confirm) {
      setError('Passwords do not match.');
      return;
    }
    setError('');
    setLoading(true);
    try {
      await confirmPasswordReset(email.trim(), code.trim(), newPassword);
      toast({ title: 'Password updated', description: 'You can now sign in.', variant: 'success' });
      navigate('/login', { replace: true });
    } catch (err) {
      setError(describeResetError(err));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1">
          <CardTitle className="text-2xl font-bold text-center">Reset password</CardTitle>
          <CardDescription className="text-center">
            {stage === 'request'
              ? "Enter your email and we'll send a verification code"
              : 'Enter the code and choose a new password'}
          </CardDescription>
        </CardHeader>
        {stage === 'request' ? (
          <form onSubmit={handleRequest}>
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
                  autoComplete="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  disabled={!configured || loading}
                />
              </div>
              <Button type="submit" className="w-full" disabled={!configured || loading}>
                {loading ? 'Sending...' : 'Send reset code'}
              </Button>
            </CardContent>
            <CardFooter>
              <p className="text-sm text-muted-foreground text-center w-full">
                Remembered it?{' '}
                <Link to="/login" className="text-primary hover:underline">
                  Back to sign in
                </Link>
              </p>
            </CardFooter>
          </form>
        ) : (
          <form onSubmit={handleConfirm}>
            <CardContent className="space-y-4">
              {error && (
                <div className="p-3 text-sm text-destructive bg-destructive/10 rounded-md">
                  {error}
                </div>
              )}
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
              <div className="space-y-2">
                <Label htmlFor="new-password">New password</Label>
                <Input
                  id="new-password"
                  type="password"
                  autoComplete="new-password"
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  disabled={!configured || loading}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="confirm-password">Confirm new password</Label>
                <Input
                  id="confirm-password"
                  type="password"
                  autoComplete="new-password"
                  value={confirm}
                  onChange={(e) => setConfirm(e.target.value)}
                  disabled={!configured || loading}
                />
              </div>
              <Button type="submit" className="w-full" disabled={!configured || loading}>
                {loading ? 'Updating...' : 'Update password'}
              </Button>
              <Button
                type="button"
                variant="ghost"
                className="w-full"
                onClick={() => setStage('request')}
                disabled={loading}
              >
                Use a different email
              </Button>
            </CardContent>
          </form>
        )}
      </Card>
    </div>
  );
}
