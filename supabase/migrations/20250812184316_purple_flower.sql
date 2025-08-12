/*
  # Create Auto-Confirmed Admin User (Safe Version)
  
  Creates an admin user with email demo2@gmail.com and password 111111
  that is automatically confirmed and ready to use.
  
  This version safely handles existing users and profiles.
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
    
    -- Update existing user to be confirmed and set password
    UPDATE auth.users 
    SET 
      email_confirmed_at = NOW(),
      confirmed_at = NOW(),
      encrypted_password = crypt('111111', gen_salt('bf')),
      updated_at = NOW()
    WHERE id = existing_user_id;
    
    -- Update or insert profile
    INSERT INTO public.profiles (
      id,
      full_name,
      role,
      created_at,
      updated_at
    ) VALUES (
      existing_user_id,
      'Admin User',
      'admin'::user_role,
      NOW(),
      NOW()
    )
    ON CONFLICT (id) 
    DO UPDATE SET 
      full_name = 'Admin User',
      role = 'admin'::user_role,
      updated_at = NOW();
    
    -- Update or insert identity
    INSERT INTO auth.identities (
      id,
      user_id,
      identity_data,
      provider,
      provider_id,
      last_sign_in_at,
      created_at,
      updated_at
    ) VALUES (
      gen_random_uuid(),
      existing_user_id,
      jsonb_build_object('sub', existing_user_id::text, 'email', 'demo2@gmail.com'),
      'email',
      existing_user_id::text,
      NOW(),
      NOW(),
      NOW()
    )
    ON CONFLICT (provider, provider_id) 
    DO UPDATE SET 
      identity_data = jsonb_build_object('sub', existing_user_id::text, 'email', 'demo2@gmail.com'),
      last_sign_in_at = NOW(),
      updated_at = NOW();
    
    RAISE NOTICE 'Updated existing user demo2@gmail.com to admin role';
    
  ELSE
    -- Create new user
    user_id := gen_random_uuid();
    
    -- Insert into auth.users
    INSERT INTO auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      confirmed_at,
      recovery_sent_at,
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
      email_change_token_new,
      email_change,
      email_change_sent_at,
      email_change_token_current,
      email_change_confirm_status,
      banned_until,
      reauthentication_token,
      reauthentication_sent_at,
      is_sso_user,
      deleted_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      user_id,
      'authenticated',
      'authenticated',
      'demo2@gmail.com',
      crypt('111111', gen_salt('bf')),
      NOW(),
      NOW(),
      NULL,
      NOW(),
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
      '',
      NULL,
      '',
      0,
      NULL,
      '',
      NULL,
      FALSE,
      NULL
    );

    -- Insert profile
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

    -- Insert identity
    INSERT INTO auth.identities (
      id,
      user_id,
      identity_data,
      provider,
      provider_id,
      last_sign_in_at,
      created_at,
      updated_at
    ) VALUES (
      gen_random_uuid(),
      user_id,
      jsonb_build_object('sub', user_id::text, 'email', 'demo2@gmail.com'),
      'email',
      user_id::text,
      NOW(),
      NOW(),
      NOW()
    );

    RAISE NOTICE 'Created new admin user demo2@gmail.com with ID: %', user_id;
  END IF;
END $$;

-- Verify the user was created/updated successfully
SELECT 
  u.id,
  u.email,
  u.email_confirmed_at IS NOT NULL as email_confirmed,
  p.full_name,
  p.role,
  i.provider
FROM auth.users u
LEFT JOIN public.profiles p ON u.id = p.id
LEFT JOIN auth.identities i ON u.id = i.user_id
WHERE u.email = 'demo2@gmail.com';

-- Show success message
SELECT 'Admin user demo2@gmail.com is ready to use!' as status;