import {useEffect,useState,type FormEvent} from 'react'
import type {Household} from './lib/households'
import {addEnergyReading,comparison,energyIntervals,loadEnergyReadings,type EnergyReading} from './lib/energy'
import './energy.css'

const number=(n:number,digits=1)=>new Intl.NumberFormat('cs-CZ',{maximumFractionDigits:digits}).format(n)
const money=(n:number)=>new Intl.NumberFormat('cs-CZ',{style:'currency',currency:'CZK'}).format(n)
const date=(value:string)=>new Date(`${value}T12:00:00Z`).toLocaleDateString('cs-CZ',{timeZone:'UTC'})
const today=(timezone:string)=>{
  const parts=new Intl.DateTimeFormat('en-US',{timeZone:timezone,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date())
  const part=(type:string)=>parts.find(value=>value.type===type)?.value||''
  return `${part('year')}-${part('month')}-${part('day')}`
}

export default function Energy({household}:{household:Household}){
  const [readings,setReadings]=useState<EnergyReading[]>([])
  const [loading,setLoading]=useState(true)
  const [available,setAvailable]=useState(false)
  const [error,setError]=useState<string|null>(null)
  const [view,setView]=useState<'overview'|'add'|'history'>('overview')
  const [busy,setBusy]=useState(false)
  async function refresh(){
    setLoading(true)
    const result=await loadEnergyReadings(household.id)
    setLoading(false)
    if(result.error){setAvailable(false);setError(result.error)}
    else{setReadings(result.data||[]);setAvailable(true);setError(null)}
  }
  useEffect(()=>{void refresh()},[household.id])
  const [latest]=readings
  const [current]=energyIntervals(readings)
  const compared=comparison(readings)
  async function submit(event:FormEvent<HTMLFormElement>){
    event.preventDefault()
    if(busy)return
    const form=new FormData(event.currentTarget)
    const dateValue=String(form.get('date')||'')
    const values=['vt','nt','priceVt','priceNt'].map(key=>String(form.get(key)??''))
    if(!dateValue||values.some(v=>v.trim()===''||!Number.isFinite(Number(v))||Number(v)<0)){
      setError('Vyplňte datum, oba stavy a obě ceny nezápornými čísly.');return
    }
    const [vt,nt,priceVt,priceNt]=values.map(Number)
    if(dateValue>today(household.timezone)||latest&&dateValue<=latest.reading_date){setError('Datum musí být pozdější než poslední odečet a nesmí být v budoucnosti.');return}
    if(latest&&(vt<latest.vt_kwh||nt<latest.nt_kwh)){setError('Stav VT ani NT nesmí být nižší než při posledním odečtu.');return}
    setBusy(true);setError(null)
    const failure=await addEnergyReading(household.id,{date:dateValue,vt,nt,priceVt,priceNt})
    if(failure)setError(failure)
    else{setView('overview');await refresh()}
    setBusy(false)
  }
  return <section className="app-content energy-page">
    <h1>Energie</h1>
    {error&&<div className="energy-error" role="alert">{error} <button onClick={()=>void refresh()}>Zkusit znovu</button></div>}
    {loading?<p>Načítám odečty…</p>:!available?<p>Odečty teď nejsou dostupné.</p>:view==='add'?<>
      <h2>Přidat odečet</h2>
      <form className="energy-form" onSubmit={event=>void submit(event)}>
        <label>Datum odečtu<input name="date" type="date" required max={today(household.timezone)} min={latest?.reading_date}/></label>
        <label>VT stav (kWh)<input name="vt" type="number" inputMode="decimal" min="0" step="0.001" required defaultValue={latest?.vt_kwh}/></label>
        <label>NT stav (kWh)<input name="nt" type="number" inputMode="decimal" min="0" step="0.001" required defaultValue={latest?.nt_kwh}/></label>
        <label>Cena VT za kWh (Kč)<input name="priceVt" type="number" inputMode="decimal" min="0" step="0.0001" required defaultValue={latest?.price_vt_kwh}/></label>
        <label>Cena NT za kWh (Kč)<input name="priceNt" type="number" inputMode="decimal" min="0" step="0.0001" required defaultValue={latest?.price_nt_kwh}/></label>
        <button className="energy-primary" disabled={busy}>{busy?'Ukládám…':'Uložit odečet'}</button>
      </form>
      <button className="energy-text-button" onClick={()=>{setError(null);setView('overview')}}>Zpět</button>
    </>:view==='history'?<>
      <h2>Historie odečtů</h2>
      <div className="energy-list">{energyIntervals(readings).map(({reading,interval})=><div className="energy-entry" key={reading.id}>
        <strong>{date(reading.reading_date)}</strong><span>VT {number(reading.vt_kwh,3)} kWh · NT {number(reading.nt_kwh,3)} kWh</span>
        <span>{interval?`${number(interval.total,3)} kWh za ${interval.days} dní · orientačně ${money(interval.cost)}`:'První odečet · výchozí stav'}</span>
      </div>)}</div>
      <button className="energy-text-button" onClick={()=>setView('overview')}>Zpět</button>
    </>:<>
      {!latest?<p>Ještě nemáte žádný odečet. První odečet nastaví výchozí stav.</p>:<div className="energy-summary">
        <h2>Aktuální interval</h2><p>Poslední odečet: {date(latest.reading_date)}</p>
        {current?.interval?<>
          <p>VT {number(current.interval.vt,3)} kWh · NT {number(current.interval.nt,3)} kWh</p>
          <strong>{number(current.interval.total,3)} kWh</strong>
          <p>{current.interval.days} dní · {number(current.interval.total/current.interval.days,2)} kWh/den</p>
          <p>Orientační cena: <strong>{money(current.interval.cost)}</strong></p>
          {compared&&<p>Oproti předchozímu intervalu: {compared.change<0?'o '+number(-compared.change,3)+' kWh méně':'o '+number(compared.change,3)+' kWh více'}{compared.percent!==null?` (${number(compared.percent,1)} %)`:''}. Předchozí interval trval {compared.previous.days} dní.</p>}
        </>:<p>První odečet · výchozí stav. Spotřebu ukáže další odečet.</p>}
      </div>}
      <div className="energy-actions"><button className="energy-primary" onClick={()=>{setError(null);setView('add')}}>Přidat odečet</button><button className="energy-secondary" onClick={()=>setView('history')} disabled={!latest}>Historie</button></div>
    </>}
  </section>
}
