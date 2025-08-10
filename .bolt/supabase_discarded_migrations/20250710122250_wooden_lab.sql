/*
  # Insert Default Data

  1. Default Settings
    - Store information settings
    - Receipt settings
    - Notification settings
    - Payment note settings

  2. Default Categories
    - General category for uncategorized products

  3. Security
    - Default data for application functionality
    - Can be customized by users later
*/

-- Insert default settings
INSERT INTO settings (key, value, description) VALUES
  ('store_name', 'Awanvisual Store', 'Name of the store'),
  ('store_address', 'Jl. Contoh No. 123, Jakarta', 'Store address'),
  ('store_phone', '+62 21 1234 5678', 'Store phone number'),
  ('store_email', 'info@awanvisual.com', 'Store email address'),
  ('store_website', 'www.awanvisual.com', 'Store website'),
  ('receipt_header', 'Terima kasih telah berbelanja!', 'Receipt header message'),
  ('receipt_footer', 'Barang yang sudah dibeli tidak dapat dikembalikan', 'Receipt footer message'),
  ('payment_note_line1', 'Transfer BCA: [amount]/AWANVISUAL', 'Payment note line 1'),
  ('payment_note_line2', 'No. Rekening: 1234567890', 'Payment note line 2'),
  ('low_stock_alerts', 'true', 'Enable low stock alerts'),
  ('daily_sales_summary', 'false', 'Enable daily sales summary'),
  ('low_stock_threshold', '10', 'Low stock threshold'),
  ('print_receipt_auto', 'true', 'Auto print receipt after sale')
ON CONFLICT (key) DO NOTHING;

-- Insert default category
INSERT INTO categories (name, description) VALUES
  ('General', 'General category for uncategorized products')
ON CONFLICT (name) DO NOTHING;