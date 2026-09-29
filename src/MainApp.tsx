import {useEffect} from 'react'
import {CalendarDays,Home,House,Lightbulb,UserRound} from 'lucide-react'
import {useLocation,useNavigate} from 'react-router-dom'
import './main-app.css'

export default function MainApp(){
  const navigate=useNavigate(),location=useLocation()
  const energy=location.pathname==='/energie'
  useEffect(()=>{if(location.pathname==='/nakup')navigate('/dnes',{replace:true})},[location.pathname,navigate])
  return <main className="app-shell">
    <header className="app-header">
      <div className="mini-brand"><Home/>Domov+</div>
      <div className="header-actions">
        <button aria-label="Správa domácnosti" onClick={()=>navigate('/domacnost')}><House/></button>
        <button aria-label="Otevřít profil" onClick={()=>navigate('/profil')}><UserRound/></button>
      </div>
    </header>
    <section className="app-content placeholder">
      <h1>{energy?'Energie':'Dnes'}</h1>
      <p>Tato část bude dostupná v další verzi.</p>
    </section>
    <BottomNav active={energy?'energy':'today'}/>
  </main>
}

export function BottomNav({active}:{active?:'today'|'energy'}){
  const navigate=useNavigate()
  return <nav className="bottom-nav" aria-label="Hlavní navigace">
    <button className={active==='today'?'active':''} onClick={()=>navigate('/dnes')}><CalendarDays/><span>Dnes</span></button>
    <button className={active==='energy'?'active':''} onClick={()=>navigate('/energie')}><Lightbulb/><span>Energie</span></button>
  </nav>
}
