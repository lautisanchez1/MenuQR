import { useState, useCallback, useEffect } from 'react';
import { jwtDecode } from 'jwt-decode';
import { authApi, type RegisterRequest } from '@/shared/api/authApi';
import { buildHostedUiLogoutUrl } from './cognito';

interface JwtPayload {
  sub: string;
  tenantId: string;
  restaurantName: string;
  exp: number;
}

interface AuthState {
  token: string | null;
  tenantId: string | null;
  restaurantName: string | null;
  isAuthenticated: boolean;
  federatedEmail: string | null;
}

export function useAuth() {
  const [authState, setAuthState] = useState<AuthState>(() => {
    const token = localStorage.getItem('md_token');
    const federatedEmail = localStorage.getItem('md_federated_email');
    if (token) {
      try {
        const decoded = jwtDecode<JwtPayload>(token);
        if (decoded.exp * 1000 > Date.now()) {
          return {
            token,
            tenantId: decoded.tenantId,
            restaurantName: decoded.restaurantName,
            isAuthenticated: true,
            federatedEmail,
          };
        }
      } catch {
        localStorage.removeItem('md_token');
      }
    }
    return {
      token: null,
      tenantId: null,
      restaurantName: null,
      isAuthenticated: false,
      federatedEmail,
    };
  });

  const register = useCallback(async (data: RegisterRequest, idToken: string) => {
    const response = await authApi.register(data, idToken);
    localStorage.setItem('md_token', response.token);
    setAuthState((current) => ({
      token: response.token,
      tenantId: response.tenantId,
      restaurantName: response.restaurantName,
      isAuthenticated: true,
      federatedEmail: current.federatedEmail,
    }));
    return response;
  }, []);

  const setFederatedEmail = useCallback((email: string) => {
    localStorage.setItem('md_federated_email', email);
    setAuthState((current) => ({
      ...current,
      federatedEmail: email,
    }));
  }, []);

  const clearFederatedEmail = useCallback(() => {
    localStorage.removeItem('md_federated_email');
    setAuthState((current) => ({
      ...current,
      federatedEmail: null,
    }));
  }, []);

  const logout = useCallback(() => {
    localStorage.removeItem('md_token');
    localStorage.removeItem('md_federated_email');
    setAuthState({
      token: null,
      tenantId: null,
      restaurantName: null,
      isAuthenticated: false,
      federatedEmail: null,
    });

    // End the Cognito hosted-UI session too, otherwise the next "Continue with Google"
    // click silently re-authenticates against the still-active IdP session.
    const cognitoLogoutUrl = buildHostedUiLogoutUrl();
    if (cognitoLogoutUrl) {
      window.location.assign(cognitoLogoutUrl);
    }
  }, []);

  useEffect(() => {
    const checkTokenExpiry = () => {
      const token = localStorage.getItem('md_token');
      if (token) {
        try {
          const decoded = jwtDecode<JwtPayload>(token);
          if (decoded.exp * 1000 <= Date.now()) {
            logout();
          }
        } catch {
          logout();
        }
      }
    };

    const interval = setInterval(checkTokenExpiry, 60000);
    return () => clearInterval(interval);
  }, [logout]);

  return {
    ...authState,
    register,
    setFederatedEmail,
    clearFederatedEmail,
    logout,
  };
}
