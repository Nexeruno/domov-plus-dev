import { createClient } from 'npm:@supabase/supabase-js@2.116.0'

const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'}
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}})

Deno.serve(async(req)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors})
  if(req.method!=='POST')return json({error:'method_not_allowed'},405)
  const auth=req.headers.get('Authorization')
  if(!auth?.startsWith('Bearer '))return json({error:'authentication_required'},401)

  const supabase=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{
    global:{headers:{Authorization:auth}},auth:{persistSession:false}
  })
  const {data:userData,error:userError}=await supabase.auth.getUser(auth.slice(7))
  if(userError||!userData.user)return json({error:'authentication_required'},401)

  let input:{householdId?:string;email?:string;appUrl?:string}
  try{input=await req.json()}catch{return json({error:'invalid_request'},400)}
  const email=String(input.email||'').trim().toLowerCase()
  const householdId=String(input.householdId||'')
  const appUrl=String(input.appUrl||'')
  if(!/^https:\/\/nexeruno\.github\.io\/domov-plus-dev\/?$/.test(appUrl))return json({error:'invalid_app_url'},400)

  const {data,error}=await supabase.rpc('create_household_invitation',{p_household_id:householdId,p_email:email})
  if(error)return json({error:error.message},400)
  const invitation=Array.isArray(data)?data[0]:data
  if(!invitation)return json({error:'invitation_creation_failed'},500)

  const brevoKey=Deno.env.get('BREVO_API_KEY')
  const senderEmail=Deno.env.get('INVITATION_SENDER_EMAIL')
  if(!brevoKey||!senderEmail)return json({error:'email_not_configured'},500)
  const inviteUrl=`${appUrl.replace(/\/$/,'')}/pozvanka?token=${encodeURIComponent(invitation.invitation_token)}`
  const response=await fetch('https://api.brevo.com/v3/smtp/email',{
    method:'POST',headers:{'Content-Type':'application/json','api-key':brevoKey},
    body:JSON.stringify({
      sender:{name:'Domov+',email:senderEmail},to:[{email}],
      subject:`Pozvánka do domácnosti ${invitation.household_name}`,
      htmlContent:`<p>${escapeHtml(invitation.inviter_name)} vás zve do domácnosti <strong>${escapeHtml(invitation.household_name)}</strong> v aplikaci Domov+.</p><p><a href="${inviteUrl}" style="display:inline-block;padding:14px 20px;background:#126454;color:#fff;text-decoration:none;border-radius:10px;font-weight:700">Přijmout pozvánku</a></p><p>Platnost pozvánky je 7 dní.</p>`
    })
  })
  if(!response.ok){
    await supabase.rpc('cancel_household_invitation',{p_invitation_id:invitation.invitation_id})
    return json({error:'email_delivery_failed'},502)
  }
  return json({ok:true})
})

function escapeHtml(value:string){return value.replace(/[&<>'"]/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[char]!))}
