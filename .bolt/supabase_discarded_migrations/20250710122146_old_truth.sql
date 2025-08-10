/*
  # Create Profiles Table

  1. New Tables
    - `profiles`
      - `id` (uuid, primary key, references auth.users)
      - `full_name` (text, required)
      - `role` (user_role, default 'cashier')
      - `created_at` (timestamp)
      - `updated_at` (timestamp)

  2. Security
    - Enable RLS on `profiles` table
    - Add policies for user access control
    - Admins can view all profiles
    - Users can view/update their own profile
    - Admins can insert and update profiles
*/

CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  role user_role NOT NULL DEFAULT 'cashier',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Policies for profiles
CREATE POLICY "Users can view their own profile"
  ON profiles
  FOR SELECT
  TO public
  USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
  ON profiles
  FOR UPDATE
  TO public
  USING (auth.uid() = id);

CREATE POLICY "Admins can view all profiles"
  ON profiles
  FOR SELECT
  TO public
  USING (get_user_role(auth.uid()) = 'admin');

CREATE POLICY "Admins can update all profiles"
  ON profiles
  FOR UPDATE
  TO public
  USING (get_user_role(auth.uid()) = 'admin');

CREATE POLICY "Admins can insert profiles"
  ON profiles
  FOR INSERT
  TO public
  WITH CHECK (get_user_role(auth.uid()) = 'admin');