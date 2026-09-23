import type { AuthError, Session, User } from '@supabase/supabase-js'
import { supabase } from './supabase'

export type AuthResult={error:string|null}
export const MIN_PASSWORD_LENGTH=10
const appUrl=(path:string)=>`${location.origin}${import.meta.env.BASE_URL}${path.replace(/^\//,'')}`

export function friendlyAuthError(error:unknown):string{
  const code=(error as AuthError|undefined)?.code
  if(code==='invalid_credentials') return 'E-mail nebo heslo není správné.'
  if(code==='email_not_confirmed') return 'Nejdřív potvrďte e-mail pomocí odkazu, který jsme vám poslali.'
  if(code==='user_already_exists'||code==='email_exists') return 'Účet s tímto e-mailem už existuje.'
  if(code==='weak_password') return `Heslo musí mít alespoň ${MIN_PASSWORD_LENGTH} znaků.`
  if(code==='over_request_rate_limit'||code==='over_email_send_rate_limit') return 'Zkuste to prosím znovu za chvíli.'
  if(code==='same_password') return 'Nové heslo musí být jiné než původní.'
  return 'Něco se nepodařilo. Zkontrolujte připojení a zkuste to znovu.'
}

export async function signUp(name:string,email:string,password:string):Promise<AuthResult>{
  if(password.length<MIN_PASSWORD_LENGTH)return{error:`Heslo musí mít alespoň ${MIN_PASSWORD_LENGTH} znaků.`}
  const {error}=await supabase.auth.signUp({email,password,options:{data:{display_name:name.trim()},emailRedirectTo:appUrl('/overeni')}})
  return{error:error?friendlyAuthError(error):null}
}
export async function signIn(email:string,password:string):Promise<AuthResult>{
  const {data,error}=await supabase.auth.signInWithPassword({email,password})
  if(error)return{error:friendlyAuthError(error)}
  if(!data.user?.email_confirmed_at){await supabase.auth.signOut();return{error:'Nejdřív potvrďte e-mail pomocí odkazu, který jsme vám poslali.'}}
  return{error:null}
}
export async function requestPasswordReset(email:string):Promise<AuthResult>{
  const {error}=await supabase.auth.resetPasswordForEmail(email,{redirectTo:appUrl('/nove-heslo')})
  return{error:error?friendlyAuthError(error):null}
}
export async function updatePassword(password:string):Promise<AuthResult>{
  if(password.length<MIN_PASSWORD_LENGTH)return{error:`Heslo musí mít alespoň ${MIN_PASSWORD_LENGTH} znaků.`}
  const {error}=await supabase.auth.updateUser({password});return{error:error?friendlyAuthError(error):null}
}
export async function signOut(){await supabase.auth.signOut({scope:'local'})}
export async function registerPasskey():Promise<AuthResult>{
  try{const {error}=await supabase.auth.registerPasskey();return{error:error?friendlyAuthError(error):null}}catch{return{error:'Rychlé přihlášení se nepodařilo zapnout. Můžete dál používat e-mail a heslo.'}}
}
export async function signInWithPasskey():Promise<AuthResult>{
  try{const {error}=await supabase.auth.signInWithPasskey();return{error:error?'Rychlé přihlášení se nepodařilo. Přihlaste se e-mailem a heslem.':null}}catch{return{error:'Rychlé přihlášení se nepodařilo. Přihlaste se e-mailem a heslem.'}}
}
export async function removePasskeys():Promise<AuthResult>{
  try{const {data,error}=await supabase.auth.passkey.list();if(error)return{error:friendlyAuthError(error)};for(const item of data??[]){const result=await supabase.auth.passkey.delete({passkeyId:item.id});if(result.error)return{error:friendlyAuthError(result.error)}}return{error:null}}catch{return{error:'Rychlé přihlášení se nepodařilo vypnout. Zkuste to znovu.'}}
}
export async function hasPasskey():Promise<boolean>{try{const {data}=await supabase.auth.passkey.list();return Boolean(data?.length)}catch{return false}}
export function subscribeAuth(callback:(session:Session|null,user:User|null)=>void){supabase.auth.getSession().then(({data})=>callback(data.session,data.session?.user??null));const {data}=supabase.auth.onAuthStateChange((_event,session)=>callback(session,session?.user??null));return()=>data.subscription.unsubscribe()}
