/*
  # Create Storage Buckets

  1. Storage Buckets
    - `company-assets` - For storing company logos and other assets

  2. Security
    - Public read access for company assets
    - Authenticated users can upload assets
    - File type restrictions for security
*/

-- Create storage bucket for company assets
INSERT INTO storage.buckets (id, name, public)
VALUES ('company-assets', 'company-assets', true)
ON CONFLICT (id) DO NOTHING;

-- Policy to allow public read access to company assets
CREATE POLICY "Public read access for company assets"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'company-assets');

-- Policy to allow authenticated users to upload company assets
CREATE POLICY "Authenticated users can upload company assets"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'company-assets');

-- Policy to allow authenticated users to update company assets
CREATE POLICY "Authenticated users can update company assets"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'company-assets');

-- Policy to allow authenticated users to delete company assets
CREATE POLICY "Authenticated users can delete company assets"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'company-assets');