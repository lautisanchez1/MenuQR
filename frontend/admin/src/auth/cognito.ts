const hostedUiBaseUrl = import.meta.env.VITE_COGNITO_HOSTED_UI_BASE_URL?.trim();
const clientId = import.meta.env.VITE_COGNITO_CLIENT_ID?.trim();
const redirectUri = import.meta.env.VITE_COGNITO_REDIRECT_URI?.trim() || `${window.location.origin}/auth/callback`;

const STORAGE_KEY_VERIFIER = 'md_cognito_pkce_verifier';
const STORAGE_KEY_STATE = 'md_cognito_pkce_state';

export type SocialProvider = 'Google' | 'Facebook';

export const socialProviders: SocialProvider[] = ['Google', 'Facebook'];

export interface CognitoTokens {
  idToken: string;
  accessToken: string;
  refreshToken?: string;
  expiresIn: number;
}

export function canUseCognitoHostedUi() {
  return Boolean(hostedUiBaseUrl && clientId);
}

export async function buildHostedUiUrl(provider: SocialProvider) {
  if (!canUseCognitoHostedUi()) {
    throw new Error('Cognito hosted UI is not configured');
  }

  const verifier = generateRandomString(32);
  const challenge = base64UrlEncode(await sha256(verifier));
  const state = generateRandomString(16);

  sessionStorage.setItem(STORAGE_KEY_VERIFIER, verifier);
  sessionStorage.setItem(STORAGE_KEY_STATE, state);

  const url = new URL('/oauth2/authorize', hostedUiBaseUrl);
  url.searchParams.set('client_id', clientId!);
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('scope', 'openid email profile');
  url.searchParams.set('redirect_uri', redirectUri);
  url.searchParams.set('identity_provider', provider);
  url.searchParams.set('code_challenge_method', 'S256');
  url.searchParams.set('code_challenge', challenge);
  url.searchParams.set('state', state);
  return url.toString();
}

export function buildHostedUiLogoutUrl() {
  if (!canUseCognitoHostedUi()) {
    return null;
  }

  const logoutUri = import.meta.env.VITE_COGNITO_LOGOUT_URI?.trim() || `${window.location.origin}/login`;
  const url = new URL('/logout', hostedUiBaseUrl);
  url.searchParams.set('client_id', clientId!);
  url.searchParams.set('logout_uri', logoutUri);
  return url.toString();
}

export async function exchangeCodeForTokens(code: string, returnedState: string): Promise<CognitoTokens> {
  if (!canUseCognitoHostedUi()) {
    throw new Error('Cognito hosted UI is not configured');
  }

  const verifier = sessionStorage.getItem(STORAGE_KEY_VERIFIER);
  const expectedState = sessionStorage.getItem(STORAGE_KEY_STATE);

  sessionStorage.removeItem(STORAGE_KEY_VERIFIER);
  sessionStorage.removeItem(STORAGE_KEY_STATE);

  if (!verifier) {
    throw new Error('Missing PKCE verifier; restart sign-in');
  }
  if (!expectedState || expectedState !== returnedState) {
    throw new Error('OAuth state mismatch; possible CSRF');
  }

  const tokenUrl = new URL('/oauth2/token', hostedUiBaseUrl).toString();
  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    code,
    client_id: clientId!,
    redirect_uri: redirectUri,
    code_verifier: verifier,
  });

  const response = await fetch(tokenUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });

  if (!response.ok) {
    throw new Error(`Cognito token exchange failed: ${response.status}`);
  }

  const data = await response.json();
  return {
    idToken: data.id_token,
    accessToken: data.access_token,
    refreshToken: data.refresh_token,
    expiresIn: data.expires_in,
  };
}

export function parseCallbackQuery(search: string) {
  const params = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  return {
    code: params.get('code'),
    state: params.get('state'),
    error: params.get('error'),
    errorDescription: params.get('error_description'),
  };
}

function generateRandomString(byteLength: number): string {
  const bytes = new Uint8Array(byteLength);
  crypto.getRandomValues(bytes);
  return base64UrlEncode(bytes);
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) {
    binary += String.fromCharCode(b);
  }
  return btoa(binary).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

async function sha256(input: string): Promise<Uint8Array> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return new Uint8Array(digest);
}
