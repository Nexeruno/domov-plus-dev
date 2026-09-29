import {afterEach,beforeEach,expect,it,vi} from 'vitest'
import {cleanup,render,screen} from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import Energy from './Energy'

const {loadEnergyReadings,addEnergyReading}=vi.hoisted(()=>({loadEnergyReadings:vi.fn(),addEnergyReading:vi.fn()}))
vi.mock('./lib/energy',async original=>({...await original<typeof import('./lib/energy')>(),loadEnergyReadings,addEnergyReading}))
const household={id:'a',name:'Domov',timezone:'Europe/Prague'}
const record=(date:string,vt:number,nt:number)=>({id:date,household_id:'a',reading_date:date,vt_kwh:vt,nt_kwh:nt,price_vt_kwh:5,price_nt_kwh:3,created_at:'',created_by:'u'})
beforeEach(()=>{vi.clearAllMocks();loadEnergyReadings.mockResolvedValue({data:[],error:null});addEnergyReading.mockResolvedValue(null)})
afterEach(cleanup)

it('bez dat zobrazí výchozí stav a historii nepovolí',async()=>{
  render(<Energy household={household}/>)
  expect(await screen.findByText(/První odečet nastaví výchozí stav/)).toBeInTheDocument()
  expect(screen.getByRole('button',{name:'Historie'})).toBeDisabled()
})

it('chyba načtení se nepovažuje za prázdný seznam',async()=>{
  loadEnergyReadings.mockResolvedValue({data:null,error:'Odečty se nepodařilo načíst.'})
  render(<Energy household={household}/>)
  expect(await screen.findByText('Odečty teď nejsou dostupné.')).toBeInTheDocument()
  expect(screen.queryByRole('button',{name:'Přidat odečet'})).not.toBeInTheDocument()
})

it('historie zobrazuje první odečet a správný interval',async()=>{
  loadEnergyReadings.mockResolvedValue({data:[record('2026-02-01',120,55),record('2026-01-01',100,50)],error:null})
  render(<Energy household={household}/>)
  await userEvent.click(await screen.findByRole('button',{name:'Historie'}))
  expect(screen.getByText(/25 kWh za 31 dní/)).toBeInTheDocument()
  expect(screen.getByText(/První odečet · výchozí stav/)).toBeInTheDocument()
})

it('nižší VT i NT odmítne ještě před odesláním a neodešle duplicitní akci',async()=>{
  loadEnergyReadings.mockResolvedValue({data:[record('2026-01-01',100,50)],error:null})
  render(<Energy household={household}/>)
  await userEvent.click(await screen.findByRole('button',{name:'Přidat odečet'}))
  const user=userEvent.setup()
  await user.type(screen.getByLabelText('Datum odečtu'),'2026-02-01')
  await user.clear(screen.getByLabelText('VT stav (kWh)'))
  await user.type(screen.getByLabelText('VT stav (kWh)'),'99')
  await user.click(screen.getByRole('button',{name:'Uložit odečet'}))
  expect(await screen.findByRole('alert')).toHaveTextContent('nesmí být nižší')
  expect(addEnergyReading).not.toHaveBeenCalled()
  await user.clear(screen.getByLabelText('VT stav (kWh)'))
  await user.type(screen.getByLabelText('VT stav (kWh)'),'100')
  await user.clear(screen.getByLabelText('NT stav (kWh)'))
  await user.type(screen.getByLabelText('NT stav (kWh)'),'49')
  await user.click(screen.getByRole('button',{name:'Uložit odečet'}))
  expect(addEnergyReading).not.toHaveBeenCalled()
})
