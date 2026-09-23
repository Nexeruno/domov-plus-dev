import {afterEach,beforeEach,expect,it,vi} from 'vitest'
import {cleanup,render,screen,waitFor} from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import {MemoryRouter} from 'react-router-dom'
import type {ShoppingItem} from './lib/shopping'

const {loadShoppingItems,subscribeShopping,unsubscribeShopping,buyShoppingItem}=vi.hoisted(()=>({loadShoppingItems:vi.fn(),subscribeShopping:vi.fn(),unsubscribeShopping:vi.fn(),buyShoppingItem:vi.fn()}))
vi.mock('./lib/shopping',()=>({loadShoppingItems,subscribeShopping,unsubscribeShopping,buyShoppingItem}))
import {Shopping} from './ShoppingApp'

const item:ShoppingItem={id:'i',household_id:'h',name:'Mléko',status:'active',created_by:'a',created_at:'2026-01-01T00:00:00Z',updated_at:'2026-01-01T00:00:00Z',version:1,bought_by:null,bought_at:null,deleted_at:null}
function deferred<T>(){let resolve!:(value:T)=>void;const promise=new Promise<T>(r=>{resolve=r});return{promise,resolve}}
beforeEach(()=>{vi.clearAllMocks();subscribeShopping.mockReturnValue({});unsubscribeShopping.mockResolvedValue(undefined);loadShoppingItems.mockResolvedValue({data:[item],error:null})})
afterEach(cleanup)

it('při Realtime změnách ignoruje opožděnou starší odpověď',async()=>{
  const old=deferred<{data:ShoppingItem[];error:null}>(),recent=deferred<{data:ShoppingItem[];error:null}>()
  loadShoppingItems.mockResolvedValueOnce({data:[item],error:null}).mockReturnValueOnce(old.promise).mockReturnValueOnce(recent.promise)
  render(<MemoryRouter><Shopping householdId="h"/></MemoryRouter>)
  expect(await screen.findByText('Mléko')).toBeInTheDocument()
  const notify=subscribeShopping.mock.calls[0][1] as ()=>void
  notify();notify()
  recent.resolve({data:[{...item,name:'Chléb'}],error:null})
  expect(await screen.findByText('Chléb')).toBeInTheDocument()
  old.resolve({data:[item],error:null})
  await waitFor(()=>expect(screen.queryByText('Mléko')).not.toBeInTheDocument())
})

it('během koupě vypne akce jen dané položky a odmítne dvojtap',async()=>{
  const buying=deferred<{data:ShoppingItem;error:null}>()
  buyShoppingItem.mockReturnValue(buying.promise)
  render(<MemoryRouter><Shopping householdId="h"/></MemoryRouter>)
  const button=await screen.findByRole('button',{name:'Označit Mléko jako koupené'})
  await userEvent.click(button)
  expect(button).toBeDisabled()
  expect(screen.getByRole('button',{name:'Odstranit Mléko'})).toBeDisabled()
  await userEvent.click(button)
  expect(buyShoppingItem).toHaveBeenCalledTimes(1)
  buying.resolve({data:{...item,status:'bought',version:2,bought_by:'a',bought_at:new Date().toISOString()},error:null})
  await waitFor(()=>expect(button).not.toBeDisabled())
})
