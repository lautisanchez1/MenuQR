import { useState, useEffect } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useAuth } from './useAuth';

const SESSION_KEY_ID_TOKEN = 'md_cognito_id_token';
const SESSION_KEY_ACCESS_TOKEN = 'md_cognito_access_token';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';
import { toast } from '@/hooks/use-toast';

const MAX_RESTAURANT_NAME_LENGTH = 255;
const MAX_SLUG_LENGTH = 100;
const MAX_EMAIL_LENGTH = 255;

export function RegisterPage() {
  const navigate = useNavigate();
  const { register, federatedEmail, clearFederatedEmail } = useAuth();
  const [formData, setFormData] = useState({
    restaurantName: '',
    slug: '',
  });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    // Without a Cognito ID token in sessionStorage we can't register — bounce to login.
    if (!sessionStorage.getItem(SESSION_KEY_ID_TOKEN)) {
      navigate('/login', { replace: true });
    }
  }, [navigate]);

  const generateSlug = (name: string) => {
    return name
      .toLowerCase()
      .replace(/[^a-z0-9\s-]/g, '')
      .replace(/\s+/g, '-')
      .substring(0, MAX_SLUG_LENGTH);
  };

  const handleNameChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const name = e.target.value;
    setFormData((prev) => ({
      ...prev,
      restaurantName: name,
      slug: generateSlug(name),
    }));
    setErrors(prev => {
      const { restaurantName, ...rest } = prev;
      return rest;
    });
  };

  const validate = (): boolean => {
    const newErrors: Record<string, string> = {};

    if (!formData.restaurantName.trim()) {
      newErrors.restaurantName = 'Restaurant name is required';
    } else if (formData.restaurantName.length > MAX_RESTAURANT_NAME_LENGTH) {
      newErrors.restaurantName = `Name must be ${MAX_RESTAURANT_NAME_LENGTH} characters or less`;
    }

    if (!formData.slug.trim()) {
      newErrors.slug = 'Menu URL is required';
    } else if (formData.slug.length > MAX_SLUG_LENGTH) {
      newErrors.slug = `URL must be ${MAX_SLUG_LENGTH} characters or less`;
    } else if (!/^[a-z0-9-]+$/.test(formData.slug)) {
      newErrors.slug = 'Only lowercase letters, numbers, and hyphens allowed';
    }

    if (!federatedEmail) {
      newErrors.ownerEmail = 'Please sign in with Google or Facebook first';
    } else if (federatedEmail.length > MAX_EMAIL_LENGTH) {
      newErrors.ownerEmail = `Email must be ${MAX_EMAIL_LENGTH} characters or less`;
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(federatedEmail)) {
      newErrors.ownerEmail = 'Cognito did not return a valid email address';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!validate()) return;

    setLoading(true);

    try {
      if (!federatedEmail) {
        throw new Error('Missing federated email');
      }
      const idToken = sessionStorage.getItem(SESSION_KEY_ID_TOKEN);
      const accessToken = sessionStorage.getItem(SESSION_KEY_ACCESS_TOKEN);
      if (!idToken || !accessToken) {
        navigate('/login', { replace: true });
        return;
      }

      await register({
        restaurantName: formData.restaurantName,
        slug: formData.slug,
      }, idToken, accessToken);
      sessionStorage.removeItem(SESSION_KEY_ID_TOKEN);
      sessionStorage.removeItem(SESSION_KEY_ACCESS_TOKEN);
      toast({ title: 'Welcome!', description: 'Your restaurant has been registered', variant: 'success' });
      clearFederatedEmail();
      navigate('/admin');
    } catch (err: unknown) {
      if (err && typeof err === 'object' && 'response' in err) {
        const axiosError = err as { response?: { status?: number; data?: { code?: string } } };
        const code = axiosError.response?.data?.code;
        if (code === 'INVALID_TOKEN' || axiosError.response?.status === 401) {
          sessionStorage.removeItem(SESSION_KEY_ID_TOKEN);
          sessionStorage.removeItem(SESSION_KEY_ACCESS_TOKEN);
          toast({ title: 'Session Expired', description: 'Please sign in again', variant: 'destructive' });
          navigate('/login', { replace: true });
        } else if (code === 'SLUG_EXISTS') {
          setErrors({ slug: 'This URL slug is already taken. Please choose another.' });
          toast({ title: 'Registration Failed', description: 'This URL slug is already taken', variant: 'destructive' });
        } else if (code === 'EMAIL_EXISTS') {
          setErrors({ ownerEmail: 'This email is already registered. Please sign in instead.' });
          toast({ title: 'Registration Failed', description: 'This email is already registered', variant: 'destructive' });
        } else {
          setErrors({ submit: 'Registration failed. Please try again.' });
          toast({ title: 'Registration Failed', description: 'Please try again', variant: 'destructive' });
        }
      } else {
        setErrors({ submit: 'Registration failed. Please try again.' });
        toast({ title: 'Registration Failed', description: 'Please try again', variant: 'destructive' });
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-background p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1">
          <CardTitle className="text-2xl font-bold text-center">Create Account</CardTitle>
          <CardDescription className="text-center">
            Complete your restaurant setup after federated sign-in
          </CardDescription>
        </CardHeader>
        <form onSubmit={handleSubmit}>
          <CardContent className="space-y-4">
            {errors.submit && (
              <div className="p-3 text-sm text-destructive bg-destructive/10 rounded-md">
                {errors.submit}
              </div>
            )}
            <div className="space-y-2">
              <Label htmlFor="email">Signed-in Email</Label>
              <Input
                id="email"
                type="email"
                value={federatedEmail || ''}
                readOnly
                disabled
                className={errors.ownerEmail ? 'border-destructive' : ''}
              />
              {errors.ownerEmail && (
                <p className="text-xs text-destructive">{errors.ownerEmail}</p>
              )}
            </div>
            <div className="space-y-2">
              <Label htmlFor="restaurantName">
                Restaurant Name * 
                <span className="text-muted-foreground text-xs ml-1">
                  ({formData.restaurantName.length}/{MAX_RESTAURANT_NAME_LENGTH})
                </span>
              </Label>
              <Input
                id="restaurantName"
                placeholder="La Trattoria"
                value={formData.restaurantName}
                onChange={handleNameChange}
                maxLength={MAX_RESTAURANT_NAME_LENGTH}
                className={errors.restaurantName ? 'border-destructive' : ''}
              />
              {errors.restaurantName && (
                <p className="text-xs text-destructive">{errors.restaurantName}</p>
              )}
            </div>
            <div className="space-y-2">
              <Label htmlFor="slug">
                Menu URL * 
                <span className="text-muted-foreground text-xs ml-1">
                  ({formData.slug.length}/{MAX_SLUG_LENGTH})
                </span>
              </Label>
              <div className="flex items-center">
                <span className="text-sm text-muted-foreground mr-2">menu/</span>
                <Input
                  id="slug"
                  placeholder="la-trattoria"
                  value={formData.slug}
                  onChange={(e) => {
                    setFormData((prev) => ({ ...prev, slug: e.target.value }));
                    setErrors(prev => {
                      const { slug, ...rest } = prev;
                      return rest;
                    });
                  }}
                  maxLength={MAX_SLUG_LENGTH}
                  pattern="^[a-z0-9-]+$"
                  className={errors.slug ? 'border-destructive' : ''}
                />
              </div>
              <p className="text-xs text-muted-foreground">
                Only lowercase letters, numbers, and hyphens
              </p>
              {errors.slug && <p className="text-xs text-destructive">{errors.slug}</p>}
            </div>
          </CardContent>
          <CardFooter className="flex flex-col space-y-4">
            <Button type="submit" className="w-full" disabled={loading}>
              {loading ? 'Creating account...' : 'Finish setup'}
            </Button>
            <p className="text-sm text-muted-foreground text-center">
              Need to sign in again?{' '}
              <Link to="/login" className="text-primary hover:underline">
                Choose a provider
              </Link>
            </p>
          </CardFooter>
        </form>
      </Card>
    </div>
  );
}
