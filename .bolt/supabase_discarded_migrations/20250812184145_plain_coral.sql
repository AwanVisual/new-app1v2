/*
  # Create Auto-Confirmed Admin User

  This script creates a pre-confirmed admin user for immediate access to the system.
  
  User Details:
  - Email: demo2@gmail.com
  - Password: 111111
  - Role: admin
  - Status: email_confirmed = true
  
  This user can immediately login without email verification.
*/

-- Create the user in auth.users table with confirmed email
INSERT INTO auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  invited_at,
  confirmation_token,
  confirmation_sent_at,
  recovery_token,
  recovery_sent_at,
  email_change_token_new,
  email_change,
  email_change_sent_at,
  last_sign_in_at,
  raw_app_meta_data,
  raw_user_meta_data,
  is_super_admin,
  created_at,
  updated_at,
  phone,
  phone_confirmed_at,
  phone_change,
  phone_change_token,
  phone_change_sent_at,
  email_change_token_current,
  email_change_confirm_status,
  banned_until,
  reauthentication_token,
  reauthentication_sent_at,
  is_sso_user,
  deleted_at,
  is_anonymous
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  gen_random_uuid(),
  'authenticated',
  'authenticated',
  'demo2@gmail.com',
  crypt('111111', gen_salt('bf')), -- Encrypted password
  NOW(), -- Email confirmed immediately
  NOW(),
  '',
  NOW(),
  '',
  NULL,
  '',
  '',
  NULL,
  NULL,
  '{"provider": "email", "providers": ["email"]}',
  '{"full_name": "Admin User"}',
  FALSE,
  NOW(),
  NOW(),
  NULL,
  NULL,
  '',
  '',
  NULL,
  '',
  0,
  NULL,
  '',
  NULL,
  FALSE,
  NULL,
  FALSE
);

-- Get the user ID for the profile creation
DO $$
DECLARE
  user_id UUID;
BEGIN
  -- Get the user ID we just created
  SELECT id INTO user_id 
  FROM auth.users 
  WHERE email = 'demo2@gmail.com';
  
  -- Create the profile with admin role
  INSERT INTO public.profiles (
    id,
    full_name,
    role,
    created_at,
    updated_at
  ) VALUES (
    user_id,
    'Admin User',
    'admin'::user_role,
    NOW(),
    NOW()
  );
  
  -- Create identity record for email provider
  INSERT INTO auth.identities (
    provider_id,
    user_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at,
    id
  ) VALUES (
    'demo2@gmail.com',
    user_id,
    format('{"sub": "%s", "email": "%s", "email_verified": %s, "phone_verified": %s}', user_id::text, 'demo2@gmail.com', 'true', 'false')::jsonb,
    'email',
    NOW(),
    NOW(),
    NOW(),
    gen_random_uuid()
  );
  
  RAISE NOTICE 'Admin user created successfully!';
  RAISE NOTICE 'Email: demo2@gmail.com';
  RAISE NOTICE 'Password: 111111';
  RAISE NOTICE 'Role: admin';
  RAISE NOTICE 'Status: Email confirmed - ready to login';
END $$;

-- Verify the user was created correctly
SELECT 
  u.email,
  u.email_confirmed_at IS NOT NULL as email_confirmed,
  p.full_name,
  p.role,
  p.created_at
FROM auth.users u
LEFT JOIN public.profiles p ON u.id = p.id
WHERE u.email = 'demo2@gmail.com';