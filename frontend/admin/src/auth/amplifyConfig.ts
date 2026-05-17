import { Amplify } from 'aws-amplify';

const userPoolId = import.meta.env.VITE_COGNITO_USER_POOL_ID?.trim();
const userPoolClientId = import.meta.env.VITE_COGNITO_CLIENT_ID?.trim();
const hostedUiBaseUrl = import.meta.env.VITE_COGNITO_HOSTED_UI_BASE_URL?.trim();
const redirectSignIn = import.meta.env.VITE_COGNITO_REDIRECT_URI?.trim() || `${window.location.origin}/auth/callback`;
const redirectSignOut = import.meta.env.VITE_COGNITO_LOGOUT_URI?.trim() || `${window.location.origin}/login`;

export function isAmplifyAuthConfigured(): boolean {
  return Boolean(userPoolId && userPoolClientId);
}

export function configureAmplifyAuth() {
  if (!isAmplifyAuthConfigured()) {
    return;
  }

  // The hosted-UI domain is only needed for federated providers (Google,
  // Facebook). Email/password sign-in talks to the Cognito API directly and
  // works without it. We pass `oauth` only when a domain is configured.
  const oauth = hostedUiBaseUrl
    ? {
        domain: hostedUiBaseUrl.replace(/^https?:\/\//, '').replace(/\/$/, ''),
        scopes: ['openid', 'email', 'profile'] as ('openid' | 'email' | 'profile')[],
        redirectSignIn: [redirectSignIn],
        redirectSignOut: [redirectSignOut],
        responseType: 'code' as const,
      }
    : undefined;

  Amplify.configure({
    Auth: {
      Cognito: {
        userPoolId: userPoolId!,
        userPoolClientId: userPoolClientId!,
        signUpVerificationMethod: 'code',
        loginWith: {
          email: true,
          ...(oauth ? { oauth } : {}),
        },
      },
    },
  });
}
