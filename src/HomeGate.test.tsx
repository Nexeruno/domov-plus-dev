import {afterEach,beforeEach,expect,it,vi} from 'vitest'
import {cleanup,render,screen} from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import {MemoryRouter} from 'react-router-dom'
import type {User} from '@supabase/supabase-js'

const {loadHousehold}=vi.hoisted(()=>({loadHousehold:vi.fn()}))
vi.mock('./lib/households',()=>({loadHousehold}))
vi.mock('./lib/supabase',()=>({isConfigured:true}))
vi.mock('./ShoppingApp',()=>({default:()=> <div>Nákup načten</div>,BottomNav:()=> <nav>Hlavní navigace</nav>}))
import {HomeGate} from './App'

const user={id:'user-a',user_metadata:{display_name:'A'},app_metadata:{},aud:'authenticated',created_at:'2026-01-01T00:00:00Z'} as User
beforeEach(()=>vi.clearAllMocks())
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
  expect(screen.getByRole('button',{name:'Zpět na nákup'})).toBeInTheDocument()
})
