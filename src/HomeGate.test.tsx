import {afterEach,beforeEach,expect,it,vi} from 'vitest'
import {cleanup,render,screen,waitFor} from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import {MemoryRouter,useLocation} from 'react-router-dom'
import type {User} from '@supabase/supabase-js'

const {loadHousehold,loadEnergyReadings}=vi.hoisted(()=>({loadHousehold:vi.fn(),loadEnergyReadings:vi.fn()}))
vi.mock('./lib/households',()=>({loadHousehold}))
vi.mock('./lib/energy',async importOriginal=>({...await importOriginal<typeof import('./lib/energy')>(),loadEnergyReadings}))
vi.mock('./lib/supabase',()=>({isConfigured:true}))
import {HomeGate} from './App'

const user={id:'user-a',user_metadata:{display_name:'A'},app_metadata:{},aud:'authenticated',created_at:'2026-01-01T00:00:00Z'} as User
beforeEach(()=>{vi.clearAllMocks();loadEnergyReadings.mockResolvedValue({data:[],error:null})})
afterEach(cleanup)

it('chyba načtení nikdy nenabídne založení domácnosti a lze opakovat',async()=>{
  loadHousehold.mockResolvedValueOnce({data:null,error:'Výpadek databáze'}).mockResolvedValueOnce({data:null,error:null})
  render(<MemoryRouter><HomeGate user={user}/></MemoryRouter>)
  expect(await screen.findByText('Domácnost se nepodařilo načíst.')).toBeInTheDocument()
  expect(screen.queryByText('Vytvořit domácnost')).not.toBeInTheDocument()
  await userEvent.click(screen.getByRole('button',{name:'Zkusit znovu'}))
  expect(await screen.findByText('Vytvořit domácnost')).toBeInTheDocument()
})

it('domácnost se dvěma členy zobrazí obě jména a návrat',async()=>{
  loadHousehold.mockResolvedValue({data:{household:{id:'h',name:'Domov',timezone:'Europe/Prague'},members:[{user_id:'user-a',role:'owner',profiles:{display_name:'A'}},{user_id:'user-b',role:'owner',profiles:{display_name:'B'}}],invitations:[]},error:null})
  render(<MemoryRouter initialEntries={['/domacnost']}><HomeGate user={user}/></MemoryRouter>)
  expect(await screen.findByText('A')).toBeInTheDocument()
  expect(screen.getByText('B')).toBeInTheDocument()
  expect(screen.getByRole('button',{name:'Zpět do aplikace'})).toBeInTheDocument()
})

it('domácnost otevře Dnes a Energie bez dalších modulů',async()=>{
  loadHousehold.mockResolvedValue({data:{household:{id:'h',name:'Domov',timezone:'Europe/Prague'},members:[{user_id:'user-a',role:'owner',profiles:{display_name:'A'}}],invitations:[]},error:null})
  render(<MemoryRouter initialEntries={['/dnes']}><HomeGate user={user}/></MemoryRouter>)
  expect(await screen.findByRole('heading',{name:'Dnes'})).toBeInTheDocument()
  expect(screen.getByRole('navigation',{name:'Hlavní navigace'}).querySelectorAll('button')).toHaveLength(2)
  await userEvent.click(screen.getByRole('button',{name:'Energie'}))
  expect(await screen.findByRole('heading',{name:'Energie'})).toBeInTheDocument()
  expect(await screen.findByRole('button',{name:'Přidat odečet'})).toBeInTheDocument()
})

it('starý odkaz do odstraněné části zobrazí Dnes bez dalšího síťového požadavku',async()=>{
  loadHousehold.mockResolvedValue({data:{household:{id:'h',name:'Domov',timezone:'Europe/Prague'},members:[],invitations:[]},error:null})
  const fetchSpy=vi.spyOn(globalThis,'fetch')
  try{
    function Path(){return <span data-testid="path">{useLocation().pathname}</span>}
    render(<MemoryRouter initialEntries={['/nakup']}><HomeGate user={user}/><Path/></MemoryRouter>)
    expect(await screen.findByRole('heading',{name:'Dnes'})).toBeInTheDocument()
    await waitFor(()=>expect(screen.getByTestId('path')).toHaveTextContent('/dnes'))
    expect(screen.queryByRole('button',{name:'Nákup'})).not.toBeInTheDocument()
    expect(fetchSpy).not.toHaveBeenCalled()
  }finally{fetchSpy.mockRestore()}
})
