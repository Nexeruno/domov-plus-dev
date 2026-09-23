import { createClient } from '@supabase/supabase-js'

const url=import.meta.env.VITE_SUPABASE_URL
const key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY
export const isConfigured=Boolean(url&&key&&!url.includes('YOUR_PROJECT'))
export const supabase=createClient(url||'https://placeholder.invalid',key||'placeholder',{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true,flowType:'pkce',experimental:{passkey:true}}})
