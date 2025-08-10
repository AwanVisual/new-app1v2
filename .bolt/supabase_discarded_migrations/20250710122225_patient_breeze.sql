/*
  # Create Settings Table

  1. New Tables
    - `settings`
      - `id` (uuid, primary key)
      - `key` (text, unique, required)
      - `value` (text, optional)
      - `description` (text, optional)
      - `updated_at` (timestamp)
      - `updated_by` (uuid, references auth.users)

  2. Security
    - Enable RLS on `settings` table
    - All authenticated users can view settings
    - Admins can manage settings
*/

CREATE TABLE IF NOT EXISTS settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text UNIQUE NOT NULL,
  value text,
  description text,
  updated_at timestamptz DEFAULT now(),
  updated_by uuid REFERENCES auth.users(id)
);

ALTER TABLE settings ENABLE ROW LEVEL SECURITY;

-- Policies for settings
CREATE POLICY "All authenticated users can view settings"
  ON settings
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admins can manage settings"
  ON settings
  FOR ALL
  TO public
  USING (get_user_role(auth.uid()) = 'admin');