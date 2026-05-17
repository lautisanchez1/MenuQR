import { apiClient } from './client';
import type { AuthResponse } from '../types';

export interface RegisterRequest {
  restaurantName: string;
  slug: string;
}

function bearerHeader(idToken: string) {
  return { headers: { Authorization: `Bearer ${idToken}` } };
}

export const authApi = {
  register: async (data: RegisterRequest, idToken: string): Promise<AuthResponse> => {
    const response = await apiClient.post<AuthResponse>('/api/auth/register', data, bearerHeader(idToken));
    return response.data;
  },

  login: async (idToken: string): Promise<AuthResponse> => {
    const response = await apiClient.post<AuthResponse>('/api/auth/login', null, bearerHeader(idToken));
    return response.data;
  },
};
