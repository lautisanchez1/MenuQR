const hostedUiBaseUrl = import.meta.env.VITE_COGNITO_HOSTED_UI_BASE_URL?.trim();
const clientId = import.meta.env.VITE_COGNITO_CLIENT_ID?.trim();
const redirectUri = import.meta.env.VITE_COGNITO_REDIRECT_URI?.trim() || `${window.location.origin}/auth/callback`;

export type SocialProvider = 'Google' | 'Facebook';

export const socialProviders: SocialProvider[] = ['Google', 'Facebook'];

export function canUseCognitoHostedUi() {
  return Boolean(hostedUiBaseUrl && clientId);
}

export function buildHostedUiUrl(provider: SocialProvider) {
  if (!canUseCognitoHostedUi()) {
    throw new Error('Cognito hosted UI is not configured');
  }

  const url = new URL('/oauth2/authorize', hostedUiBaseUrl);
  url.searchParams.set('client_id', clientId!);
  url.searchParams.set('response_type', 'token');
  url.searchParams.set('scope', 'openid email profile');
  url.searchParams.set('redirect_uri', redirectUri);
  url.searchParams.set('identity_provider', provider);
  return url.toString();
}

export function parseCognitoHash(fragment: string) {
  const params = new URLSearchParams(fragment.startsWith('#') ? fragment.slice(1) : fragment);
  return {
    idToken: params.get('id_token'),
    accessToken: params.get('access_token'),
    error: params.get('error'),
    errorDescription: params.get('error_description'),
  };
}