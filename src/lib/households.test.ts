import {beforeEach,describe,expect,it,vi} from 'vitest'

const {rpc,invoke}=vi.hoisted(()=>({rpc:vi.fn(),invoke:vi.fn()}))
vi.mock('./supabase',()=>({supabase:{rpc,functions:{invoke}}}))

import {cancelInvitation,createHousehold,friendlyHouseholdError,getInvitationPreview,renameHousehold,respondToInvitation,sendInvitation} from './households'

describe('bezpečná logika domácností a pozvánek',()=>{
  beforeEach(()=>vi.clearAllMocks())

  it('vytvoří domácnost výhradně přes databázovou funkci',async()=>{
    rpc.mockResolvedValue({data:'household-1',error:null})
    expect((await createHousehold('Domov')).data).toBe('household-1')
    expect(rpc).toHaveBeenCalledWith('create_household',{p_name:'Domov'})
  })

  it('změní název přes auditovanou databázovou funkci',async()=>{
    rpc.mockResolvedValue({error:null})
    await renameHousehold('household-1','Náš domov')
    expect(rpc).toHaveBeenCalledWith('rename_household',{p_household_id:'household-1',p_name:'Náš domov'})
  })

  it('odesílá pozvánku přes serverovou funkci, ne přímo z klienta',async()=>{
    invoke.mockResolvedValue({error:null})
    await sendInvitation('household-1','partner@example.cz')
    expect(invoke).toHaveBeenCalledWith('send-household-invitation',expect.objectContaining({body:expect.objectContaining({householdId:'household-1',email:'partner@example.cz'})}))
  })

  it('načítá náhled jen přes jednorázový token',async()=>{
    rpc.mockResolvedValue({data:[{household_name:'Domov'}],error:null})
    expect((await getInvitationPreview('bezpecny-token')).data?.household_name).toBe('Domov')
    expect(rpc).toHaveBeenCalledWith('get_invitation_preview',{p_token:'bezpecny-token'})
  })

  it('přijímá i odmítá pozvánku přes atomickou databázovou funkci',async()=>{
    rpc.mockResolvedValue({data:'household-1',error:null})
    await respondToInvitation('token',true)
    expect(rpc).toHaveBeenCalledWith('respond_to_household_invitation',{p_token:'token',p_accept:true})
    await respondToInvitation('token',false)
    expect(rpc).toHaveBeenLastCalledWith('respond_to_household_invitation',{p_token:'token',p_accept:false})
  })

  it('zruší pouze konkrétní čekající pozvánku přes databázovou funkci',async()=>{
    rpc.mockResolvedValue({error:null})
    await cancelInvitation('invite-1')
    expect(rpc).toHaveBeenCalledWith('cancel_household_invitation',{p_invitation_id:'invite-1'})
  })

  it('překládá ochrany proti duplicitám do češtiny',()=>{
    expect(friendlyHouseholdError({message:'active_invitation_exists'})).toContain('už čeká')
    expect(friendlyHouseholdError({message:'already_household_member'})).toContain('už je členem')
    expect(friendlyHouseholdError({message:'invitation_email_mismatch'})).toContain('jinému e-mailu')
  })
})
