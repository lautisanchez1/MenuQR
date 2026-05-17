import { useState, useCallback, useEffect } from 'react';
import { jwtDecode } from 'jwt-decode';
import { authApi, type RegisterRequest, type LoginRequest } from '@/shared/api/authApi';

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

  const login = useCallback(async (data: LoginRequest) => {
    const response = await authApi.login(data);
    localStorage.setItem('md_token', response.token);
    setAuthState({
      token: response.token,
      tenantId: response.tenantId,
      restaurantName: response.restaurantName,
      isAuthenticated: true,
      federatedEmail: authState.federatedEmail,
    });
    return response;
  }, [authState.federatedEmail]);

  const register = useCallback(async (data: RegisterRequest) => {
    const response = await authApi.register(data);
    localStorage.setItem('md_token', response.token);
    setAuthState({
      token: response.token,
      tenantId: response.tenantId,
      restaurantName: response.restaurantName,
      isAuthenticated: true,
      federatedEmail: data.ownerEmail,
    });
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
    login,
    register,
    setFederatedEmail,
    clearFederatedEmail,
    logout,
  };
}
