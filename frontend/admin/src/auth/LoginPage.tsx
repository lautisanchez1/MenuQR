import { Link } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { buildHostedUiUrl, canUseCognitoHostedUi, socialProviders } from './cognito';

export function LoginPage() {
  const startLogin = async (provider: 'Google' | 'Facebook') => {
    window.location.assign(await buildHostedUiUrl(provider));
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1">
          <CardTitle className="text-2xl font-bold text-center">MenuDigital</CardTitle>
          <CardDescription className="text-center">
            Sign in with a federated provider to manage your restaurant menu
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-3">
            {socialProviders.map((provider) => (
              <Button
                key={provider}
                type="button"
                className="w-full"
                variant="outline"
                disabled={!canUseCognitoHostedUi()}
                onClick={() => startLogin(provider)}
              >
                Continue with {provider}
              </Button>
            ))}
          </div>
          {!canUseCognitoHostedUi() && (
            <p className="text-xs text-muted-foreground text-center">
              Configure Cognito hosted UI to enable federated sign-in.
            </p>
          )}
          <p className="text-sm text-muted-foreground text-center">
            New restaurant?{' '}
            <Link to="/register" className="text-primary hover:underline">
              Finish setup after sign-in
            </Link>
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
