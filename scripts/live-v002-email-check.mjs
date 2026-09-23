import {createClient} from '@supabase/supabase-js'

const client=createClient(process.env.VITE_SUPABASE_URL,process.env.VITE_SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}})
const email=process.env.E2E_EMAIL
const password=process.env.E2E_PASSWORD
const target=process.env.E2E_TARGET_EMAIL
const householdId=process.env.E2E_HOUSEHOLD_ID

const login=await client.auth.signInWithPassword({email,password})
if(login.error)throw login.error
const sent=await client.functions.invoke('send-household-invitation',{body:{householdId,email:target,appUrl:'https://nexeruno.github.io/domov-plus-dev/'}})
if(sent.error){
  const detail=sent.error.context ? await sent.error.context.clone().text() : sent.error.message
  throw new Error(`Edge Function: ${detail}`)
}
const pending=await client.from('household_invitations').select('id,status,target_email').eq('household_id',householdId).eq('target_email',target).eq('status','pending')
if(pending.error||pending.data.length!==1)throw new Error(pending.error?.message??`Očekávána jedna pozvánka, nalezeno ${pending.data?.length}`)
console.log(JSON.stringify({edgeFunction:true,brevoAccepted:true,pendingInvitations:pending.data.length,status:pending.data[0].status},null,2))
