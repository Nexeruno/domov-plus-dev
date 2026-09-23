import {beforeEach,describe,expect,it,vi} from 'vitest'

const {rpc,channel,removeChannel}=vi.hoisted(()=>({rpc:vi.fn(),channel:vi.fn(),removeChannel:vi.fn()}))
vi.mock('./supabase',()=>({supabase:{rpc,channel,removeChannel,from:vi.fn()}}))
import {addShoppingItem,buyShoppingItem,deleteShoppingItem,friendlyShoppingError,isTodayInTimezone,renameShoppingItem,restoreShoppingItem,subscribeShopping,undoDeleteShoppingItem,type ShoppingItem} from './shopping'

const item:ShoppingItem={id:'10000000-0000-4000-8000-000000000001',household_id:'20000000-0000-4000-8000-000000000002',name:'Mléko',status:'active',created_by:'u',created_at:'2026-01-01T00:00:00Z',updated_at:'2026-01-01T00:00:00Z',version:3,bought_by:null,bought_at:null,deleted_at:null}

describe('nákupní seznam V0.0.3',()=>{
  beforeEach(()=>{vi.clearAllMocks();Object.defineProperty(navigator,'onLine',{value:true,configurable:true});rpc.mockResolvedValue({data:item,error:null})})
  it('přidává položku s klientským UUID přes RPC',async()=>{await addShoppingItem(item.household_id,'Mléko');expect(rpc).toHaveBeenCalledWith('add_shopping_item',expect.objectContaining({p_household_id:item.household_id,p_name:'Mléko',p_id:expect.any(String)}))})
  it('předává prázdný název databázové validaci',async()=>{await addShoppingItem(item.household_id,'   ');expect(rpc).toHaveBeenCalledWith('add_shopping_item',expect.objectContaining({p_name:'   '}))})
  it('zobrazuje prázdný název česky',()=>expect(friendlyShoppingError({message:'invalid_shopping_item_name'})).toContain('Napište'))
  it('zobrazuje aktivní duplicitu se jménem česky',()=>expect(friendlyShoppingError({message:'active_shopping_item_exists'},' Mléko ')).toBe('Mléko už je na nákupním seznamu.'))
  it('označuje položku jako koupenou s verzí',async()=>{await buyShoppingItem(item);expect(rpc).toHaveBeenCalledWith('mark_shopping_item_bought',{p_item_id:item.id,p_expected_version:3})})
  it('vrací koupenou položku přes bezpečné RPC',async()=>{await restoreShoppingItem({...item,status:'bought'});expect(rpc).toHaveBeenCalledWith('restore_shopping_item',{p_item_id:item.id,p_expected_version:3})})
  it('přejmenovává s optimistickou verzí',async()=>{await renameShoppingItem(item,'Chléb');expect(rpc).toHaveBeenCalledWith('rename_shopping_item',{p_item_id:item.id,p_name:'Chléb',p_expected_version:3})})
  it('soft-delete používá verzi položky',async()=>{await deleteShoppingItem(item);expect(rpc).toHaveBeenCalledWith('delete_shopping_item',{p_item_id:item.id,p_expected_version:3})})
  it('Undo používá oddělené auditované RPC',async()=>{await undoDeleteShoppingItem(item);expect(rpc).toHaveBeenCalledWith('undo_delete_shopping_item',{p_item_id:item.id,p_expected_version:3})})
  it('při konfliktu verze zobrazí srozumitelnou zprávu',()=>expect(friendlyShoppingError({message:'shopping_item_not_available'})).toContain('mezitím změnila'))
  it('bez internetu neodesílá změnu',async()=>{Object.defineProperty(navigator,'onLine',{value:false,configurable:true});const r=await addShoppingItem(item.household_id,'Mléko');expect(r.error).toContain('Bez připojení');expect(rpc).not.toHaveBeenCalled()})
  it('pražský den není odvozený z prostého UTC data',()=>{const now=new Date('2026-03-02T00:15:00+01:00');expect(isTodayInTimezone('2026-03-01T23:10:00Z','Europe/Prague',now)).toBe(true);expect(isTodayInTimezone('2026-03-01T21:30:00Z','Europe/Prague',now)).toBe(false)})
  it('respektuje i jiné IANA časové pásmo',()=>expect(isTodayInTimezone('2026-01-01T02:00:00Z','America/New_York',new Date('2026-01-01T03:00:00Z'))).toBe(true))
  it('Realtime odebírá pouze změny dané domácnosti',()=>{const on=vi.fn().mockReturnThis(),subscribe=vi.fn().mockReturnValue('channel');channel.mockReturnValue({on,subscribe});subscribeShopping(item.household_id,vi.fn());expect(on).toHaveBeenCalledWith('postgres_changes',expect.objectContaining({table:'shopping_items',filter:`household_id=eq.${item.household_id}`}),expect.any(Function));expect(subscribe).toHaveBeenCalled()})
})
