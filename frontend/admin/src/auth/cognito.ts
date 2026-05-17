import {
  signIn as amplifySignIn,
  signUp as amplifySignUp,
  confirmSignUp as amplifyConfirmSignUp,
  resendSignUpCode as amplifyResendSignUpCode,
  signInWithRedirect,
  resetPassword,
  confirmResetPassword,
  signOut as amplifySignOut,
  fetchAuthSession,
  autoSignIn,
} from 'aws-amplify/auth';
import { isAmplifyAuthConfigured } from './amplifyConfig';

export type SocialProvider = 'Google' | 'Facebook';

// Comma-separated list of federated providers the deploy has wired up at the
// Cognito side. Empty (the default) means native email/password only.
export const socialProviders: SocialProvider[] = (import.meta.env.VITE_COGNITO_ENABLED_PROVIDERS || '')
  .split(',')
  .map((s: string) => s.trim())
  .filter((s: string): s is SocialProvider => s === 'Google' || s === 'Facebook');

export interface CognitoTokens {
  idToken: string;
  accessToken: string;
}

export function canUseCognitoAuth() {
  return isAmplifyAuthConfigured();
}

export async function signInWithEmail(email: string, password: string) {
  return amplifySignIn({
    username: email,
    password,
    options: { authFlowType: 'USER_SRP_AUTH' },
  });
}

export async function signUpWithEmail(email: string, password: string) {
  return amplifySignUp({
    username: email,
    password,
    options: {
      userAttributes: { email },
      autoSignIn: true,
    },
  });
}

export async function confirmSignUpCode(email: string, code: string) {
  const result = await amplifyConfirmSignUp({ username: email, confirmationCode: code });
  // autoSignIn was enabled at signUp; promote the session now that the
  // account is confirmed. Throws if the auto sign-in window has lapsed —
  // callers should fall back to /login in that case.
  if (result.isSignUpComplete) {
    try {
      await autoSignIn();
    } catch {
      // Auto sign-in failed; user will sign in manually.
    }
  }
  return result;
}

export async function resendConfirmationCode(email: string) {
  return amplifyResendSignUpCode({ username: email });
}

export async function requestPasswordReset(email: string) {
  return resetPassword({ username: email });
}

export async function confirmPasswordReset(email: string, code: string, newPassword: string) {
  return confirmResetPassword({ username: email, confirmationCode: code, newPassword });
}

export async function startFederatedSignIn(provider: SocialProvider) {
  return signInWithRedirect({ provider });
}

export async function getCurrentTokens(): Promise<CognitoTokens | null> {
  try {
    const session = await fetchAuthSession();
    const idToken = session.tokens?.idToken?.toString();
    const accessToken = session.tokens?.accessToken?.toString();
    if (!idToken || !accessToken) return null;
    return { idToken, accessToken };
  } catch {
    return null;
  }
}

export async function signOutEverywhere() {
  await amplifySignOut();
}
