import { apiClient } from './client';
import type { AuthResponse } from '../types';

export interface RegisterRequest {
  restaurantName: string;
  slug: string;
  ownerEmail: string;
}

export interface LoginRequest {
  email: string;
}

export const authApi = {
  register: async (data: RegisterRequest): Promise<AuthResponse> => {
    const response = await apiClient.post<AuthResponse>('/api/auth/register', data);
    return response.data;
  },

  login: async (data: LoginRequest): Promise<AuthResponse> => {
    const response = await apiClient.post<AuthResponse>('/api/auth/login', data);
    return response.data;
  },
};
