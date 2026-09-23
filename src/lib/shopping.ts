import type {RealtimeChannel} from '@supabase/supabase-js'
import {supabase} from './supabase'
import type {Result} from './households'

export type ShoppingItem={id:string;household_id:string;name:string;status:'active'|'bought';created_by:string;created_at:string;updated_at:string;version:number;bought_by:string|null;bought_at:string|null;deleted_at:string|null}

export function friendlyShoppingError(error:unknown,name?:string):string{
  const raw=String((error as {message?:string})?.message||'')
  if(raw.includes('active_shopping_item_exists'))return `${name?.trim()||'Tato položka'} už je na nákupním seznamu.`
  if(raw.includes('invalid_shopping_item_name'))return 'Napište, co chcete koupit.'
  if(raw.includes('shopping_item_not_available'))return 'Položka se mezitím změnila. Seznam jsme obnovili.'
  if(raw.includes('not_household_member'))return 'K tomuto nákupnímu seznamu nemáte přístup.'
  if(!navigator.onLine)return 'Bez připojení k internetu tuto akci nelze provést.'
  return 'Položku se nepodařilo uložit. Zkuste to znovu.'
}

export function isTodayInTimezone(iso:string,timezone:string,now=new Date()):boolean{
  const format=(date:Date)=>new Intl.DateTimeFormat('en-CA',{timeZone:timezone,year:'numeric',month:'2-digit',day:'2-digit'}).format(date)
  return format(new Date(iso))===format(now)
}

export async function loadShoppingItems(householdId:string):Promise<Result<ShoppingItem[]>>{
  const {data,error}=await supabase.rpc('list_current_shopping_items',{p_household_id:householdId})
  if(error)return{data:null,error:friendlyShoppingError(error)}
  return{data:(data||[]) as ShoppingItem[],error:null}
}

async function mutate(fn:string,args:Record<string,unknown>,name?:string):Promise<Result<ShoppingItem>>{
  if(!navigator.onLine)return{data:null,error:friendlyShoppingError(new Error(),name)}
  const {data,error}=await supabase.rpc(fn,args)
  return{data:error?null:data as ShoppingItem,error:error?friendlyShoppingError(error,name):null}
}

export function addShoppingItem(householdId:string,name:string){return mutate('add_shopping_item',{p_household_id:householdId,p_id:crypto.randomUUID(),p_name:name},name)}
export function renameShoppingItem(item:ShoppingItem,name:string){return mutate('rename_shopping_item',{p_item_id:item.id,p_name:name,p_expected_version:item.version},name)}
export function buyShoppingItem(item:ShoppingItem){return mutate('mark_shopping_item_bought',{p_item_id:item.id,p_expected_version:item.version},item.name)}
export function restoreShoppingItem(item:ShoppingItem){return mutate('restore_shopping_item',{p_item_id:item.id,p_expected_version:item.version},item.name)}
export function deleteShoppingItem(item:ShoppingItem){return mutate('delete_shopping_item',{p_item_id:item.id,p_expected_version:item.version},item.name)}
export function undoDeleteShoppingItem(item:ShoppingItem){return mutate('undo_delete_shopping_item',{p_item_id:item.id,p_expected_version:item.version},item.name)}

export function subscribeShopping(householdId:string,onChange:()=>void):RealtimeChannel{return supabase.channel(`shopping:${householdId}`).on('postgres_changes',{event:'*',schema:'public',table:'shopping_items',filter:`household_id=eq.${householdId}`},onChange).subscribe(status=>{if(status==='SUBSCRIBED')onChange()})}
export async function unsubscribeShopping(channel:RealtimeChannel){await supabase.removeChannel(channel)}
