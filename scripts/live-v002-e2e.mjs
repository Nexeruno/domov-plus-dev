import {createClient} from '@supabase/supabase-js'

const url=process.env.VITE_SUPABASE_URL
const key=process.env.VITE_SUPABASE_PUBLISHABLE_KEY
const emailA=process.env.E2E_EMAIL_A
const emailB=process.env.E2E_EMAIL_B
const passwordA=process.env.E2E_PASSWORD_A
const passwordB=process.env.E2E_PASSWORD_B

if(!url||!key||!emailA||!emailB||!passwordA||!passwordB) throw new Error('Chybí E2E konfigurace')

const makeClient=()=>createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}})
const a=makeClient()
const b=makeClient()
const checks=[]
const ok=(name,condition,details='')=>{
  if(!condition) throw new Error(`FAILED: ${name}${details?` – ${details}`:''}`)
  checks.push(name)
}
const mustFail=async(name,operation,expected)=>{
  const result=await operation()
  const message=result?.error?.message??''
  ok(name,Boolean(result?.error)&&(!expected||message.includes(expected)),message)
}

const loginA=await a.auth.signInWithPassword({email:emailA,password:passwordA})
const loginB=await b.auth.signInWithPassword({email:emailB,password:passwordB})
ok('živé přihlášení User A',!loginA.error,loginA.error?.message)
ok('živé přihlášení User B',!loginB.error,loginB.error?.message)
await a.auth.updateUser({data:{display_name:'Test A'}})
await b.auth.updateUser({data:{display_name:'Test B'}})

const suffix=new Date().toISOString().replace(/\D/g,'').slice(0,14)
const createdA=await a.rpc('create_household',{p_name:`E2E A ${suffix}`})
const createdB=await b.rpc('create_household',{p_name:`E2E B ${suffix}`})
ok('User A vytvoří Household A',!createdA.error&&Boolean(createdA.data),createdA.error?.message)
ok('User B vytvoří Household B',!createdB.error&&Boolean(createdB.data),createdB.error?.message)
const householdA=createdA.data
const householdB=createdB.data

const ownA=await a.from('households').select('id,name').eq('id',householdA)
const foreignA=await a.from('households').select('id,name').eq('id',householdB)
const ownB=await b.from('households').select('id,name').eq('id',householdB)
const foreignB=await b.from('households').select('id,name').eq('id',householdA)
ok('API A čte Household A',!ownA.error&&ownA.data.length===1)
ok('API A nečte Household B',!foreignA.error&&foreignA.data.length===0)
ok('API B čte Household B',!ownB.error&&ownB.data.length===1)
ok('API B nečte Household A',!foreignB.error&&foreignB.data.length===0)

await mustFail('API A nepřejmenuje Household B',()=>a.rpc('rename_household',{p_household_id:householdB,p_name:'Útok A'}),'not_household_owner')
await mustFail('API B nepřejmenuje Household A',()=>b.rpc('rename_household',{p_household_id:householdA,p_name:'Útok B'}),'not_household_owner')

const foreignMembersA=await a.from('household_memberships').select('*').eq('household_id',householdB)
const foreignMembersB=await b.from('household_memberships').select('*').eq('household_id',householdA)
const foreignInvitesA=await a.from('household_invitations').select('*').eq('household_id',householdB)
const foreignInvitesB=await b.from('household_invitations').select('*').eq('household_id',householdA)
ok('API A nečte membership Household B',!foreignMembersA.error&&foreignMembersA.data.length===0)
ok('API B nečte membership Household A',!foreignMembersB.error&&foreignMembersB.data.length===0)
ok('API A nečte pozvánky Household B',!foreignInvitesA.error&&foreignInvitesA.data.length===0)
ok('API B nečte pozvánky Household A',!foreignInvitesB.error&&foreignInvitesB.data.length===0)

const userA=loginA.data.user.id
const userB=loginB.data.user.id
await mustFail('API A nevloží membership do Household B',()=>a.from('household_memberships').insert({household_id:householdB,user_id:userA,role:'owner'}))
await mustFail('API B nevloží membership do Household A',()=>b.from('household_memberships').insert({household_id:householdA,user_id:userB,role:'owner'}))
await mustFail('API A nezmění cizí membership',()=>a.from('household_memberships').update({role:'owner'}).eq('household_id',householdB).eq('user_id',userB))
await mustFail('API B nezmění cizí membership',()=>b.from('household_memberships').update({role:'owner'}).eq('household_id',householdA).eq('user_id',userA))
await mustFail('API A nevytvoří pozvánku v Household B',()=>a.rpc('create_household_invitation',{p_household_id:householdB,p_email:emailA}),'not_household_owner')
await mustFail('API B nevytvoří pozvánku v Household A',()=>b.rpc('create_household_invitation',{p_household_id:householdA,p_email:emailB}),'not_household_owner')

const renamed=await a.rpc('rename_household',{p_household_id:householdA,p_name:`E2E společná ${suffix}`})
ok('User A přejmenuje vlastní domácnost',!renamed.error,renamed.error?.message)

const invitation=await a.rpc('create_household_invitation',{p_household_id:householdA,p_email:emailB})
ok('User A vytvoří pozvánku pro User B',!invitation.error&&invitation.data?.length===1,invitation.error?.message)
const token=invitation.data[0].invitation_token
const invitationId=invitation.data[0].invitation_id

const preview=await b.rpc('get_invitation_preview',{p_token:token})
ok('User B načte platnou pozvánku',!preview.error&&preview.data?.[0]?.target_email===emailB,preview.error?.message)

const accepted=await b.rpc('respond_to_household_invitation',{p_token:token,p_accept:true})
ok('User B přijme pozvánku',!accepted.error&&accepted.data===householdA,accepted.error?.message)

const householdForA=await a.from('households').select('id,name').eq('id',householdA).single()
const householdForB=await b.from('households').select('id,name').eq('id',householdA).single()
const membersForA=await a.from('household_memberships').select('user_id,role').eq('household_id',householdA)
const membersForB=await b.from('household_memberships').select('user_id,role').eq('household_id',householdA)
ok('oba vidí stejnou domácnost',!householdForA.error&&!householdForB.error&&householdForA.data.id===householdForB.data.id)
ok('oba vidí oba členy',!membersForA.error&&!membersForB.error&&membersForA.data.length===2&&membersForB.data.length===2)
ok('oba členové mají roli owner',membersForA.data.every(member=>member.role==='owner'))
ok('nevzniklo duplicitní membership',new Set(membersForA.data.map(member=>member.user_id)).size===2)

const storedInvite=await a.from('household_invitations').select('status,responded_at').eq('id',invitationId).single()
ok('pozvánka je accepted a použitá',!storedInvite.error&&storedInvite.data.status==='accepted'&&Boolean(storedInvite.data.responded_at))
await mustFail('accepted pozvánku nelze použít znovu',()=>b.rpc('respond_to_household_invitation',{p_token:token,p_accept:true}),'invitation_not_pending')

const audit=await a.from('household_audit_log').select('event_type,actor_user_id').eq('household_id',householdA)
const auditTypes=new Set(audit.data?.map(row=>row.event_type))
ok('živý audit obsahuje vytvoření, přejmenování, pozvání a přijetí',!audit.error&&['household_created','household_name_changed','invitation_created','invitation_accepted'].every(type=>auditTypes.has(type)))

console.log(JSON.stringify({passed:checks.length,checks,householdA,householdB,invitationStatus:storedInvite.data.status},null,2))
