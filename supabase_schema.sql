-- ==========================================
-- SUPABASE DATABASE SCHEMA & POLICIES
-- Run this in the Supabase SQL Editor (https://supabase.com/dashboard/project/moofmgwxpecmtxicbceq/sql)
-- ==========================================

-- 1. Create Users Table
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('producer', 'consumer')),
  first_name TEXT,
  last_name TEXT,
  company_name TEXT,
  state TEXT,
  district TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on users
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Policies for users
CREATE POLICY "Allow public read access to users"
  ON public.users FOR SELECT TO authenticated USING (true);

CREATE POLICY "Users can insert own profile"
  ON public.users FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile"
  ON public.users FOR UPDATE TO authenticated USING (auth.uid() = id);


-- 2. Create Consumer Profiles Table
CREATE TABLE IF NOT EXISTS public.consumer_profiles (
  id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  company_name TEXT,
  phone TEXT,
  address TEXT,
  state TEXT,
  district TEXT,
  email TEXT,
  profile_image TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on consumer_profiles
ALTER TABLE public.consumer_profiles ENABLE ROW LEVEL SECURITY;

-- Policies for consumer_profiles
CREATE POLICY "Allow read access to consumer profiles"
  ON public.consumer_profiles FOR SELECT TO authenticated USING (true);

CREATE POLICY "Users can insert own consumer profile"
  ON public.consumer_profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own consumer profile"
  ON public.consumer_profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);


-- 3. Create Producer Profiles Table
CREATE TABLE IF NOT EXISTS public.producer_profiles (
  id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  company_name TEXT,
  phone TEXT,
  address TEXT,
  email TEXT,
  profile_image TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on producer_profiles
ALTER TABLE public.producer_profiles ENABLE ROW LEVEL SECURITY;

-- Policies for producer_profiles
CREATE POLICY "Allow read access to producer profiles"
  ON public.producer_profiles FOR SELECT TO authenticated USING (true);

CREATE POLICY "Users can insert own producer profile"
  ON public.producer_profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own producer profile"
  ON public.producer_profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);


-- 4. Trigger to automatically create Consumer/Producer profiles when a user is registered
CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.role = 'consumer' THEN
    INSERT INTO public.consumer_profiles (id, email, company_name)
    VALUES (NEW.id, NEW.email, COALESCE(NEW.company_name, NEW.first_name || ' ' || NEW.last_name))
    ON CONFLICT (id) DO NOTHING;
  ELSIF NEW.role = 'producer' THEN
    INSERT INTO public.producer_profiles (id, email, company_name)
    VALUES (NEW.id, NEW.email, COALESCE(NEW.company_name, NEW.first_name || ' ' || NEW.last_name))
    ON CONFLICT (id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_user_created
  AFTER INSERT ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();


-- 5. Create Products Table
CREATE TABLE IF NOT EXISTS public.products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  producer_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  price NUMERIC NOT NULL,
  quantity NUMERIC NOT NULL,
  description TEXT,
  address TEXT,
  district TEXT,
  state TEXT,
  image_urls TEXT[],
  status TEXT DEFAULT 'available',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on products
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- Policies for products
CREATE POLICY "Allow read access to products"
  ON public.products FOR SELECT TO authenticated USING (true);

CREATE POLICY "Producers can insert their own products"
  ON public.products FOR INSERT TO authenticated WITH CHECK (auth.uid() = producer_id);

CREATE POLICY "Producers can update their own products"
  ON public.products FOR UPDATE TO authenticated USING (auth.uid() = producer_id) WITH CHECK (auth.uid() = producer_id);

CREATE POLICY "Producers can delete their own products"
  ON public.products FOR DELETE TO authenticated USING (auth.uid() = producer_id);


-- 6. Create Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  producer_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  buyer_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  quantity NUMERIC NOT NULL,
  total_price NUMERIC NOT NULL,
  total_amount NUMERIC NOT NULL, -- Included to support profile page queries
  buyer_name TEXT,
  buyer_company TEXT,
  status TEXT DEFAULT 'Pending',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Trigger to automatically populate total_amount from total_price on insert/update
CREATE OR REPLACE FUNCTION public.sync_order_amounts()
RETURNS TRIGGER AS $$
BEGIN
  NEW.total_amount := NEW.total_price;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER on_order_amount_sync
  BEFORE INSERT OR UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.sync_order_amounts();

-- Enable RLS on orders
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Policies for orders
CREATE POLICY "Users can view their own orders (buyer or producer)"
  ON public.orders FOR SELECT TO authenticated
  USING (auth.uid() = buyer_id OR auth.uid() = producer_id);

CREATE POLICY "Buyers can insert orders"
  ON public.orders FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = buyer_id);

CREATE POLICY "Users can update their own orders (buyer or producer)"
  ON public.orders FOR UPDATE TO authenticated
  USING (auth.uid() = buyer_id OR auth.uid() = producer_id);


-- 7. Create Messages Table
CREATE TABLE IF NOT EXISTS public.messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  is_read BOOLEAN DEFAULT FALSE
);

-- Enable RLS on messages
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Policies for messages
CREATE POLICY "Users can view messages they sent or received"
  ON public.messages FOR SELECT TO authenticated
  USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

CREATE POLICY "Users can send messages"
  ON public.messages FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Users can update their received messages"
  ON public.messages FOR UPDATE TO authenticated
  USING (auth.uid() = receiver_id);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_messages_sender ON public.messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_receiver ON public.messages(receiver_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON public.messages(created_at);


-- 8. Create Producer Analytics View
CREATE OR REPLACE VIEW public.producer_analytics AS
SELECT 
  u.id AS producer_id,
  COALESCE(SUM(CASE WHEN o.status = 'Completed' THEN o.total_price ELSE 0 END), 0) AS total_revenue,
  COALESCE(COUNT(DISTINCT CASE WHEN p.status = 'available' OR p.status IS NULL THEN p.id END), 0) AS active_listings,
  COALESCE(SUM(CASE WHEN o.status = 'Completed' THEN o.quantity ELSE 0 END), 0) AS total_sold
FROM 
  public.users u
LEFT JOIN 
  public.products p ON p.producer_id = u.id
LEFT JOIN 
  public.orders o ON o.producer_id = u.id
WHERE 
  u.role = 'producer'
GROUP BY 
  u.id;


-- 9. Storage Buckets (Optional but recommended)
-- Run these queries to register public image buckets in your Supabase project

INSERT INTO storage.buckets (id, name, public)
VALUES ('profile-images', 'profile-images', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('product-images', 'product-images', true)
ON CONFLICT (id) DO NOTHING;

-- RLS Policies for Storage
CREATE POLICY "Allow public read of profile images" ON storage.objects FOR SELECT TO public USING (bucket_id = 'profile-images');
CREATE POLICY "Allow auth uploads of profile images" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'profile-images');
CREATE POLICY "Allow auth updates of profile images" ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'profile-images');

CREATE POLICY "Allow public read of product images" ON storage.objects FOR SELECT TO public USING (bucket_id = 'product-images');
CREATE POLICY "Allow auth uploads of product images" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'product-images');
CREATE POLICY "Allow auth updates of product images" ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'product-images');
