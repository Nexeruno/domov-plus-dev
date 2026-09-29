import {supabase} from './supabase'

export type EnergyReading={
  id:string;household_id:string;reading_date:string;vt_kwh:number;nt_kwh:number;
  price_vt_kwh:number;price_nt_kwh:number;created_at:string;created_by:string
}

const days=(later:string,earlier:string)=>
  (Date.parse(`${later}T00:00:00Z`)-Date.parse(`${earlier}T00:00:00Z`))/86400000

export function energyIntervals(readings:EnergyReading[]){
  const sorted=[...readings].sort((a,b)=>a.reading_date.localeCompare(b.reading_date))
  return sorted.map((reading,index)=>{
    const previous=sorted[index-1]
    if(!previous)return {reading,interval:null}
    const vt=reading.vt_kwh-previous.vt_kwh
    const nt=reading.nt_kwh-previous.nt_kwh
    return {reading,interval:{vt,nt,total:vt+nt,cost:vt*reading.price_vt_kwh+nt*reading.price_nt_kwh,days:days(reading.reading_date,previous.reading_date)}}
  }).reverse()
}

export function comparison(readings:EnergyReading[]){
  const [current,previous]=energyIntervals(readings)
  if(!current?.interval||!previous?.interval)return null
  const change=current.interval.total-previous.interval.total
  return {change,percent:previous.interval.total>0?change/previous.interval.total*100:null,previous:previous.interval}
}

export function energyError(error:unknown){
  const raw=String((error as {message?:string})?.message||'')
  if(raw.includes('reading_lower_than_previous'))return 'Stav VT ani NT nesmí být nižší než při posledním odečtu.'
  if(raw.includes('reading_date_not_newer'))return 'Datum musí být pozdější než poslední odečet.'
  if(raw.includes('invalid_reading_date'))return 'Zadejte platné datum, které není v budoucnosti.'
  if(raw.includes('invalid_energy_value'))return 'Vyplňte nezáporné stavy a ceny.'
  if(raw.includes('not_household_member'))return 'K odečtům této domácnosti nemáte přístup.'
  if((error as {code?:string})?.code==='23505')return 'Pro tento den už odečet existuje.'
  return 'Odečet se nepodařilo uložit. Zkuste to znovu.'
}

export async function loadEnergyReadings(householdId:string){
  const {data,error}=await supabase.from('energy_readings')
    .select('id,household_id,reading_date,vt_kwh,nt_kwh,price_vt_kwh,price_nt_kwh,created_at,created_by')
    .eq('household_id',householdId).order('reading_date',{ascending:false})
  return {data:data as EnergyReading[]|null,error:error?'Odečty se nepodařilo načíst. Zkuste to znovu.':null}
}

export async function addEnergyReading(householdId:string,reading:{date:string;vt:number;nt:number;priceVt:number;priceNt:number}){
  const {error}=await supabase.rpc('add_energy_reading',{
    p_household_id:householdId,p_reading_date:reading.date,p_vt_kwh:reading.vt,
    p_nt_kwh:reading.nt,p_price_vt_kwh:reading.priceVt,p_price_nt_kwh:reading.priceNt
  })
  return error?energyError(error):null
}
