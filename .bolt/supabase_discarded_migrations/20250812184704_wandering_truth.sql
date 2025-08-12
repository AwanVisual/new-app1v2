/*
  # Create Admin User - Safe Version
  
  This creates an admin user that can login immediately without email confirmation.
  Email: demo2@gmail.com
  Password: 111111
  Role: admin
*/

DO $$
DECLARE
  user_id uuid;
  existing_user_id uuid;
BEGIN
  -- Check if user already exists
  SELECT id INTO existing_user_id 
  FROM auth.users 
  WHERE email = 'demo2@gmail.com';
  
  IF existing_user_id IS NOT NULL THEN
    RAISE NOTICE 'User demo2@gmail.com already exists with ID: %', existing_user_id;
    
    -- Update existing user to admin role
    INSERT INTO public.profiles (id, full_name, role, created_at, updated_at)
    VALUES (existing_user_id, 'Demo Admin', 'admin'::user_role, NOW(), NOW())
    ON CONFLICT (id) DO UPDATE SET 
      role = 'admin'::user_role,
      full_name = 'Demo Admin',
      updated_at = NOW();
      
    RAISE NOTICE 'Updated existing user to admin role';
    RETURN;
  END IF;
  
  -- Generate new UUID for user
  user_id := gen_random_uuid();
  
  -- Create user in auth.users with confirmed email
  INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    recovery_sent_at,
    last_sign_in_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    user_id,
    'authenticated',
    'authenticated',
    'demo2@gmail.com',
    crypt('111111', gen_salt('bf')),
    NOW(),
    NOW(),
    NOW(),
    '{"provider": "email", "providers": ["email"]}',
    '{"full_name": "Demo Admin"}',
    NOW(),
    NOW(),
    '',
    '',
    '',
    ''
  );
  
  -- Create identity record
  INSERT INTO auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    user_id,
    format('{"sub": "%s", "email": "%s"}', user_id::text, 'demo2@gmail.com')::jsonb,
    'email',
    NOW(),
    NOW(),
    NOW()
  );
  
  -- The profile will be created automatically by the trigger
  -- But let's ensure it has admin role
  UPDATE public.profiles 
  SET 
    role = 'admin'::user_role,
    full_name = 'Demo Admin'
  WHERE id = user_id;
  
  RAISE NOTICE 'Successfully created admin user: demo2@gmail.com with ID: %', user_id;
  RAISE NOTICE 'User can now login with password: 111111';
  
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Error creating user: %', SQLERRM;
    RAISE NOTICE 'This might be normal if user already exists';
END $$;

-- Verify the user was created
SELECT 
  u.email,
  u.email_confirmed_at IS NOT NULL as email_confirmed,
  p.full_name,
  p.role
FROM auth.users u
LEFT JOIN public.profiles p ON u.id = p.id
WHERE u.email = 'demo2@gmail.com';