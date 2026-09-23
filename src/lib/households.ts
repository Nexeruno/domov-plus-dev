import { supabase } from './supabase'

export type Household={id:string;name:string;timezone:string}
export type HouseholdMember={user_id:string;role:'owner'|'member';profiles:{display_name:string}|null}
export type HouseholdInvitation={id:string;target_email:string;status:string;created_at:string;expires_at:string}
export type HouseholdData={household:Household;members:HouseholdMember[];invitations:HouseholdInvitation[]}|null
export type InvitationPreview={household_name:string;inviter_name:string;target_email:string;invitation_status:string;expires_at:string}
export type Result<T=void>={data:T|null;error:string|null}

export function friendlyHouseholdError(error:unknown):string{
  const raw=String((error as {message?:string})?.message||'')
  if(raw.includes('active_invitation_exists'))return 'Na tento e-mail už čeká platná pozvánka.'
  if(raw.includes('already_household_member'))return 'Tento člověk už je členem domácnosti.'
  if(raw.includes('invitation_email_mismatch'))return 'Tato pozvánka patří jinému e-mailu.'
  if(raw.includes('invitation_expired'))return 'Platnost pozvánky už skončila.'
  if(raw.includes('invitation_not_pending'))return 'Tato pozvánka už byla vyřízena.'
  if(raw.includes('invitation_not_found'))return 'Pozvánku se nepodařilo najít.'
  if(raw.includes('invalid_email'))return 'Zadejte platnou e-mailovou adresu.'
  if(raw.includes('invalid_household_name'))return 'Název domácnosti musí mít 1 až 80 znaků.'
  if(raw.includes('not_household_owner'))return 'Tuto změnu může provést pouze vlastník domácnosti.'
  return 'Něco se nepodařilo. Zkuste to prosím znovu.'
}

export async function loadHousehold():Promise<Result<HouseholdData>>{
  const {data:{user},error:userError}=await supabase.auth.getUser()
  if(userError||!user)return{data:null,error:'Domácnost se nepodařilo načíst.'}
  const {data:profile,error:profileError}=await supabase.from('profiles').select('current_household_id').eq('id',user.id).single()
  if(profileError)return{data:null,error:friendlyHouseholdError(profileError)}
  if(!profile.current_household_id)return{data:null,error:null}
  const id=profile.current_household_id
  const [household,members,invitations]=await Promise.all([
    supabase.from('households').select('id,name,timezone').eq('id',id).single(),
    supabase.from('household_memberships').select('user_id,role,profiles(display_name)').eq('household_id',id).order('created_at'),
    supabase.from('household_invitations').select('id,target_email,status,created_at,expires_at').eq('household_id',id).eq('status','pending').order('created_at',{ascending:false})
  ])
  const error=household.error||members.error||invitations.error
  if(error)return{data:null,error:friendlyHouseholdError(error)}
  return{data:{household:household.data as Household,members:(members.data||[]) as unknown as HouseholdMember[],invitations:(invitations.data||[]) as HouseholdInvitation[]},error:null}
}

export async function createHousehold(name:string):Promise<Result<string>>{
  const {data,error}=await supabase.rpc('create_household',{p_name:name})
  return{data:error?null:data as string,error:error?friendlyHouseholdError(error):null}
}

export async function renameHousehold(householdId:string,name:string):Promise<Result>{
  const {error}=await supabase.rpc('rename_household',{p_household_id:householdId,p_name:name})
  return{data:null,error:error?friendlyHouseholdError(error):null}
}

export async function sendInvitation(householdId:string,email:string):Promise<Result>{
  const {error}=await supabase.functions.invoke('send-household-invitation',{body:{householdId,email,appUrl:`${location.origin}${import.meta.env.BASE_URL}`}})
  return{data:null,error:error?friendlyHouseholdError(error):null}
}

export async function cancelInvitation(invitationId:string):Promise<Result>{
  const {error}=await supabase.rpc('cancel_household_invitation',{p_invitation_id:invitationId})
  return{data:null,error:error?friendlyHouseholdError(error):null}
}

export async function getInvitationPreview(token:string):Promise<Result<InvitationPreview>>{
  const {data,error}=await supabase.rpc('get_invitation_preview',{p_token:token})
  if(error)return{data:null,error:friendlyHouseholdError(error)}
  const preview=(data as InvitationPreview[]|null)?.[0]||null
  return{data:preview,error:preview?null:'Pozvánku se nepodařilo najít.'}
}

export async function respondToInvitation(token:string,accept:boolean):Promise<Result<string>>{
  const {data,error}=await supabase.rpc('respond_to_household_invitation',{p_token:token,p_accept:accept})
  return{data:error?null:data as string,error:error?friendlyHouseholdError(error):null}
}
