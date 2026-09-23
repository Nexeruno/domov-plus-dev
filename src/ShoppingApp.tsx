import {FormEvent,useCallback,useEffect,useRef,useState} from 'react'
import {CalendarDays,Check,ChevronDown,Home,House,Lightbulb,Pencil,RotateCcw,ShoppingBasket,Trash2,UserRound,X} from 'lucide-react'
import {useLocation,useNavigate} from 'react-router-dom'
import type {HouseholdData} from './lib/households'
import {addShoppingItem,buyShoppingItem,deleteShoppingItem,loadShoppingItems,renameShoppingItem,restoreShoppingItem,subscribeShopping,undoDeleteShoppingItem,unsubscribeShopping,type ShoppingItem} from './lib/shopping'
import './shopping.css'

type Status={kind:'error'|'success';text:string}|null
const Message=({status}:{status:Status})=>status?<div role="alert" className={`message ${status.kind}`}>{status.text}</div>:null

export default function ShoppingApp({data}:{data:NonNullable<HouseholdData>}){
  const nav=useNavigate(),loc=useLocation();
  const tab=loc.pathname==='/dnes'?'today':loc.pathname==='/energie'?'energy':'shopping'
  return <main className="app-shell"><header className="app-header"><div className="mini-brand"><Home/>Domov+</div><div className="header-actions"><button aria-label="Správa domácnosti" onClick={()=>nav('/domacnost')}><House/></button><button aria-label="Otevřít profil" onClick={()=>nav('/profil')}><UserRound/></button></div></header><div className="app-content">{tab==='shopping'?<Shopping householdId={data.household.id} timezone={data.household.timezone}/>:<Placeholder title={tab==='today'?'Dnes':'Energie'}/>}</div><nav className="bottom-nav" aria-label="Hlavní navigace"><button className={tab==='today'?'active':''} onClick={()=>nav('/dnes')}><CalendarDays/><span>Dnes</span></button><button className={tab==='shopping'?'active':''} onClick={()=>nav('/nakup')}><ShoppingBasket/><span>Nákup</span></button><button className={tab==='energy'?'active':''} onClick={()=>nav('/energie')}><Lightbulb/><span>Energie</span></button></nav></main>
}

function Placeholder({title}:{title:string}){return <section className="placeholder"><h1>{title}</h1><p>Tato část bude dostupná v další verzi.</p></section>}

function Shopping({householdId,timezone}:{householdId:string;timezone:string}){
  const [items,setItems]=useState<ShoppingItem[]>([]),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[status,setStatus]=useState<Status>(null),[boughtOpen,setBoughtOpen]=useState(false),[editing,setEditing]=useState<string|null>(null),[undo,setUndo]=useState<ShoppingItem|null>(null)
  const undoTimer=useRef<number|undefined>(undefined)
  const refresh=useCallback(async()=>{const r=await loadShoppingItems(householdId,timezone);setLoading(false);if(r.error)setStatus({kind:'error',text:r.error});else setItems(r.data||[])},[householdId,timezone])
  useEffect(()=>{void refresh();const channel=subscribeShopping(householdId,()=>void refresh());return()=>{void unsubscribeShopping(channel)}},[householdId,refresh])
  useEffect(()=>()=>window.clearTimeout(undoTimer.current),[])
  async function add(e:FormEvent<HTMLFormElement>){e.preventDefault();if(busy)return;const form=e.currentTarget,input=form.elements.namedItem('item') as HTMLInputElement,name=input.value.trim();if(!name){setStatus({kind:'error',text:'Napište, co chcete koupit.'});return}setBusy(true);setStatus(null);const r=await addShoppingItem(householdId,name);setBusy(false);if(r.error)setStatus({kind:'error',text:r.error});else{form.reset();await refresh()}}
  async function buy(item:ShoppingItem){setBusy(true);const r=await buyShoppingItem(item);setBusy(false);if(r.error)setStatus({kind:'error',text:r.error});await refresh()}
  async function restore(item:ShoppingItem){setBusy(true);const r=await restoreShoppingItem(item);setBusy(false);if(r.error)setStatus({kind:'error',text:r.error});await refresh()}
  async function rename(e:FormEvent<HTMLFormElement>,item:ShoppingItem){e.preventDefault();const name=String(new FormData(e.currentTarget).get('name')||'').trim();if(!name){setStatus({kind:'error',text:'Napište název položky.'});return}const r=await renameShoppingItem(item,name);if(r.error)setStatus({kind:'error',text:r.error});else setEditing(null);await refresh()}
  async function remove(item:ShoppingItem){const r=await deleteShoppingItem(item);if(r.error)setStatus({kind:'error',text:r.error});else{const removed=r.data||item;setUndo(removed);window.clearTimeout(undoTimer.current);undoTimer.current=window.setTimeout(()=>setUndo(null),6000)}await refresh()}
  async function undoRemove(){if(!undo)return;const r=await undoDeleteShoppingItem(undo);if(r.error)setStatus({kind:'error',text:r.error});setUndo(null);await refresh()}
  const active=items.filter(x=>x.status==='active'),bought=items.filter(x=>x.status==='bought')
  return <section className="shopping-page"><h1>Nákup</h1><form className="quick-add" onSubmit={add}><label htmlFor="shopping-name">Co koupit?</label><div><input id="shopping-name" name="item" maxLength={120} autoComplete="off" disabled={busy}/><button className="primary" disabled={busy}>Přidat</button></div></form><Message status={status}/>{loading?<p className="empty-state">Načítám seznam…</p>:active.length===0?<p className="empty-state">Nákupní seznam je prázdný.</p>:<ul className="shopping-list">{active.map(item=><li key={item.id}>{editing===item.id?<form className="edit-item" onSubmit={e=>rename(e,item)}><input name="name" defaultValue={item.name} maxLength={120} autoFocus/><button aria-label="Uložit název"><Check/></button><button type="button" aria-label="Zrušit úpravu" onClick={()=>setEditing(null)}><X/></button></form>:<><button className="buy-button" aria-label={`Označit ${item.name} jako koupené`} onClick={()=>buy(item)}><Check/></button><span>{item.name}</span><div className="item-actions"><button aria-label={`Upravit ${item.name}`} onClick={()=>setEditing(item.id)}><Pencil/></button><button aria-label={`Odstranit ${item.name}`} onClick={()=>remove(item)}><Trash2/></button></div></>}</li>)}</ul>}{bought.length>0&&<section className="bought-section"><button className="bought-toggle" aria-expanded={boughtOpen} onClick={()=>setBoughtOpen(v=>!v)}>Koupeno dnes <span>{bought.length}</span><ChevronDown className={boughtOpen?'open':''}/></button>{boughtOpen&&<ul>{bought.map(item=><li key={item.id}><span><Check/>{item.name}</span><button onClick={()=>restore(item)}><RotateCcw/>Vrátit na seznam</button></li>)}</ul>}</section>}{undo&&<div className="undo-toast" role="status">Položka odstraněna <button onClick={undoRemove}>Zpět</button></div>}</section>
}
